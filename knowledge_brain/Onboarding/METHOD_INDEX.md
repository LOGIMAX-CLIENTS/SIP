---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — Method Index

All in `lib/features/onboarding/onboarding_screen.dart` unless noted.

| Method/Member | File:Line | Purpose | Called by |
|---|---|---|---|
| `_OnboardingScreenState.build(BuildContext)` | `:24-132` | Watches `onboardingContentProvider`, renders `AsyncValue.when` (data/loading/error), builds the `PageView` + dot indicators + CTA | Flutter framework |
| `buildDot(int index, int total, bool isDark)` | `:134-158` | Renders one progress-dot indicator, active/inactive styling | `build()` loop (`:69`) |
| `OnboardingModel` (class) | `:161-168` | Plain data holder: `title`, `description`, `image` | constructed in `build()` from either API slides or the hardcoded fallback |
| `OnboardingPage.build(BuildContext)` | `:174-253` | Renders one slide: background image, gradient scrim, title/description with `FadeInAnimation` | `PageView.builder`'s `itemBuilder` (`:54-56`) |

## External calls made by this module

| Call | Defined in | Used at |
|---|---|---|
| `ref.watch(onboardingContentProvider)` | `core/services/content_service.dart:147-151` | `onboarding_screen.dart:25` |
| `ContentService.getOnboardingContent()` | `core/services/content_service.dart:8-20` | invoked by the provider above |
| `SessionManager.setOnboardingSeen()` | `core/security/session_manager.dart:50-52` | `onboarding_screen.dart:89` |
| `ref.refresh(onboardingContentProvider)` | Riverpod | `onboarding_screen.dart:124` (error-branch retry button — effectively unreachable, see `MODULE_BRAIN.md` §2.1) |

## Note on unused capability

`SessionManager.hasSeenOnboarding()` (`core/security/session_manager.dart:45-48`) exists but is
never called anywhere in `lib/` — not by this module, not by `splash`. Listed here because it's
the natural counterpart to `setOnboardingSeen()`, which this module does call.
