---
module: Home
brain_status: 🟢 (≈90% — see COVERAGE_TRACKER.md)
last_updated: 2026-08-19
round: 1 (Build)
files_read: 9/9 .dart files under lib/features/home/ + 11 core/ cross-reference files
---

# Home — Module Brain

## 1. Purpose

`home` is the primary post-login dashboard (bottom-nav tab 0, `IndexedStack` in
`lib/features/main/main_screen.dart:163`). It shows: portfolio overview (weight/value/returns), a live
sell-rate header with countdown-lock timer, gold/silver toggle, market open/closed status, a "100-Day Grand
Launch" countdown offer, dashboard sections sourced from an API (rate-history, invest blocks, learn
carousel, footer/compliance), a notification bell with unread badge, and pull-to-refresh.

There is **no dedicated route** for Home — it is not pushed via `Navigator.pushNamed`; it's the fixed tab-0
widget inside `MainScreen`'s `IndexedStack` (`main_screen.dart:160-163`). `AppRouter.home = '/home'`
(`lib/routes/app_router.dart:75`) maps to `MainScreen` itself (`app_router.dart:165`), not to `HomeScreen`
directly.

## 2. File Inventory

```
lib/features/home/
├── home_screen.dart                     (2251 lines) — HomeScreen, PremiumHomeHeader, _LiveBadge, _ClosedBadge
├── models/
│   ├── home_dashboard.dart              — HomeDashboard, RateHistory, InvestSection, InvestBlock,
│   │                                       LearningSection, LearningBanner, FooterInfo, ComplianceItem
│   └── countdown_offer_model.dart       — CountdownOfferResponse, NewCustomerOffer, ExistingCustomerOffer
└── widgets/
    ├── learn_carousel.dart              — LearnCarousel (auto-sliding image carousel)
    ├── countdown_offer_widget.dart      — CountdownOfferWidget (orchestrator: NEW vs EXISTING vs disabled)
    ├── countdown_offer_new.dart         — CountdownOfferNew (new-customer countdown UI, local ticking timer)
    ├── countdown_offer_existing.dart    — CountdownOfferExisting (existing-customer progress UI)
    ├── micro_savings_banner.dart        — MicroSavingsBanner (swipe-to-navigate CTA card)
    └── offer_webview_screen.dart        — OfferWebViewScreen (in-app WebView for offer benefits page)
```

No `controller/`, `services/`, or `providers/` subfolder in this module — Home is UI-only and consumes
services/providers from `lib/core/` (see `CROSS_MODULE_MAP.md`). `HomeService` itself lives in
`lib/core/services/home_service.dart`, not under `features/home/`.

## 3. Screen / Route Table

| Screen | Route | File | Notes |
|---|---|---|---|
| HomeScreen | tab 0 of `MainScreen` (no own route) | `home_screen.dart:30` | `ConsumerStatefulWidget` |
| OfferWebViewScreen | pushed via `MaterialPageRoute` (not a named route) | `widgets/offer_webview_screen.dart:19` | Opened from "About the Offer" / "Know more" |

## 4. State Dependencies (Riverpod)

All providers Home watches/reads live in `lib/core/providers/` or a **different feature's** controller
(see §6 violations). Full detail in `STATE_ANALYSIS.md`.

