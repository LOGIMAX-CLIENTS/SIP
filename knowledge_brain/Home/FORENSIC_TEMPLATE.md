---
module: Home
last_updated: 2026-08-19
---

# Home — Forensic Template

Symptom → check first → likely suspects, for the recurring bug shapes this module's architecture makes
possible. Cross-reference `DATA_FLOW.md` for the full traces and `BUSINESS_RULES.md` for the RULE-HOME-NNN
each suspect maps to.

---

## Symptom: Rates stuck at zero (header shows ₹0.00/gm while market should be open)

**Check first:**
1. Is `marketStatusProvider` actually reporting this commodity as open? (`ref.watch(marketStatusProvider)` in
   `home_screen.dart:72-73`) — if the socket never sent a `5|...` frame and the 1s grace-period inference
   (`native_socket_service.dart:106-111,221-253`) fired closed, the UI will correctly show CLOSED, which is
   a different bug (see next symptom).
2. If market status says OPEN but rate is still `0`: is `sellRateTimerProvider.lockedRates` for this
   commodity `<= 0`? Check `timer_provider.dart` state via debug print in `_evaluateTimer`.
3. Has the race-condition guard (`home_screen.dart:97-125`, RULE-HOME-004) actually fired? It only re-locks
   when `marketRatesStreamProvider` emits a *new* frame — if the socket itself is silent (no frames at all
   post-reopen), the guard never gets a chance to run because it's listener-driven, not polling.

**Likely suspects:**
- Socket reconnect loop stuck (`native_socket_service.dart:119-128`, 5s reconnect timer) — check
  `socketStatusProvider` for repeated `connecting`/`error` cycles.
- `NativeSocketService._handleRateUpdate` never receiving a `3|...` frame for this `goldId`/`silverId` — id
  mismatch between `commoditiesProvider`'s `id_metal` and what the socket actually sends (see
  `market_provider.dart:26-30` comment warning `web_soc_id` must NOT be used, only `id_metal`).
- `RateTimerNotifier.startOrRefresh` returning early because `marketRatesStreamProvider` has no value yet
  (`timer_provider.dart:46-47`) — a genuine "no rate ever arrived" case, not a bug in the guard itself.

---

## Symptom: Market status badge wrong (shows LIVE when market is actually closed, or vice versa)

**Check first:**
1. Which commodity is selected? Status is per-commodity (`marketStatusMap[commodityId]`,
   `home_screen.dart:74-75`) — confirm the bug is on the currently-toggled commodity, not the other one.
2. Was there ever an explicit `5|commodityId|name|status` frame for this commodity, or is the app relying on
   the 1-second grace-period inference (`native_socket_service.dart:221-253`)? The inference only fires once,
   1 second after connect, and only for commodities with NO explicit status yet — a late-arriving `5|` frame
   after that window is still authoritative and should update the map (`:154-159`), but if the grace period
   inferred `false` and the real server never sends an explicit frame, the UI is stuck on the inferred value
   until reconnect.
3. Check `_commodityOpenStatus` default — a commodity absent from the map is treated as **open**
   (`market_provider.dart:57`, `native_socket_service.dart:32-34` doc comment) — so "missing" and "closed"
   are visually different; if the badge shows LIVE for a commodity that should show unknown/closed, this
   default-open behavior is the first thing to check.

**Likely suspects:**
- Commodity ID mismatch between `commoditiesProvider` (`shared_service.dart`, `id_metal` field) and the
  socket's own commodity IDs — same class of bug as the rates-stuck-at-zero symptom.
- Grace-period timer (1s) too short for a slow initial connection, causing a false "closed" inference that
  then never gets corrected because the server only sends `5|` frames on actual status *changes*, not on a
  steady-state poll.

---

## Symptom: Portfolio value wrong / stale after tab switch (Gold↔Silver toggle, or bottom-nav tab switch)

**Check first:**
1. Bottom-nav tab switch: did `ref.listen<int>(selectedTabProvider, ...)` actually fire? It only triggers on
   `next == 0 && prev != 0` (`home_screen.dart:133`) — switching from Home to itself, or a state where
   `prev` was already `0` on some rebuild, will not refresh. Check with a debug print inside the listener.
