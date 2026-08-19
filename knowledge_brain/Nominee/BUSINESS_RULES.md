# Business Rules — Nominee

---

### RULE-NOMINEE-001: One nominee record per customer, single create/update endpoint
There is no separate "create" vs "update" API — `POST users/nominee/update` is used for both, with
`NomineeDetails.toJson()` conditionally including `id` only if the local model already has one
(`nominee_model.dart:71`). The server is presumed to upsert based on the authenticated customer,
`unconfirmed` whether the server-side additionally keys on the `id` field when present.
- Code: `lib/features/nominee/services/nominee_service.dart:31-38`, `lib/features/nominee/models/nominee_model.dart:63-83`.

### RULE-NOMINEE-002: Nominee validity is defined as four required fields present
`NomineeDetails.isValid` requires non-empty `name`, `relationship`, `dob`, and `mobile`. This gate
drives whether the screen shows the read-only detail view (valid) or the form (invalid/absent) —
email, ID proof, and address are NEVER required for a nominee to be considered "added."
- Code: `lib/features/nominee/models/nominee_model.dart:86-87`.

### RULE-NOMINEE-003: Only the `mobile` field is field-level encrypted, despite the endpoint being flagged sensitive
`users/nominee/update` is listed in `AppConfig.encryptedEndpoints` (`app_config.dart:70`), which
triggers the interceptor's encryption pass — but `EncryptionService.encryptJson()` only transforms
keys that ALSO appear in `AppConfig.sensitiveFields` (`app_config.dart:74-99`). Of the nominee
payload's keys, only `mobile` (`app_config.dart:96`, tagged "encrypt PII") matches. `id_number`
(which can hold an Aadhaar/PAN/Passport/Voter-ID/DL number depending on `idType`) does NOT match
`aadhaar_number` or `pan`/`pan_number` — it is sent in **plaintext**. This is a real gap per
AGENTS.md §3's stated scope (aadhaar_number, bank_account_number, etc. must be encrypted) if a user's
nominee ID proof is an Aadhaar number entered under the generic `id_number` key.
- Code: `lib/core/config/app_config.dart:47-99`, `lib/core/security/api_interceptor.dart:165-180`,
  `lib/core/security/encryption_service.dart:108-126`.

### RULE-NOMINEE-004: Relationship list is server-driven with a hardcoded fallback, doubled
`nomineeRelationshipsProvider` fetches from `POST users/nominee/relationships`; on any failure
`NomineeService.fetchRelationships()` returns `null`, and the provider substitutes the hardcoded
`nomineeRelationships` const list (8 entries: Father/Mother/Spouse/Son/Daughter/Brother/Sister/Other).
The dropdown widget's own `.when(loading/error)` branches ALSO fall back to the same hardcoded list —
redundant double-fallback, not a bug, but worth simplifying.
- Code: `lib/features/nominee/controller/nominee_controller.dart:28-33`,
  `lib/features/nominee/models/nominee_model.dart:143-152`,
  `lib/features/nominee/screens/nominee_screen.dart:761-765`.

### RULE-NOMINEE-005: Pincode validity gates form submission
If a pincode is entered and the pincode check fails (`_isPincodeValid = false`), the Save/Update
button is disabled regardless of whether all other required fields are valid. Pincode itself is
optional (empty pincode never triggers a check, so `_isPincodeValid` stays at its default `true`).
- Code: `lib/features/nominee/screens/nominee_screen.dart:577` (`onPressed` gate), `:1210-1239` (`_handlePincodeCheck`).

### RULE-NOMINEE-006: ID proof type/number are modeled and submitted, but not user-editable
`NomineeDetails.idType` and `.idNumber` are populated from server data on load, included in the
submit payload, but the form (`_buildFormView`) contains no widget to let the user set or change
them — `_buildDropdownField` (presumably meant for `idType`) is defined but never invoked, and there
is no text field for `idNumber`. Net effect: a user can only ever round-trip an existing ID
type/number set by some other channel (e.g. a legacy screen version, admin backend, or KYC-adjacent
flow); the current form cannot originate one.
- Code: `lib/features/nominee/screens/nominee_screen.dart:838-944` (dead `_buildDropdownField`),
  `:436-606` (`_buildFormView`, no ID-proof widgets), `:99,110-112,133` (idType/idNumber wiring exists
  in populate/clear but not in the form body).

### RULE-NOMINEE-007: DOB is normalized to `yyyy-MM-dd` on submit regardless of server's return format
The server returns DOB as `dd-MM-yyyy` (parsed first in `_parseDob`, with `yyyy-MM-dd` as fallback),
but the app always SENDS `yyyy-MM-dd` on submit (`DateFormat('yyyy-MM-dd').format(_selectedDob!)`).
The DOB picker itself clamps the selectable range to `[DateTime(1900), yesterday]` — no future dates,
no exact-today DOB.
- Code: `lib/features/nominee/screens/nominee_screen.dart:1011-1023` (picker clamp),
  `:1088` (outgoing format), `:1200-1207` (`_parseDob`).

### RULE-NOMINEE-008: Cross-feature dependency on `profile` for pincode lookup
Nominee's pincode-to-location lookup delegates to `profile/profile_controller.dart`'s
`profileProvider.notifier.checkPincode(pincode)` rather than owning its own pincode service — a
direct import of another feature's controller, which `AGENTS.md` §1 calls out to avoid without
recording an exception. Recorded as a known exception in `CROSS_MODULE_MAP.md`.
- Code: `lib/features/nominee/screens/nominee_screen.dart:16,1216`.
