# Cross-Module Map — Referral

## Dependency Table

| Dependency | Type | Used for | File:line |
|---|---|---|---|
| `core/network/api_client.dart` (`ApiClient`) | Core service | Both HTTP calls (`fetchReferralData`, `fetchList`) | `referral_service.dart:3,68`; `referee_list_service.dart:3,49` |
| `core/config/app_config.dart` (`encryptedEndpoints`) | Core config | Indirect — determines whether `users/auth/referral/details` / `referrals/referee-list` get payload-encrypted (they don't; see `BUSINESS_RULES.md` RULE-REFERRAL-003) | `app_config.dart:47-71` |
| `shared/theme/app_theme.dart` | Shared theme | Colors (imported, direct hardcoded hex colors used more than theme constants in this module) | `referral_screen.dart:9` |
| `shared/widgets/app_toast.dart` (`AppToast`) | Shared widget | "Referral code copied!" toast | `referral_screen.dart:10,411` |
| `shared/widgets/numeric_styled_text.dart` (`NumericStyledText`) | Shared widget | Bullet text rendering (`referral_screen.dart`), referee count text (`referee_list_screen.dart`) | `referral_screen.dart:11,319`; `referee_list_screen.dart:5,161` |
| `shared/widgets/gradient_header.dart` (`GradientHeader`) | Shared widget | `RefereeListScreen`'s top header — **not independently re-verified line-by-line this round**, cross-module | `referee_list_screen.dart:8,35` |
| `shared/theme/app_text_styles.dart` (`AppTextStyles`) | Shared theme | Empty-state title style | `referee_list_screen.dart:9,114` |
| `features/main/main_screen.dart` (`selectedTabProvider`) | Feature (main) | Back-button behavior resets the bottom-nav tab to 0 when `ReferralScreen` is reached as an embedded tab rather than a pushed route | `referral_screen.dart:13,118` |
| `routes/app_router.dart` (`AppRouter`) | Routing | Route constants (`referral`, `refereeList`) and navigation | `referral_screen.dart:14,115,116,247`; `app_router.dart:79,107,177,304` |
| `package:share_plus` | 3rd-party | Native OS share sheet for referral text | `referral_screen.dart:7,42`; `pubspec.yaml:56` (`share_plus: ^10.0.3`) |
| `package:shimmer` | 3rd-party | Referee list loading skeleton | `referee_list_screen.dart:6,56-67`; `pubspec.yaml:45` (`shimmer: ^3.0.0`) |

## Inbound Dependents (who calls into this module)

| Caller | What it does | File:line |
|---|---|---|
| `features/home/home_screen.dart` | Navigates to `AppRouter.referral` (menu/banner entry point) | `home_screen.dart:853` |
| `features/profile/profile_screen.dart` | Navigates to `AppRouter.referral` (menu entry point) | `profile_screen.dart:259` |
| `routes/app_router.dart` | Registers both routes | `app_router.dart:177,304` |

No other feature module reads `ReferralData`, `RefereeItem`, or the referral providers directly — state
is fully local to this module (not exposed via `core/providers/`).

## The Signup-Time Half of the Loop (owned by `auth`, cross-referenced here)

The referral **code entry** happens entirely inside the `auth`/registration flow, not in this module.
This module only ever displays the *result* of that flow (referral count, earned amount, referee list)
after the fact, on a separate visit to a separate screen.

| File | Role | File:line |
|---|---|---|
| `lib/features/auth/registration/registration_screen.dart` | Owns the "Referral Code (Optional)" text field; calls `register-check` then passes the code forward as a nav argument | `registration_screen.dart:36,304-311,532-539,548-556` |
| `lib/features/auth/pin/pin_creation_screen.dart` | Receives `referralCode` as a constructor param; passes it to `AuthController.register()` during PIN setup | `pin_creation_screen.dart:28,36,405-414` |
| `lib/core/services/auth_service.dart` | `registerCheck()` and `register()` both send `referral_code` to the backend | `auth_service.dart:128-147,180-197` |
| `lib/routes/app_router.dart` | `mpinCreation` route wiring passes `args['referralCode']` through to `PinCreationScreen` | `app_router.dart:179-191` |

**No shared model or provider connects the two halves** — the referral code is a plain `String` passed
through constructor args and JSON request bodies; there is no `core/providers/` referral state that both
`auth` and `referral` read from. If the referral-brain and auth-brain (once built) ever need to trace
"why didn't my referral count go up," the trail is: registration payload → (opaque backend processing,
not visible in this codebase) → `users/auth/referral/details` response on next `ReferralScreen` visit.

## Mermaid Dependency Graph

```mermaid
graph TD
    subgraph Referral Module
        RS[ReferralScreen]
        RSVC[ReferralService]
        RLS[RefereeListScreen]
        RLSVC[RefereeListService]
    end

    subgraph Core
        API[core/network/ApiClient]
        CFG[core/config/AppConfig<br/>encryptedEndpoints]
    end

    subgraph Shared
        TOAST[shared/widgets/AppToast]
        NST[shared/widgets/NumericStyledText]
        GH[shared/widgets/GradientHeader]
        THEME[shared/theme]
    end

    subgraph Other Features
        HOME[features/home/HomeScreen]
        PROFILE[features/profile/ProfileScreen]
        MAIN[features/main/MainScreen<br/>selectedTabProvider]
    end

    subgraph Auth (signup-time half)
        REG[features/auth/registration/<br/>RegistrationScreen]
        PIN[features/auth/pin/<br/>PinCreationScreen]
        AUTHSVC[core/services/AuthService]
    end

    HOME -->|pushNamed /referral| RS
    PROFILE -->|pushNamed /referral| RS
    RS -->|invalidate/watch| RSVC
    RS -->|pushNamed /referee-list| RLS
    RS --> TOAST
    RS --> NST
    RS --> MAIN
    RLS -->|invalidate/watch| RLSVC
    RLS --> GH
    RLS --> NST
    RSVC -->|POST users/auth/referral/details| API
    RLSVC -->|POST referrals/referee-list| API
    API --> CFG

    REG -->|referral_code field| AUTHSVC
    PIN -->|referral_code param| AUTHSVC
    AUTHSVC -->|POST users/auth/register-check<br/>POST users/auth/register| API

    RSVC -.->|no shared state -<br/>reads eventual result only| AUTHSVC
```

## Known Violations of `AGENTS.md` Conventions

- **No `controller/`/`models/`/`services/` subfolder split** — the module puts model + service classes
  directly in the same file as (or a sibling to) the screen, contrary to the feature-first structure
  described in `AGENTS.md` §1. Not flagged as a bug, just noted as a structural outlier versus the
  convention.
- Route back-navigation in `referral_screen.dart:113-120` inspects `ModalRoute.of(context)?.settings.name`
  string-compares it against `AppRouter.referral` rather than using a dedicated "came from tab vs. pushed"
  flag — works but is a slightly fragile pattern (would silently misbehave if the same screen were ever
  registered under a second route name).
