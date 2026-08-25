---
module: kyc
---

# KYC — Data Flows

All flows reference the LIVE code path (`screens/kyc_screen.dart` + `controllers/kyc_controller.dart` +
`repositories/kyc_repository.dart`), not the dead `kyc_screen.dart` (root) path — see `MODULE_BRAIN.md` §2.

## Flow 1 — Dynamic step determination / hub load

There is no client-side "step sequence" computation in the live flow — the hub renders **all** documents the
backend returns in one shot, plus a hardcoded second Aadhaar card. There is no multi-screen wizard; PAN and
Aadhaar are both visible on one scrollable page.

1. Caller navigates to `AppRouter.kyc` (or `dynamicKyc`) with `arguments: {'request_from': ..., ...extra}`
   (`kyc_flow.dart:26-33`, or a direct `Navigator.pushNamed` from a different call site).
2. `app_router.dart:144-152` builds `KycScreen(requestFrom: args['request_from'] ?? 'instant', extraData: args)`.
3. `screens/kyc_screen.dart:472` — `ref.watch(kycDocumentsProvider(widget.requestFrom))`.
4. `controllers/kyc_controller.dart:8-16` (`kycDocumentsProvider`, `FutureProvider.autoDispose.family`) reads
   `userProvider`; if no user, returns an empty `KycDocumentsResult` (no crash, but the screen would render
   with no cards — edge case, effectively unreachable since KYC screens require an authenticated session).
5. `KycRepository.getDocumentTypes()` (`kyc_repository.dart:12-34`) → `POST kyc/document-types` with
   `{id_customer, request_from}` → parses response into:
   - `documents: List<KycDocumentType>` — today, PAN only, each with a dynamic `fields` list (name/label/
     type/regex per field) and `already_uploaded`/`status`/`masked_value`/`verified_name`.
   - `aadhaarApproved` (from `aadhaar_status == 'APPROVED'`), `aadhaarMaskedNumber`, `aadhaarName` — Aadhaar's
     status rides on the SAME response but is NOT in the `documents` array (`kyc_document.dart:45-48` doc
     comment explains why: Aadhaar is rendered as a separate client-side card, not a generic fields form).
6. `docsAsync.when(data: ...)` → `_initControllers(result.documents)` builds text controllers per field per
   doc and seeds `_completedDocIds` for anything already APPROVED; `_seedAadhaarIfApproved(...)` does the
   equivalent for the Aadhaar card via a post-frame callback (mutating a provider from inside `build()` would
   otherwise assert).
