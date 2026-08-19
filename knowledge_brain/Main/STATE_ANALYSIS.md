---
module: main
last_updated: 2026-08-19
---

# Main — State Analysis

## Riverpod providers owned by this module

| Provider | Type | File:Line | Purpose |
|---|---|---|---|
| `selectedTabProvider` | `StateProvider<int>` | `main_screen.dart:23` | The active tab index (0-3; index 4/Jewellery never sets this since it's a pushed route). Deliberately module-level (not private) so any child screen can programmatically switch tabs — inline comment: "Shared provider so any child screen can switch tabs." |

## Providers watched/invalidated (owned elsewhere — see `CROSS_MODULE_MAP.md`)

`homeDashboardProvider`, `portfolioProvider`, `profileProvider`, `savingConfigProvider`,
`historyProvider`, `authControllerProvider`, `notificationProvider` — this module never
`ref.watch`es any of these directly (only `selectedTabProvider` is watched, `:118`); the others are
only `ref.read`/`ref.invalidate`d as side effects of mount/tab-tap, per §2 of `MODULE_BRAIN.md`.
Their internal state shapes are out of scope for this brain — see each owning module's own
`STATE_ANALYSIS.md` once built.

## Local widget state (`_MainScreenState`)

| Field | Type | Purpose |
|---|---|---|
| `_visitedTabs` | `Set<int>`, seeded `{0}` | Tracks which tab indices have been visited at least once — gates lazy construction of tabs 1-3 inside the `IndexedStack`, and gates the conditional `historyProvider.refresh()` call on tab 2. |
| `_lastBackPressTime` | `DateTime?` | Timestamp of the last back-press while on the Home tab, used for the 2-second double-tap-to-exit window. |

## Route arguments consumed

| Argument | Type | Source | Effect |
|---|---|---|---|
| `resetTab` | `bool` (checked `== true`) | `ModalRoute.of(context)?.settings.arguments` | If `true`, forces `selectedTabProvider` to `0` on mount (post-frame) — used when returning to `MainScreen` after a payment-success flow, per the inline comment at `main_screen.dart:39-40`. |

## Secure storage / persistence

None directly — `authControllerProvider.notifier.rehydrateFromStorage()` (called from this
module's `initState`) reads secure storage, but that read/write logic is owned by the `auth`
module, not documented here beyond the call site itself.
