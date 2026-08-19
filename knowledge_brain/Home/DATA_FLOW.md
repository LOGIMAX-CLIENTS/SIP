---
module: Home
last_updated: 2026-08-19
---

# Home — Data Flow

## Flow 1 — Dashboard Load (cold start / commodity switch)

```
MainScreen builds IndexedStack, tab 0 = HomeScreen (main_screen.dart:163)
  → HomeScreen.initState() (home_screen.dart:41)
      → postFrameCallback: ref.read(notificationProvider.notifier).refreshUnreadCount()
            (home_screen.dart:45) → NotificationService.fetchUnreadCount()
            → POST users/notifications/unread-count (notification_service.dart:82-83)

  → HomeScreen.build() (home_screen.dart:50) watches:
      • commodityProvider (commodity_provider.dart:14)              → CommodityType.gold|silver
      • selectedMetalIdProvider (commodity_provider.dart:26)         → real id_metal string
      • userProvider (user_provider.dart:28)
      • profileProvider (features/profile/profile_controller.dart:331)
      • portfolioProvider (portfolio_provider.dart:99)
            → PortfolioNotifier(service, idMetal, idCustomer) constructor calls fetchPortfolio()
              (portfolio_provider.dart:64-65,67-91)
              → PortfolioService.getPortfolioSummary(idMetal, idCustomer)
                → POST portfolio/summary { id_metal } (core/services/portfolio_service.dart:11-17)
              → caches result in module-level _portfolioCache[idMetal] (portfolio_provider.dart:81,97)
                so switching Gold↔Silver shows cached data instantly (no skeleton flicker)
      • marketRatesStreamProvider (market_provider.dart:16)          → live socket rates (Flow 2)
      • sellRateTimerProvider (timer_provider.dart:121)              → rate-lock countdown (Flow 2)
      • savingConfigProvider (features/instant_saving/controller/saving_controller.dart:8)
            → SavingService.getSavingConfig() → POST savings/config (saving_service.dart:9)
            → yields SavingConfig.sellRateLockSeconds (saving_models.dart:6,33)
      • marketStatusProvider (market_provider.dart:58)               → per-commodity open/closed map
      • homeDashboardProvider (home_dashboard_provider.dart:9)
            → guards on userProvider != null (home_dashboard_provider.dart:13-14)
            → HomeService.getHomeDashboard(idMetal)
              → POST home/dashboard { id_metal } (core/services/home_service.dart:9-21)
              → HomeDashboard.fromJson (home_dashboard.dart:14-29): rate_history, invest_sections,
                learning_sections, footer_info
            → re-fires automatically whenever selectedMetalIdProvider changes (commodity toggle)
      • countdownOfferProvider (countdown_offer_provider.dart:14)
            → guards on userProvider != null (countdown_offer_provider.dart:16-17)
            → HomeService.getCountdownOffer() → POST home/countdown-offer (home_service.dart:28-39)
              → CountdownOfferResponse.fromJson; on any error returns .disabled() (fails silently,
                widget renders SizedBox.shrink — home_service.dart:33-38, countdown_offer_widget.dart:39)

  → Render: header (rate + LIVE/CLOSED badge) → portfolio card OR new-customer banner
      (AnimatedSwitcher keyed by data-shape, home_screen.dart:267-320) → countdown offer card
      (home_screen.dart:330-366) → dashboard content (rate-history / invest / discover / learn / support /
      footer, home_screen.dart:367-387, built by _buildDashboardContent at :394)
```

## Flow 2 — Live-Rate Timer Lifecycle (sell-rate lock + race-condition guard)

