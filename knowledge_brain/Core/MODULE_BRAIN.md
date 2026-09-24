---
module: core/ (shared layer, not a feature)
brain_folder: Core
last_updated: 2026-08-19
round: 1
files_read: 47 / 47 (100%)
---

# Core — Module Brain

`lib/core/` is the shared foundation every one of the 23 feature modules sits on top of: the single Dio
client, the encryption/session/security stack, global Riverpod providers, and cross-feature business
services. Nothing here renders a screen. See `.agents/config.md` and `.agents/AGENTS.md` §1 for the layering
rule this module anchors: `Screen → Controller/StateNotifier → Service (core or feature) → ApiClient (core)`.

## Subfolder Map (11 folders, 47 files)

| Folder | Files | Purpose |
|---|---|---|
| `config/` | 1 | `AppConfig` — base URL, storage-key names, timeouts, cert pins, the two encryption gate lists (`encryptedEndpoints`, `sensitiveFields`). |
| `constants/` | 1 | `AppConstants` — static UI copy strings (screen titles/subtitles) and withdrawal numeric limits. |
| `error/` | 1 | `failures.dart` — `Failure` hierarchy + `ApiFailureMapper.map(DioException)`, the single place HTTP status codes become typed app errors. |
| `ldui/` | 1 | `LduiParser` — a JSON→Widget tree renderer. **Confirmed dead code** — see below. |
| `localization/` | 3 | `LanguageProvider`/`LanguageCache`/`LanguageService` — i18n scaffold. Only `en` is actually populated; remote-translation fetch is commented out. |
| `models/` | 1 | `AppControlModel` (`app_control_model.dart`) — version/alert/maintenance response shape for `POST app/control`. |
| `network/` | 3 | `ApiClient` (the one Dio instance), `interceptors.dart` (**unused** `AuthInterceptor**), `NativeSocketService` (raw WebSocket, not Socket.IO — see Known Gaps). |
| `providers/` | 10 | Global Riverpod state: app-control, commodity selection, connectivity, countdown-offer, environment, home-dashboard, market rates, portfolio, rate-lock timers, user profile. |
| `security/` | 10 | Encryption, session, secure storage, root/jailbreak detection, screenshot block, cert pinning, app-lifecycle/app-lock, clipboard clearing, scrubbing logger. |
| `services/` | 13 | Business services: auth, biometric, content (CMS), device-id, device (dup, unused), environment, FCM, home, mpin, notification, portfolio, shared (country/commodity/denomination lookups), app-control. |
| `utils/` | 5 | `Validators`, `KycValidator`, `MaskingUtils`, `NavigationUtils` (safe-pop fallback), `AppLogger` (**unused**). |

## End-to-End Architecture

```
Screen/Controller (feature)
        │
        ▼
core/services/*.dart  ──uses──►  core/network/api_client.dart (ApiClient, Dio singleton)
        │                                │
        │                        _dio.interceptors = [ApiSecurityInterceptor]
        │                                │  (QueuedInterceptor — see security/api_interceptor.dart)
        │                                ▼
        │                    onRequest:  force-logout gate → offline check → RSA key
        │                                bootstrap → Bearer token attach → field encryption
        │                                (RSA-OAEP-SHA256) for AppConfig.encryptedEndpoints
        │                                ▼
        │                          Dio → HTTPS (cert-pinned via CertificatePinning.setup)
        │                                ▼
        │                    onResponse: field decryption (no-op passthrough today —
        │                                see BUSINESS_RULES RULE-CORE-004)
        │                    onError:    409 → SessionManager.forceLogout() + dialog
        │                                401 → silent refresh (Completer-locked) → retry
        ▼
error/failures.dart ApiFailureMapper.map() → typed Failure → widget-safe message
```

Full request lifecycle with file:line references is in `DATA_FLOW.md`.

## Security Stack (verified against AGENTS.md §3)

- **Encryption**: `security/encryption_service.dart` — RSA-OAEP-SHA256, public key fetched once from
  `crypto/public-key` (`AppConfig.publicKeyEndpoint`) and cached in secure storage
  (`SecureStorageService.saveServerPublicKey`/`getServerPublicKey`). No hardcoded key. **Decryption is a
  no-op** (`EncryptionService.decrypt`, line 101) — the interceptor's "AES-256 decrypted" log message at
  `security/api_interceptor.dart:200` is misleading; nothing is actually decrypted client-side today (see
  RULE-CORE-004).
- **Which fields get encrypted**: two independent gates in `config/app_config.dart` — a request is only
  touched at all if its path matches `AppConfig.encryptedEndpoints` (line 47), and within that request only
  keys present in `AppConfig.sensitiveFields` (line 74) are individually RSA-encrypted (recursing into nested
  maps/lists via `EncryptionService.encryptJson`).
- **Session**: `security/session_manager.dart` (static flags) + `security/secure_storage_service.dart`
  (`flutter_secure_storage`, `encryptedSharedPreferences` on Android, `first_unlock` Keychain on iOS). 401 →
  silent refresh with a `Completer`-based concurrency lock so N simultaneous 401s trigger exactly one refresh
  call; 409 → `SessionManager.forceLogout()` (deduplicated) + `SessionInvalidatedDialog`. Full contract in
  BUSINESS_RULES RULE-CORE-002/003.
- **App-lock**: `security/app_lifecycle_observer.dart` — pre-caches auth/MPIN/biometric flags on `paused` so
  the `resumed` check is fully synchronous (zero-await lock screen). `suppressAppLock` static flag is the
  documented escape hatch for payment SDK flows.
- **Runtime protection**: `security/root_detection_service.dart` (7-layer Android/iOS check, called once at
  `main.dart:37` before `runApp`; on positive detection the entire app is replaced with
  `CompromisedDeviceScreen` — no bypass path) and `security/screenshot_security_service.dart` (`FLAG_SECURE`
  + iOS blur, gated by `AppConfig.enableScreenshotProtection`, toggled dynamically by
  `AppControlNotifier._fetch()` from the `app/control` response — see `providers/app_control_provider.dart:130`).
- **Cert pinning**: `security/certificate_pinning.dart` supports both cert-fingerprint and SPKI-hash pin
  formats simultaneously, hand-parses ASN.1 to avoid extra dependencies, and accepts server-pushed pin
  updates via `app/control`'s `certificate_pins` field — cert renewals don't require a republish.
- **Clipboard**: `security/clipboard_security_service.dart` clears the clipboard via native
  `MethodChannel('com.startgold.app/security')` on Android (to avoid the Android 13+ "Copied" toast) and via
  `Clipboard.setData('')` elsewhere; called on cold start (`main.dart:56`) and every resume
  (`app_lifecycle_observer.dart:67`).

## Top Risks / Known Gaps

1. **`core/ldui/ldui_parser.dart` is dead code.** Its doc comment claims it's "Used by the countdown-offer
   'Know More' bottom sheet," but `LduiParser` has zero call sites anywhere in `lib/` (confirmed by grep) and
   `features/home/widgets/countdown_offer_widget.dart` renders `CountdownOfferNew`/`CountdownOfferExisting`
   directly, not a server-driven JSON tree. Resolves the Round-0 gap flagged in
   `_OVERVIEW/SYSTEM_ARCHITECTURE.md` — the parser is a real, fully-implemented, but currently unwired
   feature (likely built ahead of a backend contract that hasn't shipped, or left over from a removed one).
2. **`core/network/interceptors.dart` (`AuthInterceptor`) is dead code.** `ApiClient._internal()`
   (`network/api_client.dart:27`) only registers `ApiSecurityInterceptor`; `AuthInterceptor` is never
   constructed or added to any Dio instance. Its 401 handler (unconditional `SessionManager.logout()`, no
   refresh attempt) would in fact be *wrong* if it ever did run — it would defeat the silent-refresh flow in
   `ApiSecurityInterceptor`. Safe to delete, but don't accidentally wire it back in.
3. **`core/utils/logger.dart` (`AppLogger`) is dead code** — its only caller is the also-unused
   `AuthInterceptor`. Live logging goes through `security/secure_logger.dart` (`SecureLogger`), which scrubs
   `AppConfig.sensitiveFields` before printing.
4. **WebSocket transport claim in `_OVERVIEW/SYSTEM_ARCHITECTURE.md` is stale/wrong.** It states Socket.IO at
   `ws://bullion_v4.logimaxindia.com/ratesocket/socket.io/`. The actual implementation
   (`network/native_socket_service.dart`) uses the plain `web_socket_channel` package (raw WebSocket, not the
   Socket.IO protocol) against `EnvironmentService.wsUrl` — staging
   `wss://startgoldapp.logimaxindia.com/ws/`, production `wss://sgbackoffice.startgold.com/ws/`
   (`services/environment_service.dart:12-16`). Flagged in `_OVERVIEW/BUILD_SUMMARY.md`.
5. **`core/providers/*` reach into `features/*/models/`.** `user_provider.dart` watches
   `authControllerProvider` (defined in `features/auth/controller/auth_controller.dart`), and
   `market_provider.dart`, `home_dashboard_provider.dart`, `countdown_offer_provider.dart`,
   `native_socket_service.dart`, `home_service.dart` all import model classes from `features/home/models/`
   and `features/market/models/`. This inverts the layering rule in AGENTS.md §1 ("never import one
   feature's internals directly from another feature" — core doing it is the same violation one level up).
   Functionally stable today, but a `core/` refactor can now silently break `features/auth` and
   `features/home`/`features/market`. Full list in `CROSS_MODULE_MAP.md`.
6. **`core/services/device_service.dart` (`DeviceService`) is unused** — a simpler, non-persisting duplicate
   of `DeviceIdService`. Zero call sites found. Candidate for deletion.
7. **Client-side RSA decryption does not exist.** `EncryptionService.decrypt()` is a pass-through no-op
   (comment: "Server responses are not encrypted in the current architecture"). The interceptor still runs
   `decryptJson` on every response from an `encryptedEndpoints` path and logs "Response decrypted (AES-256)"
   — the label is inaccurate; response bodies are never actually AES- or RSA-decrypted on this client. If the
   backend ever starts truly encrypting response fields, this will silently return ciphertext to the UI.
8. **Two parallel auth-state stacks.** `core/services/auth_service.dart` defines `authProvider`
   (`AuthNotifier`/`AuthState`) but the app-wide `userProvider` (`core/providers/user_provider.dart:29`)
   watches `authControllerProvider` from `features/auth/controller/auth_controller.dart` (`AuthController
   extends AuthNotifier`, adds `setPin`/`verifyPin`). `authProvider` itself appears to have no consumers
   found by grep in this pass — verify before assuming it's load-bearing anywhere.

## Where To Look Next

- `DATA_FLOW.md` — 5 traced flows (encrypted API call, 401 refresh, 409 force-logout, app-resume lock,
  live-rate socket lifecycle) with file:line citations.
- `BUSINESS_RULES.md` — RULE-CORE-001…NNN, the codified contracts (which fields encrypt, 401 vs 409, root
  detection, rate-lock).
- `STATE_ANALYSIS.md` — every provider's state shape + every secure-storage key.
- `CROSS_MODULE_MAP.md` — per-feature consumption of `core/`, Mermaid graph, the layering violations above.
