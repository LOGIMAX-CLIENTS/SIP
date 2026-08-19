---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — Business Rules

| ID | Rule | Code |
|---|---|---|
| RULE-ONBOARDING-001 | The onboarding screen is unreachable in the shipped navigation graph — no code path anywhere in `lib/` calls `Navigator.push*Named(..., AppRouter.onboarding, ...)`. Confirmed dead route, same class of finding as `daily_savings`. | Absence confirmed via repo-wide grep; route registered at `app_router.dart:65,130` |
| RULE-ONBOARDING-002 | No skip control exists. The only way to leave the carousel is completing every slide via the CTA button (which pages forward one slide at a time until the last, then completes). | `onboarding_screen.dart:74-102` (absence of any skip element confirmed via grep) |
| RULE-ONBOARDING-003 | Onboarding content is server-driven (`POST users/content/onboarding`) with a single hardcoded fallback slide if the API returns no slides or fails. API errors are caught inside the service and converted to an empty list, so the screen's own `error:` UI branch is not reachable from a real network failure — only from an exception thrown by `AsyncValue.when` itself, which doesn't happen given the service never rethrows. | `content_service.dart:8-20`, `onboarding_screen.dart:39-46`, `:113-129` |
| RULE-ONBOARDING-004 | Completing onboarding sets `hasSeenOnboarding=true` in secure storage via `SessionManager.setOnboardingSeen()`, but this flag is not consumed anywhere else in the code — `splash_screen.dart` never reads it via `SessionManager.hasSeenOnboarding()`, and no other file calls that getter either. The flag currently has no functional effect on app behavior. **Unconfirmed** whether intentional (forward-looking) or vestigial (a removed gate). | `onboarding_screen.dart:89` writes; absence of any reader confirmed via grep |
| RULE-ONBOARDING-005 | Completing onboarding always routes to `/login` via `pushReplacementNamed`, regardless of any prior session or mpin state — there is no branch equivalent to splash's "logged in + mpin enabled → /mpin" logic here. | `onboarding_screen.dart:91-95` |
