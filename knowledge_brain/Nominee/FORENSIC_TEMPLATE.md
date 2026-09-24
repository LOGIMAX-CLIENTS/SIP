# Forensic Template — Nominee

Symptom → check first → likely suspects. Use alongside `DATA_FLOW.md` for the exact call chain and
`STATE_ANALYSIS.md` for provider/model shapes.

---

## Symptom: "Nominee screen always shows the form, never the saved detail view (even after a successful save)"

**Check first**: Is `NomineeDetails.isValid` actually returning `true` for the fetched data? It
requires `name`, `relationship`, `dob`, AND `mobile` all non-empty — log the raw
`response.data['data']` from `POST users/nominee/details` to confirm all four keys are present and
non-empty strings server-side.

**Likely suspects**:
1. Server returned the nominee with one of the four required fields null/empty (e.g. `dob` in an
   unexpected format that `fromJson` coerces to `''` via `?.toString() ?? ''`... actually
   `fromJson` uses `json['dob']?.toString() ?? ''`, so a genuinely-missing key becomes `''`, failing
   `isValid`).
2. `getNomineeDetails()`'s emptiness check treats the response as absent: it returns `null` if
   `data.isEmpty || (data['name']==null && data['relationship']==null)` — a response with SOME fields
   present but both `name` and `relationship` null would still short-circuit to `null` even if e.g.
   `mobile` and `dob` are present (`nominee_service.dart:20-24`).
3. `NomineeScreen.initState()` invalidates the provider every time — if the invalidate races with a
   just-completed `updateNominee()` call before the server has actually persisted the write, the
   refetch could return stale (pre-save) data. Check timing between `ref.invalidate` in `_handleSubmit`
   success branch (`nominee_screen.dart:1116`) and any immediately-following navigation/rebuild.

---

## Symptom: "Nominee/update API field not encrypted" (audit / security review finding)

**Check first**: Confirm which specific field was expected to be encrypted. Per
`AGENTS.md` §3 and `AppConfig.sensitiveFields` (`app_config.dart:74-99`), only a payload KEY that
literally matches one of the listed strings gets transformed — `mobile` matches, but generic fields
like `id_number`, `email`, `address` do NOT, even though `users/nominee/update` as a whole is in
`encryptedEndpoints`.

**Likely suspects** (in order of how this typically gets reported):
1. Auditor assumed "encrypted endpoint" means "entire payload encrypted" — clarify the per-field model:
   `isSensitive` (endpoint-level) gates WHETHER the encryption pass runs at all;
   `AppConfig.sensitiveFields` (field-level) gates WHICH keys within the payload actually get
   transformed. See RULE-NOMINEE-003.
2. A nominee's Aadhaar/PAN number entered via `idNumber`/`id_number` is genuinely sent in plaintext —
   this is a real finding, not a false positive, if the auditor's concern is specifically about
   government-ID numbers. Confirm by checking the raw outgoing request body (or `SecureLogger`'s
   request log, `SecureLogger.logRequest`) for an unencrypted `id_number` value.
3. If the concern is `mobile` specifically NOT being encrypted, check that `EncryptionService.isRsaReady`
   was true at request time — if the RSA public key hadn't loaded yet (a slow/failed
   `fetchAndCachePublicKey()`), `EncryptionService.encryptJson` might fall back to a different algorithm
   (AES-256-CBC per the log message at `api_interceptor.dart:174-175`) rather than skip encryption
   entirely — confirm via the `SECURE LAYER: Payload encrypted (...)` debug log which algorithm ran.

---

## Symptom: "Pincode check fails or never returns state/city, even for a valid pincode"

**Check first**: This delegates entirely to `profile`'s `checkPincode` — the bug may not be in Nominee
at all. Reproduce the same pincode check from the Profile module's own bank/address screen (if one
exists) to see if it also fails there.

