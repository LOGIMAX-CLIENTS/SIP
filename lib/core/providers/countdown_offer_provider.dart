import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/home_service.dart';
import '../../features/home/models/countdown_offer_model.dart';
import 'home_dashboard_provider.dart';
import 'user_provider.dart';

/// Fetches the countdown offer configuration from the backend.
///
/// Follows the same pattern as [homeDashboardProvider]:
///   • Watches [userProvider] → auto-invalidates on login/logout
///   • Returns [CountdownOfferResponse.disabled] for unauthenticated users
///   • Uses [homeServiceProvider] for the API call
///   • `autoDispose` — cleans up when no longer watched
final countdownOfferProvider =
    FutureProvider.autoDispose<CountdownOfferResponse>((ref) async {
  final user = ref.watch(userProvider);
  if (user == null || user.id.isEmpty) return CountdownOfferResponse.disabled();

  final service = ref.watch(homeServiceProvider);
  return service.getCountdownOffer();
});
