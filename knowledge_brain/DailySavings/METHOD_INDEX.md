---
module: daily_savings
last_updated: 2026-08-19
---

# DailySavings — Method Index

Alphabetical by class, then method. This module has exactly one class with executable methods
(the widget's `State`), plus the anonymous `onPressed` callbacks embedded in `build()`. There is
no controller, service, or model layer to index.

## `DailySavingsScreen` (`daily_savings_screen.dart:6-11`)

| Member | Signature | file:line | Callers |
|---|---|---|---|
| constructor | `const DailySavingsScreen({super.key})` | `:7` | `app_router.dart:164` (route registration only — no in-app call site found) |
| `createState()` | `State<DailySavingsScreen> createState()` | `:10` | Flutter framework (implicit) |

## `_DailySavingsScreenState` (`daily_savings_screen.dart:13-116`)

| Member | Signature | file:line | Notes / Callers |
|---|---|---|---|
| `_selectedAmount` | `String _selectedAmount = '20'` (field) | `:14` | Read/written only within `build()`'s chip `GestureDetector.onTap` (`:60-61`) and the `isSelected` check (`:58`). Not persisted, not read by anything outside this widget. |
| `build(BuildContext context)` | `Widget build(BuildContext context)` | `:17-116` | Flutter framework. Contains all UI + the two interactive callbacks below. |
| chip `onTap` (inline) | `() => setState(() => _selectedAmount = amt.replaceAll('₹', ''))` | `:60-61` | Fired by tapping one of the four `₹10/₹20/₹50/₹100` chips (`:57`). Only effect: updates local `_selectedAmount`, triggers rebuild to restyle the selected chip. |
| back arrow `onPressed` (inline) | `() => Navigator.pop(context)` | `:29` | `IconButton` in `AppBar.leading` (`:26-30`). |
| CTA `onPressed` (inline) | `() {}` | `:90` | **Empty body — literal no-op.** This is the "Proceed to Payment" button (`:89-101`). Confirmed by direct read of the file; not a truncation artifact. |

## Non-existent (checked, confirmed absent)

Per the workflow's requirement to extract controller/service/model methods — none exist for this
module:
- No `daily_savings_controller.dart` / `DailySavingsController` / `DailySavingsNotifier`.
- No `daily_savings_service.dart` / `DailySavingsService`.
- No `daily_savings_models.dart` or any model class (`DailySavingsPlan`, `DailySavingsConfig`,
  etc. do not exist in this codebase).
- No API client calls (`ApiClient().post(...)` / `.get(...)`) anywhere in the module.
- No `core/security/encryption_service.dart` usage.
- No payment SDK import (`flutter_cashfree_pg_sdk`, HyperSDK, Razorpay) in this file.

For comparison, the equivalent real methods live in `sip`'s `SipService`
(`lib/features/sip/services/sip_service.dart`) — e.g. `getConfig()` (`:17`),
`getGoldDenominations()` (`:28`), `getSilverDenominations()` (`:42`), `createSip()` (`:62`) — see
that module's own brain (not yet built as of this writing) or `CROSS_MODULE_MAP.md` §"SIP
touchpoints referenced" in this brain for the endpoints cited.
