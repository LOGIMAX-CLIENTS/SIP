---
module: kyc
brain_status: 🟢 (Round 1, ~95%)
last_updated: 2026-08-19
files_read: 10/10 lib/features/kyc/**/*.dart + core/utils/kyc_validator.dart + cross-module callers
---

# KYC Module Brain

## 1. Purpose

PAN + Aadhaar identity verification, required by RBI KYC / PMLA before a customer can purchase, run a SIP,
or withdraw. KYC is **complete only when both PAN and Aadhaar are APPROVED** — see
`lib/features/kyc/screens/kyc_screen.dart:18-32` (module doc comment) and `RULE-KYC-001` in
`BUSINESS_RULES.md`. There is no separate "bank KYC" step in this module — bank account linking/verification
lives in the `profile` module (`profile/screens/bank_verification_hub_screen.dart`, route
`/bank-verification-hub`), not here (see `CROSS_MODULE_MAP.md`).

## 2. Folder Inventory (10 files)

```
lib/features/kyc/
├── kyc_flow.dart                       — KycVerificationFlow.start() — the ONE entry point every other
│                                          module uses to launch KYC. LIVE, heavily used.
├── kyc_screen.dart                     — ⚠️ LEGACY/DEAD. Hardcoded 3-step (PAN/Aadhaar/Bank) screen using
│                                          kycStepsProvider. NOT registered in app_router.dart. Do not extend.
├── controllers/kyc_controller.dart     — ⚠️ MISNAMED: holds the LIVE Riverpod *providers*
│                                          (kycDocumentsProvider, kycSubmitProvider, aadhaarProvider,
│                                          AadhaarNotifier). This is the file screens/kyc_screen.dart imports.
├── providers/kyc_provider.dart         — ⚠️ MISNAMED: holds the LEGACY *controller* (KycNotifier,
│                                          StateNotifier) backing the dead kyc_screen.dart above.
├── models/kyc_document.dart            — KycDocumentType, KycField, KycImagesRequirement, KycDocumentsResult.
│                                          LIVE model, backs the dynamic PAN form.
├── models/kyc_step.dart                — KycStep/KycStatus. LEGACY, only consumed by the dead kyc_screen.dart.
├── repositories/kyc_repository.dart    — KycRepository: the only class in this module that calls ApiClient.
├── screens/kyc_screen.dart             — LIVE unified KYC hub (PAN form + Aadhaar DigiLocker card).
│                                          Routed at BOTH `/kyc` and `/kyc-dynamic`.
├── screens/pan_verification_screen.dart— ⚠️ ORPHANED STUB. Routed at `/pan-verification` but has NO
│                                          repository call — `_handleVerify()` just does
│                                          `Future.delayed(seconds: 2)` then shows a fake success dialog.
│                                          No encryption, no real verification. Nothing in the app currently
│                                          navigates to this route (grep found zero `Navigator...panVerification`
│                                          call sites) — it is reachable only by manually typing the route.
├── widgets/aadhaar_digilocker_webview.dart — AadhaarDigilockerWebView, hosts the Cashfree DigiLocker consent
│                                           page. Routed at `/aadhaar-verification`.
└── widgets/digilocker_sdk_screen.dart  — NEW (2026-08-24). DigilockerSdkScreen, the SurePass counterpart:
                                           hosts the native `digilocker_flutter_sdk` package (v1.0.6) instead
                                           of a webview. Routed at `/digilocker-sdk`. Calls
                                           `DigilockerSdk.start(context, apiToken: sdkToken, environment:...,
                                           onComplete:, onError:)` — the real package API, read directly from
                                           the resolved pub cache source (SurePass's own docs never specified
                                           the Flutter SDK's Dart surface). The package internally pushes its
                                           OWN screens on top of this one and pops them; onComplete/onError
                                           then pop this screen with true/false, matching the webview screen's
                                           contract.
```

**Architectural note (file-naming inversion):** `controllers/kyc_controller.dart` contains Riverpod
*providers* and `providers/kyc_provider.dart` contains a Riverpod *StateNotifier controller* — the two
folders' contents are swapped relative to every other module's convention. Confirmed by direct read of both
files' first lines. Flag this before assuming "providers/" always holds providers in this codebase.

**Dead-code note:** `kyc_screen.dart` (root), `providers/kyc_provider.dart`, and `models/kyc_step.dart` form
a self-contained legacy flow (hardcoded pending PAN/Aadhaar/Bank steps, no API calls) that is never reached
from `app_router.dart` — both `AppRouter.kyc` ('/kyc') and `AppRouter.dynamicKyc` ('/kyc-dynamic') resolve to
`screens/kyc_screen.dart` (imported as `dynamic_kyc.KycScreen`), never the root file. See
`lib/routes/app_router.dart:144-152,240-248`. Treat the root file as reference-only / candidate for deletion,
not as the current behavior.

