import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/session_invalidated_dialog.dart';
import '../providers/market_provider.dart';
import 'secure_logger.dart';
import 'secure_storage_service.dart';
import 'session_manager.dart';

/// Logs this device out the moment a login on another device ends its
/// session, instead of on its next API call (the 409 in api_interceptor.dart).
///
/// An OTP login announces every session it ended on the live-rate socket as
/// `9|<sha256 of session_id>` (backend: shared/services/ended_session_push.py).
/// Every connected app receives every announcement; the one whose access
/// token carries that session_id takes the same force-logout path as a 409.
class SessionEndedListener {
  SessionEndedListener._();

  /// Whether [sessionHash] names the session this device is logged in with.
  static Future<bool> isThisSession(String sessionHash) async {
    if (SessionManager.isForceLoggedOut || SessionManager.isLoggingIn) {
      return false;
    }
    final sessionId = sessionIdOf(await SecureStorageService.getToken());
    if (sessionId == null) return false;
    return sha256.convert(utf8.encode(sessionId)).toString() == sessionHash;
  }

  static Future<void> onSessionEnded(String sessionHash) async {
    if (!await isThisSession(sessionHash)) return;

    SecureLogger.e('SESSION INVALIDATED: ended by a login on another device');
    // forceLogout() returns false if a 409 got here first (deduplication).
    if (await SessionManager.forceLogout()) {
      await SessionInvalidatedDialog.show();
    }
  }

  /// The `session_id` claim of a JWT, or null if [jwt] has none.
  static String? sessionIdOf(String? jwt) {
    final parts = jwt?.split('.');
    if (parts == null || parts.length != 3) return null;
    try {
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final sessionId = payload is Map ? payload['session_id'] : null;
      return sessionId is String && sessionId.isNotEmpty ? sessionId : null;
    } catch (_) {
      return null;
    }
  }
}

/// Watched at the app root (main.dart). Follows [socketIOServiceProvider],
/// which is rebuilt when the environment changes.
final sessionEndedListenerProvider = Provider<void>((ref) {
  final socket = ref.watch(socketIOServiceProvider);
  final subscription =
      socket.endedSessionStream.listen(SessionEndedListener.onSessionEnded);
  ref.onDispose(subscription.cancel);
  // Announcements only reach a connected socket, so connect on every screen,
  // not only on the ones that show rates.
  socket.connect();
});