| Provider | Source file | Type | Purpose in Home |
|---|---|---|---|
| `commodityProvider` | `core/providers/commodity_provider.dart:14` | `StateNotifierProvider<CommodityNotifier, CommodityType>` | Gold/Silver toggle, shared app-wide |
| `selectedMetalIdProvider` | `commodity_provider.dart:26` | `Provider<String>` | Derives real `id_metal` for API calls |
| `userProvider` | `core/providers/user_provider.dart:28` | `Provider<UserProfile?>` | Greeting name, `isNewUser` |
| `portfolioProvider` | `core/providers/portfolio_provider.dart:99` | `StateNotifierProvider.autoDispose` | Balance/value/returns card |
| `marketRatesStreamProvider` | `core/providers/market_provider.dart:16` | `StreamProvider<MarketRates>` | Live socket rates |
| `marketStatusProvider` | `market_provider.dart:58` | `StreamProvider<Map<String,bool>>` | Per-commodity open/closed |
| `sellRateTimerProvider` | `core/providers/timer_provider.dart:121` | `StateNotifierProvider<RateTimerNotifier, TimerState>` | Rate-lock countdown for header |
| `homeDashboardProvider` | `core/providers/home_dashboard_provider.dart:9` | `FutureProvider<HomeDashboard?>` | Rate-history/invest/learn/footer sections |
| `countdownOfferProvider` | `core/providers/countdown_offer_provider.dart:14` | `FutureProvider.autoDispose` | 100-Day offer card |
| `notificationProvider` / `unreadCountProvider` | `core/services/notification_service.dart:257,263` | `StateNotifierProvider` / `Provider<int>` | Bell badge |
| `savingConfigProvider` | `features/instant_saving/controller/saving_controller.dart:8` | `FutureProvider.autoDispose<SavingConfig>` | `sellRateLockSeconds` — **cross-feature import**, see §6 |
| `profileProvider` | `features/profile/profile_controller.dart:331` | — | Latest name/photo/referral message — **cross-feature import** |
| `selectedTabProvider` | `features/main/main_screen.dart:23` | `StateProvider<int>` | Detects Home tab becoming active — **cross-feature import** |
| `languageProvider` (`ref.tr`) | `core/localization/language_provider.dart` | — | i18n strings (`welcome`, `goldLabel`, `silverLabel`) |

## 5. Key Behaviors (see DATA_FLOW.md for full traces)

1. **Dashboard load** — `homeDashboardProvider` fires a `POST home/dashboard` with `id_metal`
   (`core/services/home_service.dart:9-21`); re-fires whenever `selectedMetalIdProvider` (i.e. the
   gold/silver toggle) changes, since it's a `FutureProvider` depending on it via
   `home_dashboard_provider.dart:17`.
2. **Live-rate timer lifecycle** — `sellRateTimerProvider` locks the currently-streamed `MarketRates` for
   `SavingConfig.sellRateLockSeconds` (`timer_provider.dart:41-59`); on expiry it silently restarts with the
   freshest rate (`timer_provider.dart:80-105`) rather than trying to independently detect market closure
   (see code comment `timer_provider.dart:81-103` explaining a prior bug where timestamp-based closure
   detection caused a "shake" on every timer boundary).
3. **Race-condition guard (market reopen vs. first rate frame)** — CONFIRMED, `home_screen.dart:97-125`.
   When market status flips closed→open, the timer is cleared and restarted immediately
   (`home_screen.dart:79-95`), but the socket's `3|...` rate frame may not have arrived yet, so the newly
   "locked" rate can be `0`. A second `ref.listen` on `marketRatesStreamProvider`
   (`home_screen.dart:100-125`) watches for the first non-zero live rate while the timer `isActive` and its
   locked rate is `<= 0`, and re-locks (`startOrRefresh`) as soon as one arrives. This matches the
   hand-written doc's "Race Condition Guard" claim almost verbatim — **confirmed, not drift**.
4. **Tab-refresh** — `ref.listen<int>(selectedTabProvider, ...)` (`home_screen.dart:132-163`) fires only on
   the transition *into* tab 0 (`next == 0 && prev != 0`), refreshing (via `Future.microtask`): portfolio,
   `homeDashboardProvider` (invalidate), `countdownOfferProvider` (invalidate), `profileProvider`
   (invalidate), notification badge, and — if the market is open — resets and restarts the sell-rate timer.
   Pull-to-refresh (`RefreshIndicator.onRefresh`, `home_screen.dart:178-185`) does the same minus the timer
   reset.
5. **Commodity toggle** — `_buildCommodityPillTab` taps call
   `commodityProvider.notifier.setCommodity(...)` (`home_screen.dart:1496-1506`). Because `commodityProvider`
   is a single shared `StateNotifierProvider` (not per-screen), the toggle state is **shared globally**
   across Home, InstantSaving, Withdrawal, etc. — confirmed by `selectedMetalIdProvider` in
   `commodity_provider.dart:26-41` deriving `id_metal` from it for every consumer.

## 6. Architecture Rule Violations Found

Per `AGENTS.md` §1: *"never import one feature's internals directly from another feature."* `home_screen.dart`
violates this three times:
- `import '../instant_saving/controller/saving_controller.dart';` (`home_screen.dart:28`) — pulls in
  `savingConfigProvider` for `sellRateLockSeconds`.