**Likely suspects**:
1. Genuine cross-module dependency issue — if `profile_controller.dart`'s `checkPincode` signature or
   response shape changed, Nominee's `_handlePincodeCheck` (`nominee_screen.dart:1210-1239`) reads
   `result['success']`, `result['data']['state']/['city']/['id_city']/['id_state']/['id_country']`,
   `result['message']` — any shape drift here breaks silently with just a generic toast.
2. `int.tryParse(data['id_city'] ?? '')` etc. — if the Profile module started returning these as
   actual `int` JSON types instead of strings, `tryParse` on a non-string would throw or the `?? ''`
   fallback masks a real value; check the actual JSON type returned.
3. Network/session issue unrelated to Nominee — `checkPincode` goes through the same `ApiClient`/
   interceptor chain as everything else (401 refresh, 409 force-logout).

---

## Symptom: "Can't set/edit nominee's ID proof type or number from the app"

**Check first**: This is EXPECTED current behavior, not necessarily a bug — see RULE-NOMINEE-006.
Confirm this is being reported as a regression (used to work) vs. a feature request (never worked).

**Likely suspects**:
1. If reported as a regression: check git history / prior versions of `nominee_screen.dart` for a
   removed `_buildDropdownField(...)` call and ID-number text field — `_buildDropdownField` itself
   still exists (unused), suggesting the UI was removed but the helper method and model fields were
   left behind, OR the UI was never finished.
2. If a feature request: the fix is to wire `_buildDropdownField` (or a similar pattern to
   `_buildRelationshipDropdown`) using `nomineeIdProofTypes` for `idType`, and add a
   `_buildTextField` for `_idNumberCtrl` similar to the mobile/email fields — and strongly consider
   whether `id_number` should be added to `AppConfig.sensitiveFields` at the same time given
   RULE-NOMINEE-003's plaintext-Aadhaar gap.

---

## Symptom: "Nominee form shows stale/wrong data momentarily on screen open, then corrects itself"

**Check first**: This is a known duplication — both the `ref.listen` block and the `data:` builder
branch in `build()` can populate the form, and `initState`'s post-frame invalidation means the FIRST
build may render with old/empty provider data before the fresh fetch resolves.

**Likely suspects**:
1. Expected transient loading-state flash — confirm `nomineeAsync.when(loading: ...)` is rendering the
   spinner correctly during this window rather than a half-populated form.
2. If a half-populated or previous-user's form data flashes: check whether `_isInitialized` was left
   `true` from a PREVIOUS navigation to this screen without the state object being fully disposed
   (e.g. if the screen is kept alive by a `PageView`/`IndexedStack` rather than pushed/popped fresh
   each time) — `_isInitialized` is instance state on `_NomineeScreenState`, so if the widget instance
   is reused, stale data could show before `ref.invalidate`'s refetch completes.

---

## Symptom: "Save button stuck disabled even though all required fields look filled in"

**Check first**: `onPressed: (_isSaving || !_isPincodeValid) ? null : _handleSubmit` — the gate is
`_isSaving` OR `!_isPincodeValid`, NOT a full-form-validity check. A pincode that was checked once and
failed (`_isPincodeValid = false`) stays disabled even if the user then clears the pincode field
entirely (there's no code path that resets `_isPincodeValid` back to `true` on clearing, only
`onChanged` resetting it when the pincode field's callback fires — verify `onChanged: (_) { if
(!_isPincodeValid) setState(() => _isPincodeValid = true); }` at `nominee_screen.dart:521-525` actually
fires for a clear/empty edit, since `TextFormField.onChanged` does fire on any text change including
deletion to empty).

**Likely suspects**:
1. `_isSaving` stuck `true` from a previous submit that threw before reaching the `finally` block —
   check the `finally { if (mounted) setState(() => _isSaving = false); }` at `nominee_screen.dart:1147`
   actually ran (it should, `finally` always executes, but a hot-reload during a pending Future could
   leave stale widget state in dev).
2. `_isPincodeValid == false` from a genuinely failed check, and the user hasn't re-triggered a
   passing check or cleared the field to reset it.
