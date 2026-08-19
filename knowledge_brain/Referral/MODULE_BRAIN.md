# Module Brain — Referral

> **Built**: 2026-08-19 | **Round**: 1 | **Complexity**: Low (4 files, no dedicated `controller/`,
> `models/`, or `providers/` subfolders — model classes live inline in the two `*_service.dart` files)

---

## 1. Module Overview

The Referral module is the customer-facing half of startGOLD's "Refer & Earn" programme: it displays
the logged-in user's own referral code, lets them share it via the native OS share sheet, shows
aggregate stats (referrals count, amount earned), and lists individual referees with their join/reward
status. **All reward calculation and disbursement logic lives server-side** — this module only renders
whatever the API returns; there is no client-side reward math beyond string formatting (see
`BUSINESS_RULES.md` RULE-REFERRAL-004).

The other half of the loop — entering a referral code at signup — lives in the `auth`/registration
flow, not in this module. See `CROSS_MODULE_MAP.md` for the full signup → reward-tracking chain.

### File Map

| File | Lines | Purpose |
|---|---|---|
| `lib/features/referral/referral_screen.dart` | 708 | Main "Refer & Earn" screen: hero header, referral code card (copy/share), dynamic bullet list, "How It Works" static steps, stats banner linking to referee list |
| `lib/features/referral/referral_service.dart` | 108 | `ReferralData` model + `ReferralService` (1 API call) + 2 Riverpod providers |
| `lib/features/referral/referee_list_screen.dart` | 438 | Referee list screen: shimmer loading, error/empty states, per-referee card with join-status and reward-status chips |
| `lib/features/referral/referee_list_service.dart` | 90 | `RefereeItem`/`RefereeListData` models + `RefereeListService` (1 API call) + 2 Riverpod providers |

No `controller/`, `models/`, `services/`, or `widgets/` subfolders exist — this deviates from the
feature-first layering convention in `AGENTS.md` §1 (screens embed all their model/service code in the
same or a single sibling file). Flag as tech debt, not a bug — the module is small enough that it
doesn't currently cause a maintainability problem.

### Routes

| Route constant | Path | Screen | Registered at |
|---|---|---|---|
| `AppRouter.referral` | `/referral` | `ReferralScreen` | `lib/routes/app_router.dart:79,177` |
| `AppRouter.refereeList` | `/referee-list` | `RefereeListScreen` | `lib/routes/app_router.dart:107,304` |

**Entry points into `/referral`** (grep-verified, `AppRouter.referral` usages):
- `lib/features/home/home_screen.dart:853` — a menu/banner item on the Home screen.
- `lib/features/profile/profile_screen.dart:259` — a menu item on the Profile screen.
- `lib/features/referral/referral_screen.dart:115` — the screen's own back-button reads
  `ModalRoute.of(context)?.settings.name` to decide whether to `Navigator.pop` or reset the bottom-nav
  tab (`selectedTabProvider`), i.e. it can be reached both as a pushed route and as an embedded tab.

`/referee-list` is only reached from inside `ReferralScreen` (`referral_screen.dart:247`, tapping the
stats banner when `totalReferrals > 0`) — no other screen links to it directly.

### API Surface

| Endpoint | Method | Called from | Encrypted? |
|---|---|---|---|
| `users/auth/referral/details` | POST (empty body) | `ReferralService.fetchReferralData()` — `referral_service.dart:70-98` | No — not in `AppConfig.encryptedEndpoints` (`lib/core/config/app_config.dart:47-71`) |
| `referrals/referee-list` | POST (empty body) | `RefereeListService.fetchList()` — `referee_list_service.dart:51-79` | No — same check |

Both endpoints are called with an empty `data: {}` body — the server presumably identifies the caller
via the auth-token header injected by `ApiClient`'s interceptor chain (not re-verified here; see
`Core` brain when built).

### State (Riverpod)

| Provider | Type | File:line | Purpose |
|---|---|---|---|
| `referralServiceProvider` | `Provider<ReferralService>` | `referral_service.dart:102-103` | DI for the service |
| `referralDataProvider` | `FutureProvider<ReferralData>` | `referral_service.dart:105-107` | Drives `ReferralScreen` |
| `refereeListServiceProvider` | `Provider<RefereeListService>` | `referee_list_service.dart:84-85` | DI for the service |
| `refereeListProvider` | `FutureProvider<RefereeListData>` | `referee_list_service.dart:87-89` | Drives `RefereeListScreen` |

