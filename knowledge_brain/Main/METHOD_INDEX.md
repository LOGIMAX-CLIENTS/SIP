---
module: main
last_updated: 2026-08-19
---

# Main — Method Index

All in `lib/features/main/main_screen.dart` unless noted.

| Method | File:Line | Purpose | Called by |
|---|---|---|---|
| `initState()` | `:36-66` | Schedules post-frame: `resetTab` arg handling, auth rehydration, dashboard/portfolio/profile provider invalidation, notification badge refresh | Flutter framework |
| `_onTabTapped(int index)` | `:71-115` | User-initiated tab switch: no-ops on same tab, special-cases Jewellery as a pushed route, else updates `selectedTabProvider` and invalidates tab-specific providers | `_buildNavItem`'s `onTap` (`:245`) |
| `build(BuildContext)` | `:117-180` | Watches `selectedTabProvider`, tracks `_visitedTabs`, renders `PopScope` → `Scaffold` → `Stack(IndexedStack + bottom nav)` | Flutter framework |
| `_buildBottomNav(WidgetRef, int, bool, bool)` | `:182-230` | Renders the frosted-glass bottom nav bar, hidden when keyboard open or on Invest tab | `build()` (`:175`) |
| `_buildNavItem(WidgetRef, String, bool, bool, int, String)` | `:232-270` | Renders one nav icon+label, wires `onTap` to `_onTabTapped` | `_buildBottomNav()` × 5 (`:219-223`) |

## Module-owned global state

| Symbol | File:Line | Purpose |
|---|---|---|
| `selectedTabProvider` | `main_screen.dart:23` | `StateProvider<int>` — "Shared provider so any child screen can switch tabs" (inline comment). Default `0`. |

## External calls made by this module (cross-module — see `CROSS_MODULE_MAP.md` for owning files)

| Call | Defined in | Used at |
|---|---|---|
| `authControllerProvider.notifier.rehydrateFromStorage()` | `features/auth/controller/auth_controller.dart:45` | `main_screen.dart:54` |
| `ref.invalidate(homeDashboardProvider)` | `core/providers/home_dashboard_provider.dart:9` | `main_screen.dart:57`, `:84` |
| `ref.invalidate(portfolioProvider)` | `core/providers/portfolio_provider.dart:99` | `main_screen.dart:58`, `:109` |
| `ref.invalidate(profileProvider)` | `features/profile/profile_controller.dart:331` | `main_screen.dart:59`, `:85`, `:112` |
| `notificationProvider.notifier.refreshUnreadCount()` | `core/services/notification_service.dart:257` | `main_screen.dart:64`, `:86` |
| `ref.invalidate(savingConfigProvider)` | `features/instant_saving/controller/saving_controller.dart:8` | `main_screen.dart:90` |
| `historyProvider.notifier.refresh()` | `features/history/controller/history_controller.dart:172` | `main_screen.dart:107` (conditional on prior visit) |
| `AppToast.show(...)` | `shared/widgets/app_toast.dart` | `main_screen.dart:147-151` |
