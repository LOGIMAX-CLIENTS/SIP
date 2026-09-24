# Market — Business Rules

Format: `RULE-MARKET-NNN`: plain-English rule → code that implements it.

---

### RULE-MARKET-001 — Rate updates are deduplicated by significance, not by frame arrival
A new tick is only pushed to consumers if `isSignificantChange` is true: the commodity name
changed, or any buy/sell value moved by more than `0.001`. Sub-threshold noise from the socket
never reaches the UI.
- Code: `market_rates.dart:177-184` (`isSignificantChange`), `native_socket_service.dart:204-207`
  (the gate before `_ratesController.add(newRates)`).

### RULE-MARKET-002 — Buy/sell fallback when one side is malformed
If the socket sends `-` (or anything unparsable) for buy or sell while the other side parses
successfully, the malformed side is set equal to the valid side rather than left at `0.0`.
- Code: `market_rates.dart:71-74`.
- Risk: this masks a genuinely malformed frame as a valid (if imprecise) rate — a screen showing
  identical buy/sell for one tick is not necessarily a UI bug, check the raw frame first.

### RULE-MARKET-003 — Market open/closed is tracked per commodity, independently
Gold and silver each have their own open/closed flag in `_commodityOpenStatus`. Closing one
metal does not affect the other's displayed rate or lock state.
- Code: `native_socket_service.dart:44,146-192`.

### RULE-MARKET-004 — A commodity absent from the status map is assumed OPEN
Every consumer computes `isCurrentMarketClosed = marketStatusMap[commodityId] == false` — i.e.
missing key (no signal yet) is treated as open, not closed, not unknown/loading.
- Code: `market_provider.dart:54-57` (doc comment), and every consumer
  (`home_screen.dart:73-75`, `instant_saving_screen.dart:133-137`,
  `withdrawal_screen.dart:95-99`, `payment_methods_screen.dart:96-99`).
- Consequence: on cold start, before the first `5|` frame or the 1s grace-period inference runs,
  the UI briefly assumes the market is open even if it's actually closed.

### RULE-MARKET-005 — 1-second grace period infers "closed" only from silence + zero rates
If no explicit `5|` frame arrives for a commodity within 1 second of connecting, AND that
commodity's rates are still `0`, it's inferred closed. A commodity that already has non-zero
rates (e.g. from a prior `_lastRate` before a reconnect) is never grace-period-closed.
- Code: `native_socket_service.dart:106-111, 221-253`.

### RULE-MARKET-006 — Socket reconnects on a fixed 5-second delay, unconditionally
Every connection error or clean disconnect (`onDone`) schedules exactly one reconnect attempt
5 seconds later, forever, until the service is disposed. There is no backoff growth and no
maximum retry count.
- Code: `native_socket_service.dart:119-128`.
- **Drift**: `STARTGOLD_DOCUMENTATION.md` §4 claims "Automatic with exponential backoff" — false.

### RULE-MARKET-007 — Socket disconnects on app background, reconnects on resume
Confirmed correct against the hand-written doc.
- Code: `app_lifecycle_observer.dart:61-70`.

### RULE-MARKET-008 — The socket's commodity IDs come from the commodities API, not hardcoded
`goldId`/`silverId` default to `'1'`/`'3'` but are overwritten as soon as
`commoditiesProvider` (`POST users/shared/commodities`) resolves, matched by name (`"gold"` /
`"silver"` substring, case-insensitive) on `Commodity.id` (the `id_metal` field) —
**never** `Commodity.webSocketId` (`web_soc_id`), which is explicitly unused for this purpose.
- Code: `market_provider.dart:19-41`, `commodity_provider.dart:26-41`,
  `shared_service.dart:31-47`.

### RULE-MARKET-009 — A rate-lock timer will not start on a null/absent rate
`RateTimerNotifier.startOrRefresh` reads the current `marketRatesStreamProvider` value and
returns immediately (no timer, no state change) if it's `null` — i.e. before the very first
socket tick has arrived, purchase/sell screens have no active rate lock to display.
- Code: `timer_provider.dart:46-47`.

### RULE-MARKET-010 — Rate-lock market-closed detection must go through `marketStatusProvider`, never timestamps
A prior implementation compared the locked rate's timestamp to the timer window to infer market
closure and produced a visible UI "shake" (false-positive close → restart → false-negative open →
restart...) whenever the socket ticked infrequently. This is now an explicit anti-pattern
documented in the code itself.
- Code: `timer_provider.dart:80-104` (full postmortem comment).
- **Do not** reintroduce timestamp-based closed detection into `RateTimerNotifier`.

### RULE-MARKET-011 — Rate-lock duration is not a client-side constant
The `durationSeconds` passed to `startOrRefresh` is described in code comments as coming from
server config (e.g. `sell_rate_lock_seconds`), consistent with AGENTS.md §2's rule that
GST/denomination/lock-duration values are server-driven. The exact provider that supplies this
value was not traced in this pass — **unconfirmed**, flag for the InstantSaving/Withdrawal/SIP
module brains to pin down precisely.
- Code: `home_screen.dart:58-59` (comment referencing `sell_rate_lock_seconds from config API`).
