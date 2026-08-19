---
module: daily_savings
last_updated: 2026-08-19
---

# DailySavings — Coverage Tracker

## Round 1 — 2026-08-19 — Build (from ⬜ not built)

Weighting per `.agents/workflows/build-module-brain.md` §7: screens 25%, controller/service
public methods 25%, models 15%, API endpoints 15%, business rules 10%, cross-module deps 10%.

| Dimension | Actual count in code | Documented | Weight | Score |
|---|---|---|---|---|
| Screens | 1 (`DailySavingsScreen`) | 1/1 (full read, every widget/callback cited) | 25% | 25% |
| Controller/service public methods | 0 (none exist — confirmed absent) | N/A, absence documented in `METHOD_INDEX.md` | 25% | 25% |
| Models | 0 (none exist — confirmed absent) | N/A, absence documented in `STATE_ANALYSIS.md` | 15% | 15% |
| API endpoints | 0 (none exist — confirmed absent, CTA is a no-op) | N/A, absence documented in `DATA_FLOW.md`/`BUSINESS_RULES.md` | 15% | 15% |
| Business rules | 6 rules captured (RULE-DAILYSAVINGS-001..006) + explicit absent-rules list | Captured | 10% | 10% |
| Cross-module deps | 1 real dep (`shared/theme/app_theme.dart`) + comparative `sip` dependency graph | Captured, Mermaid graph included | 10% | 10% |

**Weighted total: 100%**

## Manual spot-check (required for 🔵)

Re-verified against a fresh read of the source, not just the first pass:
1. `daily_savings_screen.dart` — confirmed `onPressed: () {}` at line 90 is exactly as cited (not
   a mis-transcription), confirmed no second file exists in the module directory.
2. `app_router.dart` lines 11, 74, 164 — confirmed import, route constant, and route-map entry
   text match exactly.
3. Repo-wide grep for `dailySavings`/`daily-savings`/`DailySavings` across `lib/` — confirmed
   only 4 total matches (2 in `app_router.dart`, 2 within `daily_savings_screen.dart` itself),
   supporting the "orphaned route" claim in `MODULE_BRAIN.md` §0 and `CROSS_MODULE_MAP.md` §3.

## Badge

**🔵 100% + verified** for the module's own code surface (which is intentionally minimal — 1
file, 0 backend integration). This badge reflects documentation completeness of what exists, not
feature completeness of the product — see `MODULE_BRAIN.md` §0 for the explicit "this is a
non-functional stub" verdict, which is itself the primary finding of this brain build.

Caveat: the `sip`-side citations used for the cross-module comparison (`CROSS_MODULE_MAP.md` §5)
were read only to the depth needed to establish the daily_savings-vs-sip distinction, not as a
full SIP audit — that remains ⬜ until `sip`'s own module brain is built. Do not treat this
brain as authoritative for `sip` beyond the specific lines cited.

## History

| Round | Date | Mode | Coverage | Badge | Notes |
|---|---|---|---|---|---|
| 1 | 2026-08-19 | Build | 100% (weighted) | 🔵 | First build. Primary finding: module is a disconnected UI-only stub; real Daily recurring-purchase flow lives in `sip`'s `AutoSavingsScreen`. |
