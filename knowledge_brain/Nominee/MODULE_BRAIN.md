# Module Brain — Nominee

> **Built**: 2026-08-19 (Round 1 — Build Mode) | **Complexity**: Low-Medium | **Status**: 🟢

---

## 1. Module Overview

Single-beneficiary management for gold/silver holdings. One nominee record per customer — add, view,
and edit via one form/detail screen. Standard feature-first layout (`controller/`, `models/`,
`screens/`, `services/`) fully self-contained EXCEPT for one direct cross-feature call into the
`profile` module for pincode lookup (see Cross-Module note in `CROSS_MODULE_MAP.md`). The
`mobile` field is field-level RSA-encrypted on submit; the rest of the payload is not.

### File Map
| Layer | File | Purpose |
|---|---|---|
| Controller/Providers | `lib/features/nominee/controller/nominee_controller.dart` | `nomineeServiceProvider`, `nomineeDetailsProvider` (FutureProvider), `hasNomineeProvider`, `nomineeRelationshipsProvider` |
| Model | `lib/features/nominee/models/nominee_model.dart` | `NomineeDetails`, `NomineeRelationship`, hardcoded fallback lists `nomineeRelationships` / `nomineeIdProofTypes` |
| Screen | `lib/features/nominee/screens/nominee_screen.dart` | View mode (existing nominee) + Form mode (add/edit), pincode auto-fill |
| Service | `lib/features/nominee/services/nominee_service.dart` | `getNomineeDetails()`, `updateNominee()`, `fetchRelationships()` |
| Route | `lib/routes/app_router.dart:120` (const `nominee = '/nominee'`), builder at `app_router.dart:356` | |
| Entry point | `lib/features/profile/profile_screen.dart:228-233` | "Nominee Details" menu item |

### Connection Flow
```
ProfileScreen menu → Navigator.pushNamed(AppRouter.nominee)
  → NomineeScreen.initState() → ref.invalidate(nomineeDetailsProvider) + nomineeRelationshipsProvider
       (forces a fresh fetch every time the screen opens — no session cache reuse on screen entry,
        DESPITE the provider's own doc comment calling it "cached for the session lifetime")
  → nomineeDetailsProvider (FutureProvider) → NomineeService.getNomineeDetails()
       → POST users/nominee/details → NomineeDetails.fromJson, or null if empty/absent
  → build(): nomineeAsync.when(loading/error/data)
       hasNominee = nominee != null && nominee.isValid
       showForm = !hasNominee || _isEditing
       → showForm ? _buildFormView() : _buildDetailView()
  → nomineeRelationshipsProvider (FutureProvider) → NomineeService.fetchRelationships()
       → POST users/nominee/relationships → list of {id, name}, falls back to hardcoded
         `nomineeRelationships` const list on any failure
  → User submits form → _handleSubmit() client-side validation → NomineeService.updateNominee()
       → POST users/nominee/update (payload built via NomineeDetails.toJson())
       → ApiSecurityInterceptor: path matches AppConfig.encryptedEndpoints ('users/nominee/update')
         → EncryptionService.encryptJson() walks the map; only the 'mobile' key matches
           AppConfig.sensitiveFields and gets RSA-OAEP-SHA256 encrypted — all other fields
           (name, relationship, dob, email, id_type, id_number, address, city, state, pincode,
           id_city, id_state, id_country) travel as plain JSON
  → On success: ref.invalidate(nomineeDetailsProvider) (refetch), exit edit mode, success toast
  → On failure: server error message surfaced via AppToast (error/data/message fallback chain)
```

---

## 2. Screens & Routes

| Screen | Route | File | Purpose |
|---|---|---|---|
| NomineeScreen | `/nominee` | `lib/features/nominee/screens/nominee_screen.dart` | Add/view/edit the single nominee record |

Screen behavior:
- Two render modes driven by `hasNominee` (server data valid) and `_isEditing` (local toggle):
  **Detail view** (read-only card with an Edit button) when a valid nominee exists and not editing;
  **Form view** (empty or pre-filled) otherwise.
- `ref.listen` on `nomineeDetailsProvider` seeds/clears the form controllers whenever new data
  arrives — handles both "existing valid nominee" (populate) and "server returned empty" (clear stale
  fields) cases (`nominee_screen.dart:146-160`).
- Pincode field has an inline "Check" action (`_handlePincodeCheck`) that calls into
  **`profile` module's** `profileProvider.notifier.checkPincode(pincode)` to auto-fill State/City and
  capture `id_city`/`id_state`/`id_country` — see Cross-Module note.
- Client-side validation before submit: name non-empty & ≥2 chars, relationship selected, DOB
  selected, mobile non-empty & exactly 10 digits (`_handleSubmit`, `nominee_screen.dart:1044-1079`).
  Email, ID type/number, address, pincode are optional.
- **ID proof fields are collected in the model but have no form UI**: `_selectedIdType` and
  `_idNumberCtrl` are declared, populated from server data, cleared, and included in the submit
  payload — but `_buildFormView()` never renders a widget for either. `_buildDropdownField()`
  (defined at `nominee_screen.dart:838`, presumably meant for the ID-type dropdown) is dead code —
  never called. See `BUSINESS_RULES.md` RULE-NOMINEE-006.
- DOB parsing accepts both `dd-MM-yyyy` (server format) and `yyyy-MM-dd` as a fallback
  (`_parseDob`, `nominee_screen.dart:1200-1207`); DOB is SENT to the server as `yyyy-MM-dd`
  (`DateFormat('yyyy-MM-dd').format(_selectedDob!)`, `nominee_screen.dart:1088`).

---

## 3. State & Providers Summary

