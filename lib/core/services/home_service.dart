import '../network/api_client.dart';
import '../../features/home/models/home_dashboard.dart';
import '../../features/home/models/countdown_offer_model.dart';
import '../security/secure_logger.dart';

class HomeService {
  final ApiClient _apiClient = ApiClient();

  Future<HomeDashboard?> getHomeDashboard(String idMetal) async {
    try {
      final response = await _apiClient.post('home/dashboard', data: {'id_metal': idMetal});
      if (response.data != null && response.data['success'] == true) {
        return HomeDashboard.fromJson(response.data['data']);
      }
      SecureLogger.e('HomeDashboard: success=false. body=${response.data}');
      return null;
    } catch (e, st) {
      SecureLogger.e('HomeDashboard error: $e\n$st');
      rethrow; // let the FutureProvider surface it
    }
  }

  /// Fetches the countdown offer configuration.
  ///
  /// This is public display data (same category as /gold-rate, /schemes)
  /// — NO encryption required per security rules.
  /// On any failure the widget silently hides via [CountdownOfferResponse.disabled].
  Future<CountdownOfferResponse> getCountdownOffer() async {
    try {
      final response = await _apiClient.post('home/countdown-offer');
      if (response.data != null && response.data['success'] == true) {
        return CountdownOfferResponse.fromJson(response.data);
      }
      return CountdownOfferResponse.disabled();
    } catch (e, st) {
      SecureLogger.e('CountdownOffer error: $e\n$st');
      return CountdownOfferResponse.disabled();
    }
  }
}
