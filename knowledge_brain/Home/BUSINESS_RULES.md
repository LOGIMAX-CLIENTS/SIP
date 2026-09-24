---
module: Home
last_updated: 2026-08-19
---

# Home — Business Rules

## RULE-HOME-001 — Sell rate is locked for a configured duration after being fetched
The header's displayed sell rate is not the raw live socket value while the timer is active; it is frozen
(`TimerState.lockedRates`) for `SavingConfig.sellRateLockSeconds` seconds, refreshed automatically on
expiry.
- Code: `RateTimerNotifier.startOrRefresh` (`core/providers/timer_provider.dart:41-59`), consumed in
  `home_screen.dart:1081-1088`.
- Source of duration: `POST savings/config` → `sell_rate_lock_seconds` (`saving_models.dart:6,33`,
  `saving_service.dart:9`).

## RULE-HOME-002 — Market-closed display overrides the rate lock
When the selected commodity's market is closed, the header ignores any locked rate (even if the timer is
still counting down) and shows the live (zeroed) socket rate instead — i.e. `₹0.00/gm` with a "CLOSED"
badge, not a stale locked price.
- Code: `home_screen.dart:1081-1088` (`lockedRates` set to `null` when `isMarketClosed`); zeroing itself
  happens in `native_socket_service.dart:164-183`.

## RULE-HOME-003 — Market reopen forces an immediate timer restart
When a commodity's market status flips closed→open (via socket `5|id|name|1` frame), the sell-rate timer is
cleared and restarted immediately rather than waiting for its current cycle to finish, so the header switches
from "CLOSED" back to "LIVE + countdown" without delay.
- Code: `home_screen.dart:79-95`, `RateTimerNotifier.clear()` (`timer_provider.dart:107-111`).

## RULE-HOME-004 — Race-condition guard: never display a zero-rate lock while market is open
If the timer is active but its locked rate for the selected commodity is `<= 0` (can happen in the gap
between a reopen event and the first subsequent rate frame), the app re-locks as soon as a non-zero rate
arrives, rather than showing `₹0.00` for the full lock duration.
- Code: `home_screen.dart:97-125` (confirmed against hand-written doc's "Race Condition Guard" claim).
- Precondition: only applies while `marketStatusProvider` reports the commodity open (`home_screen.dart:105-107`).

## RULE-HOME-005 — Home tab reactivation triggers a full data refresh
Every provider that can go stale while the user was on another tab (portfolio, dashboard sections,
countdown offer, profile, notification badge) is refreshed the moment the bottom-nav Home tab (index 0)
becomes active again — covers returning from a purchase/withdrawal success screen as well as manual tab
taps.
- Code: `ref.listen<int>(selectedTabProvider, ...)` (`home_screen.dart:132-163`), gated on
  `next == 0 && prev != 0` so it does not fire on first build.
- If the market is open at that moment, the sell-rate timer is also cleared and restarted with the freshest
  rate (`home_screen.dart:146-159`).

## RULE-HOME-006 — Gold/Silver toggle state is global, not screen-local
`commodityProvider` is a single app-wide `StateNotifierProvider`; switching commodity on Home changes
`selectedMetalIdProvider` for every consumer app-wide (portfolio, dashboard, and — per `AGENTS.md` — other
features such as InstantSaving/Withdrawal that also read it), not just the Home screen's own display.
- Code: `commodity_provider.dart:14-17` (notifier), `:26-41` (`selectedMetalIdProvider` derivation).

## RULE-HOME-007 — New-customer state hides the portfolio card
If `userProvider.isNewUser == true` OR the portfolio API's `isNewCustomer` flag is true (derived as
`invested == 0 && balance == 0`, `portfolio_service.dart:36`), the portfolio-overview card is replaced by a
"From pocket change... with just ₹10" welcome banner with its own Gold/Silver toggle.
- Code: `home_screen.dart:267-320` (`AnimatedSwitcher` branch), `_buildNewCustomerBanner`
  (`home_screen.dart:1719-1833`).

## RULE-HOME-008 — Countdown offer visibility and shape is fully server-driven
The 100-Day Grand Launch offer card only renders when `CountdownOfferResponse.enabled == true`; which
sub-widget renders (`CountdownOfferNew` vs `CountdownOfferExisting`) is decided by the server's
`customer_type` field, not by client-side new/existing-customer logic (distinct from RULE-HOME-007, which
uses a different signal). Any API failure or malformed payload silently hides the whole card
(`SizedBox.shrink()`), never shows an error state.
- Code: `countdown_offer_widget.dart:21-41`, `CountdownOfferResponse.fromJson`
  (`countdown_offer_model.dart:21-59`), `HomeService.getCountdownOffer` catch-all
  (`core/services/home_service.dart:28-39`).

## RULE-HOME-009 — Countdown-offer timer does not re-sync with the server after initial load
`CountdownOfferNew`'s days/hours/minutes/seconds are seeded once from the API response and then tick down
locally every second for the lifetime of the widget; there is no periodic re-fetch to correct for clock
drift or a long-backgrounded app. The only re-sync point is a provider invalidation (tab-refresh or
pull-to-refresh), which remounts the widget with fresh state.
- Code: `widgets/countdown_offer_new.dart:38-70`.

## RULE-HOME-010 — Portfolio value has a client-side zero-value fallback recompute
If the portfolio API returns `current_value_inr: 0` but the user has a non-zero gram balance and a non-zero
live rate is available, the screen recomputes `currentValue = balance * liveRate`,
`returns = currentValue - totalInvested`, and `returnsPercentage` accordingly, purely for display — this is
a UI-layer financial calculation, not one done by the API or a service, and should be treated as tech debt
per `AGENTS.md` §2 rather than a pattern to extend.
- Code: `home_screen.dart:1287-1305`.

## RULE-HOME-011 — Discover/Learn/Footer sections fall back to static content when the API returns empty
If `InvestSection.blocks` is empty, `LearningSection.banners` is empty, the screen falls back to hardcoded
static assets (`MicroSavingsBanner` + a "Safe & Secure" card for Invest; `assets/home/learn1.png`..`learn3`
for Learn) rather than rendering an empty section.
- Code: `_buildInvestContent` (`home_screen.dart:736-750`), carousel image fallback
  (`home_screen.dart:478-486`).
