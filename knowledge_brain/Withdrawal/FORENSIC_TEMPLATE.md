---
module: Withdrawal
last_updated: 2026-08-19
---

# Forensic Template — Withdrawal

Symptom → check first → likely suspects, for support/debugging investigations.

## 1. "Withdrawal stuck on 'Processing...' / spinner never resolves"

**Check first**: is the device offline? `ApiSecurityInterceptor.onRequest` rejects immediately with
`DioExceptionType.connectionError` when `Connectivity().checkConnectivity()` reports none
(`core/security/api_interceptor.dart:116-127`) — this should surface as a caught exception, not a silent
hang, so if it's truly hung, offline is unlikely.

**Likely suspects**:
- `_handleWithdraw()` (`withdrawal_screen.dart:1071-1145`) chains THREE sequential awaited calls
  (`withdrawal/policy` → `savings/check-eligibility` → possibly the KYC flow) before ever reaching bank
  selection — a slow/hanging response on any of the first two reads as "stuck" on the withdrawal screen
  itself, before the user even sees the confirmation screen's own spinner.
- `_isSubmitting`/`isProcessing` flags are only reset in the `try`/`catch`/response-branches shown; if an
  `await` inside `_completeWithdrawal()` throws something not caught by the existing `catch (e)`
  (`withdrawal_confirmation_screen.dart:516-523`) — unlikely given it's a blanket catch, but check whether the
  MPIN screen navigation itself (`Navigator.pushNamed(... AppRouter.mpin ...)`, `:464-468`) can throw before
  reaching the try block — it's called with a bare `await` and no surrounding `try` (`:464`), so a navigation
  exception there is genuinely uncaught.
- Check `SessionManager.isForceLoggedOut` — a 409 mid-flow blocks all further requests silently at the
  interceptor gate (`api_interceptor.dart:103-113`); the session-invalidated dialog should appear, but if that
  dialog itself failed to build, the flow could feel "stuck" with no visible error.

## 2. "UPI verification fails silently / UPI option not visible"

**Check first**: is the user even seeing UPI as an option? Confirm which screen: `UpiSelectionScreen`'s
`_showAddOptions()` has the "UPI Handle" tile commented out (`upi_selection_screen.dart:471-484`) — **UPI
add is a disabled UI feature, not a broken one**, in the current build. If a user (or QA) reports "I can't
add UPI," the answer is "it's intentionally hidden," not a bug — verify against `RULE-WITHDRAWAL-011`
before investigating further.

**Likely suspects if the report is about a pre-existing saved UPI method disappearing**:
- `_bankOnly()` filter (`upi_selection_screen.dart:42-43`) actively strips any `WithdrawalMethod` where
  `isUpi == true` from every list this screen renders — a previously-verified UPI handle on the backend would
  simply never appear here, by design of the current rollback.

