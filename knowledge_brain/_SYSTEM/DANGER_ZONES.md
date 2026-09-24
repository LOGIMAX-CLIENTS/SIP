---
last_updated: 2026-08-19
source: Synthesized from all 24 Round-1 module brains (Core + 23 features)
---

# Danger Zones

Hard-stop anti-patterns confirmed live in this codebase during Round 1. Read this before any bug
investigation (`AGENTS.md` §0 Step Zero). Each entry cites the module brain with full detail.

## DZ-001 — Client-side response decryption is a no-op

`core/security/encryption_service.dart`'s `decrypt()` method returns its input unchanged.
`ApiSecurityInterceptor` logs `"Response decrypted (AES-256)"` on every response regardless — the log line
is false. If any response field is genuinely expected to be encrypted server→client, it currently isn't
being decrypted anywhere in the app. **Highest-severity finding in this brain build.**
→ `Core/MODULE_BRAIN.md`, `Core/BUSINESS_RULES.md`.

❌ Trusting that a field arriving from a "sensitive" endpoint has been decrypted by the time it reaches a
provider/controller.
✅ Verify server response encryption expectations against this file before assuming client-side decryption
happens at all.

## DZ-002 — Encryption fails open when the RSA key isn't ready

`core/security/api_interceptor.dart`: if the RSA public key hasn't been fetched/cached yet when a sensitive
request fires, the interceptor logs an error but **still sends the request with that field in plaintext**
rather than blocking it.
→ `Core/MODULE_BRAIN.md`, `Core/BUSINESS_RULES.md`.

❌ Assuming a field in `AppConfig.sensitiveFields` is always encrypted on the wire.
✅ Treat "field is in `sensitiveFields`" as necessary but not sufficient — the key-readiness race must also
be closed (e.g. block-and-retry instead of fail-open) before this guarantee is real.

## DZ-003 — New sub-endpoints silently miss the encrypted-endpoints substring match

`AppConfig.encryptedEndpoints` is matched by substring against the request path
(`api_interceptor.dart:134,194`). Confirmed misses:
- `sip/custom/*` (Custom SIP creation/pause/resume) — not covered by the `sip/create` entry, so Custom
  SIP's `amount` and eMandate bank fields ship unencrypted while regular SIP's don't (RULE-SIP-011).
- `sip/resume` — same substring-match gap, sibling of the above.
→ `SIP/BUSINESS_RULES.md` RULE-SIP-011.

❌ Adding a new endpoint under an existing feature path and assuming it inherits that feature's encryption
coverage.
✅ Every new endpoint carrying a `sensitiveFields` key needs its own explicit entry (or a verified prefix
match) in `AppConfig.encryptedEndpoints` — don't assume substring matching does the right thing.

## DZ-004 — Sensitive PII fields not registered in `sensitiveFields`

- Nominee's `id_number` (holds Aadhaar/PAN/Passport/Voter-ID/Driving-License depending on `idType`) ships
  in plaintext to `users/nominee/update` — only `mobile` in that payload matches `sensitiveFields`.
  Currently low real-world impact because the form has no UI to populate it yet (see DZ-code-005 below),
  but the gap goes live the moment that UI ships without also updating `sensitiveFields`.
  → `Nominee/BUSINESS_RULES.md` RULE-NOMINEE-003.
- A Dart string-escape bug (see DZ-005) independently causes `account_no`/`ifsc_code` to also miss
  encryption on the bank-account-creation call.

❌ Trusting an endpoint's presence in `encryptedEndpoints` to mean *every* sensitive-looking field in its
payload is covered — coverage is per-field-name, not per-endpoint.
✅ When adding a new field to an existing "encrypted" endpoint's payload, check `sensitiveFields` for that
exact key name, don't assume.

## DZ-005 — Dart string-escape bug corrupting an API path (and its encryption match)

`withdrawal_service.dart:106` and `:117` use non-raw Dart string literals containing `\v` (real vertical-tab
escape) and other backslash sequences instead of a literal backslash or forward slash:
`'account\verify-bank'`, `'referrals\reward-balance'`. This corrupts the runtime request path AND prevents
the `encryptedEndpoints` substring match, so `account_no`/`ifsc_code` would ship unencrypted if the request
reaches the backend at all. This is the sole bank-account-creation call for both Profile's Bank Details
screen and SIP's bank-account picker. **Flagged unconfirmed at runtime — needs a live network capture to
close out**, but the static read is unambiguous.
→ `Profile/BUSINESS_RULES.md` RULE-PROFILE-010.

❌ Writing a URL path segment as a plain double/single-quoted Dart string without checking for accidental
escape sequences (`\n`, `\t`, `\v`, `\r`, `\b`, `\f` are all real Dart escapes).
✅ Use raw strings (`r'...'`) for any string containing backslashes, or just use forward slashes for URL
paths (Dart doesn't require backslash escaping for `/`).

## DZ-006 — Cross-feature internals imports (layering violation, repeated pattern)

`AGENTS.md` §1 forbids one feature importing another feature's `controller/`/`services/`/`models/`
internals directly. Confirmed instances, found independently across 6+ module brains:
- `home_screen.dart` imports `instant_saving/controller/saving_controller.dart`,
  `profile/profile_controller.dart`, `main/main_screen.dart` directly.
- `nominee_screen.dart:16` imports `features/profile/profile_controller.dart` for pincode lookup.
- `kyc/kyc_flow.dart` imports `features/profile/profile_controller.dart` directly.
- SIP's `BankAccountPickerScreen` imports Profile's `bankAccountsProvider`/`BankAccount` model directly.
- `sip` imports `history`'s `TransactionDetailResponse` model directly (narrower, one-directional,
  explicitly acknowledged in a code comment — the least concerning instance).
