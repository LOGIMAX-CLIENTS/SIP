---
module: Profile
last_updated: 2026-08-19
---

# Profile — State Analysis

## Riverpod Providers

| Provider | Kind | Defined | Watched by | Invalidated/refreshed by |
|---|---|---|---|---|
| `profileProvider` | `StateNotifierProvider<ProfileNotifier, ProfileState>` | `profile_controller.dart:331-345` | `ProfileScreen`, `AccountDetailsScreen`, `kyc_flow.dart` (cross-module) | Never `ref.invalidate`d — updated only via `ProfileNotifier`'s own methods mutating `state`. Rebuilds when `userProvider`'s selected `id` changes (login/logout), not on unrelated auth-state churn. |
| `profileServiceProvider` | `Provider<ProfileService>` | `services/profile_service.dart:123-125` | `profileProvider`'s factory | Static — constructs a fresh `ProfileService(ApiClient())` once |
| `bankAccountsProvider` | `FutureProvider.autoDispose<List<BankAccount>>` | `services/bank_details_service.dart:59-62` | `BankDetailsScreen`, `sip/screens/bank_account_picker_screen.dart` (cross-module) | `ref.invalidate()` after add/remove/set-primary (`bank_details_screen.dart:38,55,252`; `bank_penny_verify_screen.dart:222`); pull-to-refresh calls invalidate too |
| `bankDetailsServiceProvider` | `Provider<BankDetailsService>` | `services/bank_details_service.dart:55` | `bankAccountsProvider`'s factory, `add_bank_account_sheet.dart` | Static |
| `bavHistoryProvider` | `FutureProvider.autoDispose<List<BavHistoryItem>>` | `services/bank_verification_history_service.dart:33-36` | `BankVerificationHubScreen`, `BavHistoryScreen` | Pull-to-refresh invalidate |
| `pennyVerifyHistoryProvider` | `FutureProvider.autoDispose<List<PennyVerifyHistoryItem>>` | `services/bank_verification_history_service.dart:38-43` | `BankVerificationHubScreen`, `PennyVerifyHistoryScreen`, `RefundHistoryScreen` | Pull-to-refresh invalidate on all 3 consuming screens independently |
| `bankVerificationHistoryServiceProvider` | `Provider` | `services/bank_verification_history_service.dart:30-31` | Both history providers' factories | Static |
| `bankPennyVerifyServiceProvider` | `Provider<BankPennyVerifyService>` | `screens/bank_penny_verify_screen.dart:24-25` | `BankPennyVerifyScreen` | Static; defined off-pattern (in a screen file, not `services/`) |
| `_deleteAccountServiceProvider` | `Provider<DeleteAccountService>` (file-private) | `screens/delete_account_screen.dart:17-18` | `_deleteInfoProvider`'s factory, `_onConfirmTap` | Static |
| `_deleteInfoProvider` | `FutureProvider.autoDispose<Map<String,dynamic>>` (file-private) | `screens/delete_account_screen.dart:20-22` | `DeleteAccountScreen` | `ref.refresh()` on the error-state Retry button (`delete_account_screen.dart:434`) |
| `appVersionProvider` | `FutureProvider<String>` | `profile_screen.dart:20-23` | `ProfileScreen` footer | Never invalidated — `PackageInfo` doesn't change at runtime |

## Model Shapes

### `UserProfile` (`profile_controller.dart:6-87`) — Profile module's own, NOT the same class as `core/providers/user_provider.dart`'s `UserProfile`

Two distinct classes share the name `UserProfile` in different files — a naming collision worth knowing
before grepping/importing:
- `core/providers/user_provider.dart::UserProfile` — id, name, mobile, email, photoUrl, isNewUser,
  mpinEnabled, isKycVerified, isVip. Sourced from `authControllerProvider`'s session data.
- `profile_controller.dart::UserProfile` (this module) — id, name, email, isEmailVerified, phone, dob,
  pincode, state, city, address, idCountry, idState, idCity, photoUrl, kycStatus (int),
  referralMessage, lastLoginAt, lastFailedLoginAt. Sourced from `profile/customer_details`. Immutable with
  `copyWith`.

### `ProfileState` (`profile_controller.dart:89-119`)

`{ user: UserProfile, isLoading: bool, isPhotoLoading: bool, isEditing: bool, error: String? }` — separate
loading flags for the main profile fetch/save vs. the photo upload, so a photo upload spinner doesn't block
the Save button and vice versa.

