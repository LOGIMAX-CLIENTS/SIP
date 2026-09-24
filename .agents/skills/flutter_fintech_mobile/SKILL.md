---
name: flutter_fintech_mobile
description: Domain-knowledge activation for any bug-fix or feature task in the startGOLD mobile app — Flutter architecture layering, fintech security/compliance checklist, payment-gateway abstraction, and financial-precision rules. Read this in full for any task touching security, payments, KYC, or money/weight arithmetic.
trigger: on_demand
---

# Skill: Flutter Fintech Mobile (startGOLD)

## 1. Layered Architecture — Enforcement Rules

```
Screen (Widget)
   │  reads/watches, never mutates directly
   ▼
Controller / StateNotifier / AsyncNotifier (Riverpod)
   │  orchestrates, holds UI state, calls services
   ▼
Service (feature/services/*.dart or core/services/*.dart)
   │  business logic, request/response shaping, encryption field selection
   ▼
ApiClient (core/network/api_client.dart, Dio)
   │  the ONLY place that issues HTTP requests
   ▼
Backend REST API / WebSocket
```

**Must-not edges** (flag as an anti-pattern if found, don't silently normalize by copying the pattern
elsewhere):
- Screen → ApiClient directly (skips Controller and Service — no error mapping, no loading state).
- Service → Widget (a service must never import `flutter/material.dart` or build UI).
- Feature A → Feature B's `controller/`, `services/`, or `models/` internals directly. Shared logic belongs
  in `lib/core/` (cross-cutting) or `lib/shared/` (pure UI reuse). Record any existing violation in that
  module's `CROSS_MODULE_MAP.md` under a "Known Violations" section rather than treating it as precedent.

## 2. OWASP MASVS Checklist (apply to any security-adjacent change)

| Control | Where enforced today | Check before changing |
|---|---|---|
| Secure storage (L1) | `core/security/secure_storage_service.dart` | New sensitive value → this service, not `shared_preferences` |
| Certificate pinning (L1) | `core/security/certificate_pinning.dart` | Don't disable pinning for "easier debugging" in committed code |
| Input validation (L1) | `core/utils/validators.dart`, `core/utils/kyc_validator.dart` | New form field → add/reuse a validator, don't inline regex in the widget |
| Root/tamper detection (L2) | `core/security/root_detection_service.dart` | Runs at startup — don't gate it behind a feature flag that can be silently disabled |
| Anti-screenshot/recording (L2) | `core/security/screenshot_security_service.dart` | New screen showing OTP/PAN/Aadhaar/bank details/payment → verify it's covered |
| Field-level encryption | `core/security/encryption_service.dart` (RSA-OAEP-SHA256) | New sensitive request field → route through the interceptor's encryption selection, not manual base64/plaintext |
| Session integrity | `core/security/session_manager.dart` | 401 → silent refresh; 409 → force logout. Never catch-and-ignore a 409. |
| Clipboard hygiene | `core/security/clipboard_security_service.dart` | Sensitive values (OTP, MPIN, account numbers) shouldn't be copyable by default |

## 3. Payment Gateway Abstraction

Three SDKs are integrated: **Cashfree** (`flutter_cashfree_pg_sdk`), **HyperSDK** (`hypersdkflutter`),
**Razorpay** (`razorpay_flutter`). Treat gateway selection as a runtime/config decision, not a hardcoded
choice — before modifying a payment flow, confirm which gateway(s) the specific screen actually invokes
(check `instant_saving`, `sip`, and `withdrawal` module brains once built) rather than assuming Cashfree
because it's listed first in `pubspec.yaml`.

Card/UPI/bank credential entry is **always** delegated to the native SDK UI — the Flutter app never renders
its own card-number/CVV/UPI-PIN input. `AppLifecycleObserver.suppressAppLock` is set while a payment SDK has
foreground focus so switching to a UPI app to authorize doesn't trigger the app-lock overlay on return —
this is intentional.

## 4. Financial Precision Rules

- Never use raw `double` equality (`==`) to compare money/weight values — use an epsilon comparison or a
  proper decimal type, whichever the codebase already standardizes on (verify in
  `core/utils/validators.dart` and confirm in each module's `STATE_ANALYSIS.md`).
- Amount and weight are almost always encrypted request fields (see §2) — because they're both financially
  sensitive and because a manipulated amount is a direct fraud vector. Never add a money/weight field to a
  payload without checking it goes through encryption.
- Rate values (buy/sell, gold/silver) are locked client-side for a configured window after fetch to prevent
  submitting a stale price — implemented via `core/providers/timer_provider.dart` plus a per-screen timer.
  When a rate-lock timer expires mid-flow, the correct behavior is to re-fetch and re-lock, not to silently
  submit the stale rate.
- GST/tax rate, min/max purchase amounts, and denomination chip values are server-driven config
  (`savings/config`, `savings/denominations/*` endpoints) — never hardcode these as constants in a new
  screen; fetch from the existing config provider/service.

## 5. Compliance Surface (from `STARTGOLD_DOCUMENTATION.md` §5, verify against code when touched)

| Standard | What it constrains |
|---|---|
| RBI KYC / PMLA | KYC (PAN + Aadhaar + bank verification) must gate any purchase/withdrawal eligibility check — don't add a purchase path that bypasses `savings/check-eligibility`. |
| PCI DSS | Card data never touches app code or app logs — see §3. |
| GDPR / IT Act | Account deletion flow (`profile/screens/delete_account_screen.dart`) must actually remove/anonymize data server-side, not just sign the user out client-side. |
| OWASP MASVS L1/L2 | See §2 table. |

## 6. Bug-Investigation Starting Points

Before writing a fix, check `{BRAIN_DIR}\_SYSTEM\DIAGNOSTIC_PLAYBOOK.md` for a matching symptom pattern and
`{BRAIN_DIR}\_SYSTEM\DANGER_ZONES.md` for a matching hard-stop anti-pattern — both are populated by
`/build-system-brain` from the per-module brains and are meant to be the fastest path to a root cause,
faster than re-deriving architecture from scratch.
