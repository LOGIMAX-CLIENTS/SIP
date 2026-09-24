# Data Flow — Nominee

---

## Flow 1: Screen open → fetch existing nominee → view or form mode

```
ProfileScreen "Nominee Details" menu tap                            profile_screen.dart:228-233
  └─ Navigator.pushNamed(context, AppRouter.nominee)

NomineeScreen.initState()                                           nominee_screen.dart:64-77
  └─ WidgetsBinding.addPostFrameCallback
       ├─ ref.invalidate(nomineeDetailsProvider)
       └─ ref.invalidate(nomineeRelationshipsProvider)

nomineeDetailsProvider rebuilds (FutureProvider)                    nominee_controller.dart:11-14
  └─ NomineeService.getNomineeDetails()                              nominee_service.dart:13
       └─ ApiClient.post('users/nominee/details')
            ├─ response.data['success']==true && data['data'] is non-empty Map with name/relationship
            │    → NomineeDetails.fromJson(data)
            └─ else (data empty, or name+relationship both null) → return null

build(): nomineeAsync.when(...)                                     nominee_screen.dart:143-208
  ├─ loading → CircularProgressIndicator
  ├─ error → _buildErrorState() (Retry re-invalidates the provider)
  └─ data(nominee):
       hasNominee = nominee != null && nominee.isValid
       showForm = !hasNominee || _isEditing
       ├─ !_isInitialized && hasNominee → post-frame _populateFields(nominee) + setState(_isInitialized=true)
       └─ showForm ? _buildFormView(nominee) : _buildDetailView(nominee)

ALSO: ref.listen<AsyncValue<NomineeDetails?>>(nomineeDetailsProvider, ...) fires independently
  └─ next.whenData((nominee) => nominee!=null && nominee.isValid
       ? (!_isInitialized ? _populateFields+mark initialized : noop)
       : (_clearForm(); _isInitialized=false))
```
Note the TWO separate code paths that can call `_populateFields`/set `_isInitialized` (the `ref.listen`
block and the `data:` builder branch) — both guard on `!_isInitialized`, so they don't double-populate
in practice, but it's duplicated logic (see `MODULE_BRAIN.md` §7).

---

## Flow 2: Pincode check → auto-fill State/City (cross-feature call into `profile`)

```
User types 6 digits in Pincode field, taps "Check" action           nominee_screen.dart:518-519
  └─ _handlePincodeCheck()                                          nominee_screen.dart:1210
       ├─ setState(_isPincodeChecking = true)
       └─ ref.read(pc.profileProvider.notifier).checkPincode(pincode)   ← CROSS-FEATURE CALL
            (pc = import '../../profile/profile_controller.dart' as pc, nominee_screen.dart:16)
       ├─ [success] setState:
       │    _isPincodeValid = true
       │    _stateCtrl.text / _cityCtrl.text = from result['data']
       │    _idCity / _idState = int.tryParse(...)
       │    _idCountry = int.tryParse(...) ?? 101
       └─ [failure] setState:
            _isPincodeValid = false; _stateCtrl/_cityCtrl cleared
            AppToast.show(result['message'] ?? 'Pincode not found.', error)
```
`_isPincodeValid == false` disables the Save/Update button (`nominee_screen.dart:577`,
`onPressed: (_isSaving || !_isPincodeValid) ? null : _handleSubmit`).

---

## Flow 3: Submit (add or update) → validation → encrypted API call → refresh

```
User taps "Save Nominee" / "Update Nominee"                          nominee_screen.dart:572-581
  └─ _handleSubmit()                                                 nominee_screen.dart:1044
       ├─ Client-side validation (name ≥2 chars, relationship selected, DOB selected,
       │   mobile exactly 10 digits) — each failure shows an AppToast and returns early
       ├─ setState(_isSaving = true)
       ├─ Build NomineeDetails(...) from controllers/selections
       │    dob formatted as 'yyyy-MM-dd' for the outgoing payload (regardless of how it displays)
       ├─ NomineeService.updateNominee(nominee)                      nominee_service.dart:31
       │    └─ ApiClient.post('users/nominee/update', data: nominee.toJson())
       │         └─ ApiSecurityInterceptor.onRequest (api_interceptor.dart:132-138,165-180)
       │              ├─ isSensitive = AppConfig.encryptedEndpoints.any(path.contains)
       │              │    → TRUE ('users/nominee/update' is in the list, app_config.dart:70)
       │              ├─ EncryptionService.encryptJson(mapData)
       │              │    walks every key; only keys present in AppConfig.sensitiveFields are
       │              │    transformed. Of the nominee payload's keys (name, relationship,
       │              │    relationship_id, dob, mobile, id_country, + optional email/id_type/
       │              │    id_number/address/city/state/pincode/id_city/id_state), ONLY 'mobile'
       │              │    matches (app_config.dart:96) → RSA-OAEP-SHA256 encrypted in place
       │              └─ all other fields pass through as plaintext JSON
       ├─ [response.success == true]
       │    ref.invalidate(nomineeDetailsProvider)  → triggers Flow 1 again (refetch)
       │    setState(_isEditing = false)
       │    AppToast.show(response['message'] ?? 'Nominee updated successfully', success)
       └─ [response.success != true]
            serverMsg = error.message ?? data.message ?? response.message ?? 'Failed to update nominee'
            AppToast.show(serverMsg, error)
       finally: setState(_isSaving = false)
```
Exception path (network error, thrown before a response is even parsed): caught, logged via
`SecureLogger.e('NOMINEE: Update failed: $e')`, generic AppToast shown
("Something went wrong. Please try again.") — raw exception text is never shown to the user here
(unlike Notifications' `NotificationState.error`, which does store the raw string, though it's also
unused in that screen's rendered text).

---

## Flow 4: Relationship dropdown population with fallback

```
_buildRelationshipDropdown()                                         nominee_screen.dart:760-836
  └─ ref.watch(nomineeRelationshipsProvider).when(
       data: (list) => list,
       loading: () => nomineeRelationships (hardcoded const fallback, nominee_model.dart:143-152),
       error: (_, __) => nomineeRelationships (same hardcoded fallback)
     )
  └─ DropdownButtonFormField<String> items built from relationships list
       onChanged → sets both _selectedRelationship (name string, sent as 'relationship') AND
                   _selectedRelationshipId (matched by name lookup, sent as 'relationship_id')
```
Underlying fetch: `nomineeRelationshipsProvider` → `NomineeService.fetchRelationships()` →
`POST users/nominee/relationships` → on ANY exception, returns `null`, and the provider itself
falls back to `nomineeRelationships` (`nominee_controller.dart:32`) — so there are actually TWO
layers of fallback to the same hardcoded list (provider-level AND widget-level `.when` loading/error
branches), which is redundant but not harmful.