- `import '../profile/profile_controller.dart';` (`home_screen.dart:19`) — pulls in `profileProvider`.
- `import '../main/main_screen.dart';` (`home_screen.dart:20`) — pulls in `selectedTabProvider`.

None of these three providers live in `core/`, so Home has a direct compile-time dependency on three sibling
features' internals. Flagged for `_SYSTEM/MODULE_DEPENDENCIES.md` and `DANGER_ZONES.md` candidate: changing
`saving_controller.dart`, `profile_controller.dart`, or `main_screen.dart` can silently break Home.

## 7. Top Risks / Fragile Areas

- **Rate display precedence** (`home_screen.dart:1081-1088`): when market is closed, the header
  *deliberately* ignores `timerState.lockedRates` (which may be stale) and falls back to
  `marketRates.valueOrNull` (already zeroed for that commodity by
  `native_socket_service.dart:164-183`) — i.e. showing `₹0.00/gm` is the intended closed-market display, not
  a bug.
- **Countdown timer in `CountdownOfferNew` is 100% client-side** (`widgets/countdown_offer_new.dart:47-70`):
  it seeds from the API's `remaining_days/hours/minutes/seconds` once, then ticks locally every second with
  no re-sync against the server clock. A long-backgrounded app or clock drift will show a stale countdown
  until the API is re-fetched (tab-refresh / pull-to-refresh only, no periodic re-fetch).
- **Portfolio value recalculation fallback** (`home_screen.dart:1287-1305`): if the API's `current_value`
  is `0` but `balance > 0` and a live rate exists, the screen recomputes `currentValue`/`returns` client-side
  from `balance * liveRate`. This is a UI-layer financial calculation outside the service layer — flagged per
  `AGENTS.md` §2 (financial-calc safety) as tech debt to note, not silently fix.
- Three cross-feature imports (§6) — a refactor in `instant_saving`, `profile`, or `main` can break Home
  with no compiler error if the imported provider's shape changes.
- `_formatIndianRate` (`home_screen.dart:1122-1148`) hand-rolls Indian-style digit grouping with two parallel
  loops (`buffer` unused-result loop at :1132-1136 followed by a second `groups` loop at :1138-1144 that
  actually produces the output) — dead code (`buffer`) left in place; verify before extending.

## 8. Drift vs. `STARTGOLD_DOCUMENTATION.md` §3.10

| Hand-written doc claim | Live code | Verdict |
|---|---|---|
| `POST users/portfolio` | `POST portfolio/summary` (`core/services/portfolio_service.dart:12`) | **Drift** — wrong path |
| `GET users/home/dashboard` | `POST home/dashboard` (`core/services/home_service.dart:11`) | **Drift** — wrong verb + path |
| `POST users/notifications/unread-count` | `POST users/notifications/unread-count` (`notification_service.dart:83`) | Confirmed |
| Sell Rate Timer locks rate for `sell_rate_lock_seconds` | Confirmed — `SavingConfig.sellRateLockSeconds`, `saving_models.dart:6,33`, consumed `timer_provider.dart:41-59` | Confirmed |
| Market status via socket `5|...|1/0` | Confirmed — `native_socket_service.dart:142-192` | Confirmed |
| Race-condition guard: reopen restarts timer, re-locks on first non-zero rate | Confirmed — `home_screen.dart:79-125` | Confirmed |
| Tab refresh invalidates all providers | Confirmed, and more specific than doc states — see §5.4 | Confirmed (elaborated) |
| Not mentioned at all: 100-Day Grand Launch Countdown Offer (`countdown_offer_*`), `MicroSavingsBanner`, `LearnCarousel` API-driven banners, `OfferWebViewScreen`, `home/countdown-offer` endpoint | Present and substantial in live code | **Gap** — hand doc predates this feature |

## 9. See Also

- `DATA_FLOW.md` — full sequence diagrams for dashboard load, timer lifecycle, market toggle, pull-to-refresh
- `BUSINESS_RULES.md` — RULE-HOME-NNN entries
- `CROSS_MODULE_MAP.md` — full `core/` + cross-feature dependency graph
- `STATE_ANALYSIS.md` — every provider/model in detail
- `FORENSIC_TEMPLATE.md` — symptom → suspect playbook