### `BankAccount` (`models/bank_account.dart`)

`{ idBank, bankName, accountNumberMasked, ifscCode, holderName, verificationStatus: "VERIFIED"|"PENDING",
isPrimary }` + `isVerified` getter. Note: `accountNumberMasked` implies the **full account number is never
sent back to the client** after creation — only a server-masked display string. Consistent with
`SKILL.md`'s "sensitive fields never round-trip in the clear where avoidable" spirit, though this specific
masking behavior is server-side, not enforced by this model.

### `BavHistoryItem` (`models/bank_verification_history.dart:2-36`)

`{ kycId: int, status: "Approved"|"Rejected"|"Pending"|..., accountLast4: String?, nameMatched: bool?,
nameMatchScore: double?, attemptedOn: DateTime?, provider: String? }` + `isApproved` getter.

### `PennyVerifyHistoryItem` (`models/bank_verification_history.dart:41-93`)

`{ cbpvId: int, internalOrderId, amount: String, paymentMethod: String?, status:
"Initiated"|"Paid"|"Failed", bankName: String?, accountLast4: String?, createdOn: DateTime?, refundId:
String?, refundStatus: "Not Initiated"|"Pending"|"Success"|"Failed", refundedOn: DateTime?,
gatewayProvider: "Razorpay"|"Cashfree"|String? }` + `isPaid`, `isRefunded` getters. `amount` is a `String`,
not a numeric type — defaults to `'1.00'` if absent; no client-side arithmetic performed on it (only
displayed), so the `SKILL.md` §4 float-equality concern doesn't directly apply here, but a `String` amount
means any future arithmetic on it would need explicit parsing first.

### `BankTimelineEntry` / `BankVerificationCard` / `BankTimelineKind` (`models/bank_verification_history.dart:95-242`)

Client-side-only view models — never serialized from/to JSON, purely a merge/presentation layer over the
two API responses above. `BankVerificationCard.build()` is a pure function (no side effects, no provider
access) — see METHOD_INDEX.md and DATA_FLOW.md Flow 3 for the merge algorithm and its edge-case caveat.

## Secure-Storage Keys Touched By This Module

| Key / operation | Where | Purpose |
|---|---|---|
| `SecureStorageService.setBiometricEnabled(bool)` | `profile_screen.dart:97` | Persist biometric toggle after the 3-guard enable flow (enrolled check → MPIN re-verify → biometric confirm) |
| `SecureStorageService.setMpinEnabled(true)` | `profile_screen.dart:98` | Forced alongside enabling biometrics (biometric auth implies MPIN must also be enabled as fallback) |
| `SecureStorageService.logout()` | `profile_screen.dart` (`_handleLogout` via `authControllerProvider.notifier.logout()`, not called directly), `delete_account_screen.dart:68` | Full secure-storage wipe except `persistent_device_id`/`persistent_device_type`/onboarding-seen flag. **Identical call site for both ordinary logout and account deletion** — no deletion-specific extra wipe. |
| `SharedPreferences.clear()` | `delete_account_screen.dart:71` | Clears non-secure prefs (e.g. language selection) on account deletion — not called on ordinary logout (**unconfirmed** whether that asymmetry is intentional or an oversight, since language preference arguably should survive a logout but the same argument would apply even more to a delete) |

## Notable Edge Cases Visible In Code

- `ProfileScreen._buildSkeleton()` shows a shimmer only while `profileState.isLoading && user.name.isEmpty`
  — a subsequent background refetch (e.g. returning from KYC) does NOT re-show the skeleton, so the screen
  updates in place without a loading flash (`profile_screen.dart:125-127`).
- `AccountDetailsScreen` blocks the Cancel button (not just Save) if mandatory fields are empty while
  editing — you cannot back out of an edit that has emptied Name or produced an invalid Pincode without
  first fixing it (`account_details_screen.dart:274-286`). This is arguably a UX trap: there's no way to
  discard edits and revert to server state without a valid Name/Pincode already present.
- `BankDetailsScreen` shows "Set as Primary" only when an account is both non-primary AND verified
  (`bank_details_screen.dart:221`) — an unverified account can never become primary through this UI.
- Empty-state and error-state are visually distinct across all 4 list-based screens (Bank Details, Hub, BAV
  History, ₹1 History, Refund History) — each has its own empty-copy string, consistent pattern.
