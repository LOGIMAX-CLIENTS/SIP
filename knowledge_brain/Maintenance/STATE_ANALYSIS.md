---
module: maintenance
last_updated: 2026-08-19
---

# Maintenance — State Analysis

## Riverpod providers consumed (not owned by this module)

| Provider | Type | Defined in |
|---|---|---|
| `appControlProvider` | `StateNotifierProvider<AppControlNotifier, AppControlState>` | `core/providers/app_control_provider.dart:318-324` |

`AppControlState` shape (`app_control_provider.dart:17-58`), as relevant to this screen:

| Field | Type | Used by `maintenance_screen.dart` for |
|---|---|---|
| `isMaintenance` | `bool` | the auto-resume check (`_checkResume`) |
| `data` | `AppControlData?` | `data?.maintenance` → `MaintenanceInfo` for display text |
| `isLoading` | `bool` | not read by this screen (no loading UI branch here — the pulse/fade animation plays regardless) |

`AppControlNotifier` (the provider's notifier) owns two `Timer?` fields relevant to this module:
`_pollTimer` (60s, app-wide, started once at app init) and `_maintenancePollTimer` (30s, started
by this screen, auto-cancelled by the notifier itself once maintenance lifts,
`app_control_provider.dart:159-163`).

## Local widget state (`_MaintenanceScreenState`)

| Field | Type | Purpose |
|---|---|---|
| `_pulseCtrl` / `_pulseAnim` | `AnimationController` / `Animation<double>` | 2s repeat-reverse scale pulse on the logo (0.92↔1.08) |
| `_fadeCtrl` / `_fadeAnim` | `AnimationController` / `Animation<double>` | 600ms one-shot fade-in on mount |
| `_hasNavigated` | `bool` (default `false`) | guards against firing `pushNamedAndRemoveUntil` more than once across repeated `build()` calls |

## Model shapes consumed

`MaintenanceInfo` (`core/models/app_control_model.dart:131-158`): `{ isEnabled: bool, title:
String, subtitle: String, expectedResume: String? }`, with a static `MaintenanceInfo.off` constant
used as the default when `appControl.data` is null (`maintenance_screen.dart:93`).

## Secure storage / persistence

None. This module reads no secure storage and writes nothing.