**Likely suspects if `_processAddUpi()` is somehow reached** (e.g. a build with the tile re-enabled, or a
future regression re-exposing it):
- `verifyAndAddUpi()` (`withdrawal_service.dart:85-95`) has **no try/catch of its own** — an exception
  propagates to the caller's `catch (e)` in `_processAddUpi` (`upi_selection_screen.dart:760-766`), which
  shows a generic "Could not verify UPI. Please try again." — the actual server error message is swallowed in
  that path (contrast with the `result['success'] == false` branch at `:755-758`, which DOES show the
  server's message). If verification is genuinely failing "silently" with only the generic toast, the failure
  is happening as a thrown exception (network/parse error), not a structured `success: false` response —
  check `SecureLogger` output for the raw error.
- Confirm `EncryptionService.isRsaReady` — `account/verify-upi` matches `AppConfig.encryptedEndpoints`
  substring `'verify-upi'`, so a missing/failed RSA public key fetch would cause `encryptJson` to silently
  skip encrypting `upi_id`/`mobile` (encryption only applies if `AppConfig.sensitiveFields.contains(key)` —
  it doesn't hard-fail on a missing key, see `encryption_service.dart` — the request would still go out,
  possibly with plaintext sensitive fields if `isRsaReady` was false at encrypt time). Check `SecureLogger`
  for `"ENCRYPTION: RSA key not available"`.

## 3. "Duplicate withdrawal submitted for the same day/metal"

**Check first**: `withdrawal/policy`'s response — was `is_valid: true` returned for the second attempt? If
so, the server itself didn't apply `sameDayLock`/`dailyLimit` (`models/withdrawal_policy.dart:29,37`)
correctly for that account — this is a **server-side enforcement question**, the client has no independent
dedup logic (see `BUSINESS_RULES.md` RULE-WITHDRAWAL-009).

**Likely suspects**:
- Network retry after a timeout on `POST withdrawal/withdraw` where the server actually processed the first
  request — no idempotency key/nonce is included in the submit payload (`withdrawal_service.dart:36-57`); if
  Dio or the OS retried the request transparently, or the user double-tapped fast enough to beat the
  `isProcessing`/`_isSubmitting` UI guard (race between tap and `setState`), two submissions with identical
  parameters could both reach the server.
- Confirm whether `_isSubmitting` was actually `true` at the moment of the second tap — check for a UI replay
  where the confirmation screen was popped and re-pushed (e.g. via deep link or back-then-forward) resetting
  local `State` and re-enabling the button before the first request's response arrived.

## 4. "Rate mismatch between the quoted amount and what's shown at confirmation"

**Check first**: was there a market-status flip (open→closed→open) between screens? The rate-reopen listener
(`withdrawal_screen.dart:140-157`, `withdrawal_confirmation_screen.dart:107-122`) force-restarts the timer
with a fresh lock — if that fired between the user viewing the entry screen and reaching confirmation, the
quoted rate legitimately changed and `_showUpdateSuccess` should have shown "Rate updated based on latest
market price" (`withdrawal_confirmation_screen.dart:254-265`).

**Likely suspects**:
- `WithdrawalConfirmationScreen.initState()` **always** re-locks the rate on entry if the market is open
  (`:38-49`) — this is BY DESIGN (see `RULE-WITHDRAWAL-001`), not a bug: the rate shown/locked on the entry
  screen is explicitly NOT carried forward as-is. If a support ticket says "the price changed between the two
  screens," that is expected behavior, not a defect — confirm the user understands the re-lock, or escalate
  as a product/UX question rather than a bug.
- Race-condition window: the "market-reopen vs first rate frame" guard exists specifically because `5|...|1`
  (open) can arrive on the socket before the first `3|...` rate frame, causing a locked rate of `0`
  (`withdrawal_screen.dart:159-187`, `withdrawal_confirmation_screen.dart:124-152`). If a user managed to
  submit during that exact window despite the guard, `price <= 0` guards in the amount/weight math
  (`withdrawal_confirmation_screen.dart:246-248`) should have produced `0.0`, not a wrong-but-nonzero value —
  if a nonzero-but-wrong rate was submitted, check `SecureLogger` for the sequence of socket frames around
  the timestamp.
- `withdrawal/policy`'s `amount` validation happens against the entry-screen amount BEFORE the confirmation
  screen re-locks the rate — if the policy check passed against one rate and the actual `buy_rate` submitted
  came from a different (re-locked) rate, the two numbers were never cross-validated against each other
  client-side. This is architecturally possible, not just theoretical — confirm via server logs whether
  `withdrawal/withdraw`'s `buy_rate` was ever rejected by the backend as stale/mismatched, which would
  indicate the backend does its own rate-freshness check independent of the client.

## 5. "Bank account not selectable / greyed out on the picker"

**Check first**: `account.isVerified` (`bank_account_picker_screen.dart:100`) — only `VERIFIED` accounts are
tappable; `PENDING` shows a greyed "pending" badge by design (`RULE-WITHDRAWAL-010`). Not a bug — verification
status comes from `profile/bank-accounts` (`profile/services/bank_details_service.dart:9-16`), a separate
service from this module's own `accountDetailsProvider`.

**Likely suspects if verification appears stuck indefinitely**:
- Bank verification ("penny-drop") is server-side and asynchronous — this module has no polling/refresh
  mechanism of its own for a pending account; the user must pull-to-refresh
  (`bank_account_picker_screen.dart:52` `onRefresh: () async => ref.invalidate(bankAccountsProvider)`) or
  navigate away and back. If verification is confirmed complete server-side but still shows pending, check
  provider caching/staleness rather than the verification pipeline itself.

## 6. "User reached a UPI purchase flow (Instant Saving) and ended up on a Withdrawal screen"

**Check first**: this is the known architecture issue flagged in `MODULE_BRAIN.md` Top Risk #1 —
`instant_saving_screen.dart:1654` navigates to `AppRouter.upiSelection` with purchase arguments
(`amount, metal_id, rate, buy_type, weight`), but `UpiSelectionScreen` never reads
`ModalRoute.of(context)?.settings.arguments` at all, and its submit button always navigates to
`/withdrawal-confirmation` (`upi_selection_screen.dart:392`) regardless of caller.

**Likely suspects**: confirm live-app whether `next_step == 'UPI_LIST'` from `savings/check-eligibility` is
still ever actually returned by the backend for a purchase flow — if the backend stopped returning
`UPI_LIST` (consistent with UPI payout being disabled elsewhere, `RULE-WITHDRAWAL-011`), this path may be
entirely unreachable in production and the symptom would never occur. **Unconfirmed without backend
visibility or a live device trace** — flagged here as the single highest-value thing to verify before this
brain can be marked 🔵.
