---
module: main
brain_status: 🟢 93% (built, verified for own file; hosted screens'/providers' internals are
  each other modules' scope, not independently re-verified here)
last_updated: 2026-08-19
round: 1
---

# Main — Module Brain

## 0. TL;DR

`main` is the **bottom-nav tab shell** — a single file, `lib/features/main/main_screen.dart`
(272 lines), that hosts four other modules' top-level screens inside an `IndexedStack` plus a
fifth tab that is actually a separate pushed route, not part of the stack. It owns no business
logic of its own beyond tab-switching, lazy-mount tracking, provider invalidation on tab-tap, and
a double-tap-to-exit gesture on the Home tab.

**Confirmed drift vs `STARTGOLD_DOCUMENTATION.md` §3.42**, which states: *"Bottom tab container —
Home, Invest, Market, Profile."* The actual code has **five** tabs, not four, and the third tab is
**History**, not **Market**:

| # | Label (as rendered) | Screen hosted | In `IndexedStack`? |
|---|---|---|---|
| 0 | Home | `HomeScreen` (`features/home/home_screen.dart`) | Yes — always mounted at index 0 |
| 1 | Invest | `InstantSavingScreen` (`features/instant_saving/instant_saving_screen.dart`) | Yes — lazy, only mounted after first visit |
| 2 | History | `TransactionHistoryScreen` (`features/history/screens/transaction_history_screen.dart`) | Yes — lazy |
| 3 | Profile | `ProfileScreen` (`features/profile/profile_screen.dart`) | Yes — lazy |
| 4 | Jewellery | `JewelleryScreen` (`features/jewellery/jewellery_screen.dart`, via `/jewellery` route) | **No** — tapping it does `Navigator.pushNamed('/jewellery')` instead of switching the `IndexedStack` index; it is visually a 5th nav item but architecturally a separate pushed screen, not a hosted tab |

There is no "Market" tab anywhere in this file — live rate data is embedded inside `HomeScreen`
(tab 0), consistent with the module registry's note that `market` is "mostly embedded in Home."

## 1. Inventory

| Path | Role |
|---|---|
| `lib/features/main/main_screen.dart` | Sole file. `ConsumerStatefulWidget` `MainScreen` + `_MainScreenState`. Also defines the module-level `selectedTabProvider`. |

No `screens/`, `controller/`, `providers/`, `models/`, `services/`, or `widgets/` subfolders exist
under `lib/features/main/` — everything lives in the one file, including the shared provider.

Route registration (external, per convention) — **note two route constants map to the same
widget**:
- `lib/routes/app_router.dart:40` — `import '../features/main/main_screen.dart';`
- `lib/routes/app_router.dart:75` — `static const String home = '/home';`
- `lib/routes/app_router.dart:76` — `static const String main = '/main';`
- `lib/routes/app_router.dart:165` — `home: (context) => const MainScreen(),`
- `lib/routes/app_router.dart:166` — `main: (context) => const MainScreen(),`

## 2. Screen: MainScreen

`main_screen.dart:25-271`. `ConsumerStatefulWidget`, `_MainScreenState`.

| Attribute | Detail |
|---|---|
| Route | `/home` and `/main` (both resolve to the same `MainScreen()`) |
| State mgmt | Riverpod — `selectedTabProvider` (module-owned `StateProvider<int>`, `:23`), plus reads/invalidates several other modules' providers |
| Providers watched | `selectedTabProvider` (`:118`) |
| Providers invalidated/read (cross-module — see `CROSS_MODULE_MAP.md`) | `homeDashboardProvider`, `portfolioProvider`, `profileProvider`, `savingConfigProvider`, `historyProvider`, `notificationProvider`, `authControllerProvider` |
| API calls | None directly — all delegated to the hosted screens' own controllers/services via the invalidations above |
| Security | `PopScope(canPop: false)` with custom back-press handling (non-Home tab → jump to Home; Home tab → double-tap-to-exit within 2s, `AppToast` shown on first press) |

### 2.1 Mount-time bootstrap (`initState`, `:36-66`)

Deferred via `WidgetsBinding.instance.addPostFrameCallback` (avoids a `!_doingMountOrUpdate`
assertion crash per the inline comment, `:39-40`):
1. If route arguments contain `resetTab: true` (set by the payment-success flow returning to
   `MainScreen`), force `selectedTabProvider` back to `0` (Home) — direct state set, no provider
   invalidation (`:42-48`).
2. `await ref.read(authControllerProvider.notifier).rehydrateFromStorage()` — re-hydrates auth
   state from secure storage **before** firing dashboard/portfolio calls. Inline comment explains
   why: the forgot-PIN flow's OTP-verify step can overwrite session data with a `temp_token`
   lacking `user.id_customer`, which would make `userProvider` return `null` and silently prevent
   dashboard/portfolio APIs from firing if this rehydration didn't run first (`:50-54`).
3. `ref.invalidate(homeDashboardProvider)`, `ref.invalidate(portfolioProvider)`,
   `ref.invalidate(profileProvider)` — forces fresh API calls on every `MainScreen` mount, e.g.
   after MPIN verify (`:56-59`).
4. `ref.read(notificationProvider.notifier).refreshUnreadCount()` — deliberately called **after**
   auth rehydration completes, because `HomeScreen.initState()` fires in parallel and may race
   ahead of rehydration; this call is documented in-line as "the authoritative call" for the badge
   count (`:61-64`).

### 2.2 Tab-tap handling (`_onTabTapped`, `:71-115`)

Called **only** from user-initiated bottom-nav taps — never during programmatic navigation
(explicitly documented in-line as the safe place to refresh providers without the
`!_doingMountOrUpdate` crash, `:68-70`). No-ops if tapping the already-active tab (`:73`).

- **Index 4 (Jewellery)** is special-cased **before** the tab-index state is even changed:
  `Navigator.of(context).pushNamed('/jewellery')` and `return` — it never enters the
  `IndexedStack`/`selectedTabProvider` machinery at all (`:76-79`).
- For indices 0-3, `selectedTabProvider` is updated, then a `switch` invalidates a
  tab-specific set of providers:
  - **0 (Home)**: invalidate `homeDashboardProvider`, `profileProvider`; refresh notification
    unread count (`:83-87`).
  - **1 (Invest)**: invalidate `savingConfigProvider` only — comment notes `InstantSavingScreen`
    auto-refreshes its own other providers (`:88-91`).
  - **2 (History)**: conditionally calls `historyProvider.notifier.refresh()` — **only if the tab
    was already visited before** (`_visitedTabs.contains(2)`). Comment explains why: on the very
    first visit, `TransactionHistoryScreen`'s own `build()` creates the notifier via
    `ref.watch(historyProvider)` for the first time, which already triggers an initial fetch;
    calling `refresh()` here too would duplicate that request. Also deliberately uses
    `.refresh()` rather than `ref.invalidate(historyProvider)` — invalidate would recreate the
    notifier from scratch and silently drop any currently-applied filter, whereas `refresh()`
    re-fetches page 1 with whatever filter is already active. Also invalidates `portfolioProvider`
    unconditionally (`:92-110`).
  - **3 (Profile)**: invalidate `profileProvider` (`:111-113`).

### 2.3 Body composition (`build`, `:117-180`)

`IndexedStack` with exactly 4 children (indices 0-3 — Jewellery is never a stack child):
```dart
IndexedStack(index: selectedIndex, children: [
  const HomeScreen(),                                                          // always built
  _visitedTabs.contains(1) ? const InstantSavingScreen() : SizedBox.shrink(),   // lazy
  _visitedTabs.contains(2) ? const TransactionHistoryScreen() : SizedBox.shrink(), // lazy
  _visitedTabs.contains(3) ? const ProfileScreen() : SizedBox.shrink(),         // lazy
])
```
`_visitedTabs` is a `Set<int>` seeded with `{0}` (`:33`) and grown on every tab visit
(`:122-124`) — this is the lazy-mount mechanism: a tab's screen widget isn't constructed until its
index has been visited at least once, after which `IndexedStack` keeps it alive (state preserved)
for the rest of the session.

### 2.4 Bottom nav bar (`_buildBottomNav`, `:182-230`)

A frosted-glass (`BackdropFilter`, blur 10) pill positioned above the safe-area bottom inset.
**Hidden entirely** (`SizedBox.shrink()`) when the soft keyboard is open (`viewInsets.bottom > 0`)
or when on the Invest tab (index 1) — comment: "Wise-style footer replaces it" (`:185-187`), i.e.
`InstantSavingScreen` presumably renders its own bottom CTA that would otherwise collide with the
nav bar. Five `_buildNavItem` calls, in order: Home, Invest, History, Profile, Jewellery
(`:219-223`), each swapping between a `-green.svg`/`-grey.svg` asset variant based on active state
(`:241-243`).

### 2.5 Back-press handling (`PopScope`, `:128-155`)

`canPop: false` always (comment: popping on Home tab would otherwise hit the unnamed-route "Page
Not Found" fallback, `:129-131`). On back:
- **Not on Home tab** → snap `selectedTabProvider` to `0` instead of exiting.
- **On Home tab** → double-tap-to-exit: tracks `_lastBackPressTime`; a second press within 2
  seconds calls `SystemNavigator.pop()`; otherwise shows an `AppToast` ("Press back again to
  exit") and records the timestamp (`:138-154`).

## 3. Top Risks

1. **Doc drift is significant** (§0) — anyone relying on `STARTGOLD_DOCUMENTATION.md` §3.42 for
   the tab list will get the wrong tab count and the wrong 3rd tab. Flagged in
   `_OVERVIEW/BUILD_SUMMARY.md`.
2. **Jewellery tab is architecturally inconsistent with the other four.** It's rendered by the
   same `_buildNavItem` helper (looks identical to the user) but takes a completely different code
   path (`pushNamed` vs `IndexedStack` swap) with no state preservation, no lazy-mount tracking,
   and it doesn't participate in the provider-invalidation switch in `_onTabTapped`. A future dev
   adding a 6th tab by copy-pasting the Jewellery pattern (or the other pattern) needs to
   understand this split exists.
3. **Two route names, one screen, different call-site intent.** `AppRouter.home` and
   `AppRouter.main` both resolve to `const MainScreen()` — callers elsewhere in the codebase using
   `AppRouter.home` vs `AppRouter.main` are functionally identical today, but that's easy to break
   silently if one is ever repointed without checking the other.
4. **Heavy reliance on `initState` timing/comments to avoid Flutter assertion crashes**
   (`!_doingMountOrUpdate`, `:39-40`, `:68-70`) — the ordering of `addPostFrameCallback`,
   `rehydrateFromStorage()`, and provider invalidation is load-bearing; refactors that move
   invalidations earlier or drop the post-frame deferral risk reintroducing the crash the comments
   describe avoiding.

## 4. See Also
- `METHOD_INDEX.md` — every method, file:line, callers.
- `DATA_FLOW.md` — mount bootstrap flow, tab-tap flow, back-press flow.
- `BUSINESS_RULES.md` — RULE-MAIN-001..009.
- `CROSS_MODULE_MAP.md` — the widest fan-out of the four low-complexity modules; Mermaid graph of
  all 4 hosted screens + 7 invalidated providers + `authControllerProvider`.
- `STATE_ANALYSIS.md` — `selectedTabProvider`, `_visitedTabs`, `_lastBackPressTime`.
- `FORENSIC_TEMPLATE.md` — symptom → suspect entries.
- `COVERAGE_TRACKER.md` — Round 1 coverage.
