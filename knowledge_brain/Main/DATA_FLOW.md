---
module: main
last_updated: 2026-08-19
---

# Main — Data Flow

## Flow 1: Mount bootstrap (arriving at `/main` or `/home`)

```
Navigator lands on MainScreen (e.g. from MPIN verify, or splash's /mpin→success, or payment-success
with arguments: {resetTab: true})
   │
   ▼
initState()                                                          main_screen.dart:36
   │  WidgetsBinding.instance.addPostFrameCallback(...)
   ▼
resetTab arg present? ──yes──► ref.read(selectedTabProvider.notifier).state = 0     :44-48
   │
   ▼
await authControllerProvider.notifier.rehydrateFromStorage()                        :54
   │  (re-syncs auth/session state from secure storage BEFORE firing dependent calls —
   │   guards against forgot-PIN's temp_token leaving userProvider null)
   ▼
ref.invalidate(homeDashboardProvider)   ─┐
ref.invalidate(portfolioProvider)        ├─ forces fresh fetch on this mount           :57-59
ref.invalidate(profileProvider)         ─┘
   │
   ▼
ref.read(notificationProvider.notifier).refreshUnreadCount()                         :64
   (deliberately AFTER rehydration — HomeScreen.initState fires in parallel and could
    race ahead of auth being ready)
```

## Flow 2: User taps a bottom-nav tab

```
_buildNavItem onTap → _onTabTapped(index)                                            main_screen.dart:71
   │
   ├─ index == current? ──yes──► return (no-op)                                       :73
   │
   ├─ index == 4 (Jewellery)? ──yes──► Navigator.of(context).pushNamed('/jewellery')   :76-79
   │                                    return  (selectedTabProvider NOT changed;
   │                                             IndexedStack untouched)
   │
   └─ index ∈ {0,1,2,3}:
        ref.read(selectedTabProvider.notifier).state = index                          :81
        switch(index):
          0 → invalidate(homeDashboardProvider), invalidate(profileProvider),
              notificationProvider.refreshUnreadCount()                               :83-87
          1 → invalidate(savingConfigProvider)                                        :88-91
          2 → if _visitedTabs.contains(2): historyProvider.notifier.refresh()         :106-108
              invalidate(portfolioProvider)                                           :109
          3 → invalidate(profileProvider)                                             :112-113
   │
   ▼
build() re-runs: selectedIndex changes → IndexedStack swaps visible child
_visitedTabs grows if this is index's first visit                                     :122-124
```

## Flow 3: Back press

```
PopScope.onPopInvokedWithResult                                                       main_screen.dart:133
   │
   ├─ selectedIndex != 0 (not on Home)?
   │      └─ ref.read(selectedTabProvider.notifier).state = 0   (jump to Home, no exit)
   │
   └─ selectedIndex == 0 (on Home)?
          isSecondPress = now - _lastBackPressTime < 2s ?
             ├─ yes → SystemNavigator.pop()   (app exits)
             └─ no  → _lastBackPressTime = now
                       AppToast.show(context, 'Press back again to exit', info)
```

## Flow 4: Keyboard/tab-driven bottom-nav visibility

```
build() computes keyboardOpen = MediaQuery.viewInsets.bottom > 0                       main_screen.dart:119
   │
   ▼
_buildBottomNav(...)                                                                   :182
   │
   └─ (keyboardOpen || selectedIndex == 1) ? SizedBox.shrink() : <rendered nav bar>     :187
```
