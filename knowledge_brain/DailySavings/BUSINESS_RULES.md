---
module: daily_savings
last_updated: 2026-08-19
---

# DailySavings — Business Rules

Because the module has no controller/service/API layer, most "rules" below describe UI-only
constants or explicitly document the *absence* of a rule a reader might otherwise assume exists.
Each cites the enforcing (or non-enforcing) code.

## RULE-DAILYSAVINGS-001 — Fixed preset amount tiers, no free-text entry
The only selectable daily amounts are the four hardcoded presets `₹10, ₹20, ₹50, ₹100`; there is
no numeric text field for a custom amount. — `daily_savings_screen.dart:57`.
Status: implemented (as UI-only local state), unconfirmed whether this matches the intended
product design (no config/denomination fetch backs it — contrast with `sip`'s
`sipGoldDenominationsProvider`/`sipSilverDenominationsProvider`, which pull denomination lists
from the backend per `sip_service.dart:28-54`).

## RULE-DAILYSAVINGS-002 — Default selected amount is ₹20
`_selectedAmount` initializes to `'20'`. — `daily_savings_screen.dart:14`.
Status: implemented, cosmetic only (see DATA_FLOW.md Flow 1 — never submitted anywhere).

## RULE-DAILYSAVINGS-003 — No amount is ever submitted to a backend
There is no `ApiClient` call, no `SipService`/`InstantSavingService`-style class, in this module.
Selecting an amount and tapping "Proceed to Payment" has no effect (`onPressed: () {}`,
`daily_savings_screen.dart:90`). Status: **not implemented** — flagged as the module's primary
gap, not a business rule to preserve.

## RULE-DAILYSAVINGS-004 — No field-level encryption applies (nothing to encrypt)
`AGENTS.md` §3 requires amount-bearing fields to go through
`core/security/encryption_service.dart` before hitting `ApiClient`. This module has no request
payload at all, so the rule is vacuously "not violated" — but also not something a future
implementer gets for free; they must wire it up like every other module. Status: N/A today,
mandatory if the CTA is ever implemented.

## RULE-DAILYSAVINGS-005 — Route exists but has no in-app entry point
`/daily-savings` (`AppRouter.dailySavings`, `app_router.dart:74,164`) is reachable only by
directly calling `Navigator.pushNamed(context, AppRouter.dailySavings)` or an external deep
link — no button, tile, or menu item anywhere else in `lib/` navigates to it (verified via
repo-wide grep for `dailySavings`/`daily-savings`/`DailySavings`, matches limited to the file
itself and the two router lines). Status: confirmed dead route as of this brain's build date.

## RULE-DAILYSAVINGS-006 (cross-module, informational) — "Daily" recurring investment is
already a first-class option inside SIP, not unique to this module
`sip`'s `AutoSavingsScreen` exposes frequency tabs Daily/Weekly/Monthly
(`sip/screens/auto_savings_screen.dart` frequency-tab UI, e.g. `:570-620`), with
`frequencyId: 1 = Daily` documented at `sip/services/sip_service.dart:59`, and a working
`createSip()` call (`sip_service.dart:62`) that actually creates a backend plan and proceeds to
payment (`sip_payment_screen.dart`). This is the functioning equivalent of what
`daily_savings_screen.dart` visually promises. See `CROSS_MODULE_MAP.md` for full detail.
Status: confirmed via code read of both modules' entry screens/services (SIP read was scoped to
config/create/frequency plumbing, not every SIP screen — full SIP verification belongs to that
module's own brain-build).

## Rules explicitly NOT found (checked for, absent)
- No minimum/maximum daily amount validation rule (no validator logic in this file at all).
- No rate-lock timer usage (`core/providers/timer_provider.dart` not imported) — unlike
  `instant_saving`/`sip`/`withdrawal`, which per `AGENTS.md` §2 lock buy/sell rates client-side.
- No market-closed guard (`marketStatusProvider` not imported/watched here, contrast with
  `auto_savings_screen.dart:87-95`).
- No screenshot/app-lock security treatment (`AGENTS.md` §3 requires this on payment screens;
  this screen presents itself as a payment step in its copy — "Secure Payment Gateway",
  `:105` — but implements none of the actual protections).
