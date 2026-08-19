---
module: Profile
last_updated: 2026-08-19
---

# Profile — Business Rules

Each rule: plain-English statement + the code that implements/enforces it. "Unconfirmed" = inferred from
client code only, not verified against backend source or a live run.

## RULE-PROFILE-001 — Phone number and DOB are permanently read-only in Account Details

Name, E-Mail, Pincode, State (auto), City (auto), Address are editable; Phone and DOB never render an
editable `TextField` regardless of `isEditing` state.
**Code**: `account_details_screen.dart:330` (`isEditable: false` hardcoded for Phone),
`account_details_screen.dart:332` (same for DOB).

## RULE-PROFILE-002 — Save requires Name + valid Email + exactly 6-digit Pincode

`_canSave` computed property gates the Save button.
**Code**: `account_details_screen.dart:42-47`. Server-side re-validation on `profile/update` is
**unconfirmed** (not visible from client code).

## RULE-PROFILE-003 — Editing an already-verified e-mail address resets its verified badge locally

If the saved value differs from the previously on-file (and verified) e-mail, `isEmailVerified` is reset to
`false` client-side immediately on successful save — a verification stamp belongs to the mailbox it
verified, not the account. **Code**: `profile_controller.dart:266-274` — comment cites backend
`identity.py` doing the equivalent reset server-side, so this is mirroring, not inventing, server behavior.

## RULE-PROFILE-004 — E-mail re-verification only offered when the input field exactly matches the on-file value

The "Verify" / "Verified" badge next to the E-Mail field is hidden entirely if the field currently holds an
unsaved edit (`currentInput != onFileEmail`) — verifying a not-yet-saved address would check against a
value the backend doesn't have yet.
**Code**: `account_details_screen.dart:404-410`.

## RULE-PROFILE-005 — A bank account must pass live BAV before a ₹1 verification payment can even start

Per code comment, the backend's `cbank_is_verify` gate blocks `account/verify-bank/penny/initiate` unless
the account already passed `account\verify-bank` (BAV). The client enforces this implicitly by chaining
`BankPennyVerifyScreen` immediately after a successful "Verify & Add", never exposing the ₹1-payment screen
as an independently reachable action for an unverified account.
**Code**: `add_bank_account_sheet.dart:223-241` (chaining); comment reference at
`models/bank_verification_history.dart:141-143`. **Unconfirmed**: whether the backend actually enforces
this server-side (client never attempts to call penny/initiate for an unverified account, so this path is
untested from the client alone).

## RULE-PROFILE-006 — ₹1 verification is never confirmed on the SDK callback alone

Both Cashfree and Razorpay success/error callbacks route to the same `_confirmAndFinish()`, which calls the
server's `.../penny/confirm` endpoint and only treats the account as verified if the server responds
`verified: true`.
**Code**: `bank_penny_verify_screen.dart:137-145` (Cashfree), `188-203` (Razorpay), `207-240`
(`_confirmAndFinish`). Matches `SKILL.md` §2's session-integrity spirit applied to payments.

## RULE-PROFILE-007 — Removing a bank account is a soft-delete; verification history is retained

The confirmation dialog explicitly tells the user "You can add this account again anytime — your
verification history is kept."
**Code**: `bank_details_screen.dart:348-350` (UI copy); `bank_details_service.dart:30-33` (doc comment:
"soft-remove (backend keeps history)"). Backend behavior itself is **unconfirmed** from client code — this
is the client's stated assumption.

## RULE-PROFILE-008 — Account deletion is gated server-side by `is_allowed`; the destructive action is hidden, not just disabled, when not allowed

If `users/delete-account/info` returns `is_allowed: false`, the "Delete My Account" footer button doesn't
render at all (the user only sees the policy content + deletion-scope list, no way to trigger deletion).
**Code**: `delete_account_screen.dart:123-125,205-206`. The actual eligibility rule (e.g. open SIP, non-zero
holdings, pending KYC) is **unconfirmed** — lives entirely in the backend response.

## RULE-PROFILE-009 — Account deletion requires an explicit double-confirmation, then performs the same local data wipe as logout

Tap "Delete My Account" → styled confirm dialog ("Yes, Delete" / "Cancel") → only then is the API called.
On success, local wipe = `SecureStorageService.logout()` + `SharedPreferences.clear()`, identical routine to
a normal logout, not a deletion-specific wipe.
**Code**: `delete_account_screen.dart:38-64` (confirm flow), `66-72` (`_clearAllData`).
**GDPR/IT-Act note** (per `SKILL.md` §5): the client's job here — call the real delete endpoint and wipe
local secrets — is done correctly. Whether the *server* actually purges/anonymizes data (vs. a soft
deactivation) is outside this module's code and **unconfirmed**.

## RULE-PROFILE-010 — (Critical, likely bug) The bank-account-creation endpoint path is corrupted by an unescaped Dart string literal

`withdrawal_service.dart:106`: `_apiClient.post('account\verify-bank', data: {...})`. This is a plain
(non-raw) Dart string; `\v` is a recognized Dart escape sequence (vertical tab, `U+000B`), so the actual
runtime string is `"account" + U+000B + "erify-bank"`, **not** `"account/verify-bank"`. Two consequences,
both **unconfirmed at runtime** (would need a live network capture or the actual Dio-resolved URL to
verify) but follow directly from Dart's string-literal grammar:
1. The HTTP request path sent to the backend is malformed and would not route to the intended endpoint
   unless the backend/Dio layer somehow tolerates/strips the control character.
2. `AppConfig.encryptedEndpoints` gates on `path.contains('verify-bank')` (`api_interceptor.dart:134,194`)
   — a corrupted path containing `U+000B` instead of `/` would **not** contain the substring `'verify-bank'`
   (missing `v`), so the encryption interceptor would never fire for this request, meaning `account_no`
   and `ifsc_code` — both listed in `AppConfig.sensitiveFields` — would ship in plaintext JSON if the
   request went through at all.
**Impact scope**: this single call is the creation step for every "Add Bank Account" action app-wide
(Profile's `BankDetailsScreen` and SIP's `BankAccountPickerScreen` both funnel through
`shared/widgets/add_bank_account_sheet.dart` → this exact call). A sibling bug of the same shape exists in
`withdrawal_service.dart:117` (`'referrals\reward-balance'`, `\r` = carriage return) — outside this
module's scope but confirms the pattern isn't a one-off.
**Recommended fix** (not applied — flagging only per this task's scope): change to
`'account/verify-bank'` (forward slash) or use a raw string `r'account\verify-bank'` if a literal backslash
were ever actually intended (it isn't — no other endpoint in the codebase uses backslash path separators).
See FORENSIC_TEMPLATE.md for the matching symptom entry.
