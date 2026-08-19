# State Analysis — Nominee

---

## Riverpod Providers

| Provider | Type | File:Line | Scope | Notes |
|---|---|---|---|---|
| `nomineeServiceProvider` | `Provider<NomineeService>` | `nominee_controller.dart:6` | App-wide | Simple DI |
| `nomineeDetailsProvider` | `FutureProvider<NomineeDetails?>` | `nominee_controller.dart:11` | App-wide, no `autoDispose`/`family` | Doc comment claims "cached for session lifetime," but `NomineeScreen.initState()` invalidates it on every screen open — so in practice this only caches BETWEEN re-entries within the same screen instance's lifetime, not across screen visits |
| `hasNomineeProvider` | `Provider<bool>` | `nominee_controller.dart:17` | App-wide | Derived from `nomineeDetailsProvider`; not observed to be watched anywhere in the scanned code — see `CROSS_MODULE_MAP.md` reverse-deps note |
| `nomineeRelationshipsProvider` | `FutureProvider<List<NomineeRelationship>>` | `nominee_controller.dart:28` | App-wide | Also invalidated on every `NomineeScreen` open |

No `StateNotifierProvider`/`AsyncNotifier` in this module — all server-derived state is plain
`FutureProvider`, and all screen-editing state (form controllers, edit-mode flags) lives in
`_NomineeScreenState`, NOT in Riverpod. This differs from the pattern AGENTS.md §1 recommends
("Prefer `StateNotifier`/`AsyncNotifier`... over ad-hoc `setState` for non-trivial screens") — this
screen has non-trivial async loading/error/edit states and uses `setState` throughout for the mutable
form/editing portion. Not flagged as a hard violation (the read-side IS Riverpod, `FutureProvider`),
but the local `setState`-heavy form logic is a candidate for a future `StateNotifier` refactor if this
screen grows more complex.

## Model Shapes

### `NomineeDetails` (`nominee_model.dart:5-126`)
| Field | Type | Required for `isValid` | JSON key | Notes |
|---|---|---|---|---|
| `id` | `int?` | No | `id` (omitted from `toJson` if null) | Present only after first successful create |
| `name` | `String` | Yes | `name` | |
| `relationship` | `String` | Yes | `relationship` | Human-readable name (e.g. "Father") |
| `relationshipId` | `int?` | No | `relationship_id` (omitted if null) | Matched by name lookup against the relationships list on dropdown change |
| `dob` | `String` | Yes | `dob` | Stored as whatever was parsed/formatted — see RULE-NOMINEE-007 |
| `mobile` | `String` | Yes | `mobile` | **RSA-OAEP-SHA256 encrypted on submit** (see `BUSINESS_RULES.md` RULE-NOMINEE-003) |
| `email` | `String?` | No | `email` (omitted if null/empty) | Validated with a regex if provided |
| `idType` | `String?` | No | `id_type` (omitted if null/empty) | One of `nomineeIdProofTypes` — no form UI to set it currently |
| `idNumber` | `String?` | No | `id_number` (omitted if null/empty) | **Plaintext even for Aadhaar/PAN values** — no form UI to set it currently |
| `address` | `String?` | No | `address` (omitted if null/empty) | Multi-line free text |
| `city` | `String?` | No | `city` (omitted if null/empty) | Auto-filled by pincode check, read-only in the form |
| `state` | `String?` | No | `state` (omitted if null/empty) | Auto-filled by pincode check, read-only in the form |
| `pincode` | `String?` | No | `pincode` (omitted if null/empty) | 6-digit, triggers `_handlePincodeCheck` |
| `idCity` | `int?` | No | `id_city` (omitted if null) | Location ID from pincode check |
| `idState` | `int?` | No | `id_state` (omitted if null) | Location ID from pincode check |
| `idCountry` | `int?` | No | `id_country` (ALWAYS included, `?? 101`) | Only field with a non-null default baked into `toJson()` |

`fromJson` uses `?.toString()` coercion on every `String?` field — defensive against the server
returning a non-string JSON type for any of these keys.

### `NomineeRelationship` (`nominee_model.dart:129-140`)
| Field | Type | Notes |
|---|---|---|
| `id` | `int` | Defaults to `0` if missing/malformed |
| `name` | `String` | Defaults to `''` |

### Hardcoded fallback constants (`nominee_model.dart:143-162`)
- `nomineeRelationships`: 8 entries (Father, Mother, Spouse, Son, Daughter, Brother, Sister, Other), IDs 1-8.
- `nomineeIdProofTypes`: 6 entries (Aadhaar, PAN, Voter ID, Passport, Driving License, Others) — defined
  but, per RULE-NOMINEE-006, currently has no consuming widget in the form.

## Secure Storage Keys Touched

None. This module does not read or write `flutter_secure_storage` directly — token attachment for
its API calls is handled generically by the interceptor, and no nominee-specific data is cached
locally beyond in-memory Riverpod provider state (which is cleared on process death / provider
invalidation, never persisted).

## Local (non-Riverpod) State — `_NomineeScreenState`

| Field | Type | Purpose |
|---|---|---|
| `_formKey` | `GlobalKey<FormState>` | Not observed to be validated via `_formKey.currentState.validate()` in `_handleSubmit` — validation is done manually field-by-field with `AppToast` messages instead; `unconfirmed` whether the `Form`/`_formKey` wiring is vestigial |
| `_nameCtrl`, `_mobileCtrl`, `_emailCtrl`, `_idNumberCtrl`, `_addressCtrl`, `_cityCtrl`, `_stateCtrl`, `_pincodeCtrl` | `TextEditingController` | Form field backing |
| `_selectedRelationship` / `_selectedRelationshipId` | `String?` / `int?` | Relationship dropdown selection |
| `_selectedIdType` | `String?` | Populated/cleared but no UI to change it (RULE-NOMINEE-006) |
| `_selectedDob` | `DateTime?` | DOB picker result |
| `_isEditing` | `bool` | Toggles detail view ↔ form view when a valid nominee already exists |
| `_isSaving` | `bool` | Submit-in-flight guard, disables the button |
| `_isInitialized` | `bool` | Guards against re-populating the form on every rebuild |
| `_isPincodeChecking` | `bool` | Pincode-check-in-flight guard |
| `_isPincodeValid` | `bool` | Gates submit button; `true` by default (only flips false after a failed check) |
| `_idCity`, `_idState`, `_idCountry`, `_nomineeId` | `int?` | Location/record IDs carried through from either existing data or pincode check |
| `_fadeController` | `AnimationController` | Simple fade-in on screen build, unrelated to data state |
