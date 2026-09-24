# Aadhaar/PAN KYC frontend issues — for frontend engineer

**Status: Issue 1 fixed on this branch (`fix/error-handling-surepass`). Issue
2 documented but NOT fixed — needs a design decision, see below.**

Found while testing the new `CONFIRM_NAME_UPDATE` name/DOB mismatch flow
(backend PRs on `fix/meon-kyc-aadhar-verification`, branch merged into
`phase1` in several commits today). Both are frontend-only — the backend
contract is confirmed correct and unchanged.

---

## Issue 1: Real backend error messages are replaced with a generic "technical issue" message

**FIXED on this branch** — see the diff to `_sanitizeErrorMessage()` below.

**File:** `lib/features/kyc/controllers/kyc_controller.dart`
**Function:** `_sanitizeErrorMessage()` (~line 226)

**What's happening:**

When the backend rejects an Aadhaar verification attempt for a real,
user-facing reason (name mismatch, DOB mismatch, expired session, etc.), it
returns HTTP 400 with a structured error body, e.g.:

```json
{
  "success": false,
  "error": { "code": "NAME_MISMATCH", "message": "Your profile name and/or date of birth doesn't match your Aadhaar record. Please re-enter your name and date of birth exactly as on your Aadhaar and try again." }
}
```

`ApiClient.post()` maps any non-2xx response to a `Failure` via
`ApiFailureMapper.map()` — this correctly extracts the real backend message
into `ServerFailure(message: ..., statusCode: 400)`.

But `AadhaarNotifier.pollUntilTerminal()`'s catch block calls
`_sanitizeErrorMessage(e)`, whose **first check** is:

```dart
if (e is Failure) {
  SecureLogger.e('[Aadhaar] technical error (not shown to user)', e);
  return _temporaryIssueMessage;
}
```

This treats **every** `Failure` as a generic network/technical fault and
discards its message — including deliberate, well-formed 400 business
responses that carry a real, safe-to-show message. The customer just sees
"We're currently experiencing a temporary technical service issue…" no
matter what actually went wrong.

**Scope:** not specific to one status or one provider — affects every
terminal Aadhaar failure the backend returns as HTTP 400 (`NAME_MISMATCH`,
`REJECTED`, `EXPIRED`, `CONSENT_DENIED`), for both the SurePass (native SDK)
and Cashfree/Meon (webview) flows, since both funnel through the same
`pollUntilTerminal()` → `_sanitizeErrorMessage()` path. The switch-case that
handles these statuses by name (~line 370-389) is effectively dead code for
this reason — the exception is thrown before that switch ever runs.

**Fix:**

Only collapse to the generic message for genuinely infrastructure-level
failures (timeouts, connection drops, 5xx, SSL errors) — not for a
`ServerFailure` carrying a real backend-authored message from a 4xx business
response:

```dart
String _sanitizeErrorMessage(Object e) {
  if (e is ServerFailure && e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
    // A deliberate 4xx business response (NAME_MISMATCH, REJECTED, EXPIRED,
    // PROFILE_NAME_MISMATCH, etc.) — the backend already crafted this
    // message to be safe to show verbatim.
    return e.message;
  }
  if (e is Failure) {
    SecureLogger.e('[Aadhaar] technical error (not shown to user)', e);
    return _temporaryIssueMessage;
  }
  final raw = e.toString().replaceFirst('Exception: ', '');
  if (_technicalErrorPattern.hasMatch(raw)) {
    SecureLogger.e('[Aadhaar] technical error (not shown to user)', e);
    return _temporaryIssueMessage;
  }
  return raw;
}
```

`ServerFailure` and its `statusCode`/`message` fields already exist in
`lib/core/error/failures.dart` — no new type needed.

**Test plan:**
- Trigger a real `NAME_MISMATCH` via both the SurePass SDK flow and the
  Cashfree/Meon webview flow → the actual backend message should appear
- Trigger a genuine network failure (airplane mode, kill connection mid-request)
  → generic technical-issue message should still appear (must not regress)
- Trigger an expired/declined DigiLocker session → real backend message shown

---

## Issue 2: The "Verify via Meon (native)" button doesn't persist the verification to the backend at all (NOT FIXED — needs a design decision)

**This is bigger than "the mismatch dialog doesn't show" — it's that this
entire button doesn't record a KYC result on the backend, mismatch or not.**

