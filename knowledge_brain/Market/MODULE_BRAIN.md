# Market — Module Brain

```
status: 🔵 100% (Round 1)
last_updated: 2026-08-19
owns: lib/features/market/  (1 model file only)
real implementation lives in: lib/core/network/native_socket_service.dart,
                               lib/core/providers/market_provider.dart,
                               lib/core/providers/commodity_provider.dart,
                               lib/core/providers/timer_provider.dart,
                               lib/core/services/environment_service.dart
```

## 1. What this module actually is

`STARTGOLD_DOCUMENTATION.md` is right that there is no dedicated Market screen — it's
"(Embedded in Home)". But the folder `lib/features/market/` is thinner than that implies: it
contains exactly one file, `models/market_rates.dart` (the `MarketRates` model + its raw-socket
parser). There is no `screens/`, `controller/`, or `services/` subfolder.

The actual live-rate **architecture** — socket connection, reconnection, market-open/closed
tracking, rate-lock timers — lives entirely in `lib/core/`, because rates are genuinely
cross-feature shared state (Home, InstantSaving, Withdrawal, SIP all need it), not a
feature-owned concern. This brain documents that core architecture here since `market` is its
most natural home; see `CROSS_MODULE_MAP.md` for exactly who consumes it, and cross-reference
from `Home/MODULE_BRAIN.md` when that brain is built.

## 2. File inventory

