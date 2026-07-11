import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../features/market/models/market_rates.dart';
import '../security/secure_logger.dart';

enum SocketStatus { connecting, connected, disconnected, error }

class NativeSocketService {
  final String _wsUrl = 'wss://sgbackoffice.startgold.com/ws/'; //  Live
// final String _wsUrl = 'wss://startgoldapp.logimaxindia.com/ws/'; //  Staging
 // final String _wsUrl = 'wss://vaptbackoffice.startgold.com/ws/'; //  VAPT Server
  final List<String> _protocols = [
    '0b286a8b1100f097e7c8e879dbd4174e468a9e92f888e6e289595efdd4747b89'
  ];

  WebSocketChannel? _channel;

  final _ratesController = StreamController<MarketRates>.broadcast();
  final _statusController = StreamController<SocketStatus>.broadcast();
  final _marketStatusController =
      StreamController<Map<String, bool>>.broadcast();

  Stream<MarketRates> get ratesStream async* {
    if (_lastRate != null) {
      yield _lastRate!;
    }
    yield* _ratesController.stream;
  }

  Stream<SocketStatus> get statusStream => _statusController.stream;

  /// Emits the full commodity→open map whenever any commodity status changes.
  /// Key = commodity ID from the socket frame (e.g. '1' for Gold, '3' for Silver).
  /// Value = true (market open) / false (market closed).
  /// Default: commodity not in map = market open (no signal received yet).
  /// Replays the current status to new listeners immediately.
  Stream<Map<String, bool>> get marketStatusStream async* {
    if (_commodityOpenStatus.isNotEmpty) {
      yield Map.from(_commodityOpenStatus);
    }
    yield* _marketStatusController.stream;
  }

  /// Current per-commodity open status (used for UI replay on new listeners).
  Map<String, bool> _commodityOpenStatus = {};

  bool _isDisposed = false;
  MarketRates? _lastRate;
  Timer? _reconnectTimer;
  Timer? _gracePeriodTimer;

  String goldId = '1';
  String silverId = '3';
  String goldName = 'Gold 24KT';
  String silverName = 'Silver 999';

  void updateCommodityConfig(
      String gId, String gName, String sId, String sName) {
    goldId = gId;
    goldName = gName;
    silverId = sId;
    silverName = sName;

    // If we already have rates, update their names and re-emit
    if (_lastRate != null) {
      final updatedRates = _lastRate!.copyWith(
        goldName: gName,
        silverName: sName,
      );
      _lastRate = updatedRates;
      _ratesController.add(updatedRates);
    }
  }

  Future<void> connect() async {
    if (_isDisposed || _channel != null) return;

    _statusController.add(SocketStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse(_wsUrl),
        protocols: _protocols,
      );

      // Provide web compatibility and wait for actual connection via ready future
      await _channel!.ready;

      _statusController.add(SocketStatus.connected);
      SecureLogger.d('NativeSocket: Connected to $_wsUrl');

      _channel!.stream.listen(
        (data) => _handleRateUpdate(data),
        onError: (error) {
          SecureLogger.e('NativeSocket: Error: $error');
          _statusController.add(SocketStatus.error);
          _scheduleReconnect();
        },
        onDone: () {
          SecureLogger.d('NativeSocket: Disconnected');
          _statusController.add(SocketStatus.disconnected);
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      // Grace period: if no explicit 5| market-status frame arrives within
      // 1 second after connecting, infer closed from zero rates.
      _gracePeriodTimer?.cancel();
      _gracePeriodTimer = Timer(const Duration(seconds: 1), () {
        _inferClosedAfterGracePeriod();
      });
    } catch (e) {
      SecureLogger.e('NativeSocket: Connection failed: $e');
      _statusController.add(SocketStatus.error);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _channel?.sink.close();
    _channel = null;
    if (_isDisposed) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect();
    });
  }

