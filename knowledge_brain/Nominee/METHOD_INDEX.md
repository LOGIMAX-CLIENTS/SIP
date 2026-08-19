# Method Index — Nominee

Alphabetical by class.

---

## `NomineeDetails` (model) — `lib/features/nominee/models/nominee_model.dart`

| Method | File:Line | Purpose | Callers |
|---|---|---|---|
| `NomineeDetails.fromJson(Map)` | `nominee_model.dart:42` | Deserialize `users/nominee/details` response | `NomineeService.getNomineeDetails` |
| `toJson()` | `nominee_model.dart:63` | Serialize for `users/nominee/update` — omits null/empty optional fields, always includes `id_country` (default `101`) | `NomineeService.updateNominee` (via `nominee_screen.dart:1111`) |
| `isValid` (getter) | `nominee_model.dart:86` | `name && relationship && dob && mobile` all non-empty | `nomineeController.hasNomineeProvider`, `nominee_screen.dart` (`hasNominee` check, several places) |
| `copyWith(...)` | `nominee_model.dart:89` | Immutable update helper | Not observed to be called anywhere in read files — `unconfirmed`/likely unused currently |

## `NomineeRelationship` (model) — `lib/features/nominee/models/nominee_model.dart`

| Method | File:Line | Purpose | Callers |
|---|---|---|---|
| `NomineeRelationship.fromJson(Map)` | `nominee_model.dart:135` | Deserialize one item from `users/nominee/relationships` | `NomineeService.fetchRelationships` |

## `NomineeService` — `lib/features/nominee/services/nominee_service.dart`

| Method | File:Line | Endpoint | Purpose | Callers |
|---|---|---|---|---|
| `getNomineeDetails()` | `nominee_service.dart:13` | `POST users/nominee/details` | Fetch nominee; returns `null` if API reports success but data is empty/name+relationship both null | `nomineeDetailsProvider` (`nominee_controller.dart:13`) |
| `updateNominee(NomineeDetails)` | `nominee_service.dart:31` | `POST users/nominee/update` | Create/update; returns the raw `response.data` map (caller inspects `success`/`error`/`message`) | `_handleSubmit` (`nominee_screen.dart:1111`) |
| `fetchRelationships()` | `nominee_service.dart:45` | `POST users/nominee/relationships` | Fetch dynamic relationship list; returns `null` on any exception or empty result | `nomineeRelationshipsProvider` (`nominee_controller.dart:31`) |

## Providers — `lib/features/nominee/controller/nominee_controller.dart`

| Provider | File:Line | Type | Purpose |
|---|---|---|---|
| `nomineeServiceProvider` | `nominee_controller.dart:6` | `Provider<NomineeService>` | DI |
| `nomineeDetailsProvider` | `nominee_controller.dart:11` | `FutureProvider<NomineeDetails?>` | Fetches nominee on first watch; doc comment claims session-lifetime cache, but `NomineeScreen` invalidates it on every open (see `MODULE_BRAIN.md` §7) |
| `hasNomineeProvider` | `nominee_controller.dart:17` | `Provider<bool>` | `nomineeAsync.maybeWhen(data: nominee != null && nominee.isValid, orElse: false)` — not observed to be watched anywhere in the screen (screen computes its own `hasNominee` locally); `unconfirmed`/possibly unused outside this module, could be intended for e.g. a Profile-screen "nominee added" indicator |
| `nomineeRelationshipsProvider` | `nominee_controller.dart:28` | `FutureProvider<List<NomineeRelationship>>` | Server list with fallback to hardcoded `nomineeRelationships` on `null` result |

## `NomineeScreen` / `_NomineeScreenState` — `lib/features/nominee/screens/nominee_screen.dart`

| Method | File:Line | Purpose |
|---|---|---|
| `initState()` | `nominee_screen.dart:64` | Starts fade animation; post-frame invalidates both providers to force a fresh fetch |
| `_populateFields(NomineeDetails)` | `nominee_screen.dart:94` | Fills form controllers + selection state from server data |
| `_clearForm()` | `nominee_screen.dart:121` | Resets all form controllers/selection state (used when server returns empty nominee) |
| `build()` | `nominee_screen.dart:142` | `ref.listen` seed-on-load + `nomineeAsync.when` render switch |
| `_buildDetailView(NomineeDetails)` | `nominee_screen.dart:213` | Read-only card + Edit button |
| `_buildDetailRow(...)` | `nominee_screen.dart:349` | Row/column layout helper for the detail card |
| `_buildFormView(NomineeDetails?)` | `nominee_screen.dart:436` | Add/edit form: name, relationship, DOB, mobile, email, pincode(+Check), state/city (read-only, post-check), address, submit |
| `_buildSectionLabel(String)` | `nominee_screen.dart:610` | Section header text |
| `_buildTextField(...)` | `nominee_screen.dart:622` | Generic text field widget builder (name/mobile/email/pincode/address all route through this) |
| `_buildRelationshipDropdown()` | `nominee_screen.dart:760` | Relationship dropdown, sourced from `nomineeRelationshipsProvider` (fallback to hardcoded list on loading/error) |
| `_buildDropdownField(...)` | `nominee_screen.dart:838` | Generic dropdown widget builder — **defined but never called** (dead code; likely intended for ID-type) |
| `_buildDateField()` | `nominee_screen.dart:946` | DOB picker trigger + display |
| `_pickDate()` | `nominee_screen.dart:1011` | `showDatePicker` with clamped initial date (1900 → yesterday) |
| `_handleSubmit()` | `nominee_screen.dart:1044` | Client-side validation → builds `NomineeDetails` → `NomineeService.updateNominee()` → success/error toast, invalidates `nomineeDetailsProvider` on success |
| `_buildErrorState()` | `nominee_screen.dart:1152` | Error card + Retry (invalidates `nomineeDetailsProvider`) |
| `_formatDisplayDate(String)` | `nominee_screen.dart:1190` | DOB display formatting via `_parseDob` |
| `_parseDob(String)` | `nominee_screen.dart:1200` | Parses `dd-MM-yyyy` (server) first, falls back to `yyyy-MM-dd` |
| `_handlePincodeCheck()` | `nominee_screen.dart:1210` | Calls **`profile` module's** `pc.profileProvider.notifier.checkPincode(pincode)` — cross-feature call, see `CROSS_MODULE_MAP.md` |
| `_buildReadOnlyField(...)` | `nominee_screen.dart:1242` | Read-only State/City display, auto-filled post pincode-check |
