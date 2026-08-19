---
module: Home
last_updated: 2026-08-19
---

# Home — Coverage Tracker

## Round 1 — Build (2026-08-19)

**Mode:** Build (brain status was ⬜ → 🟢)

**Files read:** 9/9 `.dart` files under `lib/features/home/` (100%), plus 11 cross-referenced `core/` and
sibling-feature files read in full or via targeted grep to trace every provider Home consumes:
`core/providers/{timer,market,home_dashboard,portfolio,commodity,countdown_offer,user}_provider.dart`,
`core/services/{home,portfolio,notification}_service.dart`, `core/network/native_socket_service.dart`,
`core/network/api_client.dart` (baseUrl only), `core/services/shared_service.dart` (commoditiesProvider,
partial), `features/instant_saving/{controller/saving_controller.dart, services/saving_service.dart,
models/saving_models.dart}` (partial — config-relevant sections), `features/profile/profile_controller.dart`
(grep only, not full read), `features/main/main_screen.dart` (grep only, not full read),
`features/market/models/market_rates.dart` (full), `lib/routes/app_router.dart` (grep for Home-relevant
routes only).

## Weighted Coverage Calculation

| Category | Weight | Actual count | Documented | Coverage |
|---|---|---|---|---|
| Screens documented | 25% | 1 screen (`HomeScreen`) + 1 sub-screen (`OfferWebViewScreen`) | 2/2 | 100% |
| Controller/service public methods documented | 25% | Home has no own controller/service; all consumed methods on `HomeService`, `PortfolioService`, `NotificationNotifier` traced in `DATA_FLOW.md`/`STATE_ANALYSIS.md` | All Home-relevant methods (3 `HomeService`-adjacent flows + 5 `NotificationNotifier` methods referenced) | ~95% |
| Models documented | 15% | 8 classes in `home_dashboard.dart` + 3 in `countdown_offer_model.dart` = 11 | 11/11 | 100% |
| API endpoints documented | 15% | `POST home/dashboard`, `POST home/countdown-offer`, `POST portfolio/summary`, `POST savings/config`, `POST users/notifications/unread-count` = 5 endpoints Home's render path triggers | 5/5 | 100% |
| Business rules captured | 10% | RULE-HOME-001 through 011 | 11 rules, all code-grounded | 100% |
| Cross-module deps captured | 10% | 7 `core/providers` files + 3 `core/services` files + 2 `core/network` files + 3 cross-feature violation imports = 15 | 15/15 identified; Mermaid graph included | 100% |

**Weighted total:** (100×0.25) + (95×0.25) + (100×0.15) + (100×0.15) + (100×0.10) + (100×0.10) = 98.75% raw,
discounted to **≈90%** for the badge below because several cross-referenced files
(`profile_controller.dart`, `main_screen.dart`, `shared_service.dart`, `commoditiesProvider`'s consumers
beyond Home) were read via targeted `grep`/partial `Read` rather than in full — sufficient to trace Home's
own behavior accurately, but not sufficient to certify those *other* modules' internals, which is out of
scope for this round.

## Badge

🟢 **≈90%** (mostly complete — not yet 🔵 because a manual spot-check re-read of `savings_controller.dart`/
`main_screen.dart`/`profile_controller.dart` in full, and independent verification of the "Recommendation for
future refactor" note in `CROSS_MODULE_MAP.md`, has not been performed in this round).

## Manual Spot-Check (for 🔵 upgrade — not yet done)

To reach 🔵, re-read from scratch and cross-check against this brain:
1. `home_screen.dart` lines 1-200 (timer/race-condition guard logic) — the highest-risk section.
2. `core/providers/timer_provider.dart` in full — confirm `_refreshAndRestart` behavior claims.
3. `core/network/native_socket_service.dart` lines 130-260 — confirm frame-parsing claims against a real
   socket payload sample if one becomes available (not available in this round — payload format taken from
   code comments and parsing logic only, not a captured live sample).

## Open Items / Unconfirmed Claims

- `UserProfile.isKycVerified` / `.isVip` (`core/providers/user_provider.dart:13,24`) are declared but never
  populated in the `userProvider` body — marked "unconfirmed" whether they're set via a different path
  elsewhere in the app; Home doesn't currently read either field.
- Exact tab-index-to-feature mapping in `main_screen.dart`'s `IndexedStack` beyond index 0 = Home
  (`selectedTabProvider.notifier.state = 1` is assumed to be InstantSaving based on "Invest Now" button
  semantics, not independently confirmed by reading the full `IndexedStack` children list).
- Whether `portfolioProvider`/`marketRatesStreamProvider`/`marketStatusProvider` are also consumed by
  Withdrawal/InstantSaving screens as claimed in `CROSS_MODULE_MAP.md` — inferred from `AGENTS.md` and
  `STARTGOLD_DOCUMENTATION.md` §3.11/§3.16 claims, not independently verified against those modules' source
  in this round (out of scope — Home module only).

## Round History

| Round | Date | Mode | Coverage | Badge |
|---|---|---|---|---|
| 1 | 2026-08-19 | Build | ≈90% | 🟢 |
