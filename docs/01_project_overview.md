# startGOLD — Project Overview

## What is startGOLD?

**startGOLD** is a fintech-grade **digital gold and silver investment platform** built with Flutter. It enables users to buy, save, and manage 24K digital gold and silver through a secure mobile application.

> Think of it as a "Zerodha for Gold" — a sleek, secure mobile-first investment app focused on precious metals.

---

## Business Purpose

| Goal | Description |
|------|-------------|
| **Instant Buy** | Users buy 24K gold/silver by amount (₹) or weight (grams) at live market rates |
| **SIP (Systematic Investment Plan)** | Automated recurring gold purchases — daily, weekly, or monthly |
| **Daily Savings** | Micro-savings feature for habitual daily gold accumulation |
| **Withdrawal / Sell** | Users sell holdings and receive funds via UPI or bank transfer |
| **Portfolio Tracking** | Real-time portfolio valuation with live rate streaming |
| **KYC Compliance** | Mandatory PAN / Aadhaar / Bank verification before transactions |
| **Referral System** | Users earn rewards by referring friends |

---

## Tech Stack at a Glance

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter (Dart) — SDK ≥3.4.1 |
| **State Management** | Riverpod (`flutter_riverpod`) |
| **Networking** | Dio (HTTP) + WebSocket (live rates) |
| **Security** | RSA-OAEP-SHA256 encryption, SSL pinning, root detection |
| **Auth** | OTP-based + MPIN + Biometric (local_auth) |
| **Storage** | `flutter_secure_storage` (sensitive), `shared_preferences` (flags) |
| **Payments** | Cashfree Payment Gateway SDK |
| **Push Notifications** | Firebase Cloud Messaging (FCM) |
| **UI** | Material 3, ScreenUtil, Google Fonts (Lora), Lottie, SVG |
| **Platforms** | Android, iOS (primary), Web (partial) |

---

## Target Environments

The app connects to different backend servers based on build configuration:

| Environment | Usage |
|-------------|-------|
| **Production** | `https://api.startgold.com/api/api/v1/` — Live users |
| **Staging** | `https://startgoldapi.logimaxindia.com/api/api/v1/` — QA testing |
| **VAPT** | `https://vaptapi.startgold.com/api/api/v1/` — Security audit server |

Environment is controlled via `--dart-define=BASE_URL=<url>` at build time. See [app_config.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/config/app_config.dart).

---

## App Version

- **Current Version**: `1.0.0+8` (defined in `pubspec.yaml`)
- **Min SDK**: Flutter ≥3.4.1, Dart <4.0.0

---

## Supported Languages

| Locale | Language |
|--------|----------|
| `en` | English (default) |
| `ta` | Tamil |
| `te` | Telugu |

---

## Key External Dependencies

| Package | Purpose |
|---------|---------|
| `dio` | HTTP client with interceptors |
| `flutter_riverpod` | Reactive state management |
| `firebase_core` / `firebase_messaging` | Push notifications |
| `flutter_secure_storage` | Encrypted key-value store |
| `flutter_cashfree_pg_sdk` | Payment gateway integration |
| `local_auth` | Fingerprint / Face ID |
| `web_socket_channel` | Live gold/silver rate streaming |
| `encrypt` / `crypto` | RSA encryption for sensitive payloads |
| `flutter_screenutil` | Responsive screen sizing |
| `root_checker_plus` | Root / jailbreak detection |
| `screen_protector` | Screenshot & screen recording prevention |
| `image_picker` / `image_cropper` | Profile photo upload |
| `lottie` | Premium animations |

---

## Quick Links

| Document | Path |
|----------|------|
| Project Overview | You are here |
| [Folder Structure](file:///e:/Projects/Mobileapp/SIP/docs/02_folder_structure.md) | Complete directory map |
| [Architecture Guide](file:///e:/Projects/Mobileapp/SIP/docs/03_architecture.md) | Architecture & design patterns |
| [Setup Guide](file:///e:/Projects/Mobileapp/SIP/docs/04_setup_guide.md) | How to clone, build, and run |
| [Feature Guide](file:///e:/Projects/Mobileapp/SIP/docs/05_features.md) | Feature-by-feature breakdown |
| [Security Guide](file:///e:/Projects/Mobileapp/SIP/docs/06_security.md) | Security architecture |
| [API Reference](file:///e:/Projects/Mobileapp/SIP/docs/07_api_reference.md) | API endpoints and data flow |
| [State Management](file:///e:/Projects/Mobileapp/SIP/docs/08_state_management.md) | Riverpod providers guide |
| [UI & Theming](file:///e:/Projects/Mobileapp/SIP/docs/09_ui_theming.md) | Design system & theme tokens |
| [Routing Guide](file:///e:/Projects/Mobileapp/SIP/docs/10_routing.md) | Navigation & route map |
| [Coding Conventions](file:///e:/Projects/Mobileapp/SIP/docs/11_coding_conventions.md) | Style guide & best practices |
| [Troubleshooting](file:///e:/Projects/Mobileapp/SIP/docs/12_troubleshooting.md) | Common issues & fixes |