## 3. Routes (from `lib/routes/app_router.dart`)

| Route constant | Path | Screen | Live? |
|---|---|---|---|
| `AppRouter.kyc` | `/kyc` | `screens/kyc_screen.dart` (`KycScreen(requestFrom, extraData)`) | Yes — primary |
| `AppRouter.dynamicKyc` | `/kyc-dynamic` | same `screens/kyc_screen.dart` (duplicate alias) | Yes |
| `AppRouter.panVerification` | `/pan-verification` | `screens/pan_verification_screen.dart` | Reachable but non-functional stub |
| `AppRouter.aadhaarVerification` | `/aadhaar-verification` | `widgets/aadhaar_digilocker_webview.dart` | Yes — sub-step of `/kyc` (Cashfree webview) |
| `AppRouter.digilockerSdk` *(new 2026-08-24)* | `/digilocker-sdk` | `widgets/digilocker_sdk_screen.dart` | Yes — sub-step of `/kyc` (SurePass native SDK) |
| `AppRouter.bankVerification` | `/bank-verification` | inline `Scaffold(Text('Bank Verification'))` placeholder | Dead stub, not this module's concern |

`app_router.dart:144-152` and `:240-248` both build `dynamic_kyc.KycScreen(requestFrom: args['request_from']
?? 'instant', extraData: args)` — `requestFrom` values seen in callers: `'instant'`, `'withdraw'`, `'sip'`.

## 4. Live Data Flow (see `DATA_FLOW.md` for full detail)

1. Any module hits a backend eligibility/creation gate and gets `next_step == 'KYC_REQUIRED'` (inline in a
   200 response) or an HTTP error with `error.code == 'KYC_REQUIRED'` (mapped to `KycRequiredFailure` in
   `core/error/failures.dart:47-50`).
2. Caller invokes `KycVerificationFlow.start(context, ref, requestFrom: ...)` (`kyc_flow.dart:20-47`), which
   pushes `AppRouter.kyc` and awaits a `bool` result.
3. `screens/kyc_screen.dart` loads `kycDocumentsProvider(requestFrom)` → `KycRepository.getDocumentTypes()` →
   `POST kyc/document-types` (`kyc_repository.dart:12-34`) → renders one card per returned document (today:
   PAN only) plus a separate, client-side-only Aadhaar card.
4. PAN: user fills fields → `KycSubmitController.submit()` → `KycRepository.uploadKyc()` → `POST kyc/upload`
   with `id_document` = the server-supplied doc id.
5. Aadhaar: user enters number + name → `AadhaarNotifier.initiate()` → `KycRepository.initiateAadhaar()` →
   `POST kyc/upload` with `id_document: '2'` (hardcoded) → returns a `consent_url` → pushes
   `AadhaarDigilockerWebView` → user completes DigiLocker consent in-webview → webview intercepts the
   `/kyc/digilocker-callback` redirect and pops `true` → `AadhaarNotifier.pollUntilTerminal()` polls the same
   `kyc/upload` endpoint with `verification_id` until `APPROVED`/`EXPIRED`/`REJECTED`.
6. Once both are APPROVED, the hub re-fetches document-types, shows a success animation, then a **mandatory,
   non-dismissible** "choose your profile name" dialog (`_showProfileNameSelectionDialog`,
   `screens/kyc_screen.dart:392-453`), then pops `true`.
