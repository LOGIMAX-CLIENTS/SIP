---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — Cross-Module Map

## Outbound dependencies (what `onboarding` reads from)

| Dependency | File | Used for |
|---|---|---|
| `onboardingContentProvider` / `ContentService` | `core/services/content_service.dart` | fetching carousel slides from `POST users/content/onboarding` |
| `SessionManager` | `core/security/session_manager.dart` | `setOnboardingSeen()` |
| `AppRouter` | `routes/app_router.dart` | route constant (`login`) |
| `CustomButton` | `shared/widgets/custom_button.dart` | the CTA button |
| `FadeInAnimation` | `shared/widgets/animations.dart` | staggered slide-content fade-in |
| `AppTheme` | `shared/theme/app_theme.dart` | colors/gradients (`arcticBlue`, `electricCyan`, `midnightNavy`, `primaryGreen`, `greenGradient`) |

## Inbound dependencies (what depends on `onboarding`)

**None found.** `routes/app_router.dart` registers the route but nothing navigates to it —
see `MODULE_BRAIN.md` §0 for the full grep-verified claim. The only other reference to
`AppRouter.onboarding` in the codebase is a defensive entry in
`core/security/app_lifecycle_observer.dart:150` (a route-skip list for the app-lock observer,
not a navigation trigger).

## Mermaid

```mermaid
graph LR
    Onboarding["features/onboarding<br/>OnboardingScreen"]

    Onboarding --> ContentService["core/services/<br/>content_service.dart<br/>(onboardingContentProvider)"]
    Onboarding --> SessionManager["core/security/<br/>session_manager.dart<br/>(setOnboardingSeen)"]
    Onboarding --> CustomButton["shared/widgets/<br/>custom_button.dart"]
    Onboarding --> Animations["shared/widgets/<br/>animations.dart<br/>(FadeInAnimation)"]
    Onboarding --> Theme["shared/theme/<br/>app_theme.dart"]

    Onboarding -.pushReplacementNamed.-> Login["/login<br/>features/auth"]

    Router["routes/app_router.dart"] -. registers, never invoked .-> Onboarding
    LifecycleObserver["core/security/<br/>app_lifecycle_observer.dart"] -. defensive skip-list only .-> Onboarding

    style Onboarding fill:#4a4a4a,stroke:#ff6b6b,stroke-width:2px,color:#fff
```

*(Node styled to visually flag "reachable by nothing" in the graph — this module is orphaned.)*
