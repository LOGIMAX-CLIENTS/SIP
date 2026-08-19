---
module: main
last_updated: 2026-08-19
---

# Main — Coverage Tracker

| Round | Date | Screens | Methods | Models | API Endpoints | Business Rules | Cross-Module Deps | Weighted % | Badge |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-08-19 | 1/1 own screen (100%); 4 hosted screens identified/named but their internals are each hosted module's own scope (not re-verified here) | 5/5 own methods (100%) | 0 owned (N/A → scored 100%) | 0 owned — all API surface delegated to hosted screens' controllers, correctly identified as out-of-scope (100%) | 9 rules captured | 7 providers + 4 hosted screens + 1 pushed route identified and cited; declaration line numbers confirmed for all 7 providers, but their internal implementations were not independently re-read this round (~80% depth on this axis) | 93% | 🟢 |

## Method

Weighting per `build-module-brain.md` §7: screens 25%, controller/service methods 25%, models
15%, API endpoints 15%, business rules 10%, cross-module deps 10%. `main` scores 100% on every
axis it fully owns (its one screen file, in full) and is intentionally marked below 100% only on
cross-module deps, because verifying the *internals* of `homeDashboardProvider`,
`portfolioProvider`, `profileProvider`, `savingConfigProvider`, `historyProvider`,
`authControllerProvider`, and `notificationProvider` is each of those providers' owning module's
responsibility, not `main`'s — this brain confirms *what* `main` calls and *where* each symbol is
declared, not the full behavior of the callee.

Score: 25 (screens) + 25 (methods) + 15 (models, N/A) + 15 (APIs, N/A/delegated) + 9 (rules,
capped slightly under 10 pending a `_SYSTEM`-level cross-check) + 8.8 (cross-module, ~88% depth on
that one axis) ≈ 93%.

## Spot-check (Round 1)

Full read of `main_screen.dart` (272 lines). Cross-verified provider declaration sites via
targeted grep+read of the declaration line for each of the 7 external providers (confirmed exact
`file:line` for all 7 — see `METHOD_INDEX.md`), and confirmed via directory listing that
`lib/features/main/` truly has no subfolders. Also read `app_router.dart`'s `home`/`main` route
entries and `jewellery` route entry to confirm the two-routes-one-screen and
pushed-route-not-stack-child findings.

## Drift found vs `STARTGOLD_DOCUMENTATION.md` §3.42

**Significant.** Doc: "Bottom tab container — Home, Invest, Market, Profile" (4 tabs, 3rd =
Market). Code: 5 nav items — Home, Invest, **History**, Profile, **Jewellery** — with History (not
Market) as the 3rd tab, and Jewellery as a 5th item that isn't even a stack-hosted tab. No "Market"
tab exists in this file at all (market data lives inside `HomeScreen`, consistent with the module
registry's own note that `market` is "mostly embedded in Home"). Recorded in
`_OVERVIEW/BUILD_SUMMARY.md`.
