---
module: Profile
last_updated: 2026-08-19
---

# Profile — Data Flows

## Flow 1 — Profile edit (Account Details)

1. `AccountDetailsScreen.initState` (`account_details_screen.dart:50-84`) seeds `TextEditingController`s
   from the already-loaded `profileProvider` state, then in a `postFrameCallback` forces
   `setEditing(false)` and re-runs `fetchProfileDetails()` — the screen always refetches on entry because
   `profileProvider` is an app-wide singleton whose constructor only runs once per session
   (`profile_controller.dart:340-345` comment).
2. `ProfileNotifier.fetchProfileDetails()` (`profile_controller.dart:153`) → `ProfileService.getProfileDetails(customerId)`
   → `POST profile/customer_details` with `{id_customer}` (`profile_service.dart:11-24`).
3. Response `data` map is defensively parsed field-by-field (multiple key fallbacks, e.g.
   `data['name'] ?? data['full_name']`) into a fresh `UserProfile`, replacing state
   (`profile_controller.dart:158-182`). `_parseNullableField` (line 146) normalizes null/empty/`"null"`
   string sentinel values for `last_login_at`/`last_failed_login_at`.
4. User edits Name/E-Mail/Pincode/Address (DOB and Phone are always read-only —
   `account_details_screen.dart:330,332`). `_canSave` gates the Save button: name non-empty, email
   non-empty, pincode exactly 6 digits and `_isPincodeValid` (`account_details_screen.dart:42-47`).
5. Optional pincode lookup: `_handlePincodeCheck` → `ProfileNotifier.checkPincode` →
   `ProfileService.checkPincode` → `POST users/shared/check-pincode` `{pincode}`
   (`profile_service.dart:73-93`). On success, State/City auto-fill and
   `updateLocationInfo()` stashes `id_country`/`id_state`/`id_city` into `ProfileNotifier` state for the
   eventual save (`account_details_screen.dart:108-119`, `profile_controller.dart:221-237`). On failure,
   State/City are cleared and `_isPincodeValid = false` blocks Save.
6. Optional e-mail re-verification: `_verifyEmail` → `authControllerProvider.notifier.sendEmailOtp(email)`
   (cross-module, Auth) → same `email_otp_sheet.dart` UI used at registration
   (`account_details_screen.dart:136-173`). On success, profile is refetched so the server's
   `cus_email_verified_on` timestamp is picked up — not just a local flag flip.
7. Save: `_handleSubmit` validates Name/E-Mail/Pincode client-side, then
   `ProfileNotifier.updateProfile(...)` → `ProfileService.updateProfile(...)` →
   `POST profile/update` with `id_customer` + all 10 profile fields (`profile_service.dart:27-70`).
8. On success, `ProfileNotifier` optimistically merges the edited fields into local state
   (`profile_controller.dart:265-286`) rather than refetching — **and resets `isEmailVerified` to `false`
   locally if the saved email differs from the previously-verified one**
   (`profile_controller.dart:266-274`, "a verification stamp belongs to the mailbox it verified").
   `isEditing` flips back to `false`.
9. Photo update is a separate sub-flow: `ProfilePhotoWidget` → `_handlePhotoUpdate` →
   `ProfileNotifier.updateProfilePhoto(File)` → `ProfileService.updateProfilePhoto` →
   `POST customer/update-profile-photo` as `multipart/form-data` (`photo` + `id_customer`)
   (`profile_service.dart:95-120`). On success the notifier **re-fetches the whole profile** (not just the
   photo URL) to pick up the server-generated `photo_url` (`profile_controller.dart:313-316`).
10. None of these endpoints (`profile/customer_details`, `profile/update`, `users/shared/check-pincode`,
    `customer/update-profile-photo`) are in `AppConfig.encryptedEndpoints` — the whole flow is plaintext
    JSON over TLS (see MODULE_BRAIN.md §5).

## Flow 2 — Bank Account Verification (BAV): add → verify-bank → ₹1 payment → confirm

This is the newest and most complex flow in the module, undocumented in `STARTGOLD_DOCUMENTATION.md`.

1. Entry point: `BankDetailsScreen._buildAddButton` (`bank_details_screen.dart:246-278`) →
   `showAddBankAccountSheet()` (`shared/widgets/add_bank_account_sheet.dart:21`, shared with SIP's
   `BankAccountPickerScreen`).
