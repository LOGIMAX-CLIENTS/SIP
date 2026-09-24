---
module: kyc
---

# KYC — Method Index

Alphabetical by class. `file:line` → what it does → who calls it. ⚠️ marks legacy/dead code.

## AadhaarNotifier (`controllers/kyc_controller.dart`) — StateNotifier<AadhaarState>

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `initiate({requestFrom, aadhaarNumber, fullName, allowReverify})` | 157-~210 | Step 1: request DigiLocker consent session via `KycRepository.initiateAadhaar`. Short-circuits to `approved` if backend reports already-approved. Branches on the response shape: `consent_url` present → `AadhaarPhase.awaitingConsent` (Cashfree webview); `sdk_token` present → `AadhaarPhase.awaitingSdk` (SurePass native SDK, new 2026-08-24) — the two are mutually exclusive per active gateway, never both. | `screens/kyc_screen.dart:_onVerifyAadhaar()` (217) |
| `pollUntilTerminal(requestFrom, {maxAttempts=10, delay=2s})` | 201-273 | Step 2: polls `KycRepository.pollAadhaar` up to 10x/2s apart until APPROVED/EXPIRED/REJECTED; on repeated PENDING, reverts to `awaitingConsent` with a "taking longer" message (not a failure). | `screens/kyc_screen.dart:_onVerifyAadhaar()` (238) |
| `reset()` | 277 | Resets to `AadhaarState()` idle. | `screens/kyc_screen.dart:_editAadhaar()` (151) |
| `seedApproved({maskedNumber, name})` | 284-292 | Seeds card as approved from server status without a DigiLocker round trip; no-op unless phase is `idle`. | `screens/kyc_screen.dart:_seedAadhaarIfApproved()` (133) |
| `updateVerifiedDetails({maskedNumber, name})` | 301-303 | Syncs masked number/name after a live approval (poll doesn't carry these). | `screens/kyc_screen.dart:_checkAndHandleCompletion()` (281-284) |
| `_sanitizeErrorMessage(Object e)` (private) | 132-145 | Maps any `Failure`/technical exception string to a fixed user-facing "temporary technical issue" message; logs the real error via `SecureLogger`. | internal (`initiate`, `pollUntilTerminal`) |

## KycNotifier ⚠️ legacy (`providers/kyc_provider.dart`) — StateNotifier<KycState>

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `_initKycSteps()` (private, called from constructor) | 35-65 | Hardcodes 3 `KycStep`s (pan/aadhaar/bank), all `KycStatus.pending`, routes to `AppRouter.panVerification`/`aadhaarVerification`/`bankVerification`. | constructor only (30-33) |

Exposed via `kycStepsProvider` (68-70). Only consumer is the dead `kyc_screen.dart` (root) — not reachable
from `app_router.dart`.

## KycRepository (`repositories/kyc_repository.dart`) — the only ApiClient caller in this module

| Method | Line | Endpoint | Purpose | Callers |
|---|---|---|---|---|
| `getDocumentTypes({customerId, requestFrom})` | 12-34 | `POST kyc/document-types` | Fetches PAN doc-type field spec + Aadhaar status/masked-number/name in one call. | `kycDocumentsProvider` (`controllers/kyc_controller.dart:8-16`) |
| `uploadKyc({customerId, requestFrom, documentId, fields})` | 36-92 | `POST kyc/upload` | Encrypts `fields` client-side (§ MODULE_BRAIN §6), submits PAN (or any generic doc). Throws with server's error message on failure. | `KycSubmitController.submit()` (`controllers/kyc_controller.dart:28-46`) |
| `initiateAadhaar({requestFrom, aadhaarNumber, fullName, allowReverify})` | 123-137 | `POST kyc/upload` (`id_document:'2'`) via `_uploadAadhaar` | Step 1 of Aadhaar DigiLocker flow. | `AadhaarNotifier.initiate()` (165) |
| `pollAadhaar({requestFrom, verificationId})` | 142-150 | `POST kyc/upload` (`id_document:'2'`) via `_uploadAadhaar` | Step 2 poll. | `AadhaarNotifier.pollUntilTerminal()` (219) |
| `_uploadAadhaar({requestFrom, fields})` (private) | 152-180 | `POST kyc/upload` | Shared plumbing for initiate/poll — encrypts fields, posts, unwraps `data`/error. | `initiateAadhaar`, `pollAadhaar` |
| `updateProfileName({source})` | 188-202 | `POST kyc/update-profile-name` | Applies user's PAN/AADHAAR name choice server-side (`source` must be `'PAN'` or `'AADHAAR'`; backend resolves the actual name, never trusts a client string). | `screens/kyc_screen.dart:_runCompletionSequence()` (319) |

`kycRepositoryProvider` — plain `Provider((ref) => KycRepository())`, line 7.

## KycSubmitController (`controllers/kyc_controller.dart`) — StateNotifier<AsyncValue<bool>>

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `submit({requestFrom, documentId, fields})` | 28-46 | Wraps `KycRepository.uploadKyc` in loading/error `AsyncValue` state. | `screens/kyc_screen.dart:_submitDoc()` (174) |

Exposed via `kycSubmitProvider` (18-20).

## KycVerificationFlow (`kyc_flow.dart`) — the single cross-module entry point

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `static Future<bool> start(context, ref, {required requestFrom, extraData})` | 20-47 | Pushes `AppRouter.kyc` with `{request_from, ...extraData}`, awaits bool result; on success, best-effort refreshes `profileProvider` so Profile's "Verified" pill updates. Returns `false` if user backs out. | `instant_saving_screen.dart`, `withdrawal_screen.dart`, `sip/screens/auto_savings_screen.dart` (multiple call sites — see `BUSINESS_RULES.md` RULE-KYC-002/003) |

## PanVerificationScreen ⚠️ orphaned stub (`screens/pan_verification_screen.dart`)

| Method | Line | Purpose |
|---|---|---|
| `_handleVerify()` | 32-48 | Validates PAN format client-side only, then `await Future.delayed(seconds: 2)` — **no repository/API call at all** — then shows a fake success dialog. |
| `_showSuccessDialog()` | 50-100 | Cosmetic dialog, navigates to `AppRouter.home` on dismiss. |

No callers push `AppRouter.panVerification` anywhere in `lib/` (grep-confirmed) — only reachable by direct
route name.

## KycScreen — LIVE hub (`screens/kyc_screen.dart`, `ConsumerStatefulWidget`)

| Method | Line | Purpose |
|---|---|---|
| `_initControllers(docs)` | 96-121 | Builds `TextEditingController`s per field per doc; seeds already-APPROVED docs into `_completedDocIds`. |
| `_seedAadhaarIfApproved(...)` | 128-136 | Post-frame-callback seed of Aadhaar card if server reports already verified. |
| `_checkCompletionRecoveryOnLoad(result)` *(new 2026-08-26)* | ~141-~170 | Fires once per screen instance from `build()`, alongside `_seedAadhaarIfApproved`. If both PAN and Aadhaar are already log-approved (`documents.every(alreadyUploaded) && aadhaarApproved`) but `result.kycConfirmed` is false, re-runs `_runCompletionSequence()` directly — recovers a customer who auto-verified but never reached the mandatory name-selection dialog (e.g. app closed mid-way), which would otherwise leave the backend's `CustomerPan`/`CustomerAadhaar` mirror (see fintect_application's `KYC` brain, RULE-KYC-015) unconfirmed forever with no visible symptom on this screen. |
| `_editDocument(doc)` | 141-143 | Re-opens a verified PAN card's form for redo. |
| `_editAadhaar()` | 149-152 | Re-opens Aadhaar form, sets `_aadhaarEditing = true` (drives `allowReverify`). |
| `_onRetryPan()` *(new 2026-08-26)* | 154-~205 | Fires when Aadhaar is APPROVED but PAN is still pending (user unchecked "PAN Verification Record" in DigiLocker's document picker — PAN has no consent of its own, see `_buildPanAutoVerifyNotice`). Calls `_editAadhaar()`, awaits `WidgetsBinding.instance.endOfFrame` so the now-reopened Aadhaar `Form` is mounted, validates it, then re-runs `_onVerifyAadhaar()`. Toasts if the fields were empty (Aadhaar approved in an earlier session) or if PAN is still missing after the retry. |
| `_submitDoc(doc)` | 154-207 | Validates form → `kycSubmitProvider.submit()` → on success marks doc complete → `_checkAndHandleCompletion()`. Sets `allow_reverify: true` field when `doc.alreadyUploaded`. |
| `_onVerifyAadhaar()` | 213-258 | Orchestrates `initiate()` → push `AadhaarDigilockerWebView` if consent needed → `pollUntilTerminal()` → `_checkAndHandleCompletion()` on approval. |
| `_checkAndHandleCompletion()` | 267-299 | Re-fetches `kycDocumentsProvider`, checks `all docs alreadyUploaded && aadhaarApproved`; if both, runs `_runCompletionSequence()`. |
| `_runCompletionSequence({panName, aadhaarName})` | 308-334 | Success animation → mandatory name-selection dialog → `updateProfileName()` if chosen → `Navigator.pop(context, true)`. |
| `_showSuccessAnimation()` | 338-382 | 2-second auto-dismiss checkmark dialog. |
| `_showProfileNameSelectionDialog({panName, aadhaarName})` | 392-453 | `PopScope(canPop:false)` — not dismissible; returns `'PAN'`, `'AADHAAR'`, or `null`. "Not Now" button is commented out in source (lines 434-446) — effectively forces a choice today. |
| `_validateAadhaarNumber(value)` | 79-89 | 12-digit, starts 2-9, rejects all-same-digit placeholder. Client-side sanity check only — real verification is DigiLocker. |
| `build()` | 470-515 | Watches `kycDocumentsProvider(requestFrom)` + `aadhaarProvider`. |
| `_buildPanSkippedNotice(isDark, {isBusy})` *(new 2026-08-26)* | ~677-~725 | Amber warning card rendered in place of `_buildPanAutoVerifyNotice` when `aadhaarState.phase == AadhaarPhase.approved` but the PAN doc isn't done yet — "Retry PAN Verification" button wired to `_onRetryPan()`. |

## KycScreen ⚠️ legacy (`kyc_screen.dart` root, `ConsumerWidget`)

| Method | Line | Purpose |
|---|---|---|
| `build()` | 15-112 | Renders hardcoded `kycStepsProvider` list; "Commence Verification" jumps to first pending step's route. |
| `_buildKycStep()` | 114-195 | Card renderer for one `KycStep`. |

Not reachable from `app_router.dart` — reference only.

## AadhaarDigilockerWebView (`widgets/aadhaar_digilocker_webview.dart`)

| Method | Line | Purpose |
|---|---|---|
| `initState()` | 38-61 | Configures `WebViewController`, intercepts navigation containing `/kyc/digilocker-callback` and pops `true` instead of letting the WebView load it. |
| `_enableThirdPartyCookies()` | 68-77 | Android-only: explicitly allows third-party cookies so the digilocker.gov.in → Cashfree domain handoff doesn't silently stall. |

## DigilockerSdkScreen (`widgets/digilocker_sdk_screen.dart`, new 2026-08-24)

SurePass counterpart to `AadhaarDigilockerWebView` above — same pop-result contract (`true`/`false`/null),
routed at `AppRouter.digilockerSdk`. Takes `sdkToken`/`clientId`/`environment` (from `AadhaarState.sdkToken`/
`providerClientId`/`sdkEnvironment`) instead of a `consentUrl`. Android minSdk 28 already met at 29;
iOS `IPHONEOS_DEPLOYMENT_TARGET` raised from 13.0 to 15.0 to meet the package's minimum.

| Method | Purpose |
|---|---|
| `_launchSdk()` | Calls `DigilockerSdk.start(context, apiToken: widget.sdkToken, environment: Environment.SANDBOX\|PROD, onComplete:, onError:)` from `package:digilocker_flutter_sdk` (v1.0.6 — API confirmed by reading the resolved pub-cache source directly, since SurePass's own docs never specified the Flutter SDK's Dart surface). The package internally does its own login (`GET /digilocker/options` with `apiToken` as Bearer) then pushes its own verification/webview screen(s) on top of this one; `onComplete(VerificationResult)` / `onError(String)` fire once that internal stack unwinds. `environment` MUST match whichever base_url (sandbox vs prod) issued `apiToken` on the backend — threaded through as `AadhaarState.sdkEnvironment` from the `kyc/upload` response's `sdk_environment` field (see `DigiLockerInitiateResult.environment` in the backend contract). |

## KycValidator ⚠️ dead code (`core/utils/kyc_validator.dart`)

`validateAadhaar`, `validatePAN`, `validateMobile`, `validateUPI`, `validateGeneric` — zero importers anywhere
in `lib/` (grep-confirmed). Do not assume this is what backs the live PAN/Aadhaar form validation.
