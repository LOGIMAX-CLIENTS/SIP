---
module: maintenance
last_updated: 2026-08-19
---

# Maintenance — Coverage Tracker

| Round | Date | Screens | Methods | Models | API Endpoints | Business Rules | Cross-Module Deps | Weighted % | Badge |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-08-19 | 1/1 (100%) | 5/5 own methods (100%) | 1 core model consumed, fully documented (100%) | 0 direct — polling logic lives in `core/providers/app_control_provider.dart`, fully traced (100%) | 7 rules captured | Fully mapped — all 3 inbound navigators identified and documented, including the unused `MaintenanceGate` | 100% | 🔵 |

## Spot-check (Round 1)

Full read of `maintenance_screen.dart` (253 lines). To answer the task's specific "how does
auto-resume work — polling or manual retry?" question definitively, also fully read
`core/providers/app_control_provider.dart` (312 lines — the actual polling/state-machine logic),
`shared/widgets/maintenance_gate.dart` (174 lines — confirmed zero external callers via grep),
`shared/widgets/app_control_wrapper.dart` (138 lines — confirmed the mid-session redirect path and
its `resumeRoute` hardcoding), and `app_router.dart`'s maintenance route builder plus a grep for
every `AppRouter.maintenance`/`MaintenanceScreen(` reference in `lib/` to enumerate all three
inbound call sites exhaustively.

## Drift found vs `STARTGOLD_DOCUMENTATION.md` §3.41

- Doc: "Display server downtime message with auto-resume route." Directionally correct but
  provides no mechanism detail. This round adds the concrete mechanism (dual polling timers, no
  manual retry, the three-call-site `resumeRoute` inconsistency, and the unused
  `MaintenanceGate`) — none of which was documented before. Recorded in
  `_OVERVIEW/BUILD_SUMMARY.md`.