**Files:**
- `lib/features/kyc/screens/kyc_screen.dart` — `_onVerifyAadhaarMeon()` (~line 411-445)
- `lib/features/kyc/widgets/meon_digilocker_sdk_screen.dart` — `_handleSuccess()` (~line 71-91)

**What's happening:**

`_onVerifyAadhaarMeon()` calls `KycRepository.getMeonSdkConfig()`
(`kyc/meon-sdk-config`) — a **different backend endpoint** than the generic
flow, which bypasses `AadhaarNotifier.initiate()`/`initiate_digilocker()`
entirely (deliberately — see the doc comment at kyc_screen.dart:403-410).
That means the backend never creates a `KYC` log row for this attempt and
`state.verificationId` is never set for it — there is no
backend-side session to poll or confirm against.

The `flutter_digilocker_aadhar_pan` package's own `DigiLockerResponse`
(confirmed via the package's pub.dev docs) does NOT carry a session/
client_token/state identifier — but it DOES carry the **full verified data
inline**: `DigiLockerResponse.data` (`DigiLockerData`) includes name,
Aadhaar number/address/XML, PAN details, DOB, gender, father's name, and
address fields — the native SDK completes the whole DigiLocker exchange
client-side and hands back the actual result, not just a session pointer.

`MeonDigilockerSdkScreen._handleSuccess()` (line 71-75) discards all of
that:
```dart
void _handleSuccess(DigiLockerResponse response) {
  SecureLogger.d('[Meon DigiLocker SDK] completed: success=${response.success}');
  if (!mounted) return;
  Navigator.pop(context, response.success);
}
```
Only the bare `.success` bool is passed back. `_onVerifyAadhaarMeon()`
(line 439-444) then calls `_checkAndHandleCompletion()` — which is a plain
GET refresh of `kyc/document-types`, matching this existing (incorrect)
assumption in its own comment:
```dart
// Meon's SDK returns full verification data inline — no separate
// poll step like the webview/SurePass paths need. Refresh
// document-types the same way a completed submission does elsewhere.
await _checkAndHandleCompletion();
```
There is no POST anywhere in this flow that sends `response.data` to the
backend. Nothing is ever persisted. `_checkAndHandleCompletion()` re-fetches
a `KYC` table that was never written to for this attempt, so it can't show
anything new — success, mismatch, or otherwise.

**Why "Meon works" was reported anyway:** the tester most likely exercised
the **generic "Verify via DigiLocker" button** with Meon as the backend's
currently-active routed gateway, not this native button. Meon's
`initiate_digilocker()` returns a `consent_url` (like Cashfree), so the
generic button takes the webview path for Meon, which correctly goes through
`AadhaarNotifier.initiate()` → `pollUntilTerminal()` → the real backend
check — same working path SurePass's native SDK also correctly uses (see
the generic flow described in the original version of this doc / git
history). The separate "Verify via Meon (native)" button is a third,
independent path that was seemingly never fully wired to the backend.

**This needs a design decision before implementing, not a quick patch:**
1. Confirm whether the "Verify via Meon (native)" button is meant to stay in
   the app at all, given the generic button already covers Meon correctly
   via the webview/consent_url path — if this native button is legacy/
   experimental, the simplest fix may be to remove it rather than build a
   new backend endpoint for it.
2. If it should stay (e.g. for a better in-app UX than a webview), the
   backend needs a NEW endpoint to accept `DigiLockerData` submitted
   directly from the client (name, DOB, Aadhaar number, PAN, address) and
   run it through the same validation `_check_aadhaar_kyc()` does (name/DOB
   match against `Customer.cus_name`/`cus_dob`, `KYC_NAME_MISMATCH_
   RESOLUTION` handling, KYC row creation) — that's real backend work, and
   raises a trust question worth a security conversation: today the backend
   only ever trusts data it fetched itself directly from Meon's API; this
   would mean trusting Aadhaar data that passed through the client first.

**Test plan (once a direction is decided):**
- If removed: confirm the generic "Verify via DigiLocker" button still
  correctly completes Aadhaar verification when Meon is the active gateway
- If kept + wired to a new endpoint: full name-match, name-mismatch, and
  DOB-mismatch scenarios via this specific button, mirroring the test plan
  already used for the generic flow
