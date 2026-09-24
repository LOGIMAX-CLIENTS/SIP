---
module: maintenance
brain_status: 🔵 100% (built, verified)
last_updated: 2026-08-19
round: 1
---

# Maintenance — Module Brain

## 0. TL;DR

`maintenance` is a **single-file, fully automatic, poll-driven downtime gate**:
`lib/features/maintenance/maintenance_screen.dart` (253 lines). It has **no manual retry
button** — the "Checking status automatically…" row is purely decorative (a spinner + text, no
`onTap`). Resume is entirely driven by Riverpod state changes from `appControlProvider`
(`core/providers/app_control_provider.dart`), which is polled on two independent timers: a 30s
"fast" poll started by this screen itself on mount, and a 60s "global" poll that runs app-wide
regardless of which screen is showing. When `appControlProvider`'s `isMaintenance` flips to
`false`, this screen's `build()` (which `ref.watch`es that provider) detects it and navigates
away automatically.

`MaintenanceScreen` takes a **required constructor argument**, `resumeRoute: String`
(`maintenance_screen.dart:21-23`), supplied via the route's `arguments` map
(`app_router.dart:294-301`, defaulting to `AppRouter.login` if the arg is missing). There are
**three distinct call sites** that push `/maintenance`, and they disagree on what `resumeRoute`
they pass — see §3, a real behavioral inconsistency worth flagging.

## 1. Inventory

| Path | Role |
|---|---|
| `lib/features/maintenance/maintenance_screen.dart` | Sole file. `ConsumerStatefulWidget` `MaintenanceScreen` + `_MaintenanceScreenState`. |

No `screens/`, `controller/`, `providers/`, `models/`, `services/`, or `widgets/` subfolders exist
under `lib/features/maintenance/`. The module's actual logic (polling, state, gating) lives in
`core/providers/app_control_provider.dart` — this screen is a thin, reactive consumer.

Route registration (external, per convention):
- `lib/routes/app_router.dart:43` — `import '../features/maintenance/maintenance_screen.dart';`
- `lib/routes/app_router.dart:104` — `static const String maintenance = '/maintenance';`
- `lib/routes/app_router.dart:294-301` — the only route in the entire router whose builder reads a
  required constructor arg from route arguments:
  ```dart
  maintenance: (context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>? ?? {};
    return MaintenanceScreen(resumeRoute: args['resumeRoute'] as String? ?? AppRouter.login);
  },
  ```

## 2. Screen: MaintenanceScreen

`maintenance_screen.dart:19-252`. `ConsumerStatefulWidget` with `resumeRoute` as a required
`final String` field (`:21`), `_MaintenanceScreenState` mixes in `TickerProviderStateMixin`
(pulse + fade animations, `:29-35`, `:42-54`).

| Attribute | Detail |
|---|---|
| Route | `/maintenance` (`AppRouter.maintenance`) |
| State mgmt | Riverpod — watches `appControlProvider` (`core/providers/app_control_provider.dart:318-324`) |
| Providers watched | `appControlProvider` (`:90`) |
| API calls | None directly — all fetching happens inside `AppControlNotifier._fetch()`, triggered by the polling timers this screen starts |
| Navigation out | `Navigator.of(context).pushNamedAndRemoveUntil(widget.resumeRoute, (route) => false)` — clears the entire nav stack (`:73-77`) |
| Security | `WillPopScope` — back press exits the app on Android (`SystemNavigator.pop()`), no-op (still blocked) on iOS (`:81-86`, `:98-99`) |

### 2.1 Auto-resume mechanism — the exact answer to "polling vs manual retry"

**It is 100% polling-driven. There is no manual retry control anywhere in this screen's UI.**

1. On mount, `initState()` schedules (via `addPostFrameCallback`)
   `ref.read(appControlProvider.notifier).startMaintenancePolling()` (`:57-59`).
2. `startMaintenancePolling()` (`app_control_provider.dart:86-90`) cancels any existing fast timer
   and starts a new `Timer.periodic(_kMaintenancePollInterval, (_) => _fetch())`, where
   `_kMaintenancePollInterval = Duration(seconds: 30)` (`:14-15`).
3. Independently, `AppControlNotifier.initialize()` — called once at app startup by
   `AppControlWrapper` (`shared/widgets/app_control_wrapper.dart:35-37`, which wraps the entire
   `MaterialApp` in `main.dart:114`) — starts a **separate**, always-running
   `Timer.periodic(_kAlertPollInterval, (_) => _fetch())` where
   `_kAlertPollInterval = Duration(minutes: 1)` (`:13`, `_startPolling()` at `:92-95`). This one is
   never stopped by the maintenance screen and keeps running app-wide the whole session.
   Net effect: maintenance status is re-checked at least every 30s while this screen is visible
   (both timers firing independently), and at least every 60s at all other times.
