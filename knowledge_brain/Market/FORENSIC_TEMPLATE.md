# Market — Forensic Template

Symptom → check first → likely suspects. Use alongside `_SYSTEM/DIAGNOSTIC_PLAYBOOK.md` once
that's built at the system level.

---

### Symptom: "Rates froze — the price on screen never updates, even though the market should be open"
**Check first**: `socketStatusProvider` value (add a temporary debug print/watch) — is it stuck
on `connecting` or `error`?
**Likely suspects**:
1. Socket genuinely disconnected and is mid-retry — `_scheduleReconnect` retries every 5s
   forever (`native_socket_service.dart:119-128`), so it *should* self-heal; if it's been much
   longer than 5s, check whether `dispose()` was accidentally called (e.g. the provider got torn
   down and recreated in a disposed state — check `_isDisposed` guard at `connect():75`).
2. A rate-lock timer (`buyRateTimerProvider`/`sellRateTimerProvider`) is active and legitimately
   showing a locked (frozen-by-design) rate — check `timerState.isActive` before assuming this is
   a bug at all (`timer_provider.dart:18-19`).
3. The tick arrived but was below the `isSignificantChange` threshold (`> 0.001`) and was
   silently dropped (`market_rates.dart:177-184`) — expected behavior for a genuinely flat
   market, not a bug.
4. App was backgrounded — socket is intentionally disconnected
   (`app_lifecycle_observer.dart:61-62`) and only reconnects on resume.

---

### Symptom: "Socket disconnects and never reconnects"
**Check first**: is `NativeSocketService.dispose()` being called unexpectedly? Search for
`ref.invalidate(socketIOServiceProvider)` or the provider being scoped under an `autoDispose`
ancestor that's tearing down.
**Likely suspects**:
1. `dispose()` sets `_isDisposed = true` permanently — there is no "undispose." Once disposed,
   `connect()` becomes a permanent no-op (`native_socket_service.dart:75`). If the singleton
   provider itself got recreated (e.g. `environmentProvider` changed — switching
   staging/production), the *old* instance disposes correctly but make sure the *new* instance is
   actually the one being watched by the screen (stale `ref.read` reference is a classic Riverpod
   pitfall here).
2. `_reconnectTimer` was cancelled by a `disconnect()` call that raced with `_scheduleReconnect`
   (e.g. rapid background/foreground toggling) — inspect timer cancel/schedule ordering in
   `_scheduleReconnect()` (`native_socket_service.dart:119-128`) and `disconnect()`
   (`native_socket_service.dart:213-219`) for the specific sequence that occurred.

---

### Symptom: "Market status flag is wrong — shows closed when it should be open, or vice versa"
**Check first**: raw socket frames (if you can get a packet capture / server-side log) — confirm
what `5|<id>|<name>|<status>` frames actually arrived and in what order relative to `3|` frames.
**Likely suspects**:
1. **1-second grace-period false-close** (RULE-MARKET-005): if the server is slow to send the
   first `5|` frame (>1s after connect) and rates happen to still be zero, the client infers
   closed on its own, then flips back open once the real frame arrives — a visible flicker on
   slow networks. Check `_inferClosedAfterGracePeriod()` (`native_socket_service.dart:223-253`).
2. **Absent-key-means-open default** (RULE-MARKET-004): if a commodity's `5|` frame is dropped
   entirely (server bug, network filtering), every consumer treats it as open forever — there is
   no "unknown" state distinct from "open" anywhere in this pipeline.
3. Mismatched commodity ID: if `commoditiesProvider`'s `id_metal` values don't match what the
   socket actually sends in `parts[1]`, `updateCommodityConfig` will have configured the wrong
   `goldId`/`silverId`, so status/rate frames silently fail to match either commodity and get
   ignored. Cross-check the live `Commodity.id` values against the socket's `commodity_id` field.

---

### Symptom: "Buy or sell rate shows an obviously wrong value (e.g. identical to the other side, or a stale number)"
**Check first**: `MarketRates.fromRawString`'s fallback logic
(`market_rates.dart:71-74`) — did the raw frame actually send `-` or an unparseable string for
one side?
**Likely suspects**:
1. RULE-MARKET-002's buy=sell fallback masking a real backend data issue — this is working as
   designed from the client's perspective, but the *backend* frame itself may be malformed;
   escalate to backend if it's persistent rather than a one-off tick.
2. A commodity absent from the current frame retained its `previous` value (by design) — if the
   backend stopped sending that commodity's line entirely, the client will keep showing the last
   good value indefinitely with no staleness indicator (there's no "this rate is N seconds old"
   UI wired to `MarketRates.timestamp` in any consumer checked in this pass — unconfirmed whether
   any screen surfaces staleness at all).

---

### Symptom: "Rate-lock timer restarts repeatedly / UI shakes"
**Check first**: is any code comparing `MarketRates.timestamp` against the timer's start/end time
to infer market closure? That pattern was removed and is explicitly called out as an
anti-pattern.
**Likely suspects**:
1. Reintroduced timestamp-based closed detection (see RULE-MARKET-010,
   `timer_provider.dart:80-104` for the full postmortem) — grep for any new comparison of
   `lockedRates.timestamp` against wall-clock time before concluding this is a new bug.
2. A genuine race between the `5|` reopen frame and the first non-zero `3|` frame — every
   consumer screen has a `ref.listen(marketRatesStreamProvider, ...)` specifically to catch this
   and restart once a valid non-zero rate arrives (e.g. `home_screen.dart:100-107`); if that
   listener is missing on a *new* screen that also uses the rate timers, add it — its absence
   is the most likely explanation for a new occurrence of this symptom on a screen not covered
   in this pass.

---

### Symptom: "Selected commodity (gold/silver) resets unexpectedly"
**Check first**: `commodityProvider`'s lifetime — is the widget tree rebuilding the provider
scope (e.g. via a `ProviderScope` override or `autoDispose` ancestor)?
**Likely suspects**:
1. Expected behavior on app cold start: `commodityProvider` always initializes to
   `CommodityType.gold` (`commodity_provider.dart:7`) — there is no persistence of the user's
   last-selected tab across app restarts (see `STATE_ANALYSIS.md`).
2. A widget calling `ref.invalidate(commodityProvider)` or a similar reset — grep for
   `invalidate` near the affected screen.
