---
module: main
last_updated: 2026-08-19
---

# Main — Business Rules

| ID | Rule | Code |
|---|---|---|
| RULE-MAIN-001 | The tab shell hosts exactly 5 nav items but only 4 `IndexedStack` children — Jewellery (index 4) is a pushed route (`Navigator.pushNamed('/jewellery')`), not a stack member. It never participates in `selectedTabProvider` or `_visitedTabs`. | `main_screen.dart:76-79`, `:160-174` |
| RULE-MAIN-002 | Tabs 1-3 (Invest, History, Profile) are lazily mounted — their screen widgets are not constructed until the tab has been visited at least once (tracked in `_visitedTabs`); Home (tab 0) is always mounted immediately. Once mounted, `IndexedStack` keeps every visited tab's widget alive (state preserved) for the rest of the session. | `main_screen.dart:33`, `:122-124`, `:160-173` |
| RULE-MAIN-003 | `AppRouter.home` and `AppRouter.main` are two different route constants that both resolve to the same `MainScreen()` widget. | `app_router.dart:75-76`, `:165-166` |
| RULE-MAIN-004 | On every mount, `authControllerProvider.notifier.rehydrateFromStorage()` is awaited **before** invalidating `homeDashboardProvider`/`portfolioProvider`/`profileProvider` — this ordering exists specifically to avoid a scenario where the forgot-PIN flow's OTP-verify step has overwritten session data with a `temp_token` lacking `user.id_customer`, which would make `userProvider` return `null` and silently prevent the dashboard/portfolio API calls from firing. | `main_screen.dart:50-59` (inline comment) |
| RULE-MAIN-005 | Tab-tap provider invalidation only runs from user-initiated taps (`_onTabTapped`), never from programmatic tab changes (e.g. the `resetTab` arg path in `initState`) — this is explicitly documented in-line as necessary to avoid a `!_doingMountOrUpdate` Flutter assertion crash. | `main_screen.dart:68-70` |
| RULE-MAIN-006 | History tab refresh is conditional: `historyProvider.notifier.refresh()` only fires if the History tab was already visited before this tap — on the very first visit, `TransactionHistoryScreen`'s own `build()` creates the notifier via `ref.watch`, which already triggers an initial fetch; calling `refresh()` too would duplicate the request. | `main_screen.dart:96-108` (inline comment) |
| RULE-MAIN-007 | History tab refresh deliberately uses `.refresh()` rather than `ref.invalidate(historyProvider)` — invalidate would recreate the notifier from scratch and silently drop any currently-applied filter; `refresh()` re-fetches page 1 with whatever filter is already active, matching the behavior of the header/pull-to-refresh triggers elsewhere in that screen. | `main_screen.dart:96-105` (inline comment) |
| RULE-MAIN-008 | Back press never actually pops the route (`PopScope(canPop:false)` always). On any non-Home tab, back press jumps to Home instead of exiting. On the Home tab, exiting requires two back presses within 2 seconds ("double-tap-to-exit"); a toast is shown on the first press. | `main_screen.dart:128-155` |
| RULE-MAIN-009 | The bottom nav bar is hidden entirely (not just faded) when the soft keyboard is visible, or whenever the active tab is Invest (index 1) — the inline comment attributes the Invest-tab hide to a "Wise-style footer" rendered by `InstantSavingScreen` itself that would otherwise collide with the shell's nav bar. | `main_screen.dart:185-187` |