  void _handleRateUpdate(dynamic data) {
    try {
      String rawData;

      if (data is String) {
        rawData = data;
      } else if (data is List<int>) {
        rawData = String.fromCharCodes(data);
      } else {
        return; // Ignore unknown payloads
      }

      // ── Step 1: Parse market status (parts[0] == '5') ─────────────
      // Format: 5|commodity_id|commodity_name|market_status
      // market_status: 0 = closed, 1 = open
      // Each commodity tracks its own open/closed state independently.
      for (final line in rawData.split('\n')) {
        final parts = line.split('|');
        if (parts.length >= 4 && parts[0] == '5') {
          final commodityId = parts[1].trim();
          final isOpen = parts[3].trim() == '1';
          // Explicit status received — cancel grace-period inference.
          _gracePeriodTimer?.cancel();

          if (_commodityOpenStatus[commodityId] != isOpen) {
            _commodityOpenStatus = Map.from(_commodityOpenStatus)
              ..[commodityId] = isOpen;

            if (!_marketStatusController.isClosed) {
              _marketStatusController.add(Map.from(_commodityOpenStatus));
            }

            // Zero only the rates for the commodity that just closed.
            // The other commodity's rates are preserved.
            if (!isOpen && !_ratesController.isClosed) {
              final goldClosed = commodityId == goldId;
              final silverClosed = commodityId == silverId;
              final zeroRates = MarketRates(
                goldName: _lastRate?.goldName ?? goldName,
                goldBuy: goldClosed ? 0.0 : (_lastRate?.goldBuy ?? 0.0),
                goldSell: goldClosed ? 0.0 : (_lastRate?.goldSell ?? 0.0),
                goldChange: 0.0,
                goldPercentage: 0.0,
                silverName: _lastRate?.silverName ?? silverName,
                silverBuy: silverClosed ? 0.0 : (_lastRate?.silverBuy ?? 0.0),
                silverSell: silverClosed ? 0.0 : (_lastRate?.silverSell ?? 0.0),
                silverChange: 0.0,
                silverPercentage: 0.0,
                timestamp: DateTime.now(),
                currency: 'INR',
              );
              _lastRate = zeroRates;
              _ratesController.add(zeroRates);
            }

            SecureLogger.d(
              'Market status [commodity $commodityId]: '
              '${isOpen ? "OPEN" : "CLOSED"} '
              '(${parts.length > 2 ? parts[2] : "?"})',
            );
          }
        }
      }

      // ── Step 2: Parse rate data (parts[0] == '3') ─────────────────
      final MarketRates newRates = MarketRates.fromRawString(
        rawData,
        _lastRate,
        goldId: goldId,
        silverId: silverId,
        goldName: goldName,
        silverName: silverName,
      );

      if (_lastRate == null || newRates.isSignificantChange(_lastRate!)) {
        _lastRate = newRates;
        _ratesController.add(newRates);
      }
    } catch (e) {
      SecureLogger.e('NativeSocket: Data parsing error: $e');
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _gracePeriodTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _statusController.add(SocketStatus.disconnected);
  }

  /// Called after the grace period (4s post-connect). For any commodity that
  /// has no explicit 5| status AND rates are still 0, infer market closed.
  void _inferClosedAfterGracePeriod() {
    bool changed = false;

    // Only infer for commodities that have NO explicit 5| status yet.
    if (!_commodityOpenStatus.containsKey(goldId)) {
      final goldZero = _lastRate == null ||
          (_lastRate!.goldBuy <= 0 && _lastRate!.goldSell <= 0);
      if (goldZero) {
        _commodityOpenStatus = Map.from(_commodityOpenStatus)..[goldId] = false;
        changed = true;
        SecureLogger.d(
            'Market fallback: Gold inferred CLOSED (no 5| + zero rates)');
      }
    }

    if (!_commodityOpenStatus.containsKey(silverId)) {
      final silverZero = _lastRate == null ||
          (_lastRate!.silverBuy <= 0 && _lastRate!.silverSell <= 0);
      if (silverZero) {
        _commodityOpenStatus = Map.from(_commodityOpenStatus)
          ..[silverId] = false;
        changed = true;
        SecureLogger.d(
            'Market fallback: Silver inferred CLOSED (no 5| + zero rates)');
      }
    }

    if (changed && !_marketStatusController.isClosed) {
      _marketStatusController.add(Map.from(_commodityOpenStatus));
    }
  }

  void dispose() {
    _isDisposed = true;
    disconnect();
    _ratesController.close();
    _statusController.close();
    _marketStatusController.close();
  }
}
