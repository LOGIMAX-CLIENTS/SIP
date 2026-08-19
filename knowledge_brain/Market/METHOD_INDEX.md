# Market — Method Index

Alphabetical by class. All line numbers verified against the current source (2026-08-19).

## `MarketRates` — `lib/features/market/models/market_rates.dart`

| Method | Line | Signature / purpose | Callers |
|---|---|---|---|
| `MarketRates()` | 15 | Default constructor, all fields required except names/currency | `fromRawString`, `fromJson` |
| `MarketRates.initial()` | 30 | All-zero rates, `DateTime.now()` timestamp | Not referenced (grep found no call site) — **unconfirmed/dead** |
| `MarketRates.fromRawString(rawData, previous, {goldId, silverId, goldName, silverName})` | 44 | Factory — parses the pipe-delimited socket payload into a rate object, carrying forward unknown fields from `previous` | `NativeSocketService._handleRateUpdate` (`native_socket_service.dart:195`) |
| `MarketRates.fromJson(json)` | 128 | Factory — JSON→model | **No call site found — dead code.** Do not assume rates ever arrive via REST. |
| `copyWith({...})` | 147 | Returns a new instance with overridden fields | `NativeSocketService.updateCommodityConfig` (`native_socket_service.dart:65`) |
| `isSignificantChange(other)` | 177 | `true` if name changed or any buy/sell delta `> 0.001` | `NativeSocketService._handleRateUpdate` (`native_socket_service.dart:204`) — gates whether a new tick is actually emitted |

## `NativeSocketService` — `lib/core/network/native_socket_service.dart`

| Method | Line | Signature / purpose | Callers |
|---|---|---|---|
| `ratesStream` (getter) | 22 | `Stream<MarketRates>` — replays `_lastRate` then forwards `_ratesController.stream` | `marketRatesStreamProvider` (`market_provider.dart:45`) |
| `statusStream` (getter) | 29 | `Stream<SocketStatus>` | `socketStatusProvider` (`market_provider.dart:51`) |
| `marketStatusStream` (getter) | 36 | `Stream<Map<String,bool>>` — replays current `_commodityOpenStatus` then forwards updates | `marketStatusProvider` (`market_provider.dart:60`) |
| `updateCommodityConfig(gId, gName, sId, sName)` | 56 | Overrides `goldId`/`silverId`/`goldName`/`silverName`; if a rate already exists, renames + re-emits it | `marketRatesStreamProvider` body (`market_provider.dart:39`) |
| `connect()` | 74 | `Future<void>` — opens the `WebSocketChannel`, awaits `.ready`, wires `onError`/`onDone`, starts the 1s grace-period timer | `marketRatesStreamProvider` (auto-connect, `market_provider.dart:44`), `AppLifecycleObserver` on resume (`app_lifecycle_observer.dart:70`), `_scheduleReconnect` (self, after 5s) |
| `_scheduleReconnect()` | 119 | Closes the current channel, nulls it, and schedules `connect()` after a fixed 5s (no backoff) | `connect()` catch block, `onError`, `onDone` |
| `_handleRateUpdate(data)` | 130 | Decodes the frame to text, parses type-`5` (market status) then type-`3` (rates) lines, updates `_lastRate`/`_commodityOpenStatus`, emits to the relevant `StreamController`s | `channel.stream.listen` data callback (`native_socket_service.dart:92`) |
| `disconnect()` | 213 | Cancels timers, closes the channel, emits `disconnected` — leaves stream controllers open (reusable) | `AppLifecycleObserver` on background (`app_lifecycle_observer.dart:62`), `_scheduleReconnect` |
| `_inferClosedAfterGracePeriod()` | 223 | If no explicit `5|` frame arrived for a commodity within the grace period and its rates are still zero, marks it closed | `_gracePeriodTimer` callback (`native_socket_service.dart:109`) |
| `dispose()` | 255 | Marks disposed, disconnects, closes all three stream controllers | `socketIOServiceProvider`'s `ref.onDispose` (`market_provider.dart:11`) |

## `market_provider.dart` (top-level providers, no class)

| Provider | Line | Purpose | Watched by |
|---|---|---|---|
| `socketIOServiceProvider` | 8 | Singleton `NativeSocketService`, rebuilt when `environmentProvider` changes | `marketRatesStreamProvider`, `socketStatusProvider`, `marketStatusProvider`, `app_lifecycle_observer.dart` |
| `marketRatesStreamProvider` | 16 | Live `MarketRates` stream; configures commodity IDs from `commoditiesProvider`; **auto-connects the socket as a side effect of being watched** | Home, InstantSaving, Withdrawal, SIP (see `CROSS_MODULE_MAP.md`), `timer_provider.dart` |
| `socketStatusProvider` | 49 | Connection status stream | Not directly consumed by any screen found in this pass — **unconfirmed usage** beyond internal wiring |
| `marketStatusProvider` | 58 | Per-commodity open/closed map | Home, InstantSaving, Withdrawal, SIP |

## `CommodityNotifier` / `commodity_provider.dart`

| Method / Provider | Line | Purpose | Callers |
|---|---|---|---|
| `CommodityNotifier.setCommodity(type)` | 9 | Switches the UI's selected gold/silver tab | `home_screen.dart:1497,1505` (gold/silver tab taps) |
| `commodityProvider` | 14 | `StateNotifierProvider<CommodityNotifier, CommodityType>` | Home, InstantSaving, Withdrawal, SIP screens |
| `selectedMetalIdProvider` | 26 | Resolves the real `id_metal` string for the selected commodity from `commoditiesProvider`, falling back to `'1'`/`'3'` while loading | `instant_saving_screen.dart:1113`, `withdrawal_screen.dart:1581`, `withdrawal_confirmation_screen.dart:476` |

## `RateTimerNotifier` / `timer_provider.dart`

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `startOrRefresh(durationSeconds)` | 41 | Locks the current `marketRatesStreamProvider` value and starts a 1s-tick countdown | Home, InstantSaving, Withdrawal, SIP screens (on rate-lock start/restart) |
| `_evaluateTimer()` | 61 | Per-tick: decrements remaining seconds or, on expiry, calls `_refreshAndRestart()` | `Timer.periodic` callback (self); `didChangeAppLifecycleState` on resume (line 37) |
| `_refreshAndRestart()` | 80 | Restarts the timer immediately with a freshly-locked rate — deliberately has **no** timestamp-based market-closed heuristic (see comment block, lines 81-104) | `_evaluateTimer()` on expiry |
| `clear()` | 107 | Cancels the timer, resets to zero/inactive state | Screens on commodity-tab switch (e.g. `instant_saving_screen.dart:62`, `withdrawal_screen.dart:79`) |
| `buyRateTimerProvider` / `sellRateTimerProvider` | 121, 126 | Two independent `RateTimerNotifier` instances | InstantSaving/SIP (buy), Home/Withdrawal (sell) |
