---
purpose: Single source of truth for path variables and the module registry. Every rules/skill/workflow file references these as {PLACEHOLDER} tokens instead of hardcoding paths, so the whole `.agents/` + `knowledge_brain/` system can be copied to another Flutter project by editing this file only.
last_updated: 2026-08-19
---

# Config — startGOLD Mobile (SIP)

## Path Variables

| Token | Value |
|---|---|
| `{PROJECT_ROOT}` | `E:\Projects\Mobileapp\SIP` |
| `{LIB_ROOT}` | `{PROJECT_ROOT}\lib` |
| `{CORE_DIR}` | `{LIB_ROOT}\core` |
| `{FEATURES_DIR}` | `{LIB_ROOT}\features` |
| `{ROUTES_DIR}` | `{LIB_ROOT}\routes` |
| `{SHARED_DIR}` | `{LIB_ROOT}\shared` |
| `{BRAIN_DIR}` | `{PROJECT_ROOT}\knowledge_brain` |
| `{AGENTS_DIR}` | `{PROJECT_ROOT}\.agents` |
| `{WORKFLOW_DIR}` | `{AGENTS_DIR}\workflows` |
| `{SKILLS_DIR}` | `{AGENTS_DIR}\skills` |
| `{BUG_REPORT_DIR}` | `{PROJECT_ROOT}\bug_report_AI` (created on demand by `/fix-single-bug`) |

## Platform Facts

| Fact | Value |
|---|---|
| Framework | Flutter 3.x / Dart >=3.4.1 |
| State management | Riverpod 2.x (`flutter_riverpod`) |
| Networking | Dio 5.x + custom interceptor chain (`core/security/api_interceptor.dart`) |
| Real-time | Socket.IO client (`core/network/native_socket_service.dart`) — live gold/silver rates |
| Local secure storage | `flutter_secure_storage` (AES-backed) |
| Field-level payload encryption | RSA-OAEP-SHA256, key fetched from `crypto/public-key` |
| Payment SDKs | Cashfree (`flutter_cashfree_pg_sdk`), HyperSDK, Razorpay |
| Push | Firebase Cloud Messaging + `flutter_local_notifications` |
| Biometrics | `local_auth` |
| Root/tamper detection | `root_checker_plus` + `core/security/root_detection_service.dart` |
| Screenshot/record block | `screen_protector` + `core/security/screenshot_security_service.dart` |
| Package name | `startgold` (pubspec.yaml) |
| App version at last brain build | 0.0.4+20 |

## Module Registry

Brain status badges: ⬜ 0% (not built) · 🟡 1–79% (partial) · 🟢 80–99% (mostly complete) · 🔵 100% + verified.

| # | Module (folder) | Brain folder | Domain | Brain Status |
|---|---|---|---|---|
| 0 | `core/` (shared layer, not a feature) | `Core` | Network, security, session, providers, services shared by all features | 🟢 |
| 1 | `auth` | `Auth` | Mobile login, OTP, registration, PIN creation | 🟢 |
| 2 | `mpin` | `MPIN` | App-lock MPIN verification/reset/change, biometrics | 🟢 |
| 3 | `kyc` | `KYC` | PAN/Aadhaar/bank KYC, regulatory compliance | 🟢 |
| 4 | `home` | `Home` | Dashboard, portfolio overview, live rates entry point | 🟢 |
| 5 | `instant_saving` | `InstantSaving` | One-time gold/silver purchase + payment methods — 3 gateways (Cashfree/HDFC-Juspay/Razorpay) selected server-side, `PaymentMethodsScreen` is dead legacy code (see brain) | 🟢 |
| 6 | `daily_savings` | `DailySavings` | Recurring micro-investment configuration — UI prototype only, disconnected/dead route, superseded in practice by SIP's Daily frequency (see brain) | 🔵 |
| 7 | `sip` | `SIP` | Systematic Investment Plans — create/manage/cancel/pay; two products (regular + Custom SIP), 24h cancel lock-in, Custom SIP endpoints missing from encrypted-endpoints list (see brain) | 🟢 |
| 8 | `withdrawal` | `Withdrawal` | Sell gold/silver, cash out to bank/UPI | 🔵 |
| 9 | `profile` | `Profile` | User profile, bank details, account deletion, verification history | 🔵 |
| 10 | `notifications` | `Notifications` | Push notification inbox | 🟢 |
| 11 | `nominee` | `Nominee` | Beneficiary management | 🟢 |
| 12 | `referral` | `Referral` | Referral code sharing, referee list, rewards | 🟢 |
| 13 | `settings` | `Settings` | App preferences, MPIN toggle, language (biometric toggle is actually owned by `Profile`, not this module — see `Settings/BUSINESS_RULES.md` RULE-SETTINGS-008) | 🟢 |
| 14 | `support` | `Support` | Support hub (dead route, unreachable), enquiry form/list — ticket-type default/mapping bug (see brain) | 🔵 |
| 15 | `content` | `Content` | Terms, privacy, about (dead route, unreachable), refund policy, FAQ, contact — all server-fetched, rendered via `flutter_widget_from_html_core` (see brain) | 🔵 |
| 16 | `market` | `Market` | Live rate models (mostly embedded in Home) | 🔵 |
| 17 | `history` | `History` | Transaction history & details, audit trail | 🔵 |
| 18 | `splash` | `Splash` | App init gate — session/version/maintenance check | 🔵 |
| 19 | `onboarding` | `Onboarding` | First-run carousel (currently an orphaned route — never navigated to) | 🔵 |
| 20 | `maintenance` | `Maintenance` | Server-downtime screen | 🔵 |
| 21 | `main` | `Main` | Bottom-nav tab shell container | 🟢 |
| 22 | `invoice` | `Invoice` | Invoice/receipt PDF viewer — reached only from History/SIP transaction details; uses a raw `Dio()` bypassing cert pinning (see brain) | 🟢 |
| 23 | `jewellery` | `Jewellery` | "Coming Soon" marketing placeholder tab — no purchase/redemption logic exists anywhere yet (see brain) | 🟢 |

## Pre-Existing Documentation (read before rebuilding — do not duplicate, cross-check instead)

| File | Covers | Caveat |
|---|---|---|
| `{PROJECT_ROOT}\STARTGOLD_DOCUMENTATION.md` | Screen-by-screen doc for 21 of 23 modules, security architecture, WebSocket protocol, compliance matrix | Hand-written, dated 2026-05-20 — does **not** cover `jewellery` or `invoice` (added after). Verify against live code; flag drift like the fintech brain does against `project_brain.md`. |
| `{PROJECT_ROOT}\about startGOLD.md` | One-paragraph product pitch | Marketing-level, not technical |

## Bug-Recipe / Cross-Project Layer

Not yet configured. If a central recipe repo is set up later (mirroring `LOGIMAX-CLIENTS/bug-recipes`), record its location here and wire `/push-recipe` + `/pull-recipes` accordingly.
