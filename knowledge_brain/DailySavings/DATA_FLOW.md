---
module: daily_savings
last_updated: 2026-08-19
---

# DailySavings — Data Flow

This module has exactly one real flow (pure local UI state, goes nowhere) and one flow that
*doesn't* happen but a reader might expect to — documented here explicitly so nobody assumes it
exists. A third flow shows the real equivalent in `sip` for contrast.

## Flow 1: Chip selection (the only thing that actually happens)

```
User taps a "₹10/₹20/₹50/₹100" chip (daily_savings_screen.dart:59-83)
  → onTap: setState(() => _selectedAmount = amt.replaceAll('₹', ''))   (:60-61)
  → State._selectedAmount updated in memory only                       (:14)
  → build() re-runs, chip restyles to AppTheme.arcticBlue (:67)
  → NO persistence, NO provider write, NO API call, NO navigation
```
End state: purely cosmetic. Backgrounding/reopening the app, or popping and re-pushing the
route, resets `_selectedAmount` to the default `'20'` (`:14`) since it is never written to
`flutter_secure_storage`, `shared_preferences`, or any Riverpod provider.

## Flow 2: "Proceed to Payment" tap (expected flow — does NOT happen)

```
User taps "Proceed to Payment" (daily_savings_screen.dart:89-101)
  → onPressed: () {}                                                   (:90)
  → literally nothing happens — no navigation, no API call, no error toast
```
This is the flow a reader of `STARTGOLD_DOCUMENTATION.md` §3.15 ("Configure daily micro-
investment settings") would expect to trigger plan creation + payment gateway hand-off (per the
pattern used in `instant_saving` and `sip`'s `sip_payment_screen.dart`). It does not exist here.
Confirmed by reading the full 117-line file — there is no second file, no hidden import, no
navigation call anywhere else in the widget tree for this button.

## Flow 3 (contrast, not part of this module): the real "Daily" recurring-purchase flow in `sip`

Documented here only so the distinction is unambiguous for whoever builds the `sip` brain next.
Not exhaustively verified line-by-line (that's `sip`'s own brain-build job) but the entry points
are cited:

```
User opens Auto Savings (sip/screens/auto_savings_screen.dart), taps "Daily" frequency tab
  → sip_controller: ref.read(sipControllerProvider.notifier).setFrequency(freq.id)  (auto_savings_screen.dart:600-601)
  → screen reads sipConfigProvider / sipGoldDenominationsProvider(freqId) etc.       (:80, :226-228)
  → user enters/selects amount, taps bottom CTA (_buildBottomAction, not fully read in this pass)
  → SipService.createSip(frequencyId: 1 /*Daily*/, commodityId, amount, paymentMethod, ...)  (sip_service.dart:59-80)
  → POST sip/... endpoint (exact create endpoint path not captured in this pass — see sip_service.dart in full)
  → hands off to sip_payment_screen.dart for the actual payment-gateway step
```
`frequencyId: 1 = Daily, 2 = Weekly, 3 = Monthly` is documented directly in the SIP service's
docstring at `sip_service.dart:59`. This is the code path that actually implements "recurring
daily micro-investment" in the shipped app.

## Summary table

| Flow | Module | Real? | API hit | Payment gateway | Persistence |
|---|---|---|---|---|---|
| Chip selection | `daily_savings` | Yes (UI only) | No | No | No (in-memory only) |
| Proceed to Payment | `daily_savings` | No (no-op) | No | No | No |
| Daily-frequency Auto Savings | `sip` | Yes | Yes (`sip/*`) | Yes (via `sip_payment_screen.dart`) | Yes (backend-created SIP plan) |
