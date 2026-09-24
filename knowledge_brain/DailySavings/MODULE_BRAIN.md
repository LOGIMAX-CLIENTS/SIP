---
module: daily_savings
brain_status: 🟡 (built, but module itself is a non-functional UI stub — see verdict below)
last_updated: 2026-08-19
round: 1
---

# DailySavings — Module Brain

## 0. TL;DR Verdict (read this first)

`daily_savings` is a **single-file, disconnected UI mock**. It is not wired to any controller,
service, model, API, encryption path, or payment SDK. Its "Proceed to Payment" button has an
empty `onPressed: () {}` — pressing it does nothing (`daily_savings_screen.dart:90`). The route
`/daily-savings` (`app_router.dart:74`, registered `app_router.dart:164`) is never navigated to
from anywhere else in `lib/` — it is orphaned/dead code, reachable only via `Navigator.pushNamed`
called manually or a deep link, not from any in-app button, tile, or menu (verified: repo-wide
grep for `dailySavings`/`daily-savings`/`DailySavings` returns only the file itself and the two
router lines — see `CROSS_MODULE_MAP.md`).

The **real, backend-integrated recurring-purchase feature** — including a literal "Daily"
cadence option — lives in the `sip` module as `AutoSavingsScreen`
(`lib/features/sip/screens/auto_savings_screen.dart`), backed by `SipService`/`SipController`
hitting `sip/*` endpoints. See §5 and `CROSS_MODULE_MAP.md` for the full daily_savings-vs-sip
distinction.

**Recommendation for anyone extending this feature**: do not build on top of
`daily_savings_screen.dart` as if it were live. Either (a) treat it as legacy/prototype code to
delete, or (b) if product intends a real standalone "Daily Savings" product distinct from SIP's
Daily frequency, it needs a controller, service, model, and API wiring built from scratch — none
of that exists today.

## 1. Inventory

| Path | Role |
|---|---|
| `lib/features/daily_savings/daily_savings_screen.dart` | Sole file in the module. `StatefulWidget` screen, plain `setState`, no Riverpod. |

