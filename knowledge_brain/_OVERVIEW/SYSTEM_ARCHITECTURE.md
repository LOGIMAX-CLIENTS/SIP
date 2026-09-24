---
last_updated: 2026-08-19
source: Round 0 (initial brain build) — derived from STARTGOLD_DOCUMENTATION.md, pubspec.yaml, lib/ folder scan, lib/routes/app_router.dart
---

# System Architecture — startGOLD Mobile (SIP)

## What this app is
Flutter (Android + iOS) fintech app for buying/saving/withdrawing digital gold and silver. Users buy
instantly or via recurring plans (daily savings, SIP), track holdings, complete KYC, and withdraw to
bank/UPI. See `about startGOLD.md` for the one-paragraph pitch and `STARTGOLD_DOCUMENTATION.md` for the
pre-existing (hand-written, may drift — cross-check) screen-by-screen doc.

## Stack

```
┌─────────────────────────────────────────────────────────┐
│  Flutter UI (Widgets) — Material, GoogleFonts, ScreenUtil │
├─────────────────────────────────────────────────────────┤
│  State: Riverpod (StateNotifier / AsyncNotifier / providers)│
├─────────────────────────────────────────────────────────┤
│  core/services  →  core/security  →  core/network (Dio)   │
│  (business logic)  (encryption,      (ApiClient +          │
│                      session,        interceptor chain)    │
│                      storage)                              │
├─────────────────────────────────────────────────────────┤
│  Backend REST API (bullion_v4.logimaxindia.com)            │
│  + Socket.IO live-rate feed (ratesocket/socket.io/)         │
├─────────────────────────────────────────────────────────┤
│  Payment SDKs: Cashfree · HyperSDK · Razorpay (native)      │
│  Push: Firebase Cloud Messaging                             │
└─────────────────────────────────────────────────────────┘
```

## lib/ Layout

```
lib/
├── core/            # shared layer — see knowledge_brain/Core/MODULE_BRAIN.md
│   ├── config/          AppConfig — URLs, keys
│   ├── constants/        static values
│   ├── error/            Failure models
│   ├── ldui/             (LD-prefixed UI parser — purpose TBD, verify in Core brain)
│   ├── localization/     multi-language (en, ta, te per STARTGOLD_DOCUMENTATION.md)
│   ├── models/           shared data models (e.g. AppControlModel)
│   ├── network/          ApiClient (Dio), interceptors, Socket.IO service
│   ├── providers/        global Riverpod providers (app-control, commodity, connectivity,
│   │                      countdown-offer, environment, home-dashboard, market, portfolio, timer, user)
│   ├── security/         encryption, session, secure storage, root detection, screenshot block,
│   │                      certificate pinning, app-lifecycle observer, clipboard security, secure logger
│   ├── services/         auth, biometric, content, device, device-id, environment, FCM, home,
│   │                      mpin, notification, portfolio, shared, app-control
│   └── utils/            validators, kyc-validator, masking, navigation, logger
├── features/        # 23 feature modules — see Module Registry in .agents/config.md
├── routes/           # AppRouter — ~65 named routes, single source of truth
└── shared/           # theme, reusable widgets, shared utils
```

## Feature Module Inventory (23)

`auth`, `mpin`, `kyc`, `home`, `instant_saving`, `daily_savings`, `sip`, `withdrawal`, `profile`,
`notifications`, `nominee`, `referral`, `settings`, `support`, `content`, `market`, `history`, `splash`,
`onboarding`, `maintenance`, `main`, `invoice`, `jewellery`.

`jewellery` and `invoice` are **not** covered by `STARTGOLD_DOCUMENTATION.md` (added after it was written,
2026-05-20) — treat their module brains as first documentation, not a refresh.

## Security Architecture (verified against `STARTGOLD_DOCUMENTATION.md` §2 — re-verify per-module during
brain build)

- Field-level RSA-OAEP-SHA256 encryption for sensitive request fields, key fetched from `crypto/public-key`.
- Session: JWT-style token, silent refresh on 401, force-logout dialog on 409.
- App-lock: MPIN/biometric on every resume (`AppLifecycleObserver`), suppressed during native payment SDK
  focus.
- Runtime protection: root/jailbreak detection at startup, `FLAG_SECURE` screenshot/recording block on
  sensitive screens, back-navigation guards (`PopScope`) on auth/payment screens.
- Compliance surface: OWASP MASVS L1/L2, PCI DSS (delegated payment flow), RBI KYC / PMLA, GDPR/IT Act
  (account deletion).

## WebSocket / Live Rates

- Endpoint: `ws://bullion_v4.logimaxindia.com/ratesocket/socket.io/`, Socket.IO protocol.
- `market_rates` event; pipe-delimited payload (`3|goldBuy|goldSell|silverBuy|silverSell|...`); message
  type `5` carries market open/close status.
- Disconnects on app background, reconnects on resume, exponential-backoff retry.
- Consumed via `core/providers/market_provider.dart` and `core/network/native_socket_service.dart`.

## Payment

Three SDKs integrated (`pubspec.yaml`): `flutter_cashfree_pg_sdk`, `hypersdkflutter`, `razorpay_flutter`.
Card/UPI/bank credential entry is fully delegated to the native SDK — the app never renders its own
card-entry UI (PCI DSS delegated flow). Which gateway a given flow actually invokes is module-specific —
verify per module rather than assuming Cashfree.

## Known Gaps at Round 0 (to resolve during module brain builds)

- `core/ldui/ldui_parser.dart` — purpose not yet verified against `STARTGOLD_DOCUMENTATION.md` (which
  predates it or doesn't mention it); confirm in `Core` module brain.
- Financial value representation (raw `double` vs. a decimal type) for money/weight fields — not yet
  confirmed; see `AGENTS.md` §2's TODO marker.
- No branch-topology / release-channel convention documented yet (unlike the sibling `fintect_application`
  repo's phase1/phase2 split).
