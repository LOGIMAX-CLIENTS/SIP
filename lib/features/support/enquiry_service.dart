import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/core/network/api_client.dart';

// ── Type mapping: label → API integer ────────────────────────────────────────
const Map<String, int> kTicketTypes = {
  'Enquiry': 1,
  'Support': 2,
  'Review': 3,
  'Auto Savings': 5,
  'Others': 4,
};

// ── Response model from create-ticket ────────────────────────────────────────
class SupportTicket {
  final String id;
  final String submittedOn;
  final String type;
  final String subject;
  final String content;
  final String status;

  const SupportTicket({
    required this.id,
    required this.submittedOn,
    required this.type,
    required this.subject,
    required this.content,
    required this.status,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id']?.toString() ?? '',
        submittedOn: json['on'] ?? '',
        type: json['type'] ?? '',
        subject: json['subject'] ?? '',
        content: json['content'] ?? '',
        status: json['status'] ?? 'pending',
      );
}

// ── Legacy model used by enquiry_list_screen ──────────────────────────────────
class Enquiry {
  final String enquiryId;
  final String type;
  final String subject;
  final String content;
  /// Admin's reply/resolution note (sr_comments on the backend) — empty
  /// until an admin actually responds, never null.
  final String comments;
  final String status;
  final String createdAt;
  final String lastUpdate;

  Enquiry({
    required this.enquiryId,
    this.type = '',
    required this.subject,
    this.content = '',
    this.comments = '',
    required this.status,
    required this.createdAt,
    this.lastUpdate = '',
  });

  factory Enquiry.fromJson(Map<String, dynamic> json) => Enquiry(
        // id field can come as int or string
        enquiryId:
            json['id']?.toString() ?? json['enquiry_id']?.toString() ?? '',
        type: json['type'] ?? '',
        subject: json['subject'] ?? '',
        content: json['content'] ?? '',
        comments: json['comments'] ?? '',
        status: json['status'] ?? 'pending',
        // "on" is the date field from create-ticket response
        createdAt: json['on'] ?? json['created_at'] ?? '',
        lastUpdate: json['last_update'] ?? json['on'] ?? '',
      );
}

// ── Service ───────────────────────────────────────────────────────────────────
class EnquiryService {
  final ApiClient _apiClient = ApiClient();

  /// POST support/create-ticket
  /// Payload: { type: int, subject: string, content: string }
  Future<Map<String, dynamic>> submitEnquiry({
    required int type,
    required String subject,
    required String content,
  }) async {
    final response = await _apiClient.post('support/create-ticket', data: {
      'type': type,
      'subject': subject,
      'content': content,
    });
    return response.data ?? {};
  }

  /// POST support/list — authenticated via bearer token (no body needed)
  Future<List<Enquiry>> getEnquiries() async {
    try {
      final response = await _apiClient.post('support/list', data: {});
      final body = response.data;

      if (kDebugMode) {
        debugPrint('═══ SUPPORT/LIST STATUS: ${response.statusCode} ═══');
        debugPrint('═══ SUPPORT/LIST BODY: $body ═══');
        debugPrint('═══ BODY TYPE: ${body.runtimeType} ═══');
        if (body is Map) {
          body.forEach((k, v) {
            debugPrint('  [$k] (${v.runtimeType}): $v');
          });
        }
      }

      if (body == null) return [];

      // ── Try root-level list first ──────────────────────────────────
      if (body is List) {
        if (kDebugMode)
          debugPrint('SUPPORT: root is List, length=${body.length}');
        return body
            .map((e) => Enquiry.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // ── Root is Map — try common nesting patterns ──────────────────
      if (body is Map<String, dynamic>) {
        // success flag check
        if (body['success'] == false) {
          if (kDebugMode)
            debugPrint('SUPPORT: success=false, msg=${body['message']}');
          return [];
        }

        final dataField = body['data'];
        if (kDebugMode)
          debugPrint('SUPPORT: data field type=${dataField.runtimeType}');

        // data IS a list
        if (dataField is List) {
          if (kDebugMode)
            debugPrint('SUPPORT: data is List, length=${dataField.length}');
          return dataField
              .map((e) => Enquiry.fromJson(e as Map<String, dynamic>))
              .toList();
        }

        // data is a nested map — try every possible key
        if (dataField is Map<String, dynamic>) {
          if (kDebugMode)
            debugPrint(
                'SUPPORT: data is Map, keys=\${dataField.keys.toList()}');
          for (final key in [
            'tickets',
            'enquiries',
            'list',
            'items',
            'data',
            'records'
          ]) {
            final inner = dataField[key];
            if (inner is List) {
              if (kDebugMode)
                debugPrint(
                    'SUPPORT: found list under data[$key], len=\${inner.length}');
              return inner
                  .map((e) => Enquiry.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          }
        }
      }

      if (kDebugMode)
        debugPrint('SUPPORT: no list found in response, returning []');
      return [];
    } catch (e, st) {
      if (kDebugMode) debugPrint('SUPPORT/LIST ERROR: $e\n$st');
      return [];
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────
final enquiryServiceProvider =
    Provider<EnquiryService>((ref) => EnquiryService());

/// Token is managed by ApiInterceptor — no need to gate on userProvider.
/// autoDispose: fires the API call every time the screen opens, and never
/// carries one user's tickets over to the next login.
final enquiriesProvider = FutureProvider.autoDispose<List<Enquiry>>((ref) {
  return ref.read(enquiryServiceProvider).getEnquiries();
});
