import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/core/network/api_client.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class RefereeItem {
  final String referee;
  final String referralDate;
  final String reward;
  final String quantity;
  final String status;
  final int? statusCode;
  final String rewardStatus;

  const RefereeItem({
    required this.referee,
    required this.referralDate,
    required this.reward,
    required this.quantity,
    required this.status,
    this.statusCode,
    required this.rewardStatus,
  });

  factory RefereeItem.fromJson(Map<String, dynamic> j) => RefereeItem(
        referee: j['referee']?.toString() ?? '',
        referralDate: j['referral_date']?.toString() ?? '',
        reward: j['reward']?.toString() ?? '—',
        quantity: j['quantity']?.toString() ?? '—',
        status: j['status']?.toString() ?? '',
        statusCode: j['status_code'] as int?,
        rewardStatus: j['reward_status']?.toString() ?? '',
      );
}

class RefereeListData {
  final int count;
  final List<RefereeItem> results;

  const RefereeListData({required this.count, required this.results});

  static const empty = RefereeListData(count: 0, results: []);
}

// ── Service ───────────────────────────────────────────────────────────────────

class RefereeListService {
  final ApiClient _apiClient = ApiClient();

  Future<RefereeListData> fetchList() async {
    try {
      final response = await _apiClient.post('referrals/referee-list', data: {});
      final body = response.data;

      if (kDebugMode) debugPrint('═══ REFEREE-LIST STATUS: ${response.statusCode} ═══');

      if (body == null) return RefereeListData.empty;
      if (body is! Map<String, dynamic>) return RefereeListData.empty;
      if (body['success'] != true) return RefereeListData.empty;

      final data = body['data'];
      if (data is! Map<String, dynamic>) return RefereeListData.empty;

      final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
      final rawResults = data['results'];
      final results = (rawResults is List)
          ? rawResults
              .whereType<Map<String, dynamic>>()
              .map(RefereeItem.fromJson)
              .toList()
          : <RefereeItem>[];

      return RefereeListData(count: count, results: results);
    } catch (e, st) {
      if (kDebugMode) debugPrint('REFEREE-LIST ERROR: $e');
      return RefereeListData.empty;
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final refereeListServiceProvider =
    Provider<RefereeListService>((ref) => RefereeListService());

final refereeListProvider = FutureProvider<RefereeListData>((ref) {
  return ref.read(refereeListServiceProvider).fetchList();
});
