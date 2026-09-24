---
module: Profile
last_updated: 2026-08-19
---

# Profile — Coverage Tracker

## Round 1 — Full Build (2026-08-19)

**Mode**: Build (brain status was ⬜ → this round).

**Source read**: 17/17 `.dart` files under `lib/features/profile/` (100%), plus 4 cross-module files read
in full to ground the BAV/Add-Bank-Account flow and encryption gating: `shared/widgets/add_bank_account_sheet.dart`,
`features/withdrawal/services/withdrawal_service.dart` (the `verifyAndAddBank` method + surrounding
context), `core/providers/user_provider.dart`, `core/security/api_interceptor.dart` +
`core/config/app_config.dart` (encryption/sensitive-field config). Also read `lib/routes/app_router.dart`
in full for the route table, `core/security/screenshot_security_service.dart` for the security posture
claim, and `core/security/secure_storage_service.dart`'s `logout()` for the deletion-wipe claim.

### Weighted Coverage Computation

| Dimension | Weight | Count found | Count documented | Score |
|---|---|---|---|---|
| Screens documented | 25% | 9 screens (`profile_screen.dart`, `account_details_screen.dart`, `bank_details_screen.dart`, `bank_verification_hub_screen.dart`, `bav_history_screen.dart`, `penny_verify_history_screen.dart`, `refund_history_screen.dart`, `bank_penny_verify_screen.dart`, `delete_account_screen.dart`) | 9/9 | 25% |
| Controller/service public methods | 25% | 21 (`ProfileNotifier` 6, `ProfileService` 4, `DeleteAccountService` 2, `BankDetailsService` 4, `BankPennyVerifyService` 2, `BankVerificationHistoryService` 2, `BankVerificationCard.build` 1) | 21/21 | 25% |
| Models documented | 15% | 7 (`UserProfile`, `ProfileState` in `profile_controller.dart`; `BankAccount`; `BavHistoryItem`, `PennyVerifyHistoryItem`, `BankTimelineEntry`, `BankVerificationCard` in `bank_verification_history.dart`) | 7/7 | 15% |
| API endpoints documented | 15% | 15 (14 in-module + 1 cross-module creation call) | 15/15 | 15% |
| Business rules captured | 10% | 10 rules (`RULE-PROFILE-001`–`010`), spanning edit validation, verification badge, BAV gating, soft-delete, GDPR deletion gate/confirm/wipe, and the critical endpoint-path bug | Comprehensive | 10% |
| Cross-module deps captured | 10% | `core/` deps table, other-features deps table, reverse-deps table (SIP + KYC), Mermaid graph, Known Violations section | Comprehensive | 10% |

**Total: 100%** → 🔵

### Manual Spot-Check (workflow requirement for 🔵: re-verify 2-3 claims against a fresh read)

1. **`profile_controller.dart:334-345`** — re-read the `profileProvider` factory: confirmed it watches
   `userProvider.select((u) => u?.id)`, not the whole object, exactly as documented in
   `MODULE_BRAIN.md` §4 and `STATE_ANALYSIS.md`. Comment text matches verbatim.
2. **`withdrawal_service.dart:106`** — re-read the literal `'account\verify-bank'`; confirmed no `r` raw-
   string prefix, confirming the `\v` vertical-tab escape interpretation cited in RULE-PROFILE-010 is
   correct per Dart's string-escape grammar (not a formatting artifact of the Read tool).
3. **`models/bank_verification_history.dart:163-241`** — re-read `BankVerificationCard.build()`; confirmed
   the oldest-first sort of `bav` before pairing, and newest-first sort of the final `cards` list, matches
   the description in `DATA_FLOW.md` Flow 3 and the "unconfirmed edge case" caveat about no shared attempt
   id between the two backend tables.

All three checks confirmed the docs accurately reflect the source at the cited lines.

### Drift Found vs `STARTGOLD_DOCUMENTATION.md` §3.29–3.31

- Hand-written doc lists 3 screens; live code has 9. The entire Bank Details / Bank Account Verification
  surface (6 of the 9 screens) is undocumented there — added after the 2026-05-20 doc date per its own
  footer. Recorded in `MODULE_BRAIN.md` §1 and reported to `_OVERVIEW/BUILD_SUMMARY.md` (this round).
- Hand-written doc's one-line "Delete Account — GDPR/regulatory account deletion" purpose string is
  accurate as far as it goes but omits the mechanism entirely (info/is_allowed gate, confirm dialog,
  client-side wipe vs. server-side deletion) — now covered in `DATA_FLOW.md` Flow 4 and
  `BUSINESS_RULES.md` RULE-PROFILE-008/009.

### New Cross-Module Deps Discovered (not previously documented anywhere)

- SIP's `BankAccountPickerScreen` directly importing Profile's `bankAccountsProvider`/`BankAccount`.
- KYC's `kyc_flow.dart` directly importing Profile's `profile_controller.dart`.
- Profile's Add-Bank-Account flow calling into Withdrawal's `WithdrawalService.verifyAndAddBank()` via the
  shared `add_bank_account_sheet.dart` widget.
- `BankPennyVerifyScreen` reusing InstantSaving's `PaymentMethodSheet`.

### Flagged For `_SYSTEM/` Synthesis

- **DANGER_ZONES candidate**: RULE-PROFILE-010 (corrupted endpoint path via unescaped Dart string) —
  pattern worth a repo-wide grep (`\\[a-z]` inside non-raw string literals used as API paths) since a
  sibling instance (`'referrals\reward-balance'`) was found in the same file during this pass.
- **DIAGNOSTIC_PLAYBOOK candidate**: FORENSIC_TEMPLATE.md entries 1 and 2 (Add Bank Account failing /
  stuck pending) — high-value symptom-to-suspect mapping given the endpoint bug's blast radius (affects
  both Profile and SIP).

## Next Round Trigger

Refresh when any file under `lib/features/profile/` changes after 2026-08-19, or when
`withdrawal_service.dart:106`'s endpoint string is fixed (re-verify RULE-PROFILE-010 is resolved and update
BUSINESS_RULES.md / FORENSIC_TEMPLATE.md accordingly rather than leaving stale bug documentation).