Both screens call `ref.invalidate(...)` inside `initState` via `Future.microtask` (`referral_screen.dart:29-31`,
`referee_list_screen.dart:23-24`) to force a fresh network fetch every time the screen opens, rather than
relying on Riverpod's default caching — the same pattern in both files. Full detail in `STATE_ANALYSIS.md`.

### Top Risks / Notable Findings

1. **Both service methods swallow all errors into an empty-state model** (`ReferralData.empty` /
   `RefereeListData.empty`) instead of surfacing a `Failure` — see `referral_service.dart:94-97` and
   `referee_list_service.dart:75-78`. This violates `AGENTS.md` §5 ("map API/network errors to a
   `Failure` type at the service layer, don't let raw exceptions leak... but also don't silently
   swallow them into empty success-shaped data"). Practical effect: a network failure and "you have
   zero referrals" render identically to the user. `RefereeListScreen` does have its own `error` state
   in the `AsyncValue.when` (`referee_list_screen.dart:39,71-91`), but it can only ever fire on a Dart
   exception thrown before the try/catch — which never happens here — so the built error UI is
   effectively **dead code**; failures always land in the empty-state branch instead of the error branch.
   Same for `ReferralScreen`'s `error` branch (`referral_screen.dart:60-61`), which just calls
   `_buildBody` with `ReferralData.empty` — visually identical to a legitimate zero-referral state.
2. **Reward amount is a free-text string from the server**, not a typed number — `ReferralData.rewardAmount`
   is `String` (`referral_service.dart:10,48`) and the UI does ad hoc `startsWith('₹')` checks in three
   separate places (`referral_screen.dart:37,84,269`) to decide whether to prepend the ₹ symbol. No
   shared formatting helper — copy/paste drift risk if the server ever changes its format.
2. **Referral code entry lives entirely outside this module.** The referral-code text field is on the
   registration screen (`lib/features/auth/registration/registration_screen.dart:304-311`), submitted to
   `POST users/auth/register-check` then `POST users/auth/register` (`lib/core/services/auth_service.dart:128-147,180-197`).
   This module has no way to know whether a code was ever entered — it only ever reads the *result*
   (`total_referrals`, `total_earned`) after the fact. See `CROSS_MODULE_MAP.md` for the full chain.
3. **Clipboard auto-clear on code copy**: `referral_screen.dart:406-410` clears the clipboard 60 seconds
   after "Copy Code" is tapped, to reduce clipboard-sniffing exposure — a deliberate security touch for
   a non-secret value (the referral code itself isn't sensitive, but the pattern mirrors what more
   sensitive screens likely do).
4. **Referee list has no pagination** — `RefereeListService.fetchList()` sends no page/limit/offset
   params and the model has no pagination metadata beyond a flat `count` (`referee_list_service.dart:37-44`).
   Unconfirmed whether the server paginates internally; if a user has hundreds of referees this could be
   a large single response.
5. **Asset filename typo**: `referral_screen.dart:191` references `assets/home/referal.png` (missing an
   "r") — cosmetic, not a functional bug, but flagged in case the asset is ever renamed/refactored.
6. **No screenshot/root-detection surface** — this module shows no PAN/bank/OTP-grade sensitive data, so
   the absence of `screenshot_security_service.dart` wiring here is consistent with `AGENTS.md` §3's
   scope ("active on auth, OTP, MPIN, and payment screens at minimum") — not a gap.

### Business Rules

See `BUSINESS_RULES.md` for the full RULE-REFERRAL-NNN set (9 rules).

### Cross-Module Impact

See `CROSS_MODULE_MAP.md` for the full dependency graph. Headline: this module depends on `core/network`
(`ApiClient`), `shared/theme`, `shared/widgets` (`AppToast`, `GradientHeader`, `NumericStyledText`), and
`main/main_screen.dart` (`selectedTabProvider` for bottom-nav reset on back). The **signup-time** half of
the referral loop lives in `auth`/`registration`, cross-referenced but not owned by this module.

### Anti-Patterns Register

*(none logged yet — populate after the first bug-fix round on this module)*
