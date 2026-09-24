---
module: Profile
last_updated: 2026-08-19
---

# Profile — Method Index

Alphabetical by class. Public API surface only (private `_`-prefixed helpers omitted unless load-bearing).

## `BankDetailsService` (`services/bank_details_service.dart`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `checkBeneficiaryName` | `Future<Map<String,dynamic>> checkBeneficiaryName(String name)` | 44 | `shared/widgets/add_bank_account_sheet.dart` (on Beneficiary Name field-blur) |
| `fetchBankAccounts` | `Future<List<BankAccount>> fetchBankAccounts()` | 9 | `bankAccountsProvider` (line 61) |
| `removeBank` | `Future<void> removeBank(String idBank)` | 31 | `BankDetailsScreen._confirmRemove` |
| `setPrimary` | `Future<void> setPrimary(String idBank)` | 19 | `BankDetailsScreen._setPrimary` |

## `BankPennyVerifyService` (`services/bank_penny_verify_service.dart`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `confirm` | `Future<Map<String,dynamic>> confirm({required String internalOrderId})` | 37 | `BankPennyVerifyScreen._confirmAndFinish` |
| `initiate` | `Future<Map<String,dynamic>> initiate({required String cbankId, required String paymentMethod})` | 18 | `BankPennyVerifyScreen._startVerification` |

## `ReversePennyDropService` (`services/reverse_penny_drop_service.dart`) — new 2026-08-24

SurePass RPD — optional extra check layered on top of an already Pennyless-verified `CustomerBank` row
(cannot target a specific account by itself; see backend `bank_verification_surepass.py`).

| Method | Signature | Purpose | Callers |
|---|---|---|---|
| `initiate` | `Future<Map<String,dynamic>> initiate({required String cbankId})` | `POST account/verify-bank/rpd/initiate` — returns `client_id`, `payment_link`, `ios_links` | `ReversePennyDropScreen._startVerification` |
| `status` | `Future<Map<String,dynamic>> status({required String clientId})` | `POST account/verify-bank/rpd/status` — server-authoritative re-check, never trusts client state | `ReversePennyDropScreen._checkStatus` |
| `history` | `Future<List<Map<String,dynamic>>> history()` | `GET account/verify-bank/rpd/history` | not yet wired to a screen |

## `WithdrawalService` additions (`features/withdrawal/services/withdrawal_service.dart`) — new 2026-08-24

| Method | Signature | Purpose | Callers |
|---|---|---|---|
| `getActiveBankVerificationMethod` | `Future<String> getActiveBankVerificationMethod()` | `GET account/verify-bank/active-method` — `'cashfree'` \| `'pennyless'`, server-resolved from `gateways_config`; defaults to `'cashfree'` on any error | `add_bank_account_sheet.dart` (before calling verify) |
| `verifyAndAddBankPennyless` | `Future<Map<String,dynamic>> verifyAndAddBankPennyless({required String holderName, required String accNo, required String ifsc})` | `POST account/verify-bank/pennyless` — SurePass instant BAV, alternative to `verifyAndAddBank` | `add_bank_account_sheet.dart` (when active method is `'pennyless'`) |

## `BankVerificationCard` (`models/bank_verification_history.dart`) — static merge logic, not a service

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `build` (static) | `List<BankVerificationCard> build(List<BavHistoryItem> bav, List<PennyVerifyHistoryItem> penny)` | 163 | `BankVerificationHubScreen.build` — pairs BAV rows with the nearest-preceding ₹1-payment row for the same masked account, newest-first |

## `BankVerificationHistoryService` (`services/bank_verification_history_service.dart`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `fetchBavHistory` | `Future<List<BavHistoryItem>> fetchBavHistory()` | 9 | `bavHistoryProvider` (line 35); feeds `BankVerificationHubScreen` + `BavHistoryScreen` |
| `fetchPennyVerifyHistory` | `Future<List<PennyVerifyHistoryItem>> fetchPennyVerifyHistory()` | 20 | `pennyVerifyHistoryProvider` (line 40); feeds `BankVerificationHubScreen` + `PennyVerifyHistoryScreen` + `RefundHistoryScreen` |

