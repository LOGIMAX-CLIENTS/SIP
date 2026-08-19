---
last_updated: 2026-08-19
source: Derived primarily from Core/STATE_ANALYSIS.md and Core/METHOD_INDEX.md, cross-checked against consumer modules
---

# Shared Services & Providers (core/)

Full detail lives in `knowledge_brain/Core/STATE_ANALYSIS.md` (all 30 providers, 14 secure-storage keys) and
`Core/METHOD_INDEX.md` (every public method). This is the quick-reference index.

## Networking & Security

| Component | File | Purpose | Known Issues |
|---|---|---|---|
| `ApiClient` | `core/network/api_client.dart` | Single Dio instance every feature should route through | Invoice bypasses this with a raw `Dio()` (DANGER_ZONES-adjacent, cert-pinning gap) |
| `ApiSecurityInterceptor` | `core/security/api_interceptor.dart` | Encryption field selection, 401 refresh, 409 force-logout | See DZ-002/DZ-003 |
| `EncryptionService` | `core/security/encryption_service.dart` | RSA-OAEP-SHA256 field encryption | `decrypt()` is a no-op — DZ-001 |
| `SessionManager` | `core/security/session_manager.dart` | Auth state, force-logout | — |
| `SecureStorageService` | `core/security/secure_storage_service.dart` | Tokens, MPIN state, biometric flags (14 keys) | — |
| `CertificatePinning` | `core/security/certificate_pinning.dart` | Cert pinning setup | Bypassed when a raw `Dio()` is used instead of `ApiClient` |
| `RootDetectionService` | `core/security/root_detection_service.dart` | Root/jailbreak check at startup | — |
| `ScreenshotSecurityService` | `core/security/screenshot_security_service.dart` | `FLAG_SECURE` on sensitive screens | Inconsistently applied — e.g. `change_mpin_screen.dart` lacks it unlike `mpin_screen.dart`; OTP screen has it but login/registration/PIN-creation don't |
| `AppLifecycleObserver` | `core/security/app_lifecycle_observer.dart` | App-lock on resume, suppressed during payment SDK focus | — |
| `NativeSocketService` | `core/network/native_socket_service.dart` | Live rate feed (raw `web_socket_channel`, not Socket.IO) | Flat 5s reconnect, no backoff |

## Providers (Riverpod, global/cross-feature)

30 total — see `Core/STATE_ANALYSIS.md` for the full list with state shapes. Highest-consumed: `timer_provider`,
`market_provider`, `commodity_provider`, `user_provider`, `portfolio_provider`, `home_dashboard_provider`,
`connectivity_provider`, `app_control_provider`, `countdown_offer_provider`, `environment_provider`.

## Services

`auth_service`, `biometric_service`, `content_service` (shared by Content + Onboarding), `device_id_service`,
`device_service` (dead — duplicate of `device_id_service`), `environment_service`, `fcm_service`,
`home_service`, `mpin_service`, `notification_service`, `portfolio_service`, `shared_service`,
`app_control_service`.

## Consumers Needing This Doc Most

`Home` (10+ core dependencies — the heaviest consumer), `Auth`/`MPIN`/`KYC`/`Withdrawal` (full security
stack), `InstantSaving`/`SIP`/`Withdrawal` (market rates + encryption + payment lifecycle),
`Splash`/`Maintenance`/`Onboarding`/`Main` (app-control + session + content services).
