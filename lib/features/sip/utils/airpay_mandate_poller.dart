import 'dart:async';

import '../../../core/error/failures.dart';

/// Where an Airpay UPI AutoPay request stands, as far as the app knows.
///
/// Airpay doesn't use a checkout: when SIP / Custom SIP create picks Airpay,
/// the server has already sent a UPI AutoPay (collect) request to the
/// customer's UPI ID, and the customer approves it in their UPI app. The app
/// only waits, asking `sip/confirm` every few seconds — see
/// [AirpayMandatePoller].
enum AirpayMandateStatus {
  /// Not approved yet (`BANK_APPROVAL_PENDING`), or the last check couldn't
  /// reach the server — keep waiting.
  pending,

  /// Approved: the mandate is `ACTIVE`.
  active,

  /// Declined, expired or refused — [AirpayMandateUpdate.message] says why.
  failed,

  /// The wait ran out before an answer. Not a failure: the server's
  /// pending-auth cron still finishes the mandate if it was approved.
  timedOut,
}

/// One answer while waiting for an Airpay UPI AutoPay approval.
class AirpayMandateUpdate {
  final AirpayMandateStatus status;

  /// Server message — the reason for [AirpayMandateStatus.failed].
  final String? message;

  /// The raw `sip/confirm` body ({} when the check threw).
  final Map<String, dynamic> response;

  const AirpayMandateUpdate(
    this.status, {
    this.message,
    this.response = const {},
  });

  /// `sip/confirm` statuses that mean "not approved yet". The server answers
  /// BANK_APPROVAL_PENDING while Airpay is waiting; the others are older
  /// spellings of the same thing and never mean a decline.
  static const _pendingStatuses = {
    '',
    'BANK_APPROVAL_PENDING',
    'PENDING_AUTH',
    'PENDING',
    'INITIALIZED',
    'INITIALISED',
  };

  /// Reads a `sip/confirm` body that came back without an HTTP error.
  factory AirpayMandateUpdate.fromResponse(Map<String, dynamic>? response) {
    final body = response ?? const <String, dynamic>{};
    final data = body['data'] is Map ? body['data'] as Map : const {};
    if (body['success'] != true) {
      return AirpayMandateUpdate(
        AirpayMandateStatus.failed,
        message: _firstText([
              body['message'],
              body['error'] is Map ? (body['error'] as Map)['message'] : null,
            ]) ??
            'Authorization could not be verified.',
        response: body,
      );
    }
    final status = data['status']?.toString().trim().toUpperCase() ?? '';
    if (status == 'ACTIVE') {
      return AirpayMandateUpdate(AirpayMandateStatus.active, response: body);
    }
    if (_pendingStatuses.contains(status)) {
      return AirpayMandateUpdate(AirpayMandateStatus.pending, response: body);
    }
    return AirpayMandateUpdate(
      AirpayMandateStatus.failed,
      message: _firstText([body['message']]) ?? 'Authorization status: $status',
      response: body,
    );
  }

  /// Reads a `sip/confirm` call that threw.
  ///
  /// The server refuses a declined / expired request with HTTP 400, which
  /// ApiClient throws as a [ServerFailure] carrying the server's message —
  /// that ends the wait. So do session/auth errors, which no retry fixes.
  /// Anything else (no network, timeouts, 5xx, a garbled body) is treated as
  /// a missed check, and the next poll tries again.
  factory AirpayMandateUpdate.fromError(Object error) {
    if (error is SessionInvalidatedFailure ||
        error is AuthenticationFailure ||
        error is KycRequiredFailure ||
        error is BankVerificationRequiredFailure) {
      return AirpayMandateUpdate(
        AirpayMandateStatus.failed,
        message: (error as Failure).message,
      );
    }
    if (error is ServerFailure) {
      final code = error.statusCode;
      if (code != null && code >= 400 && code < 500) {
        return AirpayMandateUpdate(
          AirpayMandateStatus.failed,
          message: error.message.trim().isNotEmpty
              ? error.message
              : 'Mandate authorization failed. Please try again.',
        );
      }
    }
    return const AirpayMandateUpdate(AirpayMandateStatus.pending);
  }