No `screens/`, `controller/`, `providers/`, `models/`, `services/`, or `widgets/` subfolders
exist under `lib/features/daily_savings/` — confirmed via directory listing
(`E:\Projects\Mobileapp\SIP\lib\features\daily_savings\`, single file, no subdirectories).

Route registration (external to the module folder, per convention — see `AGENTS.md` §1):
- `lib/routes/app_router.dart:11` — `import '../features/daily_savings/daily_savings_screen.dart';`
- `lib/routes/app_router.dart:74` — `static const String dailySavings = '/daily-savings';`
- `lib/routes/app_router.dart:164` — `dailySavings: (context) => const DailySavingsScreen(),`

## 2. Screen: DailySavingsScreen

`daily_savings_screen.dart:6-117`. `StatefulWidget`, state class
`_DailySavingsScreenState` (`:13`).

| Attribute | Detail |
|---|---|
| Route | `/daily-savings` (`AppRouter.dailySavings`) |
| State mgmt | Local `setState` only — `String _selectedAmount = '20'` (`:14`). No Riverpod `Consumer`/`ConsumerStatefulWidget`. |
| Providers watched | None |
| API calls | None |
| Encryption | None |
| Payment gateway invocation | **None.** CTA button `onPressed: () {}` (`:90`) — no-op. |
| Navigation out | Only `Navigator.pop(context)` on back arrow (`:29`). No forward navigation exists in the file. |
| Security (screenshot block / app-lock suppression) | None present |

### UI content (what it actually renders)
- Title "Daily Savings Setup" in the `AppBar` (`:31`).
- Heading "Automate Your Savings" + subcopy "Set a small amount to save daily and watch your
  gold grow effortlessly." (`:41-49`).
- "Select Daily Amount" chip row: four hardcoded fixed options `₹10 / ₹20 / ₹50 / ₹100`
  (`:57`), single-select via local string state, default `'20'` (`:14`).
- CTA button "Proceed to Payment" (`:96`) — **not wired to anything**.
- Footer caption "Secure Payment Gateway" (`:105`) — text only, no actual gateway SDK import or
  call exists anywhere in the file.

No amount input field, no frequency selector (daily/weekly/monthly), no commodity (gold/silver)
selector, no start-date picker, no min/max validation, no error/loading/empty states — none of
the scaffolding a real purchase-setup flow in this codebase normally has (contrast with
`sip/screens/auto_savings_screen.dart`, which has all of the above).

## 3. Controllers / Services / Models

**None exist.** No `daily_savings_controller.dart`, no `daily_savings_service.dart`, no
`daily_savings_models.dart`. This is a hard divergence from every other feature module in the
registry (see `{AGENTS_DIR}\config.md` module list), which uniformly follow
`Screen → Controller (Riverpod) → Service → ApiClient` per `AGENTS.md` §1.

## 4. What "daily savings" would need to configure (inferred from UI copy only)

Per the on-screen copy alone (not backed by any executable logic), the intended concept is: a
**fixed recurring daily debit amount** (₹10/20/50/100 preset tiers) that is auto-invested into
gold "effortlessly" — i.e., a recurring micro-investment amount, not a savings **goal** (no
target amount/date UI exists) and not a one-time purchase (copy says "save daily"). This framing
is consistent with the `config.md` module registry description ("Recurring micro-investment
configuration") — but it is **unimplemented**; the screen cannot actually create such a plan.

## 5. Relationship to `sip` (see `CROSS_MODULE_MAP.md` for full detail)

The `sip` module's `AutoSavingsScreen` (`lib/features/sip/screens/auto_savings_screen.dart`)
already implements essentially this concept, live:
- Frequency tabs literally labelled Daily / Weekly / Monthly, sourced from
  `SipConfig.frequencies` (`sip_controller.dart` / `sip_models.dart`), with
  `frequencyId: 1 = Daily, 2 = Weekly, 3 = Monthly` documented at
  `sip/services/sip_service.dart:59`.
- A user picking the "Daily" frequency tab in `AutoSavingsScreen` and completing setup creates a
  real backend SIP plan via `SipService.createSip(...)` (`sip_service.dart:62`), POSTing to
  `sip/*` endpoints, with a real payment step (`sip_payment_screen.dart`) and gateway
  invocation — none of which `daily_savings_screen.dart` has.
- There is also a separate "Custom SIP" product (`custom_sip_service.dart`,
  `manage_custom_savings_screen.dart`) for arbitrary day-of-month selections, further evidence
  that "recurring investment with a Daily cadence" is a fully-built concept inside `sip`, not in
  `daily_savings`.

**Working conclusion (unconfirmed with product/backend team, but strongly evidenced by code):**
`daily_savings` appears to be an early prototype/mock screen for the same concept that was later
built for real inside the `sip` module as the "Daily" frequency of Auto Savings, and the
standalone module was left in place but disconnected (no nav entry point, no backend wiring).
It is not a distinct product from SIP in the shipped app today.

## 6. Top Risks

1. **Dead/misleading route.** `/daily-savings` exists and renders a screen that looks
   functional (branded, styled, "Secure Payment Gateway" text) but silently does nothing on
   submit. If any future deep link, push-notification payload, or marketing link points here,
   users hit a dead end with no error message. — `daily_savings_screen.dart:90`.
2. **Duplicate-concept confusion for future devs.** Because `sip`'s Auto Savings screen already
   implements "Daily" recurring investment, a developer asked to "finish daily savings" could
   easily build a second, parallel implementation instead of recognizing SIP's Daily frequency
   already covers it — wasting effort and fragmenting the product surface further.
3. **No encryption/validation surface to audit** — because there's no request payload, this
   module currently carries no PCI/security risk of its own, but *if* someone wires the CTA to a
   real API without reading `AGENTS.md` §3 first, amount fields would need to go through
   `core/security/encryption_service.dart` like every other financial field — not obvious from
   this file alone since no other module code is present to copy from.

## 7. Route Table

| Route constant | Path | Screen | Registered |
|---|---|---|---|
| `AppRouter.dailySavings` | `/daily-savings` | `DailySavingsScreen` | `app_router.dart:74`, `:164` |

## 8. See Also
- `METHOD_INDEX.md` — the (very short) method list.
- `DATA_FLOW.md` — the one flow that exists (local UI state only) plus the SIP flow it should be
  compared against.
- `BUSINESS_RULES.md` — RULE-DAILYSAVINGS-NNN entries, all either "not implemented" or "inferred
  from copy only".
- `CROSS_MODULE_MAP.md` — full daily_savings vs sip distinction, Mermaid graph.
- `STATE_ANALYSIS.md` — the single local `String` field, and comparison to `SipState`.
- `FORENSIC_TEMPLATE.md` — symptom→suspect entries (mostly "why doesn't this button do
  anything").
- `COVERAGE_TRACKER.md` — Round 1 coverage.
