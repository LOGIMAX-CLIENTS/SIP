---
module: maintenance
last_updated: 2026-08-19
---

# Maintenance — Data Flow

## Flow 1: Entering `/maintenance` (three possible triggers)

```
(A) features/splash/splash_screen.dart:85-88
    app/control response has maintenance.isEnabled == true
       │
       ▼
    Navigator.pushReplacementNamed('/maintenance', arguments: {resumeRoute: <precomputed login|mpin>})

(B) shared/widgets/app_control_wrapper.dart:51-63
    Global 60s poll tick (AppControlNotifier._fetch) flips appControl.isMaintenance → true
    WHILE the user is already past splash, anywhere in the app
       │
       ▼
    navigatorKey.currentState.pushNamedAndRemoveUntil('/maintenance', (r)=>false,
                                                        arguments: {resumeRoute: '/login'})

(C) shared/widgets/maintenance_gate.dart:29-45  (MaintenanceGate.check — CURRENTLY UNUSED,
    zero call sites in lib/ as of this round, see MODULE_BRAIN.md §2.2)
    Would fire before a critical transaction (payment/withdrawal/SIP) if any module called it
       │
       ▼
    navigatorKey.currentState.pushNamedAndRemoveUntil('/maintenance', (r)=>false,
                                                        arguments: {resumeRoute: '/login'})
```

All three ultimately hit the same router builder:

```
app_router.dart:294-301
    args['resumeRoute'] as String? ?? AppRouter.login
       │
       ▼
    MaintenanceScreen(resumeRoute: <resolved above>)
```

## Flow 2: On-screen — polling → auto-resume

```
MaintenanceScreen.initState()                              maintenance_screen.dart:38
   │  (post-frame)
   ▼
appControlProvider.notifier.startMaintenancePolling()       maintenance_screen.dart:58
   │
   ▼
Timer.periodic(30s, _fetch)                                 app_control_provider.dart:86-90
   │                                                          (in ADDITION to the pre-existing
   │                                                           app-wide 60s timer from
   │                                                           AppControlWrapper.initState)
   ▼  (every 30s, or every 60s from the other timer)
AppControlNotifier._fetch()                                 app_control_provider.dart:97
   │  POST app/control
   ▼
maintenance.isEnabled == false ?
   ├─ NO  → state.isMaintenance stays true → no UI change, poll continues
   └─ YES → state = state.copyWith(isMaintenance: false, ...)               :198-206
              also cancels the 30s fast timer if it was running             :159-163
              │
              ▼ (Riverpod notifies watchers)
           MaintenanceScreen.build() re-runs                                 :89
              │
              ▼
           _checkResume(appControl)                                          :91
              !isMaintenance && !_hasNavigated → true
              │
              ▼
           Navigator.pushNamedAndRemoveUntil(resumeRoute, (route) => false)  :73-77
              (stack fully cleared — resumeRoute becomes the new stack root)
```

## Flow 3: Back press while maintenance is active

```
Hardware/system back gesture
   │
   ▼
WillPopScope.onWillPop → _onWillPop()                        maintenance_screen.dart:81
   │
   ├─ Platform.isAndroid → SystemNavigator.pop()  (app exits)
   └─ iOS                → no side effect
   │
   ▼
return false   (framework never actually pops this route, on either platform)
```
