---
module: kyc
---

# KYC — Business Rules

## RULE-KYC-001 — KYC is complete only when PAN AND Aadhaar are both APPROVED

There is no partial-credit state. `_checkAndHandleCompletion()`
(`screens/kyc_screen.dart:287-289`): `bothComplete = result.documents.every((d) => d.alreadyUploaded) &&
result.aadhaarApproved`. Bank account is NOT part of this module's completion condition (see
`CROSS_MODULE_MAP.md` — bank verification is a separate `profile`-module concern).

## RULE-KYC-002 — `savings/check-eligibility` is the shared purchase/withdrawal gate

Both InstantSaving and Withdrawal call the identical `POST savings/check-eligibility` endpoint
(`instant_saving/services/saving_service.dart:16-35`, `withdrawal/services/withdrawal_service.dart:59`) and
branch on `next_step` (`'KYC_REQUIRED'` vs `'PAYMENT'`). This matches
`.agents/skills/flutter_fintech_mobile/SKILL.md` §5's RBI KYC/PMLA rule: "don't add a purchase path that
bypasses `savings/check-eligibility`."

## RULE-KYC-003 — `KYC_REQUIRED` can arrive as either a thrown error OR an inline 200-OK field

`core/error/failures.dart:39-98` — `ApiFailureMapper` inspects `error.code` on non-2xx responses and throws
`KycRequiredFailure` when it equals `'KYC_REQUIRED'`. But SIP's create endpoints wrap this same signal inside
a 200 OK response body (`ResponseStandardizationMiddleware`, per code comment at
`sip/screens/auto_savings_screen.dart:2255-2258`) — so SIP checks `response.errorCode == 'KYC_REQUIRED'`
*and* keeps a `on KycRequiredFailure catch` around the same call as a backstop in case the endpoint ever
starts returning it as a real HTTP error instead. Any new caller integrating this gate must handle **both**
shapes, not just one.

## RULE-KYC-004 — SIP has a proactive client-side gate in addition to the backend backstop

`sip/screens/auto_savings_screen.dart:1393-1400` — before letting the user reach the bank-picker/payment
steps, SIP force-refreshes the profile (`fetchProfileDetails()`) then checks `user.kycStatus == 1` and routes
through `KycVerificationFlow` immediately if not verified, rather than waiting for the backend to reject the
create call. InstantSaving and Withdrawal do NOT do this — they rely solely on the `check-eligibility` round
trip.

## RULE-KYC-005 — Re-verifying an already-approved PAN requires `allow_reverify: true`

`screens/kyc_screen.dart:164-171` — when the user taps "Edit" on a verified PAN card and resubmits,
`allow_reverify: true` is added to the `fields` payload. Without it, the backend's idempotency short-circuit
would silently ignore a corrected name/number instead of re-verifying via the PAN gateway (code comment,
same lines).

## RULE-KYC-006 — Re-verifying an already-approved Aadhaar requires `allowReverify: true`

Same idempotency short-circuit on the Aadhaar side. `_editAadhaar()` sets `_aadhaarEditing = true`
(`screens/kyc_screen.dart:149-152`), which flows into `AadhaarNotifier.initiate(..., allowReverify: true)`
(`controllers/kyc_controller.dart:161`) → `KycRepository.initiateAadhaar(allowReverify: true)`
(`kyc_repository.dart:119-122,127-136`), which the backend uses to bypass its "already approved, do nothing"
default behavior.

## RULE-KYC-007 — Profile-name selection is mandatory after every completion, first-time or redo

`_showProfileNameSelectionDialog()` (`screens/kyc_screen.dart:384-453`) fires after EVERY successful
PAN+Aadhaar completion — including re-verification via Edit — "with no exceptions, even when both verified
names are identical to each other or to the current profile name" (doc comment, 384-388). As shipped, the
dialog's only visible actions are "Use PAN Name" / "Use Aadhaar Name" (the "Not Now" button is commented out,
lines 434-446) — functionally the user must choose one, though the surrounding code (`_runCompletionSequence`,
331) still tolerates a `null` choice as "leave profile name unchanged" if that branch is ever re-enabled.

## RULE-KYC-008 — PAN format is validated client-side against `AAAAA9999A`

`^[A-Z]{5}[0-9]{4}[A-Z]{1}$`, enforced independently in two places: `screens/kyc_screen.dart:958-960` (the
live dynamic form) and `screens/pan_verification_screen.dart:30` (the orphaned stub) — duplicated, not
shared via a common validator (see `core/utils/kyc_validator.dart` dead-code note in `MODULE_BRAIN.md`).

## RULE-KYC-009 — Aadhaar number's client-side check is cosmetic only; DigiLocker is the real verification

`_validateAadhaarNumber()` (`screens/kyc_screen.dart:79-89`) mirrors the backend's
`validate_aadhaar_number` (12 digits, first digit 2-9, rejects an obvious all-same-digit placeholder like
`222222222222`) but the code comment is explicit: "actual identity verification always happens via DigiLocker
consent, never this number." A syntactically valid Aadhaar number that doesn't belong to the user will still
fail at the DigiLocker consent step, not at this client-side check.

## RULE-KYC-010 — Sensitive KYC fields are always RSA-OAEP-SHA256 encrypted before transmission

`AppConfig.sensitiveFields` (`core/config/app_config.dart:74-95`) includes `pan_number`, `pan`,
`aadhaar_number`, `bank_account_number`, `account_no`, `ifsc_code`, `upi_id`. `EncryptionService.encryptJson`
(`core/security/encryption_service.dart:109-126`) recursively encrypts only keys present in that list,
leaving `name`/`full_name`/`request_from`/`id_document` in plaintext. Matches AGENTS.md §3's non-negotiable
rule.

## RULE-KYC-011 — `kyc/upload` payload is passed through `encryptJson` twice (confirmed code path; see FORENSIC_TEMPLATE §1 for likely runtime effect)

`KycRepository.uploadKyc()`/`_uploadAadhaar()` pre-encrypt `fields` themselves
(`kyc_repository.dart:51-58,160-166`) before posting to `kyc/upload`, which is ALSO listed in
`AppConfig.encryptedEndpoints` (`app_config.dart:57`) — so `ApiSecurityInterceptor.onRequest`
(`core/security/api_interceptor.dart:166-182`) attempts to encrypt the entire (already-partially-encrypted)
payload again. Do not copy this pattern into a new module's repository — either pre-encrypt AND keep the
endpoint out of `encryptedEndpoints`, or rely solely on the interceptor, not both.

## Unconfirmed / needs a fresh backend-contract check

- Exact `id_document` value the backend assigns to the PAN document type (the app never hardcodes it — it's
  read from `kyc/document-types`'s response and matched by name/code containing "PAN"). Aadhaar's is
  hardcoded to `'2'` client-side (`kyc_repository.dart:163`).
- Whether `submit-kyc` / `update-kyc` (present in `AppConfig.encryptedEndpoints`, `app_config.dart:55-56`)
  are genuinely dead, or called from a part of the codebase outside `lib/` (e.g. a web admin panel sharing
  the same backend) — zero call sites found anywhere in `lib/`.