2. User enters Beneficiary Name, Account Number, Confirm Account Number, IFSC. On Name field-blur,
   `checkName()` calls `BankDetailsService.checkBeneficiaryName(name)` →
   `POST account/check-beneficiary-name` (`bank_details_service.dart:44-52`) — a **non-blocking** live
   name-match check against the customer's verified PAN/Aadhaar name. If this check itself errors
   (network issue), the sheet treats it as a pass (`nameMatched = true`) because "the server-side
   `verify_bank()` still enforces this rule" (`add_bank_account_sheet.dart:65-73`) — pre-flight UX only,
   not the authoritative gate.
3. "Verify & Add" (enabled only once name matched + both account-number fields match + IFSC present) calls
   **`WithdrawalService.verifyAndAddBank()`** (cross-module — `withdrawal_service.dart:98-114`) →
   `POST account\verify-bank` with `mobile`, `account_holder`, `bank_name` (always sent empty string —
   `add_bank_account_sheet.dart:207`), `account_no`, `ifsc_code`.
   **The endpoint path literal is corrupted** — see RULE-PROFILE-010 in BUSINESS_RULES.md; this call's
   actual on-wire path and encryption status are unconfirmed without a live capture.
4. On `result['success'] == true`, the sheet closes, `onAdded()` invalidates `bankAccountsProvider`, and
   the response's `data.id_payout` (documented as actually meaning `CustomerBank.cbank_id`, a legacy key
   name from Cashfree payout-beneficiary registration — `add_bank_account_sheet.dart:224-227`) is used to
   immediately push `BankPennyVerifyScreen(cbankId: ...)` (`add_bank_account_sheet.dart:234-240`) — the
   ₹1-verification step is chained automatically, not a separate user-initiated action.
5. `BankPennyVerifyScreen` — user taps "Pay ₹1 & Verify" → `PaymentMethodSheet` (from `instant_saving`
   module, reused) collects `paymentMethod` ('upi'|'card'|'netbanking') →
   `BankPennyVerifyService.initiate(cbankId, paymentMethod)` →
   `POST account/verify-bank/penny/initiate` (`bank_penny_verify_service.dart:18-33`). Response shape
   depends on which gateway the backend picked (`payment_gateway` field): Cashfree → `session_id` +
   `sdk_payload.{session_id, order_id}`; Razorpay → `session_id` + `sdk_payload.{key, order_id, amount,
   currency, name, prefill}`.
6. `AppLifecycleObserver.suppressAppLock = true` is set before handing off to whichever native SDK
   (`bank_penny_verify_screen.dart:76`), reset in every completion path (§6 of MODULE_BRAIN.md).
7. SDK success/error callback (Cashfree `_onCashfreeSuccess`/`_onCashfreeError`, or Razorpay
   `_onRazorpaySuccess`/`_onRazorpayError`) always funnels into `_confirmAndFinish()` — **never trusts the
   SDK result alone**.
8. `_confirmAndFinish` → `BankPennyVerifyService.confirm(internalOrderId)` →
   `POST account/verify-bank/penny/confirm` (`bank_penny_verify_service.dart:37-48`) — server-authoritative
   `{verified: bool, status}`. Only on `verified == true` does the screen invalidate `bankAccountsProvider`
   and pop `true`; any other outcome shows an error toast and stays on-screen for retry.
9. The ₹1 itself is a **plain payment, not a penny-drop/reverse-penny-drop** per the service's own doc
   comment (`bank_penny_verify_service.dart:4-8`) — i.e. the verification signal is "payment succeeded",
   not "user correctly reported a random micro-amount". A separate, apparently asynchronous/manual refund
   process later marks `refund_status`/`refunded_on` on the same row (see Flow 3) — the comment "No refund"
   describes the *verification mechanism*, not a promise that the ₹1 is never returned.

## Flow 3 — Bank verification history (read-only, 4 screens over 2 endpoints)

1. `GET account/verify-bank/bav-history` → `List<BavHistoryItem>` (kyc_id, status, account_last4,
   name_matched, name_match_score, attempted_on, provider) — feeds `bavHistoryProvider`.