| File | Role |
|---|---|
| `lib/features/market/models/market_rates.dart` | `MarketRates` model — fields, `fromRawString` (socket parser), `fromJson` (**unused — no call site found**, dead code), `copyWith`, `isSignificantChange` |
| `lib/core/network/native_socket_service.dart` | `NativeSocketService` — raw WebSocket connection, frame parsing, reconnect, market-status tracking |
| `lib/core/providers/market_provider.dart` | Riverpod glue: `socketIOServiceProvider`, `marketRatesStreamProvider`, `socketStatusProvider`, `marketStatusProvider` |
| `lib/core/providers/commodity_provider.dart` | `commodityProvider` (user's selected gold/silver tab), `selectedMetalIdProvider` (resolves real `id_metal` from the commodities API) |
| `lib/core/providers/timer_provider.dart` | `RateTimerNotifier`, `buyRateTimerProvider`, `sellRateTimerProvider` — rate-lock countdown built on top of `marketRatesStreamProvider` |
| `lib/core/services/environment_service.dart` | Resolves `wsUrl` per environment (staging/production) |
| `lib/core/security/app_lifecycle_observer.dart` | Disconnects socket on app background, reconnects on resume |
| `lib/core/services/shared_service.dart` | `Commodity` model + `commoditiesProvider` (`POST users/shared/commodities`) — supplies real `id_metal` values used to configure the socket parser |

## 3. Transport — NOT Socket.IO (drift vs hand-written doc)

`STARTGOLD_DOCUMENTATION.md` §4 claims Socket.IO, endpoint
`ws://bullion_v4.logimaxindia.com/ratesocket/socket.io/`, event `market_rates`. **None of this
matches the code.** Verified in `native_socket_service.dart`:

- Package: `web_socket_channel` (raw `WebSocketChannel.connect`), **not** `socket_io_client`.
  No Socket.IO handshake, no named events — just a raw bidirectional text stream.
- Endpoint comes from `EnvironmentService.wsUrl` (`environment_service.dart:13,16`):
  - Staging: `wss://startgoldapp.logimaxindia.com/ws/`
  - Production: `wss://sgbackoffice.startgold.com/ws/`
  - Both `wss://` (TLS), not the doc's `ws://`.
- Connection sends a custom `protocols` header: a single opaque token string
  (`native_socket_service.dart:11-13`) — likely an auth/routing token for the gateway, not a
  Socket.IO artifact.

## 4. Wire protocol (verified against `_handleRateUpdate`, `native_socket_service.dart:130-211`)

Every inbound frame is text (or `List<int>` decoded to text), split on `\n` into lines, each line
split on `|`. Two frame types are recognized by `parts[0]`:

**Type `5` — per-commodity market status** (`parts.length >= 4`):
```
5|<commodity_id>|<commodity_name>|<status>
```
`status == '1'` → open, anything else → closed. Each commodity (gold `id='1'`, silver `id='3'`
by default, overridden dynamically — see §5) tracks its own open/closed flag independently in
`_commodityOpenStatus` (a `Map<String,bool>`). Receiving this frame cancels the grace-period
timer (§6). On a close transition, only the just-closed commodity's rates are zeroed — the other
commodity's last-known rates are preserved (`native_socket_service.dart:162-183`).

**Type `3` — rate frame** (`parts.length >= 5`), parsed by
`MarketRates.fromRawString` (`market_rates.dart:44-126`):
```
3|<commodity_id>|<unused field>|<buy>|<sell>|...
```
This is **not** the hand-written doc's claimed
`3|goldBuy|goldSell|silverBuy|silverSell|...` — that format doesn't exist in the code. The real
format is **one line per commodity, keyed by `commodity_id`** (matched against `goldId`/`silverId`
from `updateCommodityConfig`), not a single combined line. `parts[3]` = buy, `parts[4]` = sell;
`parts[2]` is read but never used. If either buy or sell parses to `0.0` while the other is
non-zero, the zero side falls back to the non-zero side's value (`market_rates.dart:71-74`) —
a defensive guard against a partial/malformed tick, not a real market state.

Change/percentage fields are computed client-side against the *previous* `MarketRates` (sell-price
delta only, not buy): `goldChange = newSell - previous.goldSell`,
`goldPercentage = (goldChange / previous.goldSell) * 100` (`market_rates.dart:102-121`). First
tick after connect has no previous, so change/percentage are `0.0`.

A new `MarketRates` is only pushed to `_ratesController` (and thus to every UI consumer) when
`isSignificantChange` is true — name change or any buy/sell delta `> 0.001`
(`market_rates.dart:177-184`, `native_socket_service.dart:204-207`). Sub-threshold ticks are
silently dropped — this is a deliberate rebuild-throttle, not a bug.

## 5. Dynamic commodity ID mapping

The socket's `goldId`/`silverId`/`goldName`/`silverName` default to `'1'`/`'3'`/`'Gold 24KT'`/
`'Silver 999'` but are overridden at runtime by `marketRatesStreamProvider`
(`market_provider.dart:19-41`), which watches `commoditiesProvider` (`POST
users/shared/commodities`) and calls `service.updateCommodityConfig(...)` using each
`Commodity.id` (`id_metal` field). **Important**: `Commodity.webSocketId` (`web_soc_id` field)
exists on the model but is explicitly *not* used for socket matching — a code comment in
`market_provider.dart:28-29` flags this: "Do NOT use c.webSocketId — socket does NOT use it."
Until `commoditiesProvider` resolves, the socket parser uses the `'1'`/`'3'` fallback defaults.

## 6. Connection lifecycle, reconnection, grace period

- `connect()` (`native_socket_service.dart:74-117`): no-op if already connected or disposed.
  Sets status `connecting` → opens `WebSocketChannel`, awaits `.ready`, sets `connected`, then
  starts listening. Any exception during connect → status `error` + `_scheduleReconnect()`.
- **Reconnection is a fixed 5-second delay, not "automatic with exponential backoff"** as the
  hand-written doc claims (`native_socket_service.dart:119-128`): both `onError` and `onDone`
  call `_scheduleReconnect()`, which cancels any pending timer and schedules a single `connect()`
  call after exactly `Duration(seconds: 5)`. No backoff growth, no jitter, no max-retry cap — it
  retries forever every 5s as long as the service isn't disposed.
- **1-second grace period** (`_gracePeriodTimer`, `native_socket_service.dart:106-111,
  221-253`): after `connect()`, if no explicit type-`5` status frame arrives for a commodity
  within 1 second, that commodity is inferred **closed** — but only if its rates are still zero.
  This is a pure client-side heuristic with no doc coverage; see `FORENSIC_TEMPLATE.md` for the
  failure mode it can produce.
- `disconnect()` cancels both timers, closes the channel, sets status `disconnected` — but does
  **not** close the stream controllers, so the service is safely reusable via `connect()` again.
  `dispose()` is the only path that closes the controllers (used by Riverpod's `ref.onDispose`).
- App-lifecycle integration (`app_lifecycle_observer.dart:61-70`) — confirmed matches the
  hand-written doc: background → `socketIOServiceProvider.disconnect()`; resume →
  `.connect()`.

## 7. Rate-lock timers (`timer_provider.dart`)

`RateTimerNotifier` locks a `MarketRates` snapshot (read once from `marketRatesStreamProvider` at
`startOrRefresh(durationSeconds)`) and counts down every second. On expiry it immediately
restarts with the latest rate (`_refreshAndRestart`) rather than going idle — this avoids a UI
flash between cycles. Two independent instances exist: `buyRateTimerProvider` (InstantSaving/SIP
entry) and `sellRateTimerProvider` (Withdrawal/Home sell display). See
`core/providers/timer_provider.dart:80-104` for a documented anti-pattern: a *previous* version
tried to detect market-closed by comparing the locked rate's timestamp against the timer window,
which produced a false "market closed" on every timer boundary when the socket ticks
infrequently. Market open/closed detection is now the sole responsibility of
`marketStatusProvider` (§4/type-5 frames) — **do not reintroduce timestamp-based closed
detection into the timer.**

## 8. Providers quick reference

| Provider | Type | Source |
|---|---|---|
| `socketIOServiceProvider` | `Provider<NativeSocketService>` | Singleton, recreated on `environmentProvider` change, disposed via `ref.onDispose` |
| `marketRatesStreamProvider` | `StreamProvider<MarketRates>` | Auto-connects socket on first watch; replays last value to new listeners |
| `socketStatusProvider` | `StreamProvider<SocketStatus>` | connecting / connected / disconnected / error |
| `marketStatusProvider` | `StreamProvider<Map<String,bool>>` | Per-commodity-id open flag; replays current map to new listeners |
| `commodityProvider` | `StateNotifierProvider<CommodityNotifier, CommodityType>` | User's selected gold/silver tab (UI-local, not server state) |
| `selectedMetalIdProvider` | `Provider<String>` | Real `id_metal` for the selected tab, resolved from `commoditiesProvider`, `'1'`/`'3'` fallback |
| `buyRateTimerProvider` / `sellRateTimerProvider` | `StateNotifierProvider<RateTimerNotifier, TimerState>` | Rate-lock countdown built on `marketRatesStreamProvider` |

## 9. Top risks

1. **Hand-written doc is materially wrong on transport** (§3) — anyone reading only
   `STARTGOLD_DOCUMENTATION.md` §4 would look for Socket.IO event handlers that don't exist.
2. **No reconnect backoff cap** (§6) — a persistently-down socket endpoint retries every 5s
   forever; acceptable for a mobile app but worth knowing before assuming it "gives up."
3. **Grace-period false-closed** (§6) — 1s is short; a slow network path could show a spurious
   "closed" badge before the real `5|` frame arrives. See `FORENSIC_TEMPLATE.md`.
4. **`MarketRates.fromJson` is dead code** — present but unreferenced; do not assume rates ever
   arrive via REST/JSON.
5. **`market_provider.dart` performs a side effect (`service.connect()`) inside a provider body**
   (`market_provider.dart:44`) — idiomatic-enough for this codebase's pattern, but means simply
   watching `marketRatesStreamProvider` anywhere triggers a live connection; be deliberate about
   where it's watched.

## 10. See also

- `METHOD_INDEX.md` — every public method, file:line, callers.
- `DATA_FLOW.md` — connect → subscribe → parse → provider → UI, end to end.
- `BUSINESS_RULES.md` — RULE-MARKET-NNN.
- `CROSS_MODULE_MAP.md` — Home / InstantSaving / Withdrawal / SIP consumption + Mermaid graph.
- `STATE_ANALYSIS.md` — exact model shapes.
- `FORENSIC_TEMPLATE.md` — symptom → suspect for live-rate bugs.
