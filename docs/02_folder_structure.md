# Folder Structure — startGOLD

This document maps every directory in the project with clear descriptions. Use this as your navigation compass when working on the codebase.

---

## Root Directory

```
SIP/
├── android/              # Android native project (Gradle, Manifest, etc.)
├── ios/                  # iOS native project (Xcode, Podfile, etc.)
├── web/                  # Web platform support
├── linux/                # Linux desktop support
├── macos/                # macOS desktop support
├── windows/              # Windows desktop support
├── lib/                  # ★ ALL Dart/Flutter source code lives here
├── assets/               # Static assets (images, fonts, animations)
├── docs/                 # ★ Project documentation (you are here)
├── scripts/              # Build & utility scripts
├── test/                 # Unit and widget tests
├── pubspec.yaml          # Dependencies, assets, fonts configuration
├── analysis_options.yaml # Linter rules
└── README.md             # Basic project readme
```

---

## `lib/` — Main Source Code

```
lib/
├── main.dart             # App entry point — bootstraps Firebase, security, Riverpod
├── core/                 # Shared infrastructure (used by all features)
├── features/             # Feature modules (one folder per screen/feature)
├── routes/               # Centralized route definitions
└── shared/               # Shared UI components, theme, utilities
```

---

## `lib/core/` — Core Infrastructure

The `core/` folder contains **non-feature-specific** infrastructure code that all features depend on.

```
lib/core/
├── config/
│   └── app_config.dart           # Base URLs, storage keys, timeout values, encrypted endpoints list
│
├── constants/
│   └── app_constants.dart        # UI strings, labels, error messages, withdrawal limits
│
├── error/
│   └── failures.dart             # Failure class hierarchy (NetworkFailure, ServerFailure, etc.)
│
├── localization/
│   ├── language_cache.dart       # Persists selected language to SharedPreferences
│   ├── language_provider.dart    # Riverpod provider for language state
│   └── language_service.dart     # Fetches supported languages from API
│
├── models/
│   └── app_control_model.dart    # Remote config model (maintenance mode, force update, etc.)
│
├── network/
│   ├── api_client.dart           # Dio HTTP client wrapper (GET/POST with interceptors)
│   ├── interceptors.dart         # Network interceptors (logging, error handling)
│   └── native_socket_service.dart# WebSocket service for live gold/silver rate streaming
│
├── providers/
│   ├── app_control_provider.dart # Remote config (maintenance, update) provider
│   ├── commodity_provider.dart   # Gold/Silver commodity data provider
│   ├── connectivity_provider.dart# Internet connectivity monitor
│   ├── home_dashboard_provider.dart # Dashboard data aggregator
│   ├── market_provider.dart      # Live market rates provider
│   ├── portfolio_provider.dart   # User portfolio (holdings, returns) provider
│   ├── timer_provider.dart       # Countdown timer provider (rate-lock)
│   └── user_provider.dart        # Current user profile data provider
│
├── security/
│   ├── api_interceptor.dart      # ★ Dio interceptor: auth tokens, RSA encryption, 409 handling
│   ├── app_lifecycle_observer.dart# App foreground/background security (session timeout, etc.)
│   ├── certificate_pinning.dart  # SSL certificate & public key pinning
│   ├── encryption_service.dart   # RSA-OAEP-SHA256 encryption for sensitive API payloads
│   ├── root_detection_service.dart# Root/jailbreak detection
│   ├── secure_logger.dart        # Filtered logger (redacts sensitive data in logs)
│   ├── secure_storage_service.dart# flutter_secure_storage wrapper (tokens, keys, user data)
│   └── session_manager.dart      # Session auth state + force-logout handling
│
├── services/
│   ├── app_control_service.dart  # Fetches remote app control config
│   ├── auth_service.dart         # ★ Authentication: OTP send/verify, register, login/logout
│   ├── biometric_service.dart    # Fingerprint/FaceID enrollment & verification
│   ├── content_service.dart      # CMS content (T&C, Privacy Policy, About, FAQ)
│   ├── device_id_service.dart    # Unique device ID generation
│   ├── device_service.dart       # Device info (model, OS, etc.)
│   ├── fcm_service.dart          # Firebase Cloud Messaging setup & token management
│   ├── home_service.dart         # Home dashboard API calls
│   ├── mpin_service.dart         # MPIN create/validate/change/reset API calls
│   ├── notification_service.dart # Local notification display & handling
│   ├── portfolio_service.dart    # Portfolio holdings API calls
│   └── shared_service.dart       # Shared utilities across services
│
└── utils/
    ├── kyc_validator.dart        # KYC field validation (PAN format, Aadhaar, etc.)
    ├── logger.dart               # Debug logger
    ├── masking_utils.dart        # PII masking for display (mask phone, PAN, etc.)
    ├── navigation_utils.dart     # Navigation helper methods
    └── validators.dart           # General form validators
```

---

## `lib/features/` — Feature Modules

Each feature is **self-contained** with its own screens, controllers, models, and services.

