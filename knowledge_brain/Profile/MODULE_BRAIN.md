---
module: Profile
brain_status: 🟢 (Round 1 build — see COVERAGE_TRACKER.md)
last_updated: 2026-08-19
source_root: lib/features/profile/
files_read: 17/17 (100%) + 4 cross-module files (add_bank_account_sheet.dart, withdrawal_service.dart,
  user_provider.dart, api_interceptor.dart/app_config.dart)
---

# Profile — Module Brain

## 1. What this module actually is

`STARTGOLD_DOCUMENTATION.md` §3.29–3.31 lists 3 screens (Profile, Account Details, Delete Account) for this
module. Live code has **9 screens** across 4 sub-areas — the hand-written doc predates the bank-verification
rebuild. Confirmed drift, not a doc error to "fix" — the doc is just stale (see COVERAGE_TRACKER.md).

| Sub-area | Screens | Doc'd in STARTGOLD_DOCUMENTATION.md? |
|---|---|---|
| Identity | Profile (menu hub), Account Details | Yes |
| Bank accounts | Bank Details (list/add/remove/set-primary) | **No** |
| Bank Account Verification (BAV) | Bank Verification Hub, BAV History, ₹1 Payment History, Refund History, Bank Penny Verify (payment screen) | **No** — entirely undocumented |
| Compliance | Delete Account | Yes (name only, no mechanism detail) |

## 2. Screen & Route Table

| Screen | Route constant | Path | File |
|---|---|---|---|
| ProfileScreen | `AppRouter.profile` | `/profile` | `profile_screen.dart` |
| AccountDetailsScreen | `AppRouter.accountDetails` | `/accountdetails` | `account_details_screen.dart` |
| BankDetailsScreen | `AppRouter.bankDetails` | `/bank-details` | `bank_details_screen.dart` |
| BankVerificationHubScreen | `AppRouter.bankVerificationHub` | `/bank-verification-hub` | `screens/bank_verification_hub_screen.dart` |
| BavHistoryScreen | `AppRouter.bavHistory` | `/bank-verification/bav-history` | `screens/bav_history_screen.dart` |
| PennyVerifyHistoryScreen | `AppRouter.pennyVerifyHistory` | `/bank-verification/penny-history` | `screens/penny_verify_history_screen.dart` |
| RefundHistoryScreen | `AppRouter.refundHistory` | `/bank-verification/refund-history` | `screens/refund_history_screen.dart` |
| BankPennyVerifyScreen | *(no static route — pushed directly via `MaterialPageRoute` with `cbankId` arg from `add_bank_account_sheet.dart`)* | — | `screens/bank_penny_verify_screen.dart` |
| ReversePennyDropScreen *(new, 2026-08-24)* | `AppRouter.reversePennyDrop` | `/reverse-penny-drop` | `screens/reverse_penny_drop_screen.dart` |
| DeleteAccountScreen | `AppRouter.deleteAccount` | `/delete-account` | `screens/delete_account_screen.dart` |

Registered in `lib/routes/app_router.dart:167-169,303,323-326`. Note: `AppRouter.bankVerification`
(`/bank-verification`, `app_router.dart:161-162`) is a **dead stub route** (`Scaffold` placeholder text
"Bank Verification") — not part of this module, superseded by `bankVerificationHub`; nothing navigates to
it. Flag as dead code if seen elsewhere.

`BankVerificationHubScreen` (the merged 3-line-per-card timeline) replaced an earlier "3-card nav hub"
design per its own doc comment (`bank_verification_hub_screen.dart:11-13`) — `BavHistoryScreen`,
`PennyVerifyHistoryScreen`, `RefundHistoryScreen` still exist as separate routes/screens and are still wired
in `app_router.dart`, but nothing in the Profile menu (`profile_screen.dart`) links to them directly — only
`bankVerificationHub` is linked from the menu (`profile_screen.dart:162-167`). The 3 standalone history
screens are reachable only if something deep-links to them; **unconfirmed** whether any surviving caller
exists (grep found none inside `lib/`) — likely leftover from the pre-hub design, worth a dead-route check.

## 3. Architecture

Standard 4-layer stack (Screen → Controller/Notifier → Service → ApiClient), consistent with
`AGENTS.md` §1 and `SKILL.md` §1:

```
ProfileScreen / AccountDetailsScreen ──> ProfileNotifier (profile_controller.dart) ──> ProfileService ──> ApiClient
BankDetailsScreen ──> bankAccountsProvider (FutureProvider) ──> BankDetailsService ──> ApiClient
BankVerificationHubScreen ──> bavHistoryProvider + pennyVerifyHistoryProvider ──> BankVerificationHistoryService ──> ApiClient
BankPennyVerifyScreen ──> bankPennyVerifyServiceProvider ──> BankPennyVerifyService ──> ApiClient
                       └─> Cashfree CFPaymentGatewayService / Razorpay SDK directly (native payment UI)
ReversePennyDropScreen ──> reversePennyDropServiceProvider ──> ReversePennyDropService ──> ApiClient
                        └─> url_launcher opens payment_link directly (no in-app SDK — SurePass RPD is
                            UPI-deep-link only, unlike BankPennyVerifyScreen's Cashfree/Razorpay SDK)
DeleteAccountScreen ──> _deleteInfoProvider / _deleteAccountServiceProvider ──> DeleteAccountService ──> ApiClient
```