```
Socket connects (market_provider.dart:16, socketIOServiceProvider.connect() at market_provider.dart:44)
  → NativeSocketService._handleRateUpdate() (native_socket_service.dart:130-211) parses pipe-delimited
    frames line by line:
      • "5|commodity_id|name|status" → market open/closed per commodity (native_socket_service.dart:148-192)
          - status '1' = open, '0' = closed (native_socket_service.dart:150)
          - on close: zeroes ONLY that commodity's rates, preserves the other's (native_socket_service.dart:164-183)
          - cancels the 1s post-connect "grace period" inference timer once any explicit 5| frame arrives
            (native_socket_service.dart:108-111, 152)
      • "3|id|...|buy|sell" → MarketRates.fromRawString (market_rates.dart:44-126)
  → marketRatesStreamProvider emits new MarketRates (market_provider.dart:16-46)
  → marketStatusProvider emits new Map<String,bool> (market_provider.dart:58-61)

Timer bootstrap (home_screen.dart:62-69):
  ref.listen(savingConfigProvider, ...) → once config resolves AND timer not already active
    → sellRateTimerProvider.notifier.startOrRefresh(config.sellRateLockSeconds)

RateTimerNotifier.startOrRefresh(durationSeconds) (timer_provider.dart:41-59):
  → reads current marketRatesStreamProvider value; if null, returns (waits for first socket message)
  → sets state = TimerState(remainingSeconds: duration, lockedRates: currentRates)
  → Timer.periodic(1s) → _evaluateTimer() (timer_provider.dart:61-78)
       remaining > 0  → tick down, keep lockedRates fixed
       remaining <= 0 → cancel tick, _refreshAndRestart() (timer_provider.dart:80-105)
                          → startOrRefresh(_totalDuration) again with the LATEST live rate
                          → deliberately does NOT infer market-closed from timestamp gaps (see the
                            in-code postmortem comment at timer_provider.dart:81-103 — a prior version did,
                            and it caused a "shake" bug because the socket can go quiet for a while even
                            while the market is open)

Market-reopen restart (home_screen.dart:79-95):
  ref.listen(marketStatusProvider, ...) → when currId's status flips closed→open:
    → sellRateTimerProvider.notifier.clear() (timer_provider.dart:107-111, resets to remainingSeconds:0)
    → immediately startOrRefresh(config.sellRateLockSeconds) again

RACE-CONDITION GUARD (home_screen.dart:97-125) — CONFIRMED, matches hand-written doc claim:
  ref.listen(marketRatesStreamProvider, ...) on every new rate frame, while market is open:
    liveRate = rates.goldSell | rates.silverSell for the selected commodity
    if liveRate <= 0 → return (still nothing to lock)
    lockedRate = timer.lockedRates?.goldSell|silverSell ?? 0.0
    if timer.isActive AND lockedRate <= 0:
        → startOrRefresh(config.sellRateLockSeconds) again, this time locking the non-zero rate
  This covers exactly the gap between "5|...|1 market reopen" (which restarts the timer immediately, before
  any 3|... rate has arrived) and the first subsequent non-zero rate frame — the header would otherwise show
  a locked ₹0.00 for up to sellRateLockSeconds.

Header rate display precedence (home_screen.dart:1081-1088):
  isMarketClosed          → ignore lockedRates entirely, use marketRates.valueOrNull (already zeroed by the
                              socket service for the closed commodity)
  timer.isActive           → use timerState.lockedRates
  else                      → fall back to marketRates.valueOrNull, else 0.0
```

## Flow 3 — Market-Status Toggle Handling (gold ↔ silver, open ↔ closed)

```
User taps Gold/Silver pill (_buildCommodityPillTab onTap, home_screen.dart:1496-1506)
  → commodityProvider.notifier.setCommodity(type) (commodity_provider.dart:9-11)
  → selectedMetalIdProvider recomputes id_metal from the live commoditiesProvider list
    (commodity_provider.dart:26-41, falls back to '1'/'3' only while list is loading)
  → Downstream providers that depend on selectedMetalIdProvider auto-refetch:
      • portfolioProvider (portfolio_provider.dart:106) — new PortfolioNotifier instance (autoDispose),
        seeded from _portfolioCache if this metal was fetched before (no flicker)
      • homeDashboardProvider (home_dashboard_provider.dart:17) — re-fetches POST home/dashboard
  → HomeScreen re-derives commodityId ('1' gold / '3' silver, home_screen.dart:74) and reads
    marketStatusProvider[commodityId] to compute isCurrentMarketClosed (home_screen.dart:73-75)
  → If closed: amber "market closed" banner appended under the toggle (home_screen.dart:1550-1584), header
    shows _ClosedBadge (home_screen.dart:1983) and rate falls back to live (zeroed) socket value, not the
    stale lock (see Flow 2 precedence).
  → If a referral message is present (profileProvider.user.referralMessage) it renders in an amber info box
    ONLY while the market is closed (home_screen.dart:1513-1547) — closed-market cross-sell nudge.

Market open/closed per-commodity itself is driven purely by the socket (Flow 2's "5|..." frames); the
commodity toggle only changes WHICH commodity's status/rate the UI reads, it does not affect the socket
connection itself (both commodities' rates stream simultaneously; the toggle just changes display filter).
```

## Flow 4 — Pull-to-Refresh

```
RefreshIndicator.onRefresh (home_screen.dart:178-185):
  → ref.read(portfolioProvider.notifier).fetchPortfolio()   — re-POST portfolio/summary
  → ref.invalidate(homeDashboardProvider)                    — re-POST home/dashboard on next read
  → ref.invalidate(countdownOfferProvider)                   — re-POST home/countdown-offer
  → ref.invalidate(profileProvider)                          — refreshes name/photo/referral message
  → ref.read(notificationProvider.notifier).refreshUnreadCount() — re-POST notifications/unread-count

Notably, pull-to-refresh does NOT touch sellRateTimerProvider (unlike the tab-refresh flow below) — the
rate-lock countdown keeps running through a manual refresh.

Compare: Tab-refresh (home_screen.dart:132-163, fires on selectedTabProvider transitioning TO 0):
  Same 5 calls as above, PLUS: if market is currently open, clears and restarts sellRateTimerProvider with
  the freshest live rate — deferred via Future.microtask so it runs after the build frame completes; the
  in-code comment (home_screen.dart:129-131) notes navigation-success screens use a 350ms delay before
  switching tabs specifically so this refresh fires after their own exit animation finishes.
```
