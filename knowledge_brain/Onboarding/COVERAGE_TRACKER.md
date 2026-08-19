---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — Coverage Tracker

| Round | Date | Screens | Methods | Models | API Endpoints | Business Rules | Cross-Module Deps | Weighted % | Badge |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-08-19 | 1/1 (100%) | 4/4 (100%) | 1/1 (`OnboardingModel`, 100%) | 1/1 (`users/content/onboarding`) (100%) | 5 rules captured, including the module's core "orphaned route" finding | Fully mapped — 6 outbound deps, 0 real inbound (confirmed via grep) | 100% | 🔵 |

## Spot-check (Round 1)

Full read of `onboarding_screen.dart` (256 lines). Cross-verified against
`core/services/content_service.dart` (full read of `getOnboardingContent` + provider
definitions), `core/security/session_manager.dart` and `secure_storage_service.dart` (full read
of the onboarding-flag methods), `shared/widgets/custom_button.dart` (targeted read confirming no
skip-related prop/branch exists), and a repo-wide case-insensitive grep for `skip`/`Skip` in the
file (zero matches) plus a repo-wide grep for every navigation call targeting
`AppRouter.onboarding` (zero real navigators found).

## Drift found vs `STARTGOLD_DOCUMENTATION.md` §3.2

- Doc states: "Multi-page carousel, skip button, proceed to login." **Two discrepancies**:
  1. No skip button exists in the current code (confirmed, see above).
  2. The doc doesn't mention (and presumably predates) the fact that the route is currently
     unreachable from splash or anywhere else.
- Recorded in `_OVERVIEW/BUILD_SUMMARY.md`.
