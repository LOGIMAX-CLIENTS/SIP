---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — Data Flow

> Reminder: as documented in `MODULE_BRAIN.md` §0, no code path currently navigates to this
> screen. The flows below describe what happens *if* `/onboarding` is reached (e.g. manually via
> `Navigator.pushNamed` in a debug build, or once/if a future first-run gate is wired up).

## Flow 1: Screen load → content fetch → render

```
OnboardingScreen.build()                                onboarding_screen.dart:24
   │
   ▼
ref.watch(onboardingContentProvider)                     content_service.dart:147
   │
   ▼
ContentService.getOnboardingContent()                    content_service.dart:8
   │  POST users/content/onboarding   (ApiClient/Dio — no auth)
   │
   ├─ success, data.slides present  → List<Map> slides
   ├─ success, no data.slides       → [] (empty list)
   └─ any exception                 → [] (swallowed — see Top Risks §4 in MODULE_BRAIN.md)
   │
   ▼
AsyncValue<List<Map>>.when(...)                           onboarding_screen.dart:29
   ├─ data, slides.isNotEmpty  → map to List<OnboardingModel>{title, desc, image}   :31-38
   ├─ data, slides.isEmpty     → 1 hardcoded OnboardingModel ("Artisanal Security")  :39-46
   ├─ loading                  → CircularProgressIndicator                          :110-112
   └─ error                    → error icon + Retry button (practically unreachable) :113-129
   │
   ▼
PageView.builder → OnboardingPage per slide → dot indicators + CustomButton CTA
```

## Flow 2: Completing the carousel → session flag → navigation

```
User taps CTA on last page ("Begin Your Legacy")          onboarding_screen.dart:87-95
   │
   ▼
SessionManager.setOnboardingSeen()                         session_manager.dart:50
   │
   ▼
SecureStorageService.setOnboardingSeen(true)                secure_storage_service.dart:51
   │   writes AppConfig.keyHasSeenOnboarding = 'true' to flutter_secure_storage
   │
   ▼
Navigator.pushReplacementNamed(context, AppRouter.login)    onboarding_screen.dart:93
   │
   ▼
LoginScreen (module: auth, not yet brained)
```

Note: the write in this flow (`hasSeenOnboarding` → secure storage) has no downstream reader
anywhere in the current codebase — see `MODULE_BRAIN.md` Top Risk #2.

## Flow 3: Mid-carousel page advance (no network, no navigation)

```
User taps CTA on any non-last page ("Advance Forward")      onboarding_screen.dart:96-101
   │
   ▼
_pageController.nextPage(duration: 600ms, curve: fastOutSlowIn)
   │
   ▼
onPageChanged callback → setState(() => _currentPage = index)   onboarding_screen.dart:52
   │
   ▼
Rebuild: dot indicator + CTA label update (same screen, no route change)
```