7. **PAN–Aadhaar link status (added 2026-09-03)**: every terminal Aadhaar poll response (`already approved`
   and `APPROVED`, both branches of `pollUntilTerminal()`, plus `initiate()`'s already-approved short-circuit)
   carries a sibling `aadhaar_pan_linked` field (nullable bool — see backend `KYCService._check_aadhaar_kyc`,
   sourced from the SAME PAN-comprehensive/export-data call PAN verification already makes, not a separate
   provider call or stage). Parsed into `AadhaarState.aadhaarPanLinked` (`controllers/kyc_controller.dart`)
   and rendered as a "Linked to your Aadhaar" / "Not linked to your Aadhaar" chip on the PAN card's
   `_buildVerifiedBanner` (`screens/kyc_screen.dart`, `linkedToAadhaar` param) — only when non-null.
   **Live-session only**: `kyc/document-types` does not return or persist this field, so it reads unset again
   after an app restart or leaving/reopening the screen — same limitation `verifiedDob`/`verifiedName` already
   had before this change, not a new one. Closing this gap durably (i.e. showing it after a fresh app launch)
   needs a backend change to persist `aadhaar_linked` somewhere `document-types` reads from — out of scope
   for this pass.
7. The original caller (SIP/Withdrawal/InstantSaving) resumes/retries the action it was blocked on.

## 5. Document Upload — NOT implemented as image upload

`KycImagesRequirement` (`models/kyc_document.dart:86-101`, `front`/`back` booleans) is parsed from the
`kyc/document-types` response but **no screen in this module ever reads `doc.images`** or uses
`image_picker`/`image_cropper` — grep for both packages inside `lib/features/kyc/` returns zero matches. The
entire live flow is **text-field form submission only** (PAN number, name; Aadhaar number, name) — there is
no photo/scan capture path today despite the model being shaped for one. Mark any assumption of an image
upload step as wrong until this changes.

## 6. Encryption

- `AppConfig.sensitiveFields` (`core/config/app_config.dart:74-95`) includes `pan_number`, `pan`,
  `aadhaar_number`, `bank_account_number`, `account_no`, `ifsc_code`, `upi_id` — matches AGENTS.md's claim.
- `kyc/upload` is listed in `AppConfig.encryptedEndpoints` (`app_config.dart:57`).
- **Notable quirk (confirmed from source, effect inferred — see `FORENSIC_TEMPLATE.md`):**
  `KycRepository.uploadKyc()`/`_uploadAadhaar()` call `EncryptionService.encryptJson(fields)` themselves
  (`kyc_repository.dart:51,160`) before posting. Because `kyc/upload` is also in `encryptedEndpoints`,
  `ApiSecurityInterceptor.onRequest` (`core/security/api_interceptor.dart:166-182`) runs
  `EncryptionService.encryptJson()` a **second time** on the whole `postData`, recursing into the
  already-encrypted `fields` map. Net effect is very likely a harmless caught exception (see
  `FORENSIC_TEMPLATE.md` §1) rather than payload corruption, because a failed re-encrypt throws before the
  `options.data = ...` assignment completes, leaving the correctly-once-encrypted payload in place — but this
  is inferred from RSA-OAEP's plaintext-size ceiling being smaller than its own ciphertext, not runtime-verified.
- `core/utils/kyc_validator.dart` (`KycValidator.validatePAN/validateAadhaar`) is **dead code** — zero
  importers anywhere in `lib/`. The live screen duplicates PAN/Aadhaar regex validation inline instead
  (`screens/kyc_screen.dart:79-89,954-969`).

## 7. Cross-Module Eligibility Gating (critical — read `CROSS_MODULE_MAP.md` for the full graph)

`kycStatus` (int, 0 or 1) lives on the User model in `profile` (`profile_controller.dart:21`, sourced from
`kyc_status` in the profile API response). Three other modules gate on KYC:

- **InstantSaving** (`instant_saving_screen.dart:1591-1610`): calls `savings/check-eligibility`; if
  `EligibilityResponse.nextStep == 'KYC_REQUIRED'`, awaits `KycVerificationFlow.start(requestFrom: 'instant')`.
- **Withdrawal** (`withdrawal_screen.dart:1119-1130`): same pattern via `withdrawal_service.dart`'s
  `checkEligibility()`, also hitting `savings/check-eligibility`, `requestFrom: 'withdraw'`.
- **SIP** (`sip/screens/auto_savings_screen.dart`): has BOTH a proactive client-side gate
  (`user.kycStatus == 1` check before even reaching bank/payment steps, lines 1393-1400) AND a backend
  backstop (`response.errorCode == 'KYC_REQUIRED'` / `on KycRequiredFailure catch` around SIP-create calls,
  lines 2081-2116, 2254-2301), `requestFrom: 'sip'`.

`savings/check-eligibility` is a **shared endpoint** — both `instant_saving/services/saving_service.dart:16`
and `withdrawal/services/withdrawal_service.dart:59` call the identical path.

## 8. Top Risks / Anti-Patterns Found

1. Two parallel KYC UIs exist in the same folder; the dead one (`kyc_screen.dart` root +
   `providers/kyc_provider.dart` + `models/kyc_step.dart`) could mislead a future edit if someone assumes it's
   live. Confirm against `app_router.dart` before touching any KYC screen file.
2. `/pan-verification` is a reachable route to a non-functional stub (fake delay, no API, no encryption). If a
   deep link or old client build ever targets it, the user sees a fake "Verification Sent" success with no
   backend record.
3. Double-pass encryption on `kyc/upload` (see §6) — works today but is fragile; don't copy this
   "encrypt-in-repository-AND-let-the-interceptor-encrypt-again" pattern into a new module.
4. `KycValidator` in `core/utils/` is dead code — don't assume it's the source of truth for PAN/Aadhaar regex;
   the actual regex lives inline in `screens/kyc_screen.dart`.
5. `KycImagesRequirement` is modeled but unused — if a future backend change starts requiring image upload,
   the UI has no code path for it yet.

## 9. See Also

`METHOD_INDEX.md` · `DATA_FLOW.md` · `BUSINESS_RULES.md` · `CROSS_MODULE_MAP.md` · `STATE_ANALYSIS.md` ·
`FORENSIC_TEMPLATE.md` · `COVERAGE_TRACKER.md`
