import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/error/failures.dart';
import 'package:startgold/features/sip/utils/airpay_mandate_poller.dart';

Map<String, dynamic> pending() => {
      'success': true,
      'message': 'Authorization pending bank approval',
      'data': {'subscription_id': 'SUB_1', 'status': 'BANK_APPROVAL_PENDING'},
    };

Map<String, dynamic> active() => {
      'success': true,
      'message': 'Subscription authorized successfully',
      'data': {
        'subscription_id': 'SUB_1',
        'status': 'ACTIVE',
        'mandate_status': 'ACTIVE',
      },
    };

/// sip/confirm refuses a declined / expired request with HTTP 400, which
/// ApiClient throws like this.
ServerFailure declined() => ServerFailure(
      message: 'Mandate authorization failed. Please try again.',
      statusCode: 400,
    );

/// A poller on a fake clock, with a scripted sip/confirm.
///
/// Runs inside testWidgets, whose fake async zone drives the poller's timers
/// via tester.pump — and fails the test if any timer is left running.
class Harness {
  DateTime clock = DateTime(2026, 11, 10, 12);
  int calls = 0;

  /// Answers in order (a Map, or an error to throw); the last one repeats.
  final List<Object> answers;

  /// When set, sip/confirm hangs on this instead.
  Completer<Map<String, dynamic>>? hold;

  final finished = <AirpayMandateUpdate>[];
  final ticks = <Duration>[];
  late final AirpayMandatePoller poller;

  Harness(this.answers, {Duration timeout = const Duration(minutes: 10)}) {
    poller = AirpayMandatePoller(
      confirm: () {
        calls++;
        final h = hold;
        if (h != null) return h.future;
        final a = answers.length > 1 ? answers.removeAt(0) : answers.first;
        return a is Map<String, dynamic> ? Future.value(a) : Future.error(a);
      },
      onFinished: finished.add,
      onTick: ticks.add,
      timeout: timeout,
      now: () => clock,
    );
  }