4. Every `_fetch()` tick (`app_control_provider.dart:97-214`) re-POSTs `app/control` and updates
   `AppControlState.isMaintenance`. When it flips to `false`
   (`app_control_provider.dart:159-163` also cancels the fast maintenance-only timer at that
   point), `AppControlState` changes trigger a rebuild of anything watching `appControlProvider`.
5. `MaintenanceScreen.build()` re-runs on every such state change (`ref.watch`, `:90`) and calls
   `_checkResume(appControl)` (`:91`) every time. `_checkResume` (`:70-78`) fires the navigation
   exactly once, guarded by a `_hasNavigated` flag (`:36`), when it observes
   `!appControl.isMaintenance`.

### 2.2 The three call sites that push `/maintenance` — and their `resumeRoute` disagreement

| Call site | `resumeRoute` passed | Preserves session context? |
|---|---|---|
| `features/splash/splash_screen.dart:86-87` | The pre-maintenance login/mpin decision (`AppRouter.login` or `AppRouter.mpin`, whichever splash had already computed) | **Yes** — session-aware |
| `shared/widgets/maintenance_gate.dart:39-43` (`MaintenanceGate.check`, meant for pre-transaction gating before payment/withdrawal/SIP) | Hardcoded `AppRouter.login` | No |
| `shared/widgets/app_control_wrapper.dart:56-60` (mid-session redirect when the global 60s poll detects maintenance turning on while the user is already inside the app) | Hardcoded `AppRouter.login` | No |

See §3 Top Risks — this means a logged-in user browsing the app who gets interrupted by
maintenance turning on mid-session will, once maintenance lifts, be dropped at `/login` rather
than back into `/main`, even though their session token is still valid.

**Note:** `MaintenanceGate.check()` (the pre-transaction gate) has **zero call sites** anywhere in
`lib/` besides its own definition and doc comment — confirmed via grep. Despite
`.agents/AGENTS.md` §2 describing a "pre-action gate... before any critical transaction (payment,
withdrawal, SIP creation)", no feature module currently invokes it. It is dead/unused code as of
this round.

### 2.3 UI (visual only)

Pulsing brand logo (`ScaleTransition`, 2s repeat-reverse, `:42-45`, `:52-53`), fade-in on mount
(600ms, `:47-50`, `:54`), server-driven `title`/`subtitle`/`expectedResume` text from
`MaintenanceInfo` with hardcoded English fallbacks (`:154-172`, `:183-217`), and the
"Checking status automatically…" indicator row (`:222-240`) — a `CircularProgressIndicator` +
`Text`, no button, no `InkWell`, nothing tappable.

## 3. Top Risks

1. **Inconsistent `resumeRoute` across call sites** (detailed §2.2) — the two non-splash entry
   points always resume at `/login`, discarding a still-valid session. Whether this is intentional
   (force re-auth after any maintenance interruption, as a security posture) or an oversight is
   **unconfirmed** — flagging for product/security review rather than silently treating either as
   correct.
2. **`MaintenanceGate.check()` is unused.** The pre-transaction maintenance gate documented in
   `AGENTS.md` §2 as the pattern for blocking payment/withdrawal/SIP during maintenance is fully
   implemented (`shared/widgets/maintenance_gate.dart`) but never called — critical transactions
   currently rely solely on the global `AppControlWrapper` mid-session redirect (§2.2 row 3) and/or
   server-side rejection, not this client-side pre-check.
3. **Dual, uncoordinated polling.** The 30s screen-local timer and the 60s app-wide timer both hit
   `app/control` independently while this screen is visible — not incorrect, but worth knowing
   before "optimizing" one without the other.

## 4. See Also
- `METHOD_INDEX.md` — every method, file:line, callers.
- `DATA_FLOW.md` — the polling → state-change → auto-navigate flow, plus all three entry flows.
- `BUSINESS_RULES.md` — RULE-MAINTENANCE-001..007.
- `CROSS_MODULE_MAP.md` — deps on `core/`, `shared/`; Mermaid graph of all three inbound
  navigators.
- `STATE_ANALYSIS.md` — `appControlProvider`/`AppControlState` shape as consumed here.
- `FORENSIC_TEMPLATE.md` — symptom → suspect entries.
- `COVERAGE_TRACKER.md` — Round 1 coverage.
