import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';

class ContentService {
  final ApiClient _apiClient = ApiClient();

  Future<List<Map<String, dynamic>>> getOnboardingContent() async {
    try {
      final response = await _apiClient.post('users/content/onboarding');
      if (response.data != null &&
          response.data['data'] != null &&
          response.data['data']['slides'] != null) {
        return List<Map<String, dynamic>>.from(response.data['data']['slides']);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getTermsAndConditions() async {
    try {
      final response = await _apiClient.post('content/terms');
      debugPrint('[ContentService] terms raw: ${response.data}');
      return _extractContentMap(response.data);
    } catch (e) {
      debugPrint('[ContentService] terms error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getPrivacyPolicy() async {
    try {
      final response = await _apiClient.post('content/privacy');
      debugPrint('[ContentService] privacy raw: ${response.data}');
      return _extractContentMap(response.data);
    } catch (e) {
      debugPrint('[ContentService] privacy error: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getFAQs() async {
    try {
      final response = await _apiClient.post('content/faqs');
      debugPrint('[ContentService] faqs raw: ${response.data}');
      return _extractFaqList(response.data);
    } catch (e) {
      debugPrint('[ContentService] faqs error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAboutUs() async {
    try {
      final response = await _apiClient.post('content/about-us');
      debugPrint('[ContentService] about-us raw: ${response.data}');
      return _extractContentMap(response.data);
    } catch (e) {
      debugPrint('[ContentService] about-us error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getContactUs() async {
    try {
      final response = await _apiClient.post('content/contact-us');
      debugPrint('[ContentService] contact-us raw: ${response.data}');
      return _extractContentMap(response.data);
    } catch (e) {
      debugPrint('[ContentService] contact-us error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getRefundPolicy() async {
    try {
      final response = await _apiClient.post('content/refund-policy');
      debugPrint('[ContentService] refund-policy raw: ${response.data}');
      return _extractContentMap(response.data);
    } catch (e) {
      debugPrint('[ContentService] refund-policy error: $e');
      rethrow;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Extracts a content map from any of these API response shapes:
  ///   { "data": { "content": "..." } }        ← standard
  ///   { "data": { "body": "..." } }           ← alternative key
  ///   { "content": "..." }                    ← flat
  ///   { "data": "..." }                       ← data is the string itself
  static Map<String, dynamic> _extractContentMap(dynamic raw) {
    if (raw == null) return {};
    final body = raw is Map ? raw : {};

    // Shape: { "data": { ... } }
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);

    // Shape: { "data": "<html>..." }  — wrap string into expected map
    if (data is String) return {'content': data};

    // Shape: flat body already has 'content' key
    if (body.containsKey('content')) {
      return {'content': body['content']};
    }

    return {};
  }

  /// Extracts FAQ list from any of these shapes:
  ///   { "data": { "faqs": [ ... ] } }   ← standard nested
  ///   { "data": [ ... ] }               ← data is the array
  ///   [ ... ]                           ← root is an array
  static List<dynamic> _extractFaqList(dynamic raw) {
    if (raw == null) return [];

    // Root is a list
    if (raw is List) return raw;

    final body = raw is Map ? raw : {};
    final data = body['data'];

    // data is a list directly
    if (data is List) return data;

    // data is a map with a 'faqs' key
    if (data is Map) {
      final faqs = data['faqs'];
      if (faqs is List) return faqs;
      // Sometimes the key might be 'data' inside data
      final nested = data['data'];
      if (nested is List) return nested;
    }

    return [];
  }
}

final contentServiceProvider =
    Provider<ContentService>((ref) => ContentService());

final onboardingContentProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  final service = ref.watch(contentServiceProvider);
  return service.getOnboardingContent();
});

// CMS-backed pages are autoDispose so every screen visit re-fetches from the
// API — admin edits must show up without an app restart.
final termsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(contentServiceProvider).getTermsAndConditions();
});

final privacyPolicyProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(contentServiceProvider).getPrivacyPolicy();
});

final faqsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) {
  return ref.watch(contentServiceProvider).getFAQs();
});

final aboutUsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(contentServiceProvider).getAboutUs();
});

final contactUsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(contentServiceProvider).getContactUs();
});

final refundPolicyProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  return ref.watch(contentServiceProvider).getRefundPolicy();
});

