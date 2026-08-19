# Market — Data Flow

## Flow 1: Cold start — socket connect → first rate on screen

```
1. A screen (e.g. HomeScreen.build) calls ref.watch(marketRatesStreamProvider)
   → market_provider.dart:16-46

2. Provider body runs once:
   a. ref.watch(socketIOServiceProvider)                      market_provider.dart:17
      → creates NativeSocketService() singleton (if not already created)
   b. ref.watch(commoditiesProvider).valueOrNull                market_provider.dart:20
      → if the commodities API (POST users/shared/commodities, shared_service.dart:117)
        has already resolved, calls service.updateCommodityConfig(gId, gName, sId, sName)
        with the real id_metal values                          market_provider.dart:39
      → if still loading, socket keeps default goldId='1'/silverId='3'
   c. service.connect()                                        market_provider.dart:44
   d. returns service.ratesStream                               market_provider.dart:45

3. NativeSocketService.connect()                                native_socket_service.dart:74
   → SocketStatus.connecting emitted
   → WebSocketChannel.connect(wss://<env>/ws/, protocols:[token])
   → await channel.ready
   → SocketStatus.connected emitted
   → channel.stream.listen(_handleRateUpdate, onError, onDone)
   → starts 1s _gracePeriodTimer

4. First frames arrive (order not guaranteed — server may send '5' before or after '3',
   or '3' with zero rates before the market-status frame at all):
   _handleRateUpdate(data)                                      native_socket_service.dart:130
   → Step 1: scan lines for '5|...' → update _commodityOpenStatus,
             cancel grace-period timer, possibly zero + emit rates for the closed commodity
             on marketStatusController + ratesController
   → Step 2: MarketRates.fromRawString(rawData, _lastRate, ...)  market_rates.dart:44
             parses every '3|...' line, keeping fields from `previous` for commodities
             not present in this frame
   → if isSignificantChange(_lastRate) → _lastRate = newRates; _ratesController.add(newRates)

5. marketRatesStreamProvider's Stream<MarketRates> emits the new value
   → ref.watch(marketRatesStreamProvider) in the screen rebuilds with AsyncData(newRates)
   → screen reads rates.goldBuy / rates.silverSell / etc. for display
```

## Flow 2: Market close → per-commodity zeroing → UI badge

```
1. Socket sends "5|1|Gold 24K|0\n" (gold closes)
2. _handleRateUpdate parses parts[0]=='5', commodityId='1', isOpen=false
   → _commodityOpenStatus['1'] = false  (silver untouched)
   → _marketStatusController.add({...})                          native_socket_service.dart:159
   → goldClosed=true → builds a zeroRates MarketRates with goldBuy/goldSell=0.0 but
     silverBuy/silverSell carried forward from _lastRate                 native_socket_service.dart:167-180
   → _lastRate = zeroRates; _ratesController.add(zeroRates)
3. marketStatusProvider emits {'1': false, ...}
   → Home/Withdrawal/InstantSaving/SIP screens (all watch marketStatusProvider) recompute
     isCurrentMarketClosed = marketStatusMap[commodityId] == false
   → screens show a "market closed" banner/badge and typically freeze the rate-lock timer
     display rather than starting a new lock (see RULE-MARKET-004 in BUSINESS_RULES.md)
4. marketRatesStreamProvider also emits the zeroRates value — screens watching it directly
   (not through a locked timer) would show ₹0.00 for gold unless they specifically prefer
   marketStatusProvider's closed flag to gate the display (which every consumer found does).
```

## Flow 3: Rate-lock timer (buy/sell) built on top of the stream

```
1. User opens InstantSaving screen → ref.read(buyRateTimerProvider.notifier)
   .startOrRefresh(durationSeconds)                              timer_provider.dart:41
   (durationSeconds is server-driven config — NOT hardcoded here; see savings/config-style
   pattern noted in AGENTS.md §2 — exact provider not traced in this pass, unconfirmed)

2. startOrRefresh reads ref.read(marketRatesStreamProvider).valueOrNull ONCE
   → if null (no tick yet), aborts and waits — no timer starts on a null rate
   → else locks TimerState(remainingSeconds: total, lockedRates: currentRates)
   → Timer.periodic(1s) ticks _evaluateTimer()

3. Screen displays timerState.lockedRates instead of the live stream value while
   timerState.isActive (remainingSeconds > 0 && lockedRates != null && !isMarketClosed)
   → this is the actual "rate lock" the AGENTS.md financial-safety rule refers to:
     the price shown/submitted for a purchase is the snapshot taken at lock time, not
     whatever the socket says right now.

4. On expiry, _refreshAndRestart() calls startOrRefresh(_totalDuration) again immediately
   → re-reads marketRatesStreamProvider for a fresh snapshot → new lock window starts
   → no gap where isActive is false between cycles (avoids UI flicker)

5. Screens additionally ref.listen(marketRatesStreamProvider) directly (not just the timer)
   to catch the specific race where a '5|...|1' (reopen) frame arrives before the first
   non-zero '3|...' rate — in that window the timer would otherwise lock a 0 rate; the
   listener detects the first valid non-zero rate and forces a restart
   (see home_screen.dart:98-107, instant_saving_screen.dart:160-169,
   withdrawal_screen.dart:196-206, withdrawal_confirmation_screen.dart:446-454).
```

## Flow 4: App backgrounded mid-session

```
1. AppLifecycleObserver.didChangeAppLifecycleState(paused/inactive)
   → ref.read(socketIOServiceProvider).disconnect()               app_lifecycle_observer.dart:62
   → NativeSocketService.disconnect(): cancels reconnect + grace timers, closes channel,
     emits SocketStatus.disconnected — _lastRate is retained in memory (not cleared)

2. App resumes
   → ref.read(socketIOServiceProvider).connect()                  app_lifecycle_observer.dart:70
   → since _channel is null (cleared by disconnect), connect() proceeds normally
   → RateTimerNotifier.didChangeAppLifecycleState(resumed) also fires independently
     (WidgetsBindingObserver mixin) → _evaluateTimer() recalculates remaining time against
     wall-clock _targetEndTime, so a backgrounded app doesn't silently keep counting down
     server-side state that's now stale — the timer math is wall-clock based throughout
     (timer_provider.dart:33-39, 64).
```

## Flow 5: Connection error / drop → reconnect

```
1. channel.stream.listen's onError or onDone fires (network drop, server restart, etc.)
2. SocketStatus.error or .disconnected emitted → socketStatusProvider updates
3. _scheduleReconnect(): channel closed+nulled, any pending reconnect timer cancelled,
   new Timer(5s) scheduled → connect() called again
4. No cap on retry count, no exponential backoff — every failure schedules exactly one more
   5s-delayed attempt, indefinitely, until dispose() is called.
5. On reconnect success, first frames repeat Flow 1 steps 4-5 — UI recovers automatically
   once the new '3'/'5' frames arrive; there is no explicit "reconnecting..." UI state wired
   to SocketStatus.connecting in the consumers checked in this pass (unconfirmed whether any
   screen surfaces SocketStatus at all — see METHOD_INDEX.md note on socketStatusProvider).
```
