---
module: sip
last_updated: 2026-08-19
---

# SIP — Forensic Templates

## 1. "SIP shows ACTIVE but no debit is happening"

**Check first**: `SipPlanDetail.isActive` (`models/sip_models.dart:232-233`) does an exact
case-insensitive match on `status == 'ACTIVE'`. Confirm the backend isn't sending a status this
getter would silently misclassify as active (e.g. a soft/half-active state).

**Likely suspects**:
- The debit itself happens entirely gateway/server-side (see DATA_FLOW.md Flow B) — there is no
  client code path that could cause this symptom; the app can only ever be *displaying* stale or
  incorrect status, not causing a missed debit. Rule out a display bug before escalating to
  payments/backend.
- Stale `sipDetailsProvider` cache — verify the screen the user is looking at actually ran its
  `ref.invalidate(sipDetailsProvider)` on entry (RULE-SIP-013). If they're on a screen that
  doesn't force-refresh (none currently exist for this provider outside `AutoSavingsScreen`), a
  long-lived session could show week-old cached status.
- Mandate is genuinely `ACTIVE` (authorized) but the recurring charge is failing at the gateway
  (insufficient balance, expired card, revoked UPI mandate) — invisible to this module; check
  `sip/transactions` (`SipTransactionHistoryScreen`) for failed/skipped entries, and cross-check
  with the payment gateway's own dashboard (outside this codebase's scope).

## 2. "Cancel button disabled / stuck on the blocked screen incorrectly"

**Check first**: the exact `cancel_eligible_at`/`can_cancel_now` values passed through navigation
args — trace back to `app_router.dart:333-338` (parses `DateTime.tryParse(...).toLocal()`) and the
originating `sip/manage-details` or `sip/custom/{id}/status` response.

**Likely suspects**:
- Timezone mismatch — `cancelEligibleAt` is parsed with `.toLocal()`
  (`models/sip_models.dart:290-292`); if the server sends a timestamp without explicit UTC
  offset info that the backend intends as UTC, `.toLocal()` could shift it, making `_isBlocked`
  (`screens/sip_cancel_screen.dart:55-58`) evaluate incorrectly on either side.
- Device clock skew — `_isBlocked` compares against `DateTime.now()` (device clock), not a
  server-synced clock.
- Stale manage-screen data — `ManageSavingsScreen`/`ManageCustomSavingsScreen` only refetch on
  their own `initState`/pull-to-refresh; if the customer navigated here from a cached list without
  a fresh `sip/manage-details` call in between, the args could be older than the true eligibility.