**2026-08-24 addition — SurePass bank verification (additive, Cashfree unaffected):**
- `shared/widgets/add_bank_account_sheet.dart` now calls `WithdrawalService.getActiveBankVerificationMethod()`
  (`GET account/verify-bank/active-method`) before verifying, and branches: `'pennyless'` →
  `WithdrawalService.verifyAndAddBankPennyless()` (SurePass, instant, no ₹1 step afterward); `'cashfree'`
  (default) → existing `verifyAndAddBank()` + `BankPennyVerifyScreen` push, unchanged. The active method is
  server-resolved from `gateways_config` (KYC service type) — never hardcoded client-side, so this
  automatically follows whichever gateway is enabled server-side.
- `BankVerificationHubScreen` gained an "Additional Verification (Reverse Penny Drop)" button per card, shown
  only when that card's BAV line is `Verified` AND the backend resolved a live `cbank_id` for it
  (`BavHistoryItem.cbankId`, threaded through `BankTimelineEntry`/`BankVerificationCard` from the now-extended
  `account/verify-bank/bav-history` response). Opens `ReversePennyDropScreen` — an OPTIONAL extra check
  layered on top of Pennyless BAV, not a replacement for it (SurePass's RPD API can't target a specific
  account by itself; see backend `bank_verification_surepass.py` module docstring).

`ProfileNotifier` (`profile_controller.dart:121`) is the only `StateNotifier` in the module; every other
screen uses plain `FutureProvider`/`FutureProvider.autoDispose` + a stateless service call — lighter-weight
than a full controller, appropriate since these are list/detail views without multi-step edit state.

