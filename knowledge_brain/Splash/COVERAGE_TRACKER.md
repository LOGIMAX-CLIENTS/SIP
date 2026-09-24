---
module: splash
last_updated: 2026-08-19
---

# Splash — Coverage Tracker

| Round | Date | Screens | Methods | Models | API Endpoints | Business Rules | Cross-Module Deps | Weighted % | Badge |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-08-19 | 1/1 (100%) | 9/9 own methods (100%) | 1 core model consumed, fully documented (100%) | 1/1 (`app/control`) (100%) | 9 rules captured | Fully mapped (splash reads from 6 core/shared files + 2 packages; 0 outbound feature-to-feature imports) | 100% | 🔵 |

## Method

Weighting per `build-module-brain.md` §7: screens 25%, controller/service methods 25%, models
15%, API endpoints 15%, business rules 10%, cross-module deps 10%.

`splash` has no `controller/`/`services/` subfolder — its "methods" bucket is the 9 methods of
`_SplashScreenState` itself, all read and indexed in `METHOD_INDEX.md`. It has no owned models —
the "models" bucket is scored on whether the one external model it consumes
(`AppControlData` family) is correctly and fully documented for this module's usage, which it is.

## Spot-check (Round 1)

Re-read in full (not skimmed) during this round, cross-verifying every claim in `MODULE_BRAIN.md`
against live code: `splash_screen.dart` (298 lines, full read), `core/security/session_manager.dart`
(full read), `core/security/secure_storage_service.dart` (targeted read of the mpin/onboarding
methods), `core/services/app_control_service.dart` (full read), `core/models/app_control_model.dart`
(full read), `core/providers/app_control_provider.dart` (full read, to establish the "bypasses the
provider" finding), `shared/widgets/app_update_dialog.dart` (full read). `lib/main.dart` initial
route and `MyApp.build` also read to confirm `/splash` is the true entry point.

## Drift found vs `STARTGOLD_DOCUMENTATION.md` §3.1

- Doc's routing bullet list matches code closely (maintenance → update → mpin → login).
- Doc doesn't mention the maintenance-over-update precedence rule explicitly, nor the
  `forceUpdate: true` hardcoding, nor the direct-instantiation-vs-provider deviation — all new
  findings from this round, recorded in `_OVERVIEW/BUILD_SUMMARY.md`.
- No onboarding-routing claim exists in the doc either (it correctly omits it) — the drift is
  against the module registry's implied "first-run gate" framing, not against the hand-written doc
  itself.
