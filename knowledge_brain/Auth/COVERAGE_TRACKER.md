---
module: auth
last_updated: 2026-08-19
---

# Coverage Tracker — Auth Module

## Round 1 — 2026-08-19 (Build)

**Mode**: Build (brain status was ⬜ prior to this round)

**Files read in full** (8 module files + 15 core dependency files = 23 total):

Module (`lib/features/auth/`, 8/8):
- `controller/auth_controller.dart`
- `login/login_screen.dart`
- `otp/otp_screen.dart`
- `pin/pin_creation_screen.dart`
- `pin/pin_screen.dart`
- `registration/email_otp_sheet.dart`
- `registration/registration_screen.dart`
- `registration/registration_success_screen.dart`

Core dependencies (read for grounding, not this module's own files):
- `core/services/auth_service.dart` (AuthService + AuthNotifier + AuthState)
- `core/services/mpin_service.dart` (MpinService + MpinNotifier)
- `core/services/fcm_service.dart`
- `core/services/notification_service.dart`
- `core/services/device_id_service.dart`
- `core/services/shared_service.dart`
- `core/security/api_interceptor.dart`
- `core/security/encryption_service.dart`
- `core/security/secure_storage_service.dart`
- `core/security/screenshot_security_service.dart`
- `core/security/session_manager.dart`
- `core/utils/validators.dart`
- `core/utils/masking_utils.dart`
- `core/utils/navigation_utils.dart`
- `core/config/app_config.dart` (partial — key sections: encryptedEndpoints, sensitiveFields, storage keys)
- `routes/app_router.dart` (route table + argument-parsing lines for all 6 owned routes)

Also referenced (grep only, not fully read): `core/providers/app_control_provider.dart` (class/provider
existence confirmed), `lib/features/mpin/` and `lib/features/kyc/` (file listing only, for
CROSS_MODULE_MAP.md handoff verification).

## Weighted Coverage Calculation

| Category | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens | 25% | 6 routed screens + 1 bottom sheet = 7 | 7/7 documented (MODULE_BRAIN §3, METHOD_INDEX) | 25.0% |
| Controller/service public methods | 25% | `AuthController` (2) + `AuthNotifier` (8, inherited) + `AuthService` (7) + `MpinService` methods called from this module (2 of 5) = 19 relevant methods | 19/19 documented (METHOD_INDEX.md), incl. 3 `MpinService` methods NOT called from this module explicitly noted as such | 25.0% |
| Models | 15% | 1 state model (`AuthState`); **no dedicated request/response model classes exist** in this module (raw `Map<String,dynamic>` throughout) | `AuthState` shape fully documented (STATE_ANALYSIS.md); absence of typed models explicitly called out as a finding, not a gap in documentation | 15.0% |
| API endpoints | 15% | 10 endpoints touched: `generate-otp`, `verify-otp`, `generate-email-otp`, `verify-email-otp`, `register`, `register-check`, `mpin/create`, `mpin/validate`, `users/shared/country-codes`, `users/notifications/register-token` | 10/10 documented with encryption status (BUSINESS_RULES, DATA_FLOW) | 15.0% |
| Business rules | 10% | 15 rules captured (RULE-AUTH-001..015) | — | 10.0% |
| Cross-module deps | 10% | `core/services` (8 files), `core/security` (6 files), `core/network`, `core/utils` (3), `core/providers` (2), `core/localization`, `shared/widgets`, `main.dart`, plus handoffs to `mpin` and `home` modules; `kyc` handoff explicitly confirmed absent | Mermaid graph + table in CROSS_MODULE_MAP.md | 10.0% |

**Round 1 total: 100.0% (weighted)**

## Badge Determination

Per `build-module-brain.md` step 7: 🔵 requires ≥95% **and** a manual spot-check that the docs match a fresh
read of 2-3 randomly chosen files. The weighted score above is 100%, but the spot-check has not yet been
performed as a separate verification pass in this session (all files were read once, carefully, during
authoring — not re-verified against the written docs afterward).

**Badge assigned: 🟢 (80-99% equivalent — mostly complete, spot-check pending)**. Update `.agents/config.md`'s
Module Registry row for `auth` from ⬜ to 🟢 accordingly. Promote to 🔵 after a Round 2 spot-check confirms
2-3 randomly sampled claims (e.g. re-open `otp_screen.dart` and `app_config.dart` cold, verify the line
numbers cited in DATA_FLOW.md Flow 2 and BUSINESS_RULES RULE-AUTH-002 still match exactly).

## Known Gaps for Round 2

1. `PinScreen` (`/pin-entry`) usage is unconfirmed — needs an app-wide grep (outside `lib/features/auth/`) for
   any caller pushing `AppRouter.pinEntry`, to resolve whether it's dead code or a live alternate flow.
2. `authProvider` (`auth_service.dart:599-602`) usage outside this module is unconfirmed — same class of gap.
3. `mpin` module's own brain does not exist yet — the argument-contract assumptions in CROSS_MODULE_MAP.md
   (what `mpin_screen.dart` expects to receive) are inferred from the *sending* side (`otp_screen.dart`) only,
   not cross-checked against the *receiving* side's actual `ModalRoute` argument parsing.
4. Server-side OTP rate-limiting/lockout behavior is unconfirmed from client code alone (RULE-AUTH-010) —
   would need a backend API doc or test to confirm.
5. `validateOTP` (`core/utils/validators.dart:9-13`) is defined but never called anywhere in this module —
   confirm this is genuinely dead code (not called from OTP-adjacent screens elsewhere in the app either).

## Drift Found vs. `STARTGOLD_DOCUMENTATION.md` §3.3-3.7

| Doc claim | Code reality | Where |
|---|---|---|
| §3.3: `GET shared/country-codes` | Actual endpoint is `POST users/shared/country-codes` (`core/services/shared_service.dart:88-90`) — different HTTP method AND different path prefix (`users/` prefix missing from doc, and it's a POST not GET) | CROSS_MODULE_MAP.md, this file |
| §3.4: "Fintech Risk: OTP replay prevention via `otp_reference_id` tracking" (implies dedicated replay-guard logic) | `otp_reference_id` is tracked and refreshed correctly on resend (RULE-AUTH-009), but there is no additional replay-specific guard beyond "verify against the current reference id" — no attempt counter, no lockout (RULE-AUTH-010) | BUSINESS_RULES.md RULE-AUTH-009/010 |
| §3.5: Registration screen described as plain form fields (name/email/DOB/referral), no mention of mandatory email-OTP verification gate | Email verification via `EmailOtpSheet` is mandatory — Confirm button disabled until `_emailVerified == true` (`registration_screen.dart:122-123`) | BUSINESS_RULES.md RULE-AUTH-006 |
| §3.5: doesn't mention `register-check` as a separate pre-validation step | Registration is actually 2 server calls: `register-check` (validation, unencrypted) then `register` (account creation, `mobile` encrypted) inside `PinCreationScreen`, not `RegistrationScreen` | DATA_FLOW.md Flow 3 & 4 |
| §3.7: PIN Creation "Set up 4-digit MPIN" | `MpinNotifier.pinLength` = **6**, and `PinCreationScreen`'s UI dynamically reflects 6 (`'Create a ${MpinNotifier.pinLength}-digit PIN'`) — doc's "4-digit" is stale/wrong. (Confusingly, the *separate* `/pin-entry` screen in this same module DOES hardcode 4 digits — see RULE-AUTH-007) | BUSINESS_RULES.md RULE-AUTH-007 |
| §3.7: "Security: MPIN encrypted via RSA... Fire-and-forget FCM registration (non-blocking)" | Confirmed accurate for both claims | — (no drift) |
| §3.4: "Screenshot prevention (`ScreenProtector`)" listed as an OTP-screen feature | Confirmed accurate — but AGENTS.md §3's broader claim that screenshot protection is active on "auth... screens at minimum" is the actual over-broad claim, not this specific doc section | BUSINESS_RULES.md RULE-AUTH-012 |
| General: doc's Post-Verification Routing table (§3.4) lists 5 conditions matching the code's 5 branches | Confirmed accurate, including the `pop(true)` for UPI verification and the "existing user + no MPIN → setup mode" edge case | MODULE_BRAIN.md §5 (no drift — this table in the hand-written doc holds up well) |

## Flagged for `_SYSTEM` Synthesis

- **DANGER_ZONES candidate**: PIN-creation screen showing 4/6-digit PIN entry with no screenshot/recording
  block (RULE-AUTH-012) — a security-relevant screen category (PIN entry) that AGENTS.md §3 implies should be
  protected but isn't, in this module.
- **DIAGNOSTIC_PLAYBOOK candidates**: all 6 entries in `FORENSIC_TEMPLATE.md` are strong candidates,
  especially #2 (registration loop) and #3 (MPIN creation succeeds but login fails) since both hinge on
  cross-module state (backend `is_new_user` flag; the `/pin-entry` vs `/mpin` route split) that will recur as
  a support pattern.
- **MODULE_DEPENDENCIES candidate**: the `mpin` module handoff contract (route args:
  `type`/`temp_token`/`mobile`/`from_app_lock`) should be added once `mpin`'s own brain exists, so a future
  change to either side's argument shape gets caught.
