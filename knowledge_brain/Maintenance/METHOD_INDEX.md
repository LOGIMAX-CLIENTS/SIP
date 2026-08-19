---
module: maintenance
last_updated: 2026-08-19
---

# Maintenance — Method Index

All in `lib/features/maintenance/maintenance_screen.dart` unless noted.

| Method | File:Line | Purpose | Called by |
|---|---|---|---|
| `initState()` | `:38-60` | Sets up pulse (2s repeat-reverse) + fade (600ms) `AnimationController`s; schedules `startMaintenancePolling()` post-frame | Flutter framework |
| `dispose()` | `:62-67` | Disposes both animation controllers | Flutter framework |
| `_checkResume(AppControlState appControl)` | `:70-78` | If `!appControl.isMaintenance && !_hasNavigated`, sets `_hasNavigated = true` and navigates to `widget.resumeRoute`, clearing the nav stack | `build()`, on every rebuild (`:91`) |
| `_onWillPop()` | `:81-86` | Android: `SystemNavigator.pop()` (exit app). iOS: no-op. Always returns `false` (never lets the framework pop). | `WillPopScope.onWillPop` (`:99`) |
| `build(BuildContext)` | `:89-251` | Watches `appControlProvider`, calls `_checkResume`, renders the static downtime UI | Flutter framework |

## External calls made by this module

| Call | Defined in | Used at |
|---|---|---|
| `ref.watch(appControlProvider)` | `core/providers/app_control_provider.dart:318-324` | `maintenance_screen.dart:90` |
| `ref.read(appControlProvider.notifier).startMaintenancePolling()` | `core/providers/app_control_provider.dart:86-90` | `maintenance_screen.dart:58` |
| `AppControlNotifier._fetch()` (private, invoked by the timers above) | `core/providers/app_control_provider.dart:97-214` | indirectly, via both the 30s and 60s poll timers |
| `MaintenanceInfo` fields (`title`, `subtitle`, `expectedResume`) | `core/models/app_control_model.dart:131-158` | `maintenance_screen.dart:93`, `:154-172`, `:183-217` |