2. `GET account/verify-bank/penny/history` → `List<PennyVerifyHistoryItem>` (cbpv_id,
   internal_order_id, amount, payment_method, status, bank_name, account_last4, created_on, refund_id,
   refund_status, refunded_on, gateway_provider) — feeds `pennyVerifyHistoryProvider`. **Same rows** back
   both `PennyVerifyHistoryScreen` (renders payment fields) and `RefundHistoryScreen` (renders refund
   fields) — one fetch, two presentations (`refund_history_screen.dart:11-13,40-42`).
3. `BankVerificationHubScreen` fetches both lists and merges them client-side via
   `BankVerificationCard.build()` (`models/bank_verification_history.dart:163-241`): for every ₹1-payment
   row, it searches BAV rows (oldest-first) for the same `accountLast4` whose `attemptedOn` is at-or-before
   the payment's `createdOn`, picks the nearest unconsumed match, and marks it used. Any BAV row never
   consumed becomes its own standalone card. Cards sort newest-first by `sortDate`
   (payment's `createdOn`, or the standalone BAV's `attemptedOn`).
   **This pairing is a heuristic**, justified by the real flow always requiring BAV=APPROVED before a ₹1
   payment is even allowed server-side (comment at `bank_verification_history.dart:141-143`), but there is
   **no shared attempt id** between the two backend tables — if a customer ever has two BAV attempts on the
   same masked account close together, the pairing could attribute a ₹1 row to the wrong BAV attempt.
   Flag as **unconfirmed edge case**, not a proven bug.

## Flow 4 — Account deletion (GDPR/regulatory)

1. `DeleteAccountScreen` loads `_deleteInfoProvider` → `DeleteAccountService.fetchDeleteInfo()` →
   `POST users/delete-account/info` → `{content: String, is_allowed: bool}`
   (`delete_account_service.dart:6-19`). `content` is server-driven policy text rendered via
   `NumericStyledText` (`delete_account_screen.dart:190-192,233-272`); `is_allowed` gates whether the
   destructive footer button even renders (`delete_account_screen.dart:205-206`) — e.g. a customer with an
   active SIP or non-zero holdings would presumably get `is_allowed: false` server-side, though the actual
   eligibility rule lives in the backend and is **unconfirmed** from client code alone.
2. "What Will Be Deleted" list shown to the user (Profile & Personal Data, Portfolio & Holdings,
   Transaction History, Referral Rewards, Preferences & Settings) is a **hardcoded client-side array**
   (`delete_account_screen.dart:276-282`), not derived from the `content` API field — see
   MODULE_BRAIN.md §8 risk 5.
3. Tap "Delete My Account" → `_showConfirmationDialog()` (a styled `Dialog`, not a plain `AlertDialog`) →
   requires explicit "Yes, Delete" tap (`delete_account_screen.dart:456-616`).
4. On confirm → `DeleteAccountService.confirmDelete()` → `POST users/delete-account` `{confirm: true}`
   (`delete_account_service.dart:22-29`). This is the **only** server call in the whole deletion flow —
   there is no separate "verify OTP/MPIN before deleting" step in the client code (**unconfirmed** whether
   the backend itself requires re-auth via the bearer token's freshness or an additional check not visible
   client-side).
5. On success, `_clearAllData()` runs `SecureStorageService.logout()` (same routine as a normal logout —
   clears tokens/MPIN/biometric flags except `persistent_device_id`, `persistent_device_type`,
   `keyHasSeenOnboarding`) + `SharedPreferences.clear()` (`delete_account_screen.dart:66-72`), then
   navigates to `/login` with the whole stack cleared. **No server-side deletion confirmation is displayed
   to the user beyond the generic success path** — if the backend actually failed to purge data but
   returned `success: true`, the client would have no way to detect it. This is the crux of
   SKILL.md §5's GDPR/IT-Act compliance note ("must actually remove/anonymize data server-side, not just
   sign the user out client-side") — the client-side half is honest (real API call, real local wipe), but
   whether the *server* half is honest is entirely outside this module's code and **unconfirmed**.
6. On failure, the raw exception message (minus the `"Exception: "` prefix) is shown as a toast and the
   user stays on-screen — no local data is cleared (`delete_account_screen.dart:54-63`).
