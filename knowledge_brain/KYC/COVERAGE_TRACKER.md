---
module: kyc
---

# KYC — Coverage Tracker

## Round 1 — 2026-08-19 — Build

**Mode:** Build (brain status was ⬜ → this round).

**Files read (10/10 module files, 100%):**
`kyc_flow.dart`, `kyc_screen.dart` (root, legacy), `controllers/kyc_controller.dart`,
`models/kyc_document.dart`, `models/kyc_step.dart`, `providers/kyc_provider.dart`,
`repositories/kyc_repository.dart`, `screens/kyc_screen.dart`, `screens/pan_verification_screen.dart`,
`widgets/aadhaar_digilocker_webview.dart`.

**Cross-cutting files read for grounding (not owned by this module, read to verify claims):**
`lib/routes/app_router.dart` (route table + registration), `lib/core/utils/kyc_validator.dart`,
`lib/core/error/failures.dart` (`KycRequiredFailure`/`ApiFailureMapper`),
`lib/core/security/api_interceptor.dart` (encryption double-pass verification),
`lib/core/security/encryption_service.dart` (`encryptJson`/`encrypt` implementation),
`lib/core/config/app_config.dart` (`sensitiveFields`/`encryptedEndpoints`),
`lib/features/instant_saving/instant_saving_screen.dart`,
`lib/features/instant_saving/services/saving_service.dart`,
`lib/features/instant_saving/models/saving_models.dart` (`EligibilityResponse`),
`lib/features/withdrawal/screens/withdrawal_screen.dart`,
`lib/features/withdrawal/services/withdrawal_service.dart`,
`lib/features/sip/screens/auto_savings_screen.dart`,
`lib/features/profile/profile_controller.dart`, `lib/features/profile/profile_screen.dart`
(`kycStatus` field/usage), `STARTGOLD_DOCUMENTATION.md` §3.13-3.14.

## Weighted Coverage

| Category | Weight | Assessment |
|---|---|---|
| Screens documented | 25% | 4/4 route-bound UI files (`screens/kyc_screen.dart`, `pan_verification_screen.dart`, `aadhaar_digilocker_webview.dart`, dead root `kyc_screen.dart`) — 100% |
| Controller/service public methods documented | 25% | ~12/12 public methods across `KycRepository`, `KycSubmitController`, `AadhaarNotifier`, `KycVerificationFlow` — 100% |
| Models documented | 15% | 6/6 classes/enums (`KycDocumentType`, `KycDocumentsResult`, `KycField`, `KycImagesRequirement`, `KycStep`, `KycStatus`) — 100% |
| API endpoints documented | 15% | 3/3 owned endpoints (`kyc/document-types`, `kyc/upload`, `kyc/update-profile-name`) + the shared `savings/check-eligibility` gate this module is downstream of — 100% |
| Business rules captured | 10% | 11 rules (RULE-KYC-001 through 011) + 2 explicitly flagged unconfirmed items — high confidence |
| Cross-module deps captured | 10% | `core/` deps (7 files), `shared/` deps (7 files), 3 downstream consumers (InstantSaving/Withdrawal/SIP) + 1 read-only consumer (Profile) all mapped with file:line — 100% |

**Weighted total: ~97%**

## Badge: 🟢 (mostly complete, 80-99%)

Not marked 🔵 (100%+verified) because two items remain genuinely unconfirmed against the live backend
contract rather than the client code (see `BUSINESS_RULES.md` "Unconfirmed" section):
1. The exact backend `id_document` value for PAN (client never hardcodes it, only detects by name/code
   substring "PAN").
2. Whether `submit-kyc`/`update-kyc` (present in `AppConfig.encryptedEndpoints` but unreferenced anywhere in
   `lib/`) are truly dead or called from outside this Flutter client.

Additionally, the RSA-OAEP double-encryption effect documented in `FORENSIC_TEMPLATE.md` §1 / `BUSINESS_RULES.md`
RULE-KYC-011 is a code-grounded inference (traced the exact call path and the interceptor's catch behavior)
but was not confirmed with a live debugger/network capture — flagged accordingly rather than stated as fact.

## Manual Spot-Check

Every one of the 10 module `.dart` files was read directly and in full during this round (not sampled) — the
usual "re-read 2-3 random files" spot-check is inherently satisfied. The one surprising finding worth calling
out as a spot-check result: `controllers/kyc_controller.dart` and `providers/kyc_provider.dart` have their
expected contents SWAPPED relative to their folder names — this was caught only by reading both files' first
15 lines side-by-side after an initial mis-attribution during drafting (see `MODULE_BRAIN.md` §2). Any future
session should re-verify this hasn't been "fixed" (renamed back to convention) before citing it.

## Drift Found vs. `STARTGOLD_DOCUMENTATION.md` §3.13-3.14

| Doc claim | Live code | Verdict |
|---|---|---|
| API: `POST users/kyc/upload` | Actual path is `kyc/upload` (no `users/` prefix) — `kyc_repository.dart:75,162` | Drift |
| API: `POST users/submit-kyc` | No such call exists anywhere in `lib/`; live flow uses `kyc/document-types` (fetch) + `kyc/upload` (submit) + `kyc/update-profile-name` | Drift |
| "Dynamic step rendering based on pending KYC items" | Confirmed true in spirit, but there's no explicit step-sequence array — the hub renders ALL documents from one `kyc/document-types` response in a single scrollable list, not a stepper | Partially accurate, imprecise |
| "Document upload capability" | No image/file upload exists in the live flow — text-field form only (see `MODULE_BRAIN.md` §5) | Drift |
| `/pan-verification` "Standalone PAN verification for investment eligibility" | Route exists and is registered, but the screen behind it is a non-functional stub with a fake 2-second delay and no API call | Drift (functionally dead, not "standalone verification") |
| PAN encryption via RSA | Confirmed accurate | No drift |
| RBI KYC / PMLA compliance framing | Confirmed accurate at the architectural level (gating via `savings/check-eligibility` + `KYC_REQUIRED`) | No drift |

Flagged for `_OVERVIEW/BUILD_SUMMARY.md` "Open Inaccuracies" per `AGENTS.md` §10.

## Flagged for `_SYSTEM` Synthesis (once `/build-system-brain` runs)

- **DANGER_ZONES candidate:** don't add a new sensitive KYC-adjacent endpoint to `AppConfig.encryptedEndpoints`
  while ALSO pre-encrypting in the calling repository (RULE-KYC-011 pattern) — pick one layer.
- **DANGER_ZONES candidate:** don't assume `providers/` always holds Riverpod providers or `controllers/`
  always holds controllers in this codebase — `kyc` inverts the convention; check actual file contents.
- **DIAGNOSTIC_PLAYBOOK candidates:** all 6 entries in `FORENSIC_TEMPLATE.md`, especially #2 (Aadhaar webview
  hangs with no fallback/timeout) and #4 (orphaned PAN stub screen) since both produce silent/misleading user
  experiences rather than visible errors.