2. Gold↔Silver toggle: is `_portfolioCache` (`portfolio_provider.dart:97`) serving stale cached data for the
   just-selected metal? The cache is keyed by `idMetal` and never expires/invalidates on its own — only a
   fresh `fetchPortfolio()` call overwrites an entry (`:81`). If the API silently started returning different
   numbers for the same metal (e.g. after a purchase on a *different* screen that doesn't trigger Home's tab
   listener), the cached value can be shown until the next explicit refresh.
3. Confirm whether `_buildPortfolioOverview`'s client-side recompute (RULE-HOME-010,
   `home_screen.dart:1287-1305`) is firing — if `currentValue == 0` from the API but a stale `liveRate` is
   being used (e.g. wrong commodity's rate due to a toggle mid-flight), the displayed value can be wrong even
   though the raw API data is correct.

**Likely suspects:**
- A purchase/withdrawal completed on a screen that does NOT route back through the "tab becomes active"
  transition (e.g. deep-link, or a success screen that pops directly without switching
  `selectedTabProvider` back to `0` first) — RULE-HOME-005's refresh never fires.
- `PortfolioNotifier.fetchPortfolio()` swallowing an error and keeping `prev` visible
  (`portfolio_provider.dart:83-90`) — the UI shows OLD data with no visible error indicator when the API
  call actually failed.
- Race between the commodity toggle changing `selectedMetalIdProvider` and the `autoDispose` portfolio
  provider being recreated — if `_portfolioCache` doesn't yet have an entry for the new metal, it falls back
  to "any previous data" (`portfolio_provider.dart:58-62`), which will show the WRONG metal's numbers for one
  frame/fetch cycle. Confirm this isn't lingering longer than expected.

---

## Symptom: Countdown offer card missing / wrong customer type shown

**Check first:**
1. Is the user actually logged in with a non-empty `id`? `countdownOfferProvider` returns
   `.disabled()` immediately for a null/empty-id user (`countdown_offer_provider.dart:16-17`) — no network
   call is even made.
2. Check the raw API response shape — `enabled`, `customer_type` (`"NEW"`/`"EXISTING"`), and the matching
   `new_offer`/`existing_offer` object must all be present and non-null, or the widget falls through to
   `SizedBox.shrink()` (`countdown_offer_widget.dart:31-36`) even if `enabled: true`.
3. Any API error (network, non-200, malformed JSON) is swallowed to `.disabled()`
   (`home_service.dart:35-38`) — there is no visible error state for this card by design (RULE-HOME-008); a
   "missing" card is often a silent backend/network failure, not a rendering bug.

**Likely suspects:**
- `HomeService.getCountdownOffer()` `POST home/countdown-offer` returning `success: false` or a shape the
  model doesn't expect (e.g. new API field names) — check raw response in `SecureLogger.e` output.
- `webviewUrl` resolution logic (`countdown_offer_model.dart:41-46` for existing customers) picking up the
  wrong URL if both `data.webview_url` and `existing_offer.webview_url` are present with different values —
  `existing_offer`'s own key wins only if present.

---

## Symptom: Header greeting/name or referral message wrong or stale

**Check first:**
1. Home reads name from TWO sources with `profileState` taking priority: `profileState.user.name` if
   non-empty, else `userProvider?.name` (`home_screen.dart:168-170`). Confirm which one is actually stale —
   `profileProvider` is invalidated on tab-refresh/pull-to-refresh (RULE-HOME-005), `userProvider` derives
   from `authControllerProvider.sessionData` and is NOT explicitly invalidated by Home at all.
2. Referral message only shows when `isMarketClosed && referralMsg.isNotEmpty`
   (`home_screen.dart:1513-1547`) — an "invisible" referral message during open-market hours is expected
   behavior, not a bug.

**Likely suspects:**
- Cross-feature coupling (`MODULE_BRAIN.md` §6): a change to `profile_controller.dart`'s `ProfileState` shape
  or field names breaks Home's greeting/referral display with no compile error if Dart's null-safety still
  type-checks (e.g. a renamed-but-still-`String` field silently returns empty).