```
lib/features/
├── auth/                  # Authentication flows
│   ├── controller/        #   Auth flow controllers
│   ├── login/             #   Login screen (phone number input)
│   ├── otp/               #   OTP verification screen
│   ├── pin/               #   PIN creation & entry screens
│   └── registration/      #   New user registration + success screen
│
├── onboarding/            # First-time user onboarding carousel
│
├── splash/                # Splash screen (session check, routing logic)
│
├── mpin/                  # MPIN entry & change screens
│
├── home/                  # Home dashboard (portfolio, rates, quick actions)
│   ├── home_screen.dart   #   Main home screen
│   ├── models/            #   Home data models
│   └── widgets/           #   Home-specific widgets
│
├── main/                  # Main container with bottom navigation bar
│
├── market/                # Live market rates display
│   └── models/            #   Market data models
│
├── instant_saving/        # ★ Buy gold/silver instantly
│   ├── instant_saving_screen.dart  #   Main buy screen
│   ├── payment_handler.dart        #   Cashfree payment flow
│   ├── controller/                 #   Business logic
│   ├── models/                     #   Purchase data models
│   ├── screens/                    #   Payment method selection, etc.
│   └── services/                   #   Buy API calls
│
├── daily_savings/         # Daily savings auto-buy feature
│
├── sip/                   # ★ Systematic Investment Plan (Auto-Savings)
│   ├── controller/        #   SIP business logic
│   ├── models/            #   SIP subscription models
│   ├── screens/           #   Create/manage/cancel/payment/success/failure screens
│   └── services/          #   SIP API calls
│
├── withdrawal/            # ★ Sell gold & withdraw funds
│   ├── models/            #   Withdrawal data models
│   ├── providers/         #   Withdrawal state providers
│   ├── screens/           #   Withdrawal flow screens (amount, UPI, confirmation, success)
│   └── services/          #   Withdrawal API calls
│
├── kyc/                   # ★ KYC verification (PAN, Aadhaar, Bank)
│   ├── controllers/       #   KYC step controllers
│   ├── models/            #   KYC data models
│   ├── providers/         #   KYC state providers
│   ├── repositories/      #   KYC data layer
│   ├── screens/           #   Dynamic KYC form screens
│   └── kyc_screen.dart    #   Main KYC orchestrator
│
├── history/               # Transaction history & details
│   └── screens/           #   List + detail views
│
├── profile/               # User profile & account details
│   ├── profile_screen.dart     # Profile page
│   ├── account_details_screen.dart # Detailed account info
│   ├── profile_controller.dart # Profile business logic
│   ├── screens/           #   Delete account, etc.
│   ├── services/          #   Profile API calls
│   └── widgets/           #   Profile-specific widgets
│
├── nominee/               # Nominee management
│   └── screens/           #   Add/edit nominee
│
├── referral/              # Referral program
│   └── referee_list_screen.dart # List of referred users
│
├── settings/              # App settings
│
├── support/               # Customer support
│   └── screens/           #   Enquiry form, enquiry list
│
├── content/               # CMS content display
│   └── screens/           #   Terms, Privacy, FAQ, Contact Us
│
├── notifications/         # Push notification list
│
└── maintenance/           # Maintenance mode screen
```

---

## `lib/routes/` — Routing

```
lib/routes/
└── app_router.dart        # ★ Centralized named route definitions & onGenerateRoute
```

All 40+ routes are defined as static constants and mapped to their screens here.

---

## `lib/shared/` — Shared UI Layer

```
lib/shared/
├── theme/
│   ├── app_theme.dart          # ★ Light/Dark ThemeData, brand colors, gradients
│   └── app_text_styles.dart    # Typography presets (headings, body, captions)
│
├── widgets/
│   ├── custom_button.dart      # Reusable gradient button
│   ├── loaders.dart            # Loading spinners & shimmer effects
│   ├── app_toast.dart          # Toast/snackbar notifications
│   ├── app_alert_banner.dart   # Top alert banners
│   ├── app_control_wrapper.dart # Runtime control layer (maintenance, updates)
│   ├── app_update_dialog.dart  # Force update dialog
│   ├── animations.dart         # Shared animation widgets
│   ├── compromised_device_screen.dart # Rooted device block screen
│   ├── gradient_header.dart    # Gradient page headers
│   ├── maintenance_gate.dart   # Maintenance mode gate
│   ├── numeric_styled_text.dart # Number formatting widget
│   ├── offline_banner.dart     # No internet banner
│   └── session_invalidated_dialog.dart # 409 session expired dialog
│
└── utils/
    ├── no_leading_zeros_formatter.dart  # Input formatter
    └── upper_case_words_formatter.dart  # Input formatter
```

---

## `assets/` — Static Resources

```
assets/
├── images/        # General app images (logos, illustrations)
├── fonts/         # Custom fonts (Lora-Regular, Lora-SemiBold, Lora-Bold)
├── home/          # Home screen specific assets
├── sip/           # SIP feature assets
├── buttons/       # Button images/icons
├── footer/        # Bottom navigation icons
├── sidemenu/      # Side menu icons
├── withdraw/      # Withdrawal flow assets
└── resources/     # App icon, splash resources
```

---

## Platform Directories

| Directory | Purpose |
|-----------|---------|
| `android/` | Android Gradle build config, AndroidManifest, Kotlin files |
| `ios/` | Xcode project, Info.plist, Podfile |
| `web/` | Web entry point (`index.html`) |
| `windows/` | Windows desktop runner |
| `linux/` | Linux desktop runner |
| `macos/` | macOS desktop runner |

> **Note**: The primary targets are **Android** and **iOS**. Web has partial support (no FCM, no root detection).
