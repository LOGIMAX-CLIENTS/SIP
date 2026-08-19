---
module: Profile
last_updated: 2026-08-19
---

# Profile — Forensic Template

Symptom → check first → likely suspects. For use during bug triage before re-deriving architecture from
scratch (per `AGENTS.md` §0.3, feeds `_SYSTEM/DIAGNOSTIC_PLAYBOOK.md`).

## 1. "Add Bank Account" does nothing / fails silently / never verified

**Check first**: the exact runtime string passed to `_apiClient.post()` in
`withdrawal_service.dart:106`. Log or breakpoint the literal — it should read `account/verify-bank`; if it
contains a control character instead of `/`, this is RULE-PROFILE-010 (BUSINESS_RULES.md).

**Likely suspects**:
- `withdrawal_service.dart:106` — `'account\verify-bank'` is a non-raw Dart string; `\v` is a real escape
  (vertical tab), so the literal path is corrupted. This is the single highest-priority suspect for
  *any* Add-Bank-Account failure report, since it's the sole creation endpoint for both Profile's
  `BankDetailsScreen` and SIP's `BankAccountPickerScreen`.
- `add_bank_account_sheet.dart:201-210` — confirm the request payload keys (`account_holder`, `account_no`,
  `ifsc_code`, `bank_name` always `''`) match what the backend actually expects; `bank_name` being
  hardcoded empty could itself cause a validation failure unrelated to the path bug.
- `bank_details_service.dart:44-52` `checkBeneficiaryName` — if the pre-flight name-match check itself
  errors, the sheet silently treats it as a pass (`nameMatched = true`) rather than surfacing the error —
  check this isn't masking a more fundamental connectivity issue.

## 2. Bank account stuck "Pending Verification" indefinitely

**Check first**: `BankDetailsScreen` renders `Pending Verification` whenever
`account.verificationStatus != 'VERIFIED'` (`bank_account.dart:20`, `bank_details_screen.dart:205-219`).
Cross-reference against `BankVerificationHubScreen` / `BavHistoryScreen` for the same account's actual BAV
attempt status — a "Pending" bank card with a "Rejected" BAV history entry means the BAV attempt failed and
the user needs to re-add the account, not wait.

**Likely suspects**:
- The RULE-PROFILE-010 path bug (§1 above) — if bank-account creation itself is silently failing/partial,
  the account could be created server-side in a permanently-pending state with the client never completing
  the follow-up ₹1 flow.
- User closed/backgrounded the app during the Cashfree/Razorpay SDK handoff in `BankPennyVerifyScreen`
  before `_confirmAndFinish()` ran — the ₹1 payment may have succeeded on the gateway side but the app
  never called `.../penny/confirm` to record it. Check `pennyVerifyHistoryProvider` for a row with
  `status: "Initiated"` that never transitioned to `"Paid"`.
- `AppLifecycleObserver.suppressAppLock` not resetting after an OS-level app kill mid-payment (see
  MODULE_BRAIN.md §6 unconfirmed edge case) — unlikely to cause the *pending* state itself, but could
  compound a bad UX on the next launch (unexpected app-lock behavior around the same time).

## 3. Bank Account Verification Hub shows a ₹1 payment paired with the wrong BAV attempt

**Check first**: `BankVerificationCard.build()` pairing logic (`models/bank_verification_history.dart:163-241`)
matches by `accountLast4` + "nearest BAV attempt at-or-before this payment's `createdOn`, not yet
consumed." Reproduce by checking whether the customer has **two or more BAV attempts on the same last-4**
close together in time.

**Likely suspects**:
- The pairing heuristic itself — there is no shared attempt id between the BAV and ₹1-payment backend
  tables, so this is inherently best-effort. Confirm with the backend team whether a shared correlation id
  could be added; until then this is a known, documented limitation, not necessarily a regression.
- Standalone `BavHistoryScreen` (which shows BAV rows without any pairing) is the ground truth for "did
  this specific BAV attempt succeed" — cross-check against it rather than trusting the Hub's card grouping
  when investigating a specific attempt.

## 4. Account deletion "succeeds" but data still visible / account still usable

**Check first**: confirm the exact response from `POST users/delete-account` — does the client only check
`response.data['success'] == true` (`delete_account_service.dart:25`)? If the backend returns `success:
true` for e.g. "deletion request queued" rather than "deletion completed synchronously", the client would
report success immediately and navigate to `/login` while the account is still fully live server-side.

**Likely suspects**:
- Backend deletion may be asynchronous/queued rather than synchronous — entirely a backend-side
  investigation; the client has no polling or confirmation-of-completion step (see BUSINESS_RULES
  RULE-PROFILE-009).
- `_clearAllData()` only wipes **local** secure storage + prefs (`delete_account_screen.dart:66-72`) — if
  the user logs back in with the same credentials (assuming the backend didn't actually delete the
  account), the app has no client-side "this account was deleted" guard; it would just behave like a normal
  login.
- Check whether `is_allowed` was `true` for a reason that's since become stale (e.g. cached provider value)
  — `_deleteInfoProvider` is `autoDispose`, so this is unlikely but worth a first-pass check.

## 5. Profile edit "succeeds" but old values reappear on next visit

**Check first**: `ProfileNotifier.updateProfile()` optimistically merges the edited fields into local state
on success (`profile_controller.dart:265-286`) — it does **not** refetch from the server after save. If the
server silently rejected/modified a field (e.g. server-side validation altered the pincode-derived
state/city), the client would show the client-submitted values, not what the server actually persisted,
until the next full `fetchProfileDetails()` call (e.g. next screen visit).

**Likely suspects**:
- Compare what was submitted (`_handleSubmit`'s payload) against what a fresh `GET`/re-fetch of
  `profile/customer_details` returns for the same account — a mismatch confirms server-side normalization
  or rejection that the client isn't surfacing.
- `AccountDetailsScreen.initState`'s forced refetch-on-entry (`account_details_screen.dart:68-83`) should
  catch this on the *next* screen visit — if it doesn't, check whether `profileProvider`'s singleton state
  is somehow being read from a stale cache instead of the fresh fetch completing before the UI reads it.

## 6. Biometric toggle silently fails to turn on

**Check first**: the 3-guard chain in `ProfileScreen._onBiometricToggle`
(`profile_screen.dart:56-107`) — no-enrollment guard → MPIN re-verify (`Navigator.pushNamed(mpin,
{'type': 'verify_only'})`) → final biometric confirm prompt. A `false`/non-`true` return from **any** guard
silently aborts with the toggle left OFF (no error toast for the MPIN-verify-cancelled case specifically —
only the two "no biometric" cases show a toast, `profile_screen.dart:61-79`; the MPIN-cancel and
biometric-cancel-confirm paths return silently at lines 87 and 93).

**Likely suspects**:
- User believes they cancelled nothing (e.g. accidentally dismissed the MPIN screen or the final biometric
  prompt) and sees no explanation for why the toggle stayed off — this is a UX gap, not necessarily a bug,
  but a common support-ticket shape for this exact code path.