  /// Moves the clock and the timers forward one second at a time.
  Future<void> advance(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

void main() {
  group('reading sip/confirm', () {
    test('ACTIVE is approved, BANK_APPROVAL_PENDING keeps waiting', () {
      expect(AirpayMandateUpdate.fromResponse(active()).status,
          AirpayMandateStatus.active);
      expect(AirpayMandateUpdate.fromResponse(pending()).status,
          AirpayMandateStatus.pending);
    });

    test('success=false is a failure with the server message', () {
      final u = AirpayMandateUpdate.fromResponse({
        'success': false,
        'error': {
          'code': 'SIP_CONFIRM_FAILED',
          'message': 'Mandate authorization failed. Please try again.',
        },
      });
      expect(u.status, AirpayMandateStatus.failed);
      expect(u.message, 'Mandate authorization failed. Please try again.');
    });

    test('an unknown status on success is a failure, not an endless wait', () {
      final u = AirpayMandateUpdate.fromResponse({
        'success': true,
        'data': {'status': 'CUSTOMER_CANCELLED'},
      });
      expect(u.status, AirpayMandateStatus.failed);
      expect(u.message, 'Authorization status: CUSTOMER_CANCELLED');
    });

    test('an HTTP 400 refusal ends the wait with its message', () {
      final u = AirpayMandateUpdate.fromError(declined());
      expect(u.status, AirpayMandateStatus.failed);
      expect(u.message, 'Mandate authorization failed. Please try again.');
    });

    test('network errors, 5xx and odd errors are just a missed check', () {
      for (final e in [
        NetworkFailure(),
        ServerFailure(message: 'Server temporarily unavailable', statusCode: 502),
        ServerFailure(message: 'Something went wrong. Please try again.'),
        InvalidResponseFailure(),
        Exception('boom'),
      ]) {
        expect(AirpayMandateUpdate.fromError(e).status,
            AirpayMandateStatus.pending,
            reason: '$e');
      }
    });

    test('a dead session ends the wait', () {
      expect(AirpayMandateUpdate.fromError(SessionInvalidatedFailure()).status,
          AirpayMandateStatus.failed);
    });
  });

  group('polling', () {
    testWidgets('asks every 5 seconds and stops on ACTIVE', (tester) async {
      final h = Harness([pending(), pending(), active()]);
      h.poller.start();

      await h.advance(tester, 4);
      expect(h.calls, 0, reason: 'the request was only just sent');
      await h.advance(tester, 1);
      expect(h.calls, 1);
      await h.advance(tester, 5);
      expect(h.calls, 2);
      expect(h.finished, isEmpty);
      await h.advance(tester, 5);
      expect(h.calls, 3);
      expect(h.finished.single.status, AirpayMandateStatus.active);
      expect(h.finished.single.response['data']['subscription_id'], 'SUB_1');

      await h.advance(tester, 60);
      expect(h.calls, 3, reason: 'no polling after the answer');
      expect(h.finished, hasLength(1));
    });

    testWidgets('a decline ends the wait with the server message',
        (tester) async {
      final h = Harness([declined()]);
      h.poller.start();
      await h.advance(tester, 5);
      expect(h.finished.single.status, AirpayMandateStatus.failed);
      expect(h.finished.single.message,
          'Mandate authorization failed. Please try again.');
      await h.advance(tester, 30);
      expect(h.calls, 1);
    });

    testWidgets('a network error is retried on the next poll', (tester) async {
      final h = Harness([NetworkFailure(), active()]);
      h.poller.start();
      await h.advance(tester, 5);
      expect(h.finished, isEmpty);
      await h.advance(tester, 5);
      expect(h.calls, 2);
      expect(h.finished.single.status, AirpayMandateStatus.active);
    });

    testWidgets('a confirm that throws straight away is retried too',
        (tester) async {
      var calls = 0;
      final finished = <AirpayMandateUpdate>[];
      final poller = AirpayMandatePoller(
        confirm: () {
          calls++;
          if (calls == 1) throw NetworkFailure();
          return Future.value(active());
        },
        onFinished: finished.add,
      );
      poller.start();
      await tester.pump(const Duration(seconds: 5));
      expect(poller.isChecking, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 2);
      expect(finished.single.status, AirpayMandateStatus.active);
    });

    testWidgets('gives up after 10 minutes and counts down to zero',
        (tester) async {
      final h = Harness([pending()]);
      h.poller.start();
      expect(h.poller.remaining, const Duration(minutes: 10));

      await h.advance(tester, 1);
      expect(h.ticks.last, const Duration(minutes: 9, seconds: 59));

      await h.advance(tester, 598);
      expect(h.finished, isEmpty);
      await h.advance(tester, 1);
      expect(h.finished.single.status, AirpayMandateStatus.timedOut);
      expect(h.poller.remaining, Duration.zero);

      final calls = h.calls;
      expect(calls, greaterThan(100));
      await h.advance(tester, 60);
      expect(h.calls, calls, reason: 'no polling after the time-out');
    });

    testWidgets('time spent away (timers paused) still counts', (tester) async {
      final h = Harness([pending()]);
      h.poller.start();
      // The OS froze the app for 4 minutes while the customer was in the UPI
      // app: the clock moved, the timers didn't.
      h.clock = h.clock.add(const Duration(minutes: 4));
      expect(h.poller.remaining, const Duration(minutes: 6));
      h.poller.dispose();
    });

    testWidgets("\"I've approved it\" checks now and joins a check in flight",
        (tester) async {
      final h = Harness([pending()])..hold = Completer();
      h.poller.start();

      unawaited(h.poller.pollNow());
      final second = h.poller.pollNow();
      expect(h.calls, 1, reason: 'never two checks at once');
      expect(h.poller.isChecking, isTrue);

      h.hold!.complete(pending());
      h.hold = null;
      await second;
      expect(h.poller.isChecking, isFalse);
      expect(h.calls, 1);

      // The regular poll restarts 5 seconds after that answer.
      await h.advance(tester, 4);
      expect(h.calls, 1);
      await h.advance(tester, 1);
      expect(h.calls, 2);
      h.poller.dispose();
    });

    testWidgets('an approval in flight when time runs out still counts',
        (tester) async {
      final h = Harness([pending()], timeout: const Duration(seconds: 12));
      h.poller.start();
      await h.advance(tester, 5); // first check: pending
      h.hold = Completer();
      await h.advance(tester, 5); // second check hangs
      await h.advance(tester, 3); // time is up meanwhile
      expect(h.poller.remaining, Duration.zero);
      expect(h.finished, isEmpty);

      h.hold!.complete(active());
      await tester.pump();
      expect(h.finished.single.status, AirpayMandateStatus.active);
    });

    testWidgets('a pending answer after time ran out is a time-out',
        (tester) async {
      final h = Harness([pending()], timeout: const Duration(seconds: 12));
      h.poller.start();
      await h.advance(tester, 5);
      h.hold = Completer();
      await h.advance(tester, 8);
      expect(h.finished, isEmpty);

      h.hold!.complete(pending());
      await tester.pump();
      expect(h.finished.single.status, AirpayMandateStatus.timedOut);
    });

    testWidgets('dispose stops everything and reports nothing',
        (tester) async {
      final h = Harness([pending()]);
      h.poller.start();
      await h.advance(tester, 5);
      expect(h.calls, 1);

      h.poller.dispose();
      await h.poller.pollNow();
      await h.advance(tester, 700);
      expect(h.calls, 1);
      expect(h.finished, isEmpty);
    });

    testWidgets('an answer arriving after dispose is ignored', (tester) async {
      final h = Harness([pending()])..hold = Completer();
      h.poller.start();
      await h.advance(tester, 5);
      expect(h.calls, 1);
      h.poller.dispose();
      h.hold!.complete(active());
      await tester.pump();
      expect(h.finished, isEmpty);
    });
  });
}
