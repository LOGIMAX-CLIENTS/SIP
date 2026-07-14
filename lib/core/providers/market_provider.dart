import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/native_socket_service.dart';
import '../../features/market/models/market_rates.dart';
import '../services/shared_service.dart';
import 'environment_provider.dart';

// Provides the singleton instance of the service
final socketIOServiceProvider = Provider<NativeSocketService>((ref) {
  ref.watch(environmentProvider); // Recreate service when environment changes
  final service = NativeSocketService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provides the stream of rates
final marketRatesStreamProvider = StreamProvider<MarketRates>((ref) {
  final service = ref.watch(socketIOServiceProvider);

  // Watch commodities to dynamic update socket IDs
  final commodities = ref.watch(commoditiesProvider).valueOrNull;
  if (commodities != null) {
    String? gId;
    String? sId;
    String? gName;
    String? sName;
    for (var c in commodities) {
      if (c.name.toLowerCase().contains('gold')) {
        // Use c.id (id_metal field: '1') — this matches socket parts[1].
        // Do NOT use c.webSocketId (web_soc_id: 91) — socket does NOT use it.
        gId = c.id.isNotEmpty ? c.id : '1';
        gName = c.name;
      }
      if (c.name.toLowerCase().contains('silver')) {
        sId = c.id.isNotEmpty ? c.id : '3';
        sName = c.name;
      }
    }
    if (gId != null && sId != null && gName != null && sName != null) {
      service.updateCommodityConfig(gId, gName, sId, sName);
    }
  }

  // Auto-connect when this provider is first watched
  service.connect();
  return service.ratesStream;
});

// Provides the connection status
final socketStatusProvider = StreamProvider<SocketStatus>((ref) {
  final service = ref.watch(socketIOServiceProvider);
  return service.statusStream;
});

/// Provides per-commodity market open/close status from the socket.
/// Key   = commodity ID string (e.g. '1' for Gold 24K, '3' for Silver).
/// Value = true (open) / false (closed).
/// Commodity absent from map → assume open (no signal received yet).
final marketStatusProvider = StreamProvider<Map<String, bool>>((ref) {
  final service = ref.watch(socketIOServiceProvider);
  return service.marketStatusStream;
});