- `canCancelNow` field missing from an old/degraded API response — defaults to `true` (fails
  open, `sip_models.dart:265,293-295`), so this direction wouldn't produce a stuck-blocked symptom,
  but worth ruling out the inverse (a bug that sends `can_cancel_now: false` when it shouldn't).

## 3. "Custom SIP scheme_id mismatch / wrong scheme managed"

**Check first**: `ManageCustomSavingsScreen.schemeId` (route arg, `app_router.dart:319`,
`int.tryParse(args['scheme_id']?.toString() ?? '0') ?? 0` — a malformed/missing arg silently
becomes scheme `0`) vs. the scheme actually returned by `CustomSipService.getSchemeStatus()`
(`services/custom_sip_service.dart:94`).

**Likely suspects**:
- The date-picker's `dateOwners` map (`screens/auto_savings_screen.dart:1802-1808`) is built from
  `ref.refresh(customSipSchemesProvider.future)` (a true refresh, `:1793`) every time the sheet
  opens — good. But confirm any *other* caller of the ownership map isn't instead reading a stale
  `ref.read`/`ref.watch` snapshot from before a recent create/cancel.
- `scheme_id` arriving as a `String` vs `int` across the navigation boundary — the route parses
  defensively with `int.tryParse(...).toString())` (`app_router.dart:319`), but any other call site
  constructing this route (e.g. `sip_overview_screen.dart:462`, `auto_savings_screen.dart:1908`)
  must pass the raw `int` `schemeId`, not a formatted string — verify no accidental
  double-stringification.

## 4. "Amount submitted differs from what the customer typed"

**Check first**: `createSip()`/`createCustomSip()` both send `sipState.amount.toInt()`
(`auto_savings_screen.dart:2039,2211`) — a truncating cast, not rounding.

**Likely suspects**:
- Denomination chips only ever set whole-number or exact decimal values from the backend list
  (`models/sip_models.dart:81-93`) — if a denomination value is fractional (e.g. `99.5`), `.toInt()`
  silently drops the fraction with no client-side warning.
- The amount `TextField` itself only allows digits (`FilteringTextInputFormatter.digitsOnly`,
  `auto_savings_screen.dart:999`) — so manual entry can't produce a fraction; if this symptom
  occurs it's more likely from the denomination-chip path or a `sipState.amount` set via
  `ref.read(...).notifier.setAmount(popular.value)` where `popular.value` is a `double`
  (`auto_savings_screen.dart:242`) that wasn't a whole number.
- Cross-check RULE-SIP-011: for Custom SIP, the unencrypted plaintext payload makes this an easier
  field to inspect/verify directly (e.g. via a proxy) if the complaint is actually about *what was
  transmitted* rather than what was charged.

## 5. "Payment succeeded in the gateway's own app/UI but startGOLD shows failure"

**Check first**: whether `paymentData['order_id']` was non-null/non-empty when
`SipPaymentScreen` mounted — `_verifyMandateStatus()` early-returns if `orderId == null`
(`screens/sip_payment_screen.dart:406-407`), which would leave the screen stuck in the
"processing" state rather than showing an explicit error.

**Likely suspects**:
- Race between the SDK success callback and the 2-second lifecycle-resume fallback
  (`didChangeAppLifecycleState`, `:106-126`) — both can call `_verifyMandateStatus()`; the second
  guards on `_isVerifying`/`_sdkCallbackReceived` but confirm neither flag got desynced (e.g. an
  exception between setting `_sdkCallbackReceived = true` and calling `_verifyMandateStatus()`).
- `sip/confirm` returning a `status` this client doesn't treat as success — only `'ACTIVE'` and
  `'BANK_APPROVAL_PENDING'` route to `sipSuccess` (`:432`); any other status string (including a
  legitimate-but-unmapped one) routes to `sipFailure` even if the gateway itself reports success.
- Razorpay's `response.message == "undefined"` literal-string quirk — handled by
  `_friendlyRazorpayErrorMessage()` (`:351-370`), but confirm the raw `response.code` is actually
  populated; an unmapped code falls through to the generic message, which could mask a real
  distinguishable failure reason worth surfacing.

## 6. "Weekly/Monthly SIP created with the wrong day/date"

**Check first**: `SipService.createSip()`'s payload construction — `day` is only added when
`frequencyId == 2`, `date` only when `frequencyId == 3` (`services/sip_service.dart:98-103`).

**Likely suspects**:
- `SipNotifier.setFrequency()` clears both `selectedDay`/`selectedDate` on every frequency change
  (`controller/sip_controller.dart:150-156`) — verify no other code path calls
  `ref.read(sipControllerProvider.notifier)` setters directly without going through
  `setFrequency()` first (which would leave a stale day/date from a previous frequency selection
  sitting in state, though the payload-construction guard in step 1 would still prevent it from
  being sent under the wrong key).
- Confirm the day-picker (`_showWeeklyDayPicker`, `:1483`) and date-picker
  (`_showMonthlyDatePicker`, `:1617`) actually call `setDay()`/`setDate()` *before* invoking
  `_selectPaymentMethodAndCreate()` (they do, via the Confirm button's `onPressed`, `:1592-1599`
  and `:1719-1726`) — a regression here would silently send the SIP with no day/date at all rather
  than a wrong one.