7. Each doc renders as `_buildDocumentCard` — verified banner if done, else a form (`_buildPanCard` if the
   doc's name/code contains "PAN", else `_buildGenericCard`). The Aadhaar card renders separately via
   `_buildAadhaarCard`, driven entirely by `aadhaarProvider`'s `AadhaarState`, independent of the documents list.

## Flow 2 — PAN verification submit

1. User fills PAN number + name in `_buildPanCard`/`_buildDocInputs` (`screens/kyc_screen.dart:790-977`).
   Client-side format validators: PAN `^[A-Z]{5}[0-9]{4}[A-Z]{1}$` (line 958), name min length 2 (line 963).
2. `CustomButton` → `_submitDoc(doc)` (154-207): validates the doc's `Form`, collects all field controllers
   into a `Map<String,dynamic>`, adds `allow_reverify: true` if `doc.alreadyUploaded` (i.e. user tapped
   "Edit" on an already-verified card).
3. `ref.read(kycSubmitProvider.notifier).submit(requestFrom, documentId: doc.id, fields)`
   (`controllers/kyc_controller.dart:28-46`) → `KycRepository.uploadKyc()`.
4. `uploadKyc()` (`kyc_repository.dart:36-92`):
   - Builds `rawData` (unencrypted, used only for the sanitized debug log at 61-72 — PAN/Aadhaar keys masked
     as `********` before logging).
   - `EncryptionService.encryptJson(fields)` (line 51-52) — encrypts any key present in
     `AppConfig.sensitiveFields` (e.g. a PAN field literally named `pan_number` or `pan`); leaves
     `full_name`/other non-listed keys in plaintext.
   - Posts `{id_document, request_from, fields: encryptedFieldsMap}` to `kyc/upload`.
   - `ApiSecurityInterceptor.onRequest` (`core/security/api_interceptor.dart:166-182`) ALSO runs
     `encryptJson` on the whole payload since `kyc/upload` is in `AppConfig.encryptedEndpoints` — see
     `FORENSIC_TEMPLATE.md` §1 for the resulting (likely harmless) double-encrypt-attempt quirk.
   - On `success: true` returns `true`; on failure throws `Exception(serverMessage)` extracted from
     `response.data.error.message` / `.data.message` / `.message` in that priority order.
5. Back in `_submitDoc`: on success, `_completedDocIds.add(doc.id)` then `_checkAndHandleCompletion()`
   (267-299) — re-fetches `kycDocumentsProvider` fresh (never trusts pre-edit cached state), and if
   `documents.every(alreadyUploaded) && aadhaarApproved`, runs the completion sequence (Flow 4). If PAN alone
   just completed but Aadhaar hasn't, the screen simply shows PAN as verified and waits.

## Flow 3 — Aadhaar DigiLocker consent + poll

1. User enters Aadhaar number + name in `_buildAadhaarCard` (`screens/kyc_screen.dart:559-678`). Client-side
   checks only: 12 digits, first digit 2-9, rejects all-same-digit (`_validateAadhaarNumber`, 79-89) — real
   identity check is entirely DigiLocker's, this is just UX sanity.
2. `_onVerifyAadhaar()` (213-258) → `AadhaarNotifier.initiate(requestFrom, aadhaarNumber, fullName,
   allowReverify: _aadhaarEditing)` (`controllers/kyc_controller.dart:157-195`).
3. `initiate()` sets phase `initiating` → `KycRepository.initiateAadhaar()` → `_uploadAadhaar()` →
   `POST kyc/upload` with `{id_document: '2', fields: {aadhaar_number: <enc>, name: <plain>, allow_reverify?:
   true}}` (`kyc_repository.dart:123-137,152-180`). **Note:** the backend reads the name from the exact key
   `name`, not `full_name` (doc comment at `kyc_repository.dart:108-118`).
4. Response `status` branches (`controllers/kyc_controller.dart:171-194`):
   - `is_already_approved: true` or `status == 'already approved'` → phase `approved` immediately, no
     DigiLocker round trip (idempotency short-circuit; bypassed only when `allowReverify: true` was sent).
   - `status == 'PENDING'` + `consent_url` present → phase `awaitingConsent`, stores `verification_id` +
     `consent_url`.
   - anything else → phase `failed`.
5. If `awaitingConsent`, `screens/kyc_screen.dart:228-232` pushes `AppRouter.aadhaarVerification` with
   `{'consentUrl': ...}` → `AadhaarDigilockerWebView` (`widgets/aadhaar_digilocker_webview.dart`).
6. The WebView loads the Cashfree/DigiLocker consent page directly (no app-side rendering of the consent UI).
   `NavigationDelegate.onNavigationRequest` (lines 47-52) watches every navigation for the substring
   `/kyc/digilocker-callback` — when Cashfree's `redirect_url` fires, the WebView **intercepts it before it
   loads** and pops `true`. There is no manual "I'm done" fallback button and no timeout — if a DigiLocker
   consent-page variant never calls the redirect, this screen never resolves (see `FORENSIC_TEMPLATE.md` §2).
   Android third-party cookies are explicitly enabled (`_enableThirdPartyCookies`, 68-77) because the
   digilocker.gov.in → Cashfree domain handoff needs a cross-domain cookie that Android WebView blocks by
   default.
7. Back in `_onVerifyAadhaar()` (234-240): only if the webview returned `true` does it call
   `notifier.pollUntilTerminal(requestFrom)` — backing out of the webview (`null` result) skips polling.
8. `pollUntilTerminal()` (`controllers/kyc_controller.dart:201-273`) loops up to 10x, 2s apart, calling
   `KycRepository.pollAadhaar({verificationId})` → `_uploadAadhaar()` → same `kyc/upload` endpoint with just
   `{verification_id}`. Branches on `status`: `APPROVED` → done; `EXPIRED`/`REJECTED` → terminal failure;
   `PENDING` → loop again; exhausted retries while still `PENDING` → reverts to `awaitingConsent` with a
   "taking longer than expected" message (NOT treated as failure — `verificationId` is preserved so a retry
   resumes polling rather than restarting consent).
   - **Fixed 2026-08-24**: this timeout outcome used to fall through both branches in
     `_onVerifyAadhaar()` (neither the terminal-failure toast nor the approved path matched
     `awaitingConsent`), so the user saw the DigiLocker/SDK screen close and then nothing at all — no
     success, no error. `_onVerifyAadhaar()` (`screens/kyc_screen.dart`) now falls back to an
     `ToastType.info` toast showing `finalState.message` whenever the poll ends in a non-terminal phase.
     Root latency contributor for the SurePass path specifically: `_check_aadhaar_kyc`
     (`domains/masters/services/kyc.py`) now also runs `_try_persist_digilocker_pan` synchronously once
     Aadhaar authenticates — up to ~8 sequential SurePass HTTP calls (status + 2×[list-documents +
     download-document + XML fetch] + pan-comprehensive) inside the single poll response that flips
     `APPROVED`. Each individual Dio call has a 60s timeout (`AppConfig.connectTimeout/receiveTimeout`,
     `core/config/app_config.dart:32-33`) so that one heavy attempt won't itself time out, but if
     DigiLocker's own document availability genuinely lags past the full ~20s client polling budget, the
     toast above is what the user now sees instead of silence.
   - **Fixed 2026-08-24 (crash, not just silence)**: a device log showed `pollAadhaar`'s request hitting a
     401 mid-poll, going through `ApiSecurityInterceptor`'s silent refresh-and-retry detour
     (`core/security/api_interceptor.dart:298-497` — a second Dio round trip), and by the time that
     resolved the `KycScreen`/`aadhaarProvider` (`StateNotifierProvider.autoDispose`) had been disposed.
     `AadhaarNotifier`'s `state = ...` write on the disposed notifier threw `Bad state: Tried to use
     AadhaarNotifier after 'dispose' was called` as an **unhandled exception** on the button's `onPressed`
     Future (nothing awaits/catches it) — so `_onVerifyAadhaar()` never reached its own post-poll checks at
     all, no dialog and no toast, silently. Both `initiate()` and `pollUntilTerminal()`
     (`controllers/kyc_controller.dart`) now check the notifier's own `mounted` (from `package:state_notifier`)
     right after every `await` that can outlive the widget, before touching `state`.
9. On `approved`, `_onVerifyAadhaar()` calls `_checkAndHandleCompletion()` (same as Flow 2 step 5).

## Flow 4 — Completion sequence (fires once BOTH PAN and Aadhaar are APPROVED)

`_checkAndHandleCompletion()` → `_runCompletionSequence(panName, aadhaarName)` (`screens/kyc_screen.dart:
308-334`):
1. `_showSuccessAnimation()` — 2s auto-dismissing checkmark dialog (338-382).
2. `_showProfileNameSelectionDialog(panName, aadhaarName)` (392-453) — `PopScope(canPop:false)`, not
   dismissible via barrier or back button. Returns `'PAN'`, `'AADHAAR'`, or `null`. The "Not Now" button is
   present in a commented-out block (434-446) — as shipped, the user must tap "Use PAN Name" or "Use Aadhaar
   Name"; there is no visible way to decline in the current UI even though the code comment above the
   function still describes `null`/"Not Now" as a valid outcome.
3. If `'PAN'`/`'AADHAAR'` chosen → `KycRepository.updateProfileName(source: choice)` → `POST
   kyc/update-profile-name` — backend resolves the actual name server-side from the verified KYC record, never
   trusts a client-supplied string.
4. `Navigator.pop(context, true)` — the screen's terminal success signal.

## Flow 5 — Eligibility gating from other modules (cross-module — see `CROSS_MODULE_MAP.md`)

1. InstantSaving/Withdrawal call `POST savings/check-eligibility` (shared endpoint,
   `instant_saving/services/saving_service.dart:16-35`, `withdrawal/services/withdrawal_service.dart:59-`).
   Response `next_step` field → `EligibilityResponse.nextStep` (`instant_saving/models/saving_models.dart:
   95-104`), `'KYC_REQUIRED'` or `'PAYMENT'`.
2. SIP additionally short-circuits client-side using the cached `profileProvider.user.kycStatus == 1`
   (`sip/screens/auto_savings_screen.dart:1393-1400`) before ever calling its create endpoint, PLUS keeps the
   backend backstop (`errorCode == 'KYC_REQUIRED'` / `on KycRequiredFailure`) around the actual
   `sip/create`/custom-SIP-create calls (lines 2081-2116, 2254-2301) in case the cached status is stale.
3. On `KYC_REQUIRED` (either surface: inline `next_step` in a 200 response, OR a thrown `KycRequiredFailure`
   from `ApiFailureMapper` reading `error.code` on a 401/403 — see `core/error/failures.dart:39-98`), the
   caller awaits `KycVerificationFlow.start(context, ref, requestFrom: '<instant|withdraw|sip>')`
   (`kyc_flow.dart:20-47`).
4. On `true` (both PAN+Aadhaar now APPROVED), the caller retries its original blocked action — automatically
   re-attempting the same purchase/SIP-create/withdrawal-initiate call, per each screen's own retry logic
   (documented in the InstantSaving/SIP/Withdrawal brains, not owned by this module).
5. `KycVerificationFlow.start()` itself also best-effort refreshes `pc.profileProvider` on completion
   (`kyc_flow.dart:39-45`) so `user.kycStatus` and the Profile screen's "Verified" pill reflect the change
   without waiting for Profile's own next load.
