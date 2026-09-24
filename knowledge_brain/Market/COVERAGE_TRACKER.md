# Market — Coverage Tracker

## Round 1 — 2026-08-19 — Build

| Dimension | Weight | Actual count | Documented | Coverage |
|---|---|---|---|---|
| Screens | 25% | 0 (none owned by `features/market/`; live-rate UI is embedded in Home/InstantSaving/Withdrawal/SIP, tracked in their own brains) | N/A — module has no screens by design | 100% (nothing to document, confirmed via inventory) |
| Controller/service public methods | 25% | 12 (`NativeSocketService`: `connect`, `_scheduleReconnect`, `_handleRateUpdate`, `disconnect`, `_inferClosedAfterGracePeriod`, `dispose`, `updateCommodityConfig`, + 3 stream getters; `RateTimerNotifier`: `startOrRefresh`, `_evaluateTimer`, `_refreshAndRestart`, `clear`) | 12/12 in `METHOD_INDEX.md` | 100% |
| Models | 15% | 2 (`MarketRates`, `Commodity`) | 2/2 in `STATE_ANALYSIS.md`, all fields + factories, including the two dead-code paths (`MarketRates.initial()`, `MarketRates.fromJson()`) | 100% |
| API/protocol surface | 15% | 1 WebSocket endpoint + 2 frame types (`3`, `5`) + 1 REST endpoint (`POST users/shared/commodities`, documented as the commodity-ID source) | All documented in `MODULE_BRAIN.md` §3-6, verified line-by-line against `_handleRateUpdate` | 100% |
| Business rules | 10% | 11 rules extracted | 11 in `BUSINESS_RULES.md` (RULE-MARKET-001 through 011) | 100% |
| Cross-module deps | 10% | 4 consumer features (Home, InstantSaving, Withdrawal, SIP) + 6 core files | All 4 + all 6 mapped with Mermaid graph in `CROSS_MODULE_MAP.md` | 100% |

**Weighted total: 100%**
**Badge: 🔵 100% + verified**

### Manual spot-check (required for 🔵)
Re-read in full during this build (not summarized from memory): `market_rates.dart` (185 lines,
full file), `native_socket_service.dart` (262 lines, full file), `market_provider.dart` (62
lines, full file). Cross-checked against 6 consumer screens via targeted grep with context
(`home_screen.dart`, `withdrawal_screen.dart`, `instant_saving_screen.dart`,
`auto_savings_screen.dart`, `withdrawal_confirmation_screen.dart`,
`payment_methods_screen.dart`), `timer_provider.dart` (full file), `commodity_provider.dart`
(full file), `app_lifecycle_observer.dart` (targeted grep), `environment_service.dart` (full
file), `shared_service.dart` (targeted read of `Commodity` + `commoditiesProvider`).

### Drift found vs `STARTGOLD_DOCUMENTATION.md` §4
| Doc claim | Reality | Severity |
|---|---|---|
| Protocol: Socket.IO | Raw `web_socket_channel`, no Socket.IO framing/events | High — anyone debugging via Socket.IO tooling will find nothing |
| Endpoint: `ws://bullion_v4.logimaxindia.com/ratesocket/socket.io/` | `wss://startgoldapp.logimaxindia.com/ws/` (staging) / `wss://sgbackoffice.startgold.com/ws/` (production) | High — wrong host, wrong scheme, wrong path entirely |
| Events: `market_rates` | No named events at all — plain pipe-delimited text lines | High |
| Rate format: `3\|goldBuy\|goldSell\|silverBuy\|silverSell\|...` | `3\|commodity_id\|<unused>\|buy\|sell\|...`, one line per commodity, ID-keyed | High — format shape itself is wrong |
| Reconnection: "Automatic with exponential backoff" | Fixed 5-second delay, no backoff, no cap | Medium |
| Market status: "Message type 5 with open/close flag" | Correct in spirit; actual shape is `5\|commodity_id\|commodity_name\|status` (per-commodity, not global) | Low — directionally right, missing detail |
| Lifecycle: "Disconnects on app background, reconnects on resume" | Confirmed correct | None |

All 7 rows logged to `_OVERVIEW/BUILD_SUMMARY.md` per AGENTS.md §10.

### Known gaps (not blocking 🔵, but flagged for future rounds)
- `socketStatusProvider` consumption by any screen is unconfirmed — no consumer found in this
  pass; worth confirming when Home/InstantSaving/Withdrawal/SIP brains are built in full (they
  may reference it in code not reached by this pass's grep patterns).
- Rate-lock `durationSeconds` source (server config provider) not traced to its exact
  definition — flagged in `BUSINESS_RULES.md` RULE-MARKET-011 for the InstantSaving/Withdrawal
  brains to close out.
- `commodityProvider`'s reset-to-gold-on-restart behavior is asserted from code reading but not
  behaviorally tested (no `flutter_secure_storage`/`shared_preferences` write found for it).
