---
module: kyc
---

# KYC — Business Rules

## RULE-KYC-001 — KYC is complete only when PAN AND Aadhaar are both APPROVED

There is no partial-credit state. `_checkAndHandleCompletion()`
(`screens/kyc_screen.dart:287-289`): `bothComplete = result.documents.every((d) => d.alreadyUploaded) &&
result.aadhaarApproved`. Bank account is NOT part of this module's completion condition (see
`CROSS_MODULE_MAP.md` — bank verification is a separate `profile`-module concern).

⚠️ **This screen's own "complete" check is log-based, while the backend's actual SIP/withdrawal/purchase
gate reads the CustomerPan/CustomerAadhaar mirror** (backend change, 2026-08-26 — see
`fintect_application`'s KYC brain, RULE-KYC-001/014/015). `documents[].alreadyUploaded`/`aadhaarApproved`
come straight from `kyc_verification_log`; `is_kyc_complete()` reads the mirror instead, which is *also*
stricter in one direction — `invalidate_for_reverify()` drops it to `RE_VERIFICATION_REQUIRED` the moment a
reverify starts, so the screen can still show "Verified" while the gate says no.

**Corrected 2026-09-07 — the mirror does NOT require a customer confirmation step.**
`KYCService.is_kyc_complete()`'s own docstring still claims "the mirror only reaches APPROVED once the
customer explicitly confirms post-verification", and this brain note used to repeat it. That is **stale**:
`sync_from_kyc_log()` writes `cpan_status = kyc_row.kyc_status` directly, and it is called on every APPROVED
row at verification time by both `_check_aadhaar_kyc()` (kyc.py:2375) and `_try_persist_digilocker_pan()`
(kyc.py:3285) — see kyc.py:453, "sync_from_kyc_log() is now called immediately on every APPROVED
PAN/Aadhaar row". `confirm_and_sync()` is an idempotent re-sync of a mirror that is already APPROVED.
This is what made removing the confirmation popup safe (RULE-KYC-007) — verify it again before trusting
either docstring if this area changes.

`KycDocumentsResult.kycConfirmed` (mirrors the backend's `kyc_confirmed`) still exists on the response and
is still read by `_checkCompletionRecoveryOnLoad()`, but with the popup gone there is no longer a
"customer never reached the popup" state for it to recover.

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

## RULE-KYC-007 — ~~Profile-name selection is mandatory after every completion~~ **REMOVED 2026-09-07**

**This rule no longer holds.** The per-document post-verification confirmation popup — "PAN Verified" /
"Aadhaar Verified", showing the verified Name/DOB above editable Profile Name + Date of Birth fields with
Save / "Do this later" — has been **deleted from the app** (product decision).

Removed in full:
- `_VerifiedDetailsDialog` + `_showVerifiedDetailsDialog()` + `_profileAlreadyMatches()` —
  `screens/kyc_screen.dart`
- `KycVerifiedDetailsDialog` + `_showVerifiedDetailsDialog()` + `_profileAlreadyMatches()` —
  `controllers/kyc_verification_flow_mixin.dart`

`_runCompletionSequence()` now takes **no arguments** in both files and does only: success animation →
refresh `profileProvider` → (kyc_screen only) `Navigator.pop(context, true)`.

**Why removing it does NOT break KYC completion.** That dialog's Save was the only client-side trigger for
`update_profile_name_from_kyc` → `KYCStatusSyncService.confirm_and_sync()`. That call is **idempotent and
redundant on the happy path**: `_check_aadhaar_kyc()`'s and `_try_persist_digilocker_pan()`'s APPROVED
branches each already call `sync_from_kyc_log()` for their own document at verification time, and the
resulting CustomerPan/CustomerAadhaar mirror is what `is_kyc_complete()` actually reads (see
`confirm_and_sync`'s own docstring in `shared/services/kyc_status_sync.py`). The mismatch path is unaffected
— `_finalize_name_mismatch_confirmation` calls `confirm_and_sync()` itself.

**Behaviour change to be aware of:** on a clean match the profile name/DOB is no longer overwritten with the
document's version. The customer keeps the name they already had — which is what "it matched" means. The
only path that still rewrites the profile name is the mismatch confirmation (RULE-KYC-014).

Also gone with it: the "confirmation deferred" early-returns that existed so a deferral couldn't report KYC
as confirmed to a blocked-action caller (Withdraw's `KYC_REQUIRED` gate). With no dialog left to defer,
`_runCompletionSequence` has no path that finishes without popping `true`.

`KycRepository.updateProfileName` / `updateProfileDob` are now **unreferenced from `lib/`** — left in place
(the backend endpoints still exist and the mismatch flow's server side still uses the same logic), but
nothing in the app calls them. Don't assume they're live when tracing the profile-name write path.

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

## RULE-KYC-012 — Aadhaar-approved-but-PAN-pending is surfaced as a distinct "skipped in consent" state (added 2026-08-26)

PAN has no consent flow of its own — it's fetched from the SAME DigiLocker session as Aadhaar (backend's
`_try_persist_digilocker_pan`, run synchronously once Aadhaar authenticates; see `DATA_FLOW.md` Flow 3 step
8). If the user unchecks "PAN Verification Record" in DigiLocker's document-selection screen, Aadhaar comes
back APPROVED but PAN never does, and RULE-KYC-001 still holds (KYC isn't complete). Previously the PAN card
kept showing the generic `_buildPanAutoVerifyNotice` text ("complete Aadhaar verification below") even once
Aadhaar was already done — confusing, since there was nothing left to complete on the Aadhaar card. Now
`_buildDocumentCard` (`screens/kyc_screen.dart`) detects `aadhaarState.phase == AadhaarPhase.approved && !isDone`
for the PAN doc and renders `_buildPanSkippedNotice` instead, with a "Retry PAN Verification" button
(`_onRetryPan()`) that re-runs the DigiLocker consent and explicitly tells the user to check PAN this time.

## RULE-KYC-013 — A blank verified name must never open the Profile Name Selection popup (fixed 2026-09-07)

`_profileAlreadyMatches(verifiedName)` — duplicated in `controllers/kyc_verification_flow_mixin.dart:554`
and `screens/kyc_screen.dart:929` — returns **true** (nothing to confirm) when `verifiedName` is null or
blank. It used to return false, which meant "doesn't match" and opened `KycVerifiedDetailsDialog` with
`Verified PAN Name: —` and an empty, unsaveable name field.

That was reachable in production: a PAN mismatch row is created by the backend's
`_offer_pan_name_mismatch_confirmation` with **no `payload` key at all**, and
`_finalize_name_mismatch_confirmation` wrote only `verified_dob` on approval — never the name. Both readers
of the PAN verified name (`get_document_types()` and `update_profile_name_from_kyc()`) look at
`kyc_response["payload"]["name"]`, so they found nothing. Save then failed server-side with *"Verified name
not available for this document."*, leaving "Do this later" as the only exit — which aborts
`_runCompletionSequence` before `confirm_and_sync()`, so the identical popup returned on every subsequent
status check.

Backend fix (`KYCService._finalize_name_mismatch_confirmation`): also writes `payload.name` and
`entered_name` from `final_name`. Already-approved rows predating the fix need the
`backfill_kyc_mismatch_verified_name` management command — the code fix only applies at confirmation time.

**Superseded on the client (2026-09-07):** `_profileAlreadyMatches` and the popup it guarded were deleted
outright when RULE-KYC-007 was removed, so the blank-name dialog can no longer occur by construction. The
**backend half of this fix still matters** — `payload.name` is what `get_document_types()` reports as the
PAN verified name, and what `update_profile_name_from_kyc` validates against — so neither the fix nor the
backfill is redundant.

❌ Treating "no verified name" as a mismatch.
✅ No verified name to compare against means there is nothing to ask the customer to confirm.

## RULE-KYC-014 — The mismatch dialog asks for only the field that actually failed (added 2026-09-07)

`CONFIRM_NAME_UPDATE` now carries `name_mismatch` / `dob_mismatch` booleans
(`KYCService._confirm_name_update_prompt`), parsed into `NameMismatchPrompt.nameMismatch/dobMismatch`.
`NameMismatchDialog` shows the name field only when the name failed and the DOB picker only when the DOB
failed; the title and body copy follow.

Both flags are decided **server-side and never re-derived on the client** — the name comparison is fuzzy
(`NameMatchingService.compute_match`, score threshold), so a client-side string compare of `verifiedName`
vs `profileName` would disagree with the gate that actually blocked the customer.

The customer still submits **both** values: `_validate_mismatch_resubmission` re-checks both regardless, so
the hidden field is sent pre-filled from the verified value (`initState`) rather than dropped. Sending an
empty DOB when the document carried one would fail `dob_ok` and reject the resubmission.

Where the flags come from:
- **Aadhaar** (`_check_aadhaar_kyc`): `name_mismatch = not name_matched_bool`,
  `dob_mismatch = dob_conflict or dob_missing` (a profile with no DOB still prompts, so the customer sees
  and confirms the value before it's written). Persisted into `awaiting_confirmation` so a plain re-poll
  rebuilds the same single-field prompt.
- **PAN** (`_offer_pan_name_mismatch_confirmation`): the caller passes `name_mismatch` (the name-mismatch
  branch passes true, the DOB-mismatch branch passes false since the name already matched); the DOB
  condition is re-derived inside the function, because the name-mismatch caller reaches it *before* the DOB
  cross-check has run.

Backward compatibility: a backend without these keys sends neither, and `NameMismatchPrompt.fromJson`
falls back to the old behaviour — name always, DOB whenever the document carried one. Rows written before
the flags existed read the same defaults out of `awaiting_confirmation`.

Covered by `test/name_mismatch_dialog_test.dart` (10 tests: field visibility per flag combination, the
no-DOB document case, hidden-field pre-fill on submit, and the `fromJson` defaults).

❌ Deciding on the client which field mismatched, or hiding a field without still submitting its value.
✅ Server decides; client hides the field but sends the verified value back.

## RULE-KYC-015 — The name/DOB check runs on exactly ONE document, and gates on the PROFILE name (changed 2026-09-07)

Two changes, both backend-only (`KYCService`), driven by the case matrix below.

### 1. One document, PAN wins

`_name_check_document()` (new) resolves which single document the mismatch gate runs against:

```
PAN     in target_documents            -> "PAN"
AADHAAR in target_documents (and PAN not) -> "AADHAAR"
otherwise                              -> None (gate off)
```

`_is_name_check_skipped(doc)` and both prompt branches now ask this helper instead of
`_is_name_mismatch_target(doc)` directly. The gate never runs twice: prompting per-document would ask the
customer to confirm the same profile name twice over.

**Resulting behaviour** (DigiLocker selection x `target_documents`):

| Shared in DigiLocker | `target_documents` | Check |
|---|---|---|
| PAN only | `["PAN"]` | name + DOB vs **PAN** data |
| PAN only | `["AADHAAR"]` | none |
| Aadhaar only | `["PAN"]` | none |
| Aadhaar only | `["AADHAAR"]` | name + DOB vs **Aadhaar** data |
| PAN + Aadhaar | `["PAN"]` | name + DOB vs **PAN** data |
| PAN + Aadhaar | `["PAN","AADHAAR"]` | name + DOB vs **PAN** data (PAN wins) |

⚠️ With PAN in `target_documents`, AADHAAR's name/DOB is **never** gated — whether or not PAN was actually
shared in that consent. That is deliberate, not an ordering accident: the Aadhaar branch runs before PAN is
fetched, so it cannot know whether PAN is coming. Row 3 above is that case.

⚠️ "Not checked" means **auto-approved**, not rejected — `_is_name_check_skipped` bypasses the gate and the
document verifies regardless of mismatch (the real score is still recorded in `kyc_name_match_score` and
`name_check_skipped` for audit). Only a fully inactive config restores the original hard-reject default.
Confirmed live 2026-09-07: `digilocker_aadhaar` VERIFIED at `match_score: 76.92` under `["PAN"]`.

### 2. PAN gates on the PROFILE name, not `entered_name`

`_try_persist_digilocker_pan` previously gated on `compute_match(entered_name, name_at_source)` — what the
customer typed at the Aadhaar-initiate form this session — with `profile_name` recorded audit-only, plus a
rescue branch that forgave a typed typo whenever the profile already matched.

The effect: a customer whose **profile** name genuinely disagreed with their PAN passed verification as long
as they typed their PAN name correctly on the form. The dialog never fired for the one divergence that
actually matters — the one persisted on the account. Observed live: `digilocker_pan match_score: 100.0`
(entered_name, passed) alongside `profile_name_pan_name_match: NOT_MATCHED, 76.92`.

Now `profile_name` is the gate — consistent with AADHAAR (which always compared `cus_name`) and with the
dialog's own "Current Profile Name" wording. `entered_name`'s comparison is kept and recorded under
`kyc_response.entered_name_match` for audit; the rescue branch is gone (meaningless once the profile IS the
gate).

**Invariant repaired alongside it:** `kyc_response.payload.name` — read back as "the PAN-verified name" by
`get_document_types()` and `update_profile_name_from_kyc()` — used to hold `entered_name`. That was only
safe because `entered_name` was the gate and so could not diverge from the verified name. With the gate
moved it can, so `payload.name` now stores `name_at_source` (the authoritative provider name), which is
what both readers already meant by it. See RULE-KYC-013 for the other half of that field's history.

## Unconfirmed / needs a fresh backend-contract check

- Exact `id_document` value the backend assigns to the PAN document type (the app never hardcodes it — it's
  read from `kyc/document-types`'s response and matched by name/code containing "PAN"). Aadhaar's is
  hardcoded to `'2'` client-side (`kyc_repository.dart:163`).
- Whether `submit-kyc` / `update-kyc` (present in `AppConfig.encryptedEndpoints`, `app_config.dart:55-56`)
  are genuinely dead, or called from a part of the codebase outside `lib/` (e.g. a web admin panel sharing
  the same backend) — zero call sites found anywhere in `lib/`.