- `core/providers/*` (4 confirmed) reach into `features/auth`, `features/home`, `features/market`
  internals — a reverse-direction violation of the same rule, since `core/` should not depend on
  `features/`.
→ `Home/MODULE_BRAIN.md`, `Nominee/CROSS_MODULE_MAP.md`, `KYC` and `SIP` and `Profile` `CROSS_MODULE_MAP.md`
files, `Core/CROSS_MODULE_MAP.md`.

❌ Reaching into another feature's `controller/services/models` folder because "it's already there and
has what I need."
✅ Promote genuinely shared state/logic to `core/` (if used by 3+ features) or `shared/` (pure UI reuse) —
see `AGENTS.md` §1.

## DZ-007 — Dead validation/security code that looks live

- `core/utils/kyc_validator.dart` — zero importers anywhere in `lib/`.
- `MaintenanceGate.check()` (`shared/widgets/maintenance_gate.dart`) — the client-side pre-transaction
  maintenance/alert gate described in `AGENTS.md` §2 as the pattern for payment/withdrawal/SIP flows —
  fully implemented, **zero call sites** anywhere outside its own definition.
- `core/network/interceptors.dart`'s `AuthInterceptor` is never registered on any Dio instance (only
  `ApiSecurityInterceptor` is).
- `core/utils/logger.dart`'s `AppLogger` has no live callers except that same unused interceptor.

❌ Assuming a class exists and is well-formed ⇒ it's actually wired into the request/response path.
✅ Grep for call sites before relying on a security/validation class's behavior — several here are
fully-built but never invoked.

## DZ-008 — Recurring pattern: registered routes with zero in-app navigation ("orphaned routes")

Found independently across 5+ separate module builds — treat as a systemic pattern, not isolated bugs.
Full list in `_SYSTEM/DEAD_CODE_AND_ORPHANED_ROUTES.md`. Worth a deliberate decision (remove the route,
wire it up, or document it as intentionally-reserved) rather than leaving it ambiguous.

## DZ-009 — Silent exception-swallowing that masks real errors as empty/zero states

- `ReferralService.fetchReferralData()` and `RefereeListService.fetchList()` both catch every exception and
  return an empty-shaped model — a network error is indistinguishable from a legitimate "0 referrals"
  state, and makes `RefereeListScreen`'s built error/retry UI effectively dead code.
→ `Referral/BUSINESS_RULES.md` RULE-REFERRAL-006.

❌ Catching a service-layer exception and returning a default/empty model with no error signal propagated.
✅ Map to a `Failure` (per `AGENTS.md` §5) so the UI can distinguish "no data" from "couldn't load data."

## DZ-010 — Hardcoded values that should be server-driven (or vice versa)

- Splash's update dialog hardcodes `forceUpdate: true` regardless of the server's real
  `AppVersionInfo.forceUpdate`/`minVersion` distinction — every detected update is a hard block, even
  though the correct soft/hard logic already exists elsewhere in `app_control_provider.dart`.
  → `Splash/BUSINESS_RULES.md` RULE-SPLASH-007.
- `resumeRoute` after a maintenance interruption is inconsistent: only Splash's call site preserves the
  session-aware login/mpin decision; `maintenance_gate.dart` and `app_control_wrapper.dart` both hardcode
  `resumeRoute: '/login'` even for a still-logged-in user.
  → `Maintenance/BUSINESS_RULES.md` RULE-MAINTENANCE-005.
- GST is genuinely server-driven (`savings/config`'s `gst` field) but a `3.0` literal exists as a pre-load
  UI fallback — not itself wrong, but worth knowing the fallback exists if GST ever changes server-side and
  the fallback isn't updated in lockstep.
→ full catalog in `_SYSTEM/HARDCODED_VALUES.md`.

## DZ-011 — Product/UX-relevant logic bugs (not security, but real)

- `EnquiryFormScreen`'s default ticket type (`'General'`) isn't a key in the `kTicketTypes` map the chip
  picker and submit logic both use — no chip shows selected by default, and an un-tapped submit silently
  files as ticket type 1 ("Enquiry"). This also causes `manage_custom_savings_screen.dart`'s
  `initial_type: 'Custom SIP'` navigation argument to be silently dropped.
  → `Support/BUSINESS_RULES.md` RULE-SUPPORT-003/004.
- `settings_screen.dart:47-51` navigates to `/mpin` with **no `type` argument**, despite `mpin_screen.dart`
  branching on 8 distinct `type` values — could mean toggling MPIN on from Settings hits the wrong mode.
  Unconfirmed, needs a live trace. → `MPIN/COVERAGE_TRACKER.md`, `Settings/BUSINESS_RULES.md`.
- `withdrawal`'s `UpiSelectionScreen` physically lives in the withdrawal module but is unreachable from the
  withdrawal flow (which now uses SIP's `BankAccountPickerScreen`) — its only live caller is Instant
  Saving's purchase flow, and it ignores passed arguments, always routing back into Withdrawal Confirmation
  on submit. → `Withdrawal/FORENSIC_TEMPLATE.md` #6.

## Not Yet Classified

`Main` tab-shell drift (5 nav items live vs. 4 documented, "Market" tab doesn't exist), and the
`daily_savings`/`onboarding`/`support`/`about`/`settings` orphaned-route family are cataloged separately in
`_SYSTEM/DEAD_CODE_AND_ORPHANED_ROUTES.md` rather than duplicated here.
