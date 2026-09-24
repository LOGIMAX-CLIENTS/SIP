import '../../core/network/api_client.dart';
import '../../core/security/secure_logger.dart';

/// Service for fetching jewellery category images.
///
/// Calls `GET /jewellery/jewellery-image` which returns a list of image URLs.
/// This is public display data — NO encryption required.
class JewelleryService {
  final ApiClient _apiClient = ApiClient();

  /// Returns a list of image URL strings from the API.
  ///
  /// Response: `{success: true, data: [{image_url: "..."}, ...]}`
  Future<List<String>> getJewelleryImages() async {
    try {
      final response = await _apiClient.post('jewellery/jewellery-image');
      if (response.data != null &&
          response.data['success'] == true &&
          response.data['data'] is List) {
        final list = response.data['data'] as List;
        return list
            .where((item) => item is Map && item['image_url'] != null)
            .map<String>((item) => item['image_url'] as String)
            .toList();
      }
      SecureLogger.e('JewelleryImages: unexpected response format');
      return [];
    } catch (e, st) {
      SecureLogger.e('JewelleryImages error: $e\n$st');
      rethrow;
    }
  }
}