  static String? _firstText(List<Object?> candidates) {
    for (final c in candidates) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
    }
    return null;
  }
}

/// Asks `sip/confirm` every [pollInterval] while an Airpay UPI AutoPay
/// request waits for the customer's approval, and counts down [timeout].
///
/// Finishes exactly once, through [onFinished], with
/// [AirpayMandateStatus.active], [AirpayMandateStatus.failed] or
/// [AirpayMandateStatus.timedOut]. Polls never overlap: the next one is
/// scheduled only after the previous answer arrives. A poll still in flight
/// when the time runs out gets to finish — an approval that lands in that
/// moment isn't thrown away.
///
/// The countdown is wall-clock based ([now]), so time spent in the UPI app
/// counts even where the OS pauses timers in the background (iOS).
///
/// Call [dispose] when the screen goes away: it cancels every timer, and
/// nothing is reported after it.
class AirpayMandatePoller {
  final Future<Map<String, dynamic>> Function() confirm;
  final void Function(AirpayMandateUpdate update) onFinished;

  /// Called about once a second with the time left (for the countdown).
  final void Function(Duration remaining)? onTick;

  final Duration pollInterval;
  final Duration timeout;
  final DateTime Function() _now;

  AirpayMandatePoller({
    required this.confirm,
    required this.onFinished,
    this.onTick,
    this.pollInterval = const Duration(seconds: 5),
    this.timeout = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  DateTime? _deadline;
  Timer? _ticker;
  Timer? _nextPoll;
  Future<void>? _inFlight;
  bool _finished = false;
  bool _disposed = false;

  /// Time left before the wait gives up (the full [timeout] before [start]).
  Duration get remaining {
    final deadline = _deadline;
    if (deadline == null) return timeout;
    final left = deadline.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// True while a `sip/confirm` call is in flight.
  bool get isChecking => _inFlight != null;

  /// True once [onFinished] has fired (or after [dispose]).
  bool get isDone => _finished || _disposed;

  /// Starts the countdown; the first check runs after [pollInterval] (the
  /// request has only just been sent).
  void start() {
    if (_deadline != null || isDone) return;
    _deadline = _now().add(timeout);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _schedule();
  }

  /// Checks right away — "I've approved it", or the app coming back from the
  /// UPI app. Joins the check already in flight instead of starting another.
  Future<void> pollNow() {
    if (isDone || _deadline == null) return Future.value();
    final running = _inFlight;
    if (running != null) return running;
    _nextPoll?.cancel();
    return _poll();
  }

  void dispose() {
    _disposed = true;
    _stopTimers();
  }

  void _schedule() {
    _nextPoll?.cancel();
    if (isDone) return;
    _nextPoll = Timer(pollInterval, _poll);
  }

  Future<void> _poll() {
    // Marked in flight before the call starts, so a confirm() that throws
    // synchronously still clears it (in _runPoll) instead of leaving a stale
    // future behind.
    final done = Completer<void>();
    _inFlight = done.future;
    _runPoll().whenComplete(done.complete);
    return done.future;
  }

  Future<void> _runPoll() async {
    AirpayMandateUpdate update;
    try {
      update = AirpayMandateUpdate.fromResponse(await confirm());
    } catch (e) {
      update = AirpayMandateUpdate.fromError(e);
    }
    _inFlight = null;
    if (isDone) return;
    if (update.status != AirpayMandateStatus.pending) {
      _finish(update);
    } else if (remaining == Duration.zero) {
      _finish(const AirpayMandateUpdate(AirpayMandateStatus.timedOut));
    } else {
      _schedule();
    }
  }

  void _tick() {
    if (isDone) return;
    final left = remaining;
    onTick?.call(left);
    // A check in flight decides: it finishes as active/failed, or as
    // timedOut when it comes back pending (see _runPoll).
    if (left == Duration.zero && _inFlight == null) {
      _finish(const AirpayMandateUpdate(AirpayMandateStatus.timedOut));
    }
  }

  void _finish(AirpayMandateUpdate update) {
    if (isDone) return;
    _finished = true;
    _stopTimers();
    onFinished(update);
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    _nextPoll?.cancel();
    _nextPoll = null;
  }
}