## `DeleteAccountService` (`services/delete_account_service.dart`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `confirmDelete` | `Future<void> confirmDelete()` | 22 | `DeleteAccountScreen._onConfirmTap` |
| `fetchDeleteInfo` | `Future<Map<String,dynamic>> fetchDeleteInfo()` | 7 | `_deleteInfoProvider` |

## `ProfileNotifier` (`profile_controller.dart`) — StateNotifier for `profileProvider`

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `checkPincode` | `Future<Map<String,dynamic>> checkPincode(String pincode)` | 196 | `AccountDetailsScreen._handlePincodeCheck` |
| `fetchProfileDetails` | `Future<void> fetchProfileDetails()` | 153 | Constructor (auto-fetch on first build); `AccountDetailsScreen.initState`; `ProfileScreen` after KYC return; `features/kyc/kyc_flow.dart` after KYC completion (cross-module) |
| `setEditing` | `void setEditing(bool editing)` | 191 | `AccountDetailsScreen` Edit/Cancel button; reset in `initState`/`dispose` |
| `updateLocationInfo` | `void updateLocationInfo({required String stateVal, required String city, required String idCountry, required String idState, required String idCity})` | 221 | `AccountDetailsScreen._handlePincodeCheck` (after a successful pincode lookup) |
| `updateProfile` | `Future<bool> updateProfile({required String name, required String email, required String dob, required String pincode, required String stateVal, required String city, required String address})` | 239 | `AccountDetailsScreen._handleSubmit` |
| `updateProfilePhoto` | `Future<bool> updateProfilePhoto(File photo)` | 304 | `AccountDetailsScreen._handlePhotoUpdate` |

## `ProfileService` (`services/profile_service.dart`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `checkPincode` | `Future<Map<String,dynamic>> checkPincode(String pincode)` | 73 | `ProfileNotifier.checkPincode` |
| `getProfileDetails` | `Future<Map<String,dynamic>?> getProfileDetails(String customerId)` | 11 | `ProfileNotifier.fetchProfileDetails` |
| `updateProfile` | `Future<Map<String,dynamic>> updateProfile({required String customerId, ...7 more fields})` | 27 | `ProfileNotifier.updateProfile` |
| `updateProfilePhoto` | `Future<bool> updateProfilePhoto({required File photo, required String customerId})` | 95 | `ProfileNotifier.updateProfilePhoto` |

## Model factory constructors

| Class.method | file:line | Notes |
|---|---|---|
| `BankAccount.fromJson` | `models/bank_account.dart:22` | `isVerified` getter derives from `verificationStatus == 'VERIFIED'` |
| `BavHistoryItem.fromJson` | `models/bank_verification_history.dart:23` | `isApproved` getter |
| `PennyVerifyHistoryItem.fromJson` | `models/bank_verification_history.dart:73` | `isPaid`, `isRefunded` getters |

## Cross-module method this brain must track (lives outside `features/profile/`)

| Method | file:line | Why it matters here |
|---|---|---|
| `WithdrawalService.verifyAndAddBank` | `features/withdrawal/services/withdrawal_service.dart:98-114` | **This is the actual bank-account-creation call** invoked by `shared/widgets/add_bank_account_sheet.dart` on behalf of `BankDetailsScreen`'s "Add Bank Account" flow. Endpoint string is corrupted — see BUSINESS_RULES RULE-PROFILE-010. |
| `showAddBankAccountSheet` | `shared/widgets/add_bank_account_sheet.dart:21` | Shared bottom sheet UI for adding a bank account; entry point from both `BankDetailsScreen._buildAddButton` and SIP's `BankAccountPickerScreen`. |

## Widget (not a method-bearing service, listed for completeness)

`ProfilePhotoWidget` (`widgets/profile_photo_widget.dart`) — `_pickImage`, `_cropImage`, `_showPickerOptions`
are all private; public surface is just the constructor + `onPhotoSelected` callback contract. 5 MB max
file size enforced client-side (`profile_photo_widget.dart:52`), 1024×1024 pick / 512×512 crop.
