---
module: jewellery
last_updated: 2026-08-19
---

# Jewellery — Coverage Tracker

> **Primary documentation, no prior hand-written doc to cross-check.**
> `STARTGOLD_DOCUMENTATION.md` does not cover `jewellery` (confirmed via `.agents/config.md`
> §"Pre-Existing Documentation" — it's the newest module in the registry). Round 1 below is a
> from-scratch code read. There is no "drift found" section because there is nothing pre-existing
> to drift from. The module's own name and bottom-nav placement could easily be mistaken for
> implying a built catalog/redemption feature — this round's primary value is establishing, from
> the actual code, that it is currently a placeholder (MODULE_BRAIN.md §1).

## Round 1 — 2026-08-19 (Build, from scratch)

**Files read (2/2 = 100% of feature files)**:
- `lib/features/jewellery/jewellery_screen.dart` (264 lines) — full read
- `lib/features/jewellery/jewellery_service.dart` (33 lines) — full read

**Cross-module files read for context (3, plus repo-wide greps)**:
- `lib/features/main/main_screen.dart` (bottom-nav wiring, lines 1-100, 219-227) — confirmed the
  only entry point and the `IndexedStack`-exclusion mechanics
- `lib/routes/app_router.dart` (route registration, lines ~126, 376)
- `lib/core/config/app_config.dart` (`encryptedEndpoints` — confirmed `jewellery/jewellery-image`
  absent)
- `pubspec.yaml` (confirmed `assets/jewellery/` declared, then directory-listed to find it
  contains only `.gitkeep`)
- Repo-wide greps for `jewellery`/`Jewellery` (confirmed 4-file total footprint: the 2 module
  files + `app_router.dart` + `main_screen.dart`) and for `redeem`/`Redeem` inside
  `lib/features/home/` and `portfolio_provider.dart` (zero matches — the key finding backing
  MODULE_BRAIN.md §1's conclusion)

**Weighted coverage computation**:

| Component | Weight | Actual count | Documented | Score |
|---|---|---|---|---|
| Screens documented | 25% | 1 screen (`JewelleryScreen`) | 1/1 | 25% |
| Controller/service public methods documented | 25% | 1 (`getJewelleryImages`) — screen has no controller layer, its own build/callbacks covered in METHOD_INDEX.md | 1/1 | 25% |
| Models documented | 15% | 0 models owned by this module (bare `List<String>`, documented as such) | N/A — vacuously 15% (nothing to miss) | 15% |
| API endpoints documented | 15% | 1 (`POST jewellery/jewellery-image`) | 1/1, including request/response shape | 15% |
| Business rules captured | 10% | 6 rules (RULE-JEWELLERY-001 through 006) | 6/6 | 10% |
| Cross-module deps captured | 10% | 1 inbound caller (`main`), explicit "no relationship to home/portfolio/withdrawal" finding | Fully captured | 10% |

**Total: 100%**

Badge: 🟢 (≥80%) — **not yet 🔵** because 🔵 requires a separate manual spot-check re-reading 2-3
files fresh against the written docs (workflow Step 7), not performed as an independent second pass
in this round.

**Drift found vs STARTGOLD_DOCUMENTATION.md**: N/A — module not covered by that doc (see banner
above).

**Key finding for the project (flagged prominently, not just here)**: `jewellery` is a "Coming
Soon" placeholder — no catalog, no purchase flow, no redemption-of-holdings flow exists in code
today, despite the module's prominent bottom-nav placement alongside Home/Invest/History/Profile.
See MODULE_BRAIN.md §1 for full evidence.

**Housekeeping finding**: `lib/features/jewellery.zip` sits as a sibling to the `jewellery/` folder
— not extracted, flagged only (MODULE_BRAIN.md §3).

**New cross-module deps discovered**: None beyond the single `main` → `jewellery` navigation edge.
Explicitly confirmed **absence** of any `home`/`portfolio_provider`/`withdrawal` connection.

**Flagged for `_SYSTEM` synthesis** (not yet built — `_SYSTEM/` doesn't exist in this repo as of
this writing):
- DIAGNOSTIC_PLAYBOOK candidate: "user reports can't buy/redeem jewellery" → not a bug, feature
  doesn't exist yet (FORENSIC_TEMPLATE.md item 5) — useful for support-facing triage docs, not just
  engineering.
- Product/planning note (not a DANGER_ZONES candidate, no security risk found): if/when a catalog
  or redemption feature is built here, it will need net-new wiring to
  `core/providers/portfolio_provider.dart` and likely a `withdrawal`-adjacent flow — worth linking
  from this brain once that work starts.
