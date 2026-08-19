---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — State Analysis

## Riverpod providers

| Provider | Type | Defined in | Watched at |
|---|---|---|---|
| `onboardingContentProvider` | `FutureProvider<List<Map<String, dynamic>>>` | `core/services/content_service.dart:147-151` | `onboarding_screen.dart:25` |

Not owned by this module (lives in `core/services/`), but this is its only real consumer in the
codebase — grep for `onboardingContentProvider` shows one `ref.watch` and one `ref.refresh`, both
in this file.

## Local widget state (`_OnboardingScreenState`)

| Field | Type | Purpose |
|---|---|---|
| `_pageController` | `PageController` | drives the `PageView` |
| `_currentPage` | `int` (default `0`) | tracks active slide index for dot indicator + CTA label; updated via `setState` in `onPageChanged` |

## Model shapes

`OnboardingModel` (`onboarding_screen.dart:161-168`) — plain, non-`fromJson` class local to this
file: `{ title: String, description: String, image: String }`. Constructed inline in `build()`
either from API slide maps (keys `title`/`desc`/`image`) or the single hardcoded fallback. No
validation, no `toJson`, not shared with any other module.

## Secure storage keys touched

| Key (`AppConfig.keyHasSeenOnboarding`) | Written by | Read by |
|---|---|---|
| `hasSeenOnboarding` | `SessionManager.setOnboardingSeen()` (`onboarding_screen.dart:89`) | **Nobody** — see `BUSINESS_RULES.md` RULE-ONBOARDING-004 |

Also note: `secure_storage_service.dart:109-122` lists `keyHasSeenOnboarding` among keys explicitly
**preserved across logout** (i.e. not cleared on logout, alongside device identity) — consistent
with it being a durable "has this device ever seen onboarding" flag rather than per-session state,
even though nothing currently reads it.
