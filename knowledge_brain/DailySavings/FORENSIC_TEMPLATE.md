---
module: daily_savings
last_updated: 2026-08-19
---

# DailySavings — Forensic Template

Symptom → check first → likely suspects, for this module specifically. Because the module is a
disconnected stub, most "bugs" reported against it will actually be "this was never built" or
"the user meant SIP's Daily flow."

## 1. Symptom: "Proceed to Payment button on Daily Savings does nothing"
- **Check first**: `daily_savings_screen.dart:89-101` — confirm the `onPressed` handler.
- **Likely suspect**: Not a bug. `onPressed: () {}` (`:90`) is a literal no-op by current
  implementation, not a regression. There is no payment SDK call, no navigation, no API call to
  investigate further "downstream" — the trail ends at this line.
- **Do not** go looking for a broken Cashfree/HyperSDK/Razorpay integration for this screen —
  none was ever wired up here. If a real payment flow is wanted, it must be built (see
  `sip_payment_screen.dart` in the `sip` module as the closest existing reference
  implementation).

## 2. Symptom: "Users say they can't find the Daily Savings screen / how do I open it"
- **Check first**: repo-wide grep for `dailySavings`/`daily-savings`/`AppRouter.dailySavings`.
- **Likely suspect**: There is no in-app entry point (no button/tile navigates here) — confirmed
  by grep across `lib/`. If this is a genuine product ask, the fix is adding a nav entry point
  (e.g. a Home quick-action tile), not a "bug" in the screen itself. Clarify with product
  whether they actually mean SIP's Auto Savings screen (which *is* reachable and *does* support
  Daily) before doing UI work here.

## 3. Symptom: "Selected amount resets when I come back to the screen"
- **Check first**: `daily_savings_screen.dart:14` — `_selectedAmount` is a plain `State` field
  with no persistence.
- **Likely suspect**: Expected behavior given current implementation — `StatefulWidget` local
  state is discarded on dispose; there's no Riverpod provider or secure-storage write to survive
  navigation away and back. Not a regression to "fix" in isolation — would require adding real
  state management first.

## 4. Symptom: "Daily Savings and SIP seem to duplicate each other in the UI/product spec"
- **Check first**: `CROSS_MODULE_MAP.md` §0 in this brain — the full comparison table.
- **Likely suspect**: Confirmed overlap in *concept* (both target "small recurring daily
  investment"), but only `sip`'s `AutoSavingsScreen` Daily frequency is a real, working
  implementation. `daily_savings` is very likely a superseded prototype. Escalate to
  product/design to confirm intended fate of the `daily_savings` module (delete vs. repurpose)
  rather than trying to reconcile the two in code.

## 5. Symptom: "Crash or exception when navigating to `/daily-savings`"
- **Check first**: The screen itself has minimal surface area — verify it isn't a
  `flutter_screenutil` initialization-order issue (the screen uses `.w`/`.h`/`.sp`/`.r` extension
  methods at `:37,44,50,54,64,71,79,80,86,88,94,98,103,107,109,111` — these throw if
  `ScreenUtil.init()` hasn't run yet, a class of bug common when a screen is opened very early in
  app startup, e.g. via a cold-start deep link before `MaterialApp` finishes building).
- **Likely suspect**: Given the module's near-total lack of logic, a crash here is much more
  likely a `ScreenUtil` init-order issue or a theme/`Brightness` lookup issue
  (`Theme.of(context).brightness`, `:18`) than anything specific to this module's own code.

## 6. Symptom: "New requirement to actually implement Daily Savings end-to-end"
- **Check first**: `MODULE_BRAIN.md` §0 verdict and §6 top risks; `CROSS_MODULE_MAP.md` §0
  recommendation.
- **Likely suspect / guidance**: Before writing any controller/service code, get an explicit
  product decision on whether this is (a) meant to be merged into/replaced by SIP's existing
  Daily frequency flow, or (b) a genuinely separate, simpler product. Building a second parallel
  "Daily" recurring-purchase backend integration without that decision risks duplicating
  `sip`'s `createSip(frequencyId: 1, ...)` path (`sip_service.dart:59-80`).
