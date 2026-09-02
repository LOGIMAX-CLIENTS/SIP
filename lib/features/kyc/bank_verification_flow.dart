import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../profile/models/bank_account.dart';
import '../profile/services/bank_details_service.dart';
import '../../shared/widgets/add_bank_account_sheet.dart';
import '../../routes/app_router.dart';

/// Single entry point for "the backend returned BANK_VERIFICATION_REQUIRED"
/// (or eligibility's matching next_step) across SIP, Withdrawal, and
/// Investment — mirrors [KycVerificationFlow]'s role, but for the bank
/// verification gate (backend: `bank_payability()` /
/// VerificationGatewayRouting's BAV mandatory flag).
///
/// Routes the customer to whichever step they actually need:
///   - no bank account at all      → Add Bank Account (which itself does
///                                    penny-drop verification as part of
///                                    adding — see add_bank_account_sheet.dart)
///   - an account exists, unverified → straight into ₹1 Reverse Penny Drop
///                                    for THAT account
/// Every caller uses the same `await ...; if (result) retryTheOriginalAction()`
/// shape as KycVerificationFlow.start().
class BankVerificationFlow {
  /// Returns true once the customer has at least one verified bank
  /// account. Returns false if they back out before finishing.
  static Future<bool> start(BuildContext context, WidgetRef ref) async {
    final unverified = await _firstUnverifiedOrNull(ref);

    if (unverified == null) {
      // Either every account is already verified (nothing to do — treat as
      // already satisfied) or there are no accounts at all (add one).
      final accounts = await _loadAccounts(ref);
      if (accounts.isNotEmpty) return true;

      if (!context.mounted) return false;
      var added = false;
      await showAddBankAccountSheet(
        context,
        ref,
        isDark: Theme.of(context).brightness == Brightness.dark,
        onAdded: () => added = true,
      );
      // Adding a bank account already runs penny-drop verification as part
      // of the same sheet (see add_bank_account_sheet.dart's docstring), so
      // a successful add IS a verified account — no separate RPD hop needed.
      return added;
    }

    if (!context.mounted) return false;
    final verified = await Navigator.pushNamed(
      context,
      AppRouter.reversePennyDrop,
      arguments: {'cbankId': unverified.idBank},
    );
    if (verified == true) {
      ref.invalidate(bankAccountsProvider);
      return true;
    }
    return false;
  }

  static Future<List<BankAccount>> _loadAccounts(WidgetRef ref) async {
    ref.invalidate(bankAccountsProvider);
    try {
      return await ref.read(bankAccountsProvider.future);
    } catch (_) {
      return const [];
    }
  }

  static Future<BankAccount?> _firstUnverifiedOrNull(WidgetRef ref) async {
    final accounts = await _loadAccounts(ref);
    for (final account in accounts) {
      if (!account.isVerified) return account;
    }
    return null;
  }
}
