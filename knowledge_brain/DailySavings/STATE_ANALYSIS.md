---
module: daily_savings
last_updated: 2026-08-19
---

# DailySavings — State Analysis

## Riverpod providers

**None.** The module contains no `Provider`, `StateProvider`, `StateNotifierProvider`,
`FutureProvider`, or `AsyncNotifier` of any kind. `DailySavingsScreen` extends `StatefulWidget`
(not `ConsumerStatefulWidget`) — `daily_savings_screen.dart:6`. There is no `WidgetRef`, no
`ref.watch`/`ref.read` anywhere in the file.

This is a hard divergence from `AGENTS.md` §1's stated preference ("Prefer `StateNotifier`/
`AsyncNotifier` ... over ad-hoc `setState` for non-trivial screens") — though arguably this
screen currently *is* trivial precisely because it does nothing beyond cosmetic selection, so the
rule isn't being "violated" so much as the screen never graduated past a first draft.

## Local widget state

| Field | Type | Initial value | Declared | Mutated by | Read by |
|---|---|---|---|---|---|
| `_selectedAmount` | `String` | `'20'` | `daily_savings_screen.dart:14` | Chip `onTap` (`:60-61`) | `isSelected` check in chip builder (`:58`) |

No other `State` fields exist. No `TextEditingController`, no `AnimationController`, no
`FocusNode`.

## Model shapes

**None.** No `DailySavingsPlan`, `DailySavingsConfig`, `DailySavingsRequest`, or any other model
class exists for this module — there is nothing to serialize since no API call is ever made.

Contrast: `sip`'s equivalent state shape is `SipState` (`sip_controller.dart:77`) with fields for
`selectedFrequencyId`, `selectedCommodityId`, active-plan tracking, etc., backed by a real
`SipConfig`/`SipDenomination`/`SipPlanDetail`/`SipCreateResponse` model set
(`sip/models/sip_models.dart`) — not reproduced in this module.

## Secure storage keys touched

**None.** No `flutter_secure_storage` / `SecureStorageService` reads or writes anywhere in the
module.

## Persistence summary

| Mechanism | Used? |
|---|---|
| Riverpod provider (in-memory, app-lifetime) | No |
| `flutter_secure_storage` | No |
| `shared_preferences` | No |
| Backend (via API) | No |

Everything the screen "remembers" is scoped to the widget's own `State` object and is discarded
the moment the widget is disposed (e.g. on `Navigator.pop`).
