import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/withdrawal_method.dart';
import '../../../core/constants/app_constants.dart';

class WithdrawalState {
  final double amount;
  final bool isGrams;
  final WithdrawalMethod? selectedMethod;
  final List<WithdrawalMethod> savedMethods;
  final bool isProcessing;
  final String? error;

  WithdrawalState({
    this.amount = 0,
    this.isGrams = false,
    this.selectedMethod,
    this.savedMethods = const [],
    this.isProcessing = false,
    this.error,
  });

  WithdrawalState copyWith({
    double? amount,
    bool? isGrams,
    WithdrawalMethod? selectedMethod,
    List<WithdrawalMethod>? savedMethods,
    bool? isProcessing,
    String? error,
  }) {
    return WithdrawalState(
      amount: amount ?? this.amount,
      isGrams: isGrams ?? this.isGrams,
      selectedMethod: selectedMethod ?? this.selectedMethod,
      savedMethods: savedMethods ?? this.savedMethods,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error ?? this.error,
    );
  }
}

class WithdrawalNotifier extends StateNotifier<WithdrawalState> {
  WithdrawalNotifier() : super(WithdrawalState());

  /// No-ops once a withdrawal is already in flight (isProcessing) — a
  /// customer who keeps typing (e.g. "5" -> "50") in the same instant they
  /// tap Withdrawal could otherwise land on the confirmation screen with an
  /// amount the policy/eligibility checks never actually validated, since
  /// those screens re-read this same live amount rather than a value
  /// captured at validation time. This guard is a synchronous check against
  /// the CURRENT state, so it holds regardless of whether the calling
  /// screen's TextField has re-rendered as disabled yet.
  void updateAmount(double value) {
    if (state.isProcessing) return;
    state = state.copyWith(amount: value, error: null);
  }

  void selectMethod(WithdrawalMethod? method) {
    state = state.copyWith(selectedMethod: method);
  }

  void setProcessing(bool value) {
    state = state.copyWith(isProcessing: value);
  }

  String? validate(double availableBalanceGrams, double buyPrice) {
    if (state.amount <= 0) return AppConstants.enterValidAmount;

    double amountInGrams =
        state.isGrams ? state.amount : state.amount / buyPrice;

    if (amountInGrams > availableBalanceGrams) {
      return AppConstants.insufficientBalance;
    }

    if (amountInGrams < AppConstants.minWithdrawalGrams) {
      return AppConstants.minWithdrawalError;
    }

    if (amountInGrams > AppConstants.maxWithdrawalGrams) {
      return AppConstants.maxWithdrawalError;
    }

    return null;
  }
}

final withdrawalProvider =
    StateNotifierProvider<WithdrawalNotifier, WithdrawalState>((ref) {
  return WithdrawalNotifier();
});