Full detail in `STATE_ANALYSIS.md`. Headline: `nomineeDetailsProvider` is a plain `FutureProvider`
(not a `StateNotifierProvider`) — refresh happens via `ref.invalidate`, not a `.notifier` method call.
No dedicated `NomineeState` class; the screen's own `State` object holds all editing-mode local state
(form controllers, `_isEditing`, `_isSaving`, location IDs).

---

## 4. API Integrations

| API | Method (service) | Purpose | Encrypted? |
|---|---|---|---|
| `POST users/nominee/details` | `NomineeService.getNomineeDetails()` | Fetch existing nominee | No |
| `POST users/nominee/update` | `NomineeService.updateNominee(nominee)` | Create or update (same endpoint for both — no separate create endpoint) | **Yes** — endpoint is in `AppConfig.encryptedEndpoints`; only the `mobile` field within the payload is transformed (it's the only key present that also appears in `AppConfig.sensitiveFields`) |
| `POST users/nominee/relationships` | `NomineeService.fetchRelationships()` | Dynamic relationship list (id+name) | No |

Field collected: name, relationship (+ `relationship_id`), DOB, mobile, email (optional), ID proof
type + number (optional, collected in model, **no form UI** — see above), address/city/state/pincode
(optional), `id_city`/`id_state`/`id_country` (location IDs from pincode lookup or existing data,
`id_country` defaults to `101` if unset — `unconfirmed` which country code `101` maps to; treat as
India based on app context but not verified against a country-code table in this codebase).

---

## 5. Business Rules

See `BUSINESS_RULES.md` for the full RULE-NOMINEE-NNN list. Headline: `mobile` is the ONLY nominee
field that gets RSA-OAEP field-level encryption per AGENTS.md §3, despite the endpoint itself being
flagged as a sensitive/encrypted endpoint — this is a deliberate per-field selection, not "encrypt the
whole payload."

---

## 6. Cross-Module Dependencies

Summary (full detail `CROSS_MODULE_MAP.md`): `Nominee` imports `profile/profile_controller.dart`
directly (`nominee_screen.dart:16`, `import '../../profile/profile_controller.dart' as pc;`) to reuse
`profileProvider.notifier.checkPincode()` for the pincode-to-state/city lookup. This is a direct
feature-to-feature import, which `AGENTS.md` §1 flags as something to avoid ("never import one
feature's internals directly from another feature... Record any exception found in
`CROSS_MODULE_MAP.md`") — recorded there as a known violation. `Nominee` also depends on
`core/network/api_client.dart` and `core/security/secure_logger.dart`.

---

## 7. Known Risks / Top Risks

| Risk | Severity | Description |
|---|---|---|
| ID proof type/number collected but no form UI to set them | 🟡 Medium | `idType`/`idNumber` fields exist end-to-end in the model and submit payload but the form never lets a user enter them (dead `_buildDropdownField` method, no matching text field for ID number). If the server treats these as informational-only this is cosmetic; if any downstream flow (claims processing) expects them, this is a functional gap. `unconfirmed` server-side expectation. |
| Direct cross-feature import (`profile/profile_controller.dart`) | 🟡 Medium | Violates the stated feature-isolation convention in `AGENTS.md` §1. A change to `profileProvider`'s shape or `checkPincode`'s signature will silently break Nominee's pincode auto-fill with no compile-time boundary warning at the architecture level (Dart will still catch a signature break, but reviewers may not think to check Nominee when touching Profile). |
| Only `mobile` is encrypted despite the endpoint being "sensitive" | 🟢 Low (by design, but worth flagging) | `email`, `address`, `id_number` (which could be an Aadhaar/PAN/Passport number depending on `idType`) are sent in plaintext. `pan`/`aadhaar_number` ARE in `AppConfig.sensitiveFields`, but the nominee model's field is generically named `id_number` — it does NOT match either sensitive-field key, so even if a user enters an Aadhaar number as their nominee's ID proof, it is NOT encrypted. This is a genuine PII-exposure gap if `idType == 'Aadhaar'`. |
| Provider doc comment vs actual behavior mismatch | 🟢 Low | `nomineeDetailsProvider`'s doc comment says "cached for the session lifetime... use `ref.invalidate` to force refresh" (`nominee_controller.dart:9-10`), but `NomineeScreen.initState()` unconditionally invalidates BOTH providers on every screen open (`nominee_screen.dart:74-76`) — so in practice there is no session-level caching benefit for this screen; the comment describes an aspiration/general pattern rather than this screen's actual usage. |
| `_isInitialized` re-population edge case | 🟢 Low | Both `ref.listen` (line 146-160) and the `data:` builder branch (line 184-190) can call `_populateFields`/set `_isInitialized` — two separate code paths achieving similar effect; not observed to cause a bug in this read-through but is a duplication worth simplifying. |

---

## 8. Drift vs `STARTGOLD_DOCUMENTATION.md` §3.34

The hand-written doc states: Route `/nominee`, API `POST users/nominee/update — Encrypted`. Both
confirmed correct. **Gap, not contradiction**: the doc does not mention `users/nominee/details`
(fetch) or `users/nominee/relationships` (dynamic relationship list with hardcoded fallback), and does
not note that encryption is applied to only the `mobile` field within the payload rather than the
whole payload. Flagged in `_OVERVIEW/BUILD_SUMMARY.md`.

---

## 9. See Also
- `METHOD_INDEX.md` — every public method, file:line, callers
- `DATA_FLOW.md` — end-to-end flows with file:line
- `BUSINESS_RULES.md` — RULE-NOMINEE-NNN
- `CROSS_MODULE_MAP.md` — Mermaid dependency graph, `profile` cross-import
- `STATE_ANALYSIS.md` — Riverpod provider/model shapes
- `FORENSIC_TEMPLATE.md` — symptom → suspect lookup
- `COVERAGE_TRACKER.md` — round history
