import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/commodity_provider.dart';
import '../models/withdrawal_method.dart';
import '../models/withdrawal_policy.dart';
import '../models/withdrawal_balance.dart';

class WithdrawalService {
  final ApiClient _apiClient = ApiClient();

  /// Fetch all saved UPI/bank accounts for the customer.
  Future<List<WithdrawalMethod>> fetchAccountDetails({
    required String customerId,
    required String mobile,
  }) async {
    try {
      final response = await _apiClient.post('profile/accountdetails', data: {
        'id_customer': customerId,
        'mobile': mobile,
      });

      if (response.data != null && response.data['success'] == true) {
        final List data = response.data['data']?['accounts'] ??
            response.data['data']?['upi_list'] ??
            response.data['data'] ??
            [];
        return data.map((e) => WithdrawalMethod.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> submitWithdrawal({
    required String metalId,
    required double amount,
    required double weight,
    required double buyRate,
    required String withdrawalMethodId,
    required String withdrawalMethod,
  }) async {
    try {
      final response = await _apiClient.post('withdrawal/withdraw', data: {
        'id_metal': metalId,
        'amount': amount,
        'weight': weight,
        'buy_rate': buyRate,
        'withdrawal_method_id': withdrawalMethodId,
        'withdrawal_method': withdrawalMethod,
      });
      return response.data ?? {};
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> checkEligibility({
    required String customerId,
    required String mobile,
    required double amount,
    required String metalId,
  }) async {
    try {
      final response =
          await _apiClient.post('savings/check-eligibility', data: {
        'id_customer': customerId,
        'mobile': mobile,
        'id_metal': metalId,
        'amount_inr': amount,
        'request_from': 'withdraw',
      });

      if (response.data != null && response.data['success'] == true) {
        return response.data['data']?['next_step']?.toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Verify and add a UPI handle.
  Future<Map<String, dynamic>> verifyAndAddUpi({
    required String customerId,
    required String mobile,
    required String upiId,
  }) async {
    final response = await _apiClient.post('account/verify-upi', data: {
      'mobile': mobile,
      'upi_id': upiId,
    });
    return response.data ?? {};
  }

  /// Verify and add a bank account.
  Future<Map<String, dynamic>> verifyAndAddBank({
    required String customerId,
    required String mobile,
    required String holderName,
    required String bankName,
    required String accNo,
    required String ifsc,
  }) async {
    final response = await _apiClient.post('account/verify-bank', data: {
      'mobile': mobile,
      'account_holder': holderName,
      'bank_name': bankName,
      'account_no': accNo,
      'ifsc_code': ifsc,
    });
    return response.data ?? {};
  }

  /// GET account/verify-bank/active-method — which BAV method the currently
  /// active KYC verification gateway supports ("cashfree" | "pennyless"),
  /// AND which live-control SECOND step is active ("rpd" | "penny_payment").
  /// Add Bank Account calls this once before verifying so it never
  /// hardcodes a provider name client-side for either step. The second step
  /// is resolved server-side straight off VerificationGatewayRouting(RPD) —
  /// NOT derived from the BAV method here, since a gateway can be routed for
  /// RPD independently of which provider did BAV (see backend
  /// ActiveBankVerificationMethodView).
  Future<({String bavMethod, String secondStepMethod})>
      getActiveBankVerificationMethod() async {
    try {
      final response = await _apiClient.get('account/verify-bank/active-method');
      final data = response.data?['data'] as Map<String, dynamic>?;
      final method = (data?['method'] as String?) ?? 'cashfree';
      final secondStep = (data?['second_step_method'] as String?) ?? 'penny_payment';
      return (
        bavMethod: method == 'pennyless' ? 'pennyless' : 'cashfree',
        secondStepMethod: secondStep == 'rpd' ? 'rpd' : 'penny_payment',
      );
    } catch (_) {
      // Safe default — matches the only-ever-active BAV provider today, and
      // falls back to the existing ₹1-payment flow when the second-step
      // check itself fails.
      return (bavMethod: 'cashfree', secondStepMethod: 'penny_payment');
    }
  }

  /// POST account/verify-bank/contact-admin — "Contact Admin" after a BAV
  /// failure. Records what the customer typed as a case awaiting an admin;
  /// verifies nothing on its own (see backend BankAccountService.
  /// request_manual_review's docstring — no CustomerBank row is created and
  /// no verification status changes). Same raw-map return as
  /// verifyAndAddBank — caller reads result['success'].
  Future<Map<String, dynamic>> requestManualBavReview({
    required String accNo,
    required String ifsc,
    required String holderName,
  }) async {
    final response = await _apiClient.post('account/verify-bank/contact-admin', data: {
      'account_no': accNo,
      'ifsc_code': ifsc,
      'account_holder': holderName,
    });
    return response.data ?? {};
  }

  /// Verify and add a bank account via SurePass "pennyless" BAV — instant,
  /// no ₹1 transferred. Alternative to [verifyAndAddBank] (Cashfree penny
  /// drop); only succeeds when SurePass is the active KYC verification
  /// gateway (see backend BankVerificationSurePassService.verify_pennyless).
  Future<Map<String, dynamic>> verifyAndAddBankPennyless({
    required String holderName,
    required String accNo,
    required String ifsc,
  }) async {
    final response = await _apiClient.post('account/verify-bank/pennyless', data: {
      'account_holder': holderName,
      'account_no': accNo,
      'ifsc_code': ifsc,
    });
    return response.data ?? {};
  }

  /// Fetch withdrawable balance for the selected metal.
  /// Endpoint: POST referrals/reward-balance
  /// Payload:  { "id_metal": "1" }
  /// Response: data is a List — returns first element containing
  ///   withdrawable_qty, total_qty, on_hold_qty, commodity_name.
  Future<Map<String, dynamic>> fetchRewardBalance({
    required String metalId,
  }) async {
    try {
      final response =
          await _apiClient.post('referrals/reward-balance', data: {
        'id_metal': metalId,
      });
      if (response.data != null && response.data['success'] == true) {
        final rawData = response.data['data'];
        if (rawData is List && rawData.isNotEmpty) {
          return Map<String, dynamic>.from(rawData.first);
        }
        if (rawData is Map) {
          return Map<String, dynamic>.from(rawData);
        }
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Fetch the Total Holding / Requested / On Hold / Withdrawable breakdown
  /// for every commodity the customer holds.
  /// Endpoint: GET /withdrawal/eligibility
  Future<List<WithdrawalBalance>> fetchWithdrawalEligibility() async {
    final response = await _apiClient.get('withdrawal/eligibility');
    if (response.data != null && response.data['success'] == true) {
      final holdings = response.data['data']?['holdings'] as List? ?? [];
      return holdings
          .map((e) => WithdrawalBalance.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw Exception(
        response.data?['message'] ?? 'Failed to fetch withdrawal balance');
  }

  /// Fetch withdrawal policy for a given metal + amount.
  /// Endpoint: POST withdrawal/policy
  /// Payload:  { "id_metal": 1, "amount": 1000.00 }
  Future<WithdrawalPolicy> fetchWithdrawalPolicy({
    required int metalId,
    required double amount,
  }) async {
    final response = await _apiClient.post('withdrawal/policy', data: {
      'id_metal': metalId,
      'amount': amount,
    });
    if (response.data != null && response.data['success'] == true) {
      final data = response.data['data'] as Map<String, dynamic>? ?? {};
      return WithdrawalPolicy.fromJson(data);
    }
    throw Exception(
        response.data?['message'] ?? 'Failed to fetch withdrawal policy');
  }
}

final withdrawalServiceProvider = Provider((ref) => WithdrawalService());

/// Provider that fetches saved accounts (UPI + Bank) from `accountdetails` API.
final accountDetailsProvider =
    FutureProvider.autoDispose<List<WithdrawalMethod>>((ref) {
  final user = ref.watch(userProvider);
  if (user == null) return const [];
  return ref.read(withdrawalServiceProvider).fetchAccountDetails(
        customerId: user.id,
        mobile: user.mobile,
      );
});

/// Fetches the referral reward balance for the currently selected metal.
/// Auto-disposes and rebuilds whenever the commodity tab changes.
final rewardBalanceProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  final metalId = ref.watch(selectedMetalIdProvider);
  return ref.read(withdrawalServiceProvider).fetchRewardBalance(
        metalId: metalId,
      );
});

// ── Withdrawal Balance (Total Holding / Requested / On Hold / Withdrawable) ──

/// Raw per-commodity breakdown for every holding the customer has.
/// Auto-disposes and rebuilds whenever the commodity tab changes (same
/// invalidation trigger as [rewardBalanceProvider], which this replaces as
/// the withdrawal screen's balance source).
final withdrawalEligibilityProvider =
    FutureProvider.autoDispose<List<WithdrawalBalance>>((ref) {
  ref.watch(selectedMetalIdProvider); // rebuild on commodity switch
  return ref.read(withdrawalServiceProvider).fetchWithdrawalEligibility();
});

/// The breakdown row for the currently selected metal only — what the
/// withdrawal screen actually displays and validates against.
final withdrawalBalanceProvider =
    FutureProvider.autoDispose<WithdrawalBalance>((ref) async {
  final metalId = ref.watch(selectedMetalIdProvider);
  final holdings = await ref.watch(withdrawalEligibilityProvider.future);
  return holdings.firstWhere(
    (h) => h.commodityId?.toString() == metalId,
    orElse: () => WithdrawalBalance.empty,
  );
});

// ── Withdrawal Policy ─────────────────────────────────────────────────────

/// Holds the last fetched policy. Call [WithdrawalPolicyNotifier.fetch] to
/// refresh (on screen load and every amount change).
class WithdrawalPolicyNotifier
    extends AutoDisposeAsyncNotifier<WithdrawalPolicy?> {
  @override
  Future<WithdrawalPolicy?> build() async => null; // idle until first fetch

  Future<void> fetch({required int metalId, required double amount}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() =>
        ref.read(withdrawalServiceProvider).fetchWithdrawalPolicy(
              metalId: metalId,
              amount: amount,
            ));
  }
}

final withdrawalPolicyProvider = AsyncNotifierProvider.autoDispose<
    WithdrawalPolicyNotifier, WithdrawalPolicy?>(
  WithdrawalPolicyNotifier.new,
);
