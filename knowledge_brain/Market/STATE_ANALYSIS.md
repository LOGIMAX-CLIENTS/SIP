# Market — State Analysis

## Model: `MarketRates` (`lib/features/market/models/market_rates.dart`)

```dart
class MarketRates {
  final String goldName;        // default 'Gold 24KT'
  final double goldBuy;
  final double goldSell;
  final double goldChange;      // sell-price delta vs previous tick, 0.0 if no previous
  final double goldPercentage;  // (goldChange / previous.goldSell) * 100, 0.0 if no previous
  final String silverName;      // default 'Silver 999'
  final double silverBuy;
  final double silverSell;
  final double silverChange;
  final double silverPercentage;
  final DateTime timestamp;     // client-side DateTime.now() at parse time — NOT a server timestamp
  final String currency;        // always 'INR', never parsed from the wire
}
```

Constructors/factories:
- `MarketRates(...)` — all rate/name fields required except names/currency (which have defaults).
- `MarketRates.initial()` — all-zero, `now()` timestamp. **No call site found — unconfirmed/dead.**
- `MarketRates.fromRawString(rawData, previous, {goldId, silverId, goldName, silverName})` — the
  real socket parser (see `MODULE_BRAIN.md` §4). Any commodity not present in the current frame
  keeps its value from `previous` (so a frame that only updates gold doesn't zero silver).
- `MarketRates.fromJson(json)` — snake_case JSON keys (`gold_buy`, `silver_sell`, etc.). **No
  call site found anywhere in `lib/` — dead code.** Do not build new features assuming rates can
  arrive via a REST/JSON path; the socket is the only live source.
- `copyWith({...})` — standard immutable-update helper; used once, by
  `NativeSocketService.updateCommodityConfig` to rename gold/silver without changing their
  numeric values.
- `isSignificantChange(other)` — `bool`; name change OR any buy/sell delta `> 0.001`. This is
  the sole gate for whether a parsed frame reaches `_ratesController` (see RULE-MARKET-001).

**Precision note**: all rate fields are `double`. AGENTS.md §2 flags raw-`double` financial
arithmetic as tech debt to note, not silently fix. `MarketRates` itself does no rounding — display
formatting (`toStringAsFixed`) happens at the UI layer in each consumer screen, not here.

## Related model: `Commodity` (`lib/core/services/shared_service.dart:31-47`)

```dart
class Commodity {
  final String id;          // id_metal — THIS is what the socket protocol keys on
  final int webSocketId;    // web_soc_id — NOT used for socket matching (see RULE-MARKET-008)
  final String name;
}
```
Fetched via `commoditiesProvider` (`FutureProvider<List<Commodity>>`, non-autoDispose, lives for
the full app session) from `POST users/shared/commodities`. On any failure (empty response or
exception) falls back to a hardcoded 2-item list: `Commodity(id:'1', webSocketId:1,
name:'Gold 24K')` and `Commodity(id:'3', webSocketId:3, name:'Silver')` — matching the socket
service's own hardcoded defaults, so the fallback path is self-consistent even if the API is down.

## Riverpod state graph

| Provider | Kind | Autodispose? | Notes |
|---|---|---|---|
| `socketIOServiceProvider` | `Provider<NativeSocketService>` | No (default `Provider` lifetime — lives with the app / until `environmentProvider` changes) | Explicit `ref.onDispose(() => service.dispose())` |
| `marketRatesStreamProvider` | `StreamProvider<MarketRates>` | No | Broadcast stream underneath (`StreamController.broadcast()` in the service) — safe for multiple simultaneous watchers |
| `socketStatusProvider` | `StreamProvider<SocketStatus>` | No | `enum SocketStatus { connecting, connected, disconnected, error }` |
| `marketStatusProvider` | `StreamProvider<Map<String,bool>>` | No | Map keyed by commodity-id **string** (`'1'`, `'3'`, ...), not enum |
| `commodityProvider` | `StateNotifierProvider<CommodityNotifier, CommodityType>` | No | `enum CommodityType { gold, silver }` — pure UI selection state, not server-derived |
| `selectedMetalIdProvider` | `Provider<String>` | No (derived, recomputed on every dependency change) | Combines `commodityProvider` (which type) + `commoditiesProvider` (real id) |
| `buyRateTimerProvider` / `sellRateTimerProvider` | `StateNotifierProvider<RateTimerNotifier, TimerState>` | No | Two independent instances of the same notifier class |

`TimerState` shape (`timer_provider.dart:7-19`):
```dart
class TimerState {
  final int remainingSeconds;
  final MarketRates? lockedRates;
  final bool isMarketClosed;   // set only by clear(); never set true by _evaluateTimer itself
  bool get isActive => remainingSeconds > 0 && lockedRates != null && !isMarketClosed;
}
```

## Secure storage / persistence

None. No rate data, commodity selection, or timer state is written to `flutter_secure_storage`
or `shared_preferences` anywhere in this module — everything is in-memory Riverpod state, rebuilt
from the socket on every app cold start. `commodityProvider`'s selected tab also resets to
`CommodityType.gold` (the `super(CommodityType.gold)` initial state) on every app restart —
**unconfirmed** whether this is intentional UX or a missed persistence opportunity.