**Anti-pattern check**: no Screen→ApiClient or Service→Widget violations found in this module. One
**cross-feature internals violation** exists (not this module's own code, but reaches into it) — see
CROSS_MODULE_MAP.md "Known Violations".

## 4. State Dependencies (Riverpod)

| Provider | Type | Defined in | Scope |
|---|---|---|---|
| `profileProvider` | `StateNotifierProvider<ProfileNotifier, ProfileState>` | `profile_controller.dart:331` | App-wide singleton (not autoDispose) — persists across navigation |
| `profileServiceProvider` | `Provider<ProfileService>` | `services/profile_service.dart:123` | — |
| `bankAccountsProvider` | `FutureProvider.autoDispose<List<BankAccount>>` | `services/bank_details_service.dart:59` | autoDispose — refetches each visit |
| `bankDetailsServiceProvider` | `Provider<BankDetailsService>` | `services/bank_details_service.dart:55` | — |
| `bavHistoryProvider` | `FutureProvider.autoDispose<List<BavHistoryItem>>` | `services/bank_verification_history_service.dart:33` | — |
| `pennyVerifyHistoryProvider` | `FutureProvider.autoDispose<List<PennyVerifyHistoryItem>>` | `services/bank_verification_history_service.dart:38` | Shared by 3 screens: hub, penny-history, refund-history |
| `bankVerificationHistoryServiceProvider` | `Provider` | same file:30 | — |
| `bankPennyVerifyServiceProvider` | `Provider<BankPennyVerifyService>` | `screens/bank_penny_verify_screen.dart:24` | Defined in the screen file itself, not services/ — inconsistent with the module's usual pattern |
| `reversePennyDropServiceProvider` | `Provider<ReversePennyDropService>` | `screens/reverse_penny_drop_screen.dart` | Same file-local pattern as `bankPennyVerifyServiceProvider` above (deliberately mirrored) |
| `_deleteAccountServiceProvider`, `_deleteInfoProvider` | `Provider` / `FutureProvider.autoDispose` | `screens/delete_account_screen.dart:17-22` | File-private (`_` prefix) |
| `appVersionProvider` | `FutureProvider<String>` | `profile_screen.dart:20` | Reads `PackageInfo.fromPlatform()` |

`profileProvider`'s customer-id scoping (`profile_controller.dart:343`) deliberately watches only
`userProvider.select((u) => u?.id)`, not the whole `UserProfile` object — a documented fix for a rebuild
bug where watching the full object caused the notifier to be torn down and re-fetch on every unrelated
`authControllerProvider` state change (e.g. `sendEmailOtp()`'s loading toggle), blanking Account Details
mid-edit. See `profile_controller.dart:334-343` comment.

## 5. API Endpoints (method + path)

| Endpoint | Method | Caller | Encrypted? |
|---|---|---|---|
| `profile/customer_details` | POST | `ProfileService.getProfileDetails` | No (not in `AppConfig.encryptedEndpoints`) |
| `profile/update` | POST | `ProfileService.updateProfile` | No |
| `users/shared/check-pincode` | POST | `ProfileService.checkPincode` | No |
| `customer/update-profile-photo` | POST (multipart) | `ProfileService.updateProfilePhoto` | No |
| `users/delete-account/info` | POST | `DeleteAccountService.fetchDeleteInfo` | No |
| `users/delete-account` | POST | `DeleteAccountService.confirmDelete` | No |
| `profile/bank-accounts` | POST | `BankDetailsService.fetchBankAccounts` | No |
| `profile/bank-accounts/set-primary` | POST | `BankDetailsService.setPrimary` | No |
| `profile/bank-accounts/remove` | POST | `BankDetailsService.removeBank` | No |
| `account/check-beneficiary-name` | POST | `BankDetailsService.checkBeneficiaryName` | No |
| `account/verify-bank/penny/initiate` | POST | `BankPennyVerifyService.initiate` | No |
| `account/verify-bank/penny/confirm` | POST | `BankPennyVerifyService.confirm` | No |
| `account/verify-bank/bav-history` | GET | `BankVerificationHistoryService.fetchBavHistory` | No |
| `account/verify-bank/penny/history` | GET | `BankVerificationHistoryService.fetchPennyVerifyHistory` | No |
| `account/verify-bank` *(cross-module, see §7)* | POST | `withdrawal_service.dart` `verifyAndAddBank()` | Yes — see RULE-PROFILE-010 correction below |
| `account/verify-bank/active-method` *(new 2026-08-24)* | GET | `withdrawal_service.dart` `getActiveBankVerificationMethod()` | No (no sensitive fields) |
| `account/verify-bank/pennyless` *(new 2026-08-24, cross-module)* | POST | `withdrawal_service.dart` `verifyAndAddBankPennyless()` | Yes (`account_no`/`ifsc_code`, path contains `verify-bank`) |
| `account/verify-bank/rpd/initiate` *(new 2026-08-24)* | POST | `ReversePennyDropService.initiate` | Yes (path contains `verify-bank`) |
| `account/verify-bank/rpd/status` *(new 2026-08-24)* | POST | `ReversePennyDropService.status` | Yes (path contains `verify-bank`) |
| `account/verify-bank/rpd/history` *(new 2026-08-24)* | GET | `ReversePennyDropService.history` | Yes (path contains `verify-bank`) |

None of this module's own endpoints appear in `AppConfig.encryptedEndpoints`
(`core/config/app_config.dart:47-71`) — profile edit (name/email/dob/pincode/address) and bank-account
list/remove/set-primary all travel as plain JSON over TLS, not RSA-payload-encrypted. This matches the
codebase's pattern (encryption is reserved for OTP/MPIN/KYC/payment/investment fields, not general PII
edits) — **not a bug**, but worth knowing before assuming "sensitive-looking" fields are protected the same
way PAN/Aadhaar/bank-account-number are elsewhere. `bank_account_number`, `account_no`, `ifsc_code`,
`upi_id`, `mobile` ARE in `AppConfig.sensitiveFields` (`app_config.dart:74-99`) — they only actually get
encrypted if the *endpoint path* also matches `encryptedEndpoints`, which is where RULE-PROFILE-010 bites.

## 6. Security-Relevant Behavior

- **Screenshot protection**: none of this module's 9 screens call `ScreenshotSecurityService.secureScreen()`
  — only `otp_screen.dart` and `mpin_screen.dart` do, repo-wide (grep-confirmed). Protection is otherwise
  governed solely by the **global** `AppConfig.enableScreenshotProtection` flag (default `false`,
  `app_config.dart:39`), flipped remotely via `app_control_provider.dart:135`. So Account Details (full
  name/email/DOB/address) and Bank Details (masked account numbers) are screenshot-protected only when that
  remote flag is on app-wide — not screen-opted-in the way OTP/MPIN are. See SKILL.md §2 checklist row.
- **App-lock suppression**: `BankPennyVerifyScreen` sets `AppLifecycleObserver.suppressAppLock = true`
  before handing off to Cashfree/Razorpay SDK UI (`bank_penny_verify_screen.dart:76`), resets it in every
  success/error/finish path — matches the documented intentional pattern (SKILL.md §3).
  **Unconfirmed edge case**: if the app is killed by the OS while the payment SDK has focus (not just
  backgrounded), `suppressAppLock` never resets — next launch would need to independently reset this static
  flag at startup; not verified where/whether that happens.
  Also **unconfirmed**: whether the payment-in-progress state (`_internalOrderId`) survives an OS-level app
  kill during the SDK handoff — no persistence layer observed for it (in-memory only).
  - `_startVerification` catch block does NOT reset `suppressAppLock` before `_launchCashfree`/`_launchRazorpay`
    are called — only failures *inside* `initiate()` are covered; if `_launchCashfree`/`_launchRazorpay`
    themselves throw, their own catch blocks do reset it (`bank_penny_verify_screen.dart:127-134`,
    `176-186`), so it's covered, just spread across 3 separate try/catch blocks rather than one.
- **Server-authoritative confirm**: `BankPennyVerifyScreen._confirmAndFinish()` always calls
  `BankPennyVerifyService.confirm()` regardless of which SDK reported success/failure — the client SDK
  callback is never trusted alone (matches SKILL.md §2 "Session integrity" spirit, applied here to payment
  confirmation). Comment confirms this explicitly (`bank_penny_verify_service.dart:36`).
- **Account deletion — client-side data wipe**: `DeleteAccountScreen._clearAllData()`
  (`delete_account_screen.dart:66-72`) calls `SecureStorageService.logout()` (same call as ordinary logout)
  + `SharedPreferences.clear()`. It does **not** call any account-deletion-specific local wipe — it's
  identical to a normal logout's local cleanup. Server-side actual data removal is assumed but only
  evidenced by the `POST users/delete-account` call succeeding; the client has no way to verify the server
  actually purged data. See BUSINESS_RULES RULE-PROFILE-008 and FORENSIC_TEMPLATE.

## 7. Cross-Module Coupling (see CROSS_MODULE_MAP.md for full detail + Mermaid graph)

- `shared/widgets/add_bank_account_sheet.dart` (NOT under `features/profile/`, correctly lives in
  `shared/`) is the actual "Add Bank Account" UI, used by both `BankDetailsScreen` (this module) and SIP's
  `BankAccountPickerScreen`. It calls **`withdrawal_service.dart`'s `verifyAndAddBank()`** — a Withdrawal-
  module service — to create the bank account server-side. This is the real BAV *creation* step; Profile's
  own `BankDetailsService` only lists/removes/set-primary already-created accounts.
- SIP's `BankAccountPickerScreen` (`features/sip/screens/bank_account_picker_screen.dart`) imports and
  directly watches Profile's `bankAccountsProvider` and reuses the `BankAccount` model —
  a direct feature-to-feature internals import (`AGENTS.md` §1 "Must-not edges").
- `features/kyc/kyc_flow.dart` imports `profile_controller.dart` to call
  `profileProvider.notifier.fetchProfileDetails()` after KYC completes (refreshes the "Verified" badge) —
  another direct cross-feature controller call.

## 8. Top Risks / Anti-Patterns Found

1. **RULE-PROFILE-010 — CORRECTED (2026-08-24), original finding does not reproduce**: this entry
  previously claimed `withdrawal_service.dart:106` contained `'account\verify-bank'` (a `\v`
  vertical-tab escape instead of a literal `/`). Direct read of the current file (byte-level check via
  `cat -A`, confirming no `^K`/control character) and `git log -p` across the last 3 commits touching this
  file all show a plain `'account/verify-bank'` with a literal forward slash — the string matches
  `AppConfig.encryptedEndpoints`'s `'verify-bank'` entry correctly, and `account_no`/`ifsc_code` DO get
  encrypted on this call. Whatever produced the original finding (stale read, tool artifact) was wrong;
  treat this specific claim as retracted. See BUSINESS_RULES.md for the corresponding correction.
2. Three separate standalone history screens (`BavHistoryScreen`, `PennyVerifyHistoryScreen`,
   `RefundHistoryScreen`) appear to be orphaned after the `BankVerificationHubScreen` redesign — still
   routed but not linked from any in-module UI found. Confirm before removing.
3. `bankPennyVerifyServiceProvider` lives in a screen file instead of `services/`, inconsistent with the
   rest of the module — cosmetic, not a bug.
4. No screen in this module opts into screenshot protection individually — relies entirely on a global,
   remotely-toggled flag (§6).
5. "What Will Be Deleted" list on `DeleteAccountScreen` (`delete_account_screen.dart:276-282`) is a
   **hardcoded client-side UI list** (Profile & Personal Data, Portfolio & Holdings, Transaction History,
   Referral Rewards, Preferences & Settings) — not driven by the `content` string the API returns. If the
   backend's actual deletion scope changes, this list can silently drift out of sync with reality.

## 9. Related Docs

`METHOD_INDEX.md` · `DATA_FLOW.md` · `BUSINESS_RULES.md` · `CROSS_MODULE_MAP.md` · `STATE_ANALYSIS.md` ·
`FORENSIC_TEMPLATE.md` · `COVERAGE_TRACKER.md` (this folder).
