---
module: Profile
last_updated: 2026-08-19
---

# Profile — Business Rules

Each rule: plain-English statement + the code that implements/enforces it. "Unconfirmed" = inferred from
client code only, not verified against backend source or a live run.

## RULE-PROFILE-001 — Phone number and DOB are permanently read-only in Account Details

Name, E-Mail, Pincode, State (auto), City (auto), Address are editable; Phone and DOB never render an
editable `TextField` regardless of `isEditing` state.
**Code**: `account_details_screen.dart:330` (`isEditable: false` hardcoded for Phone),
`account_details_screen.dart:332` (same for DOB).

## RULE-PROFILE-002 — Save requires Name + valid Email + exactly 6-digit Pincode

`_canSave` computed property gates the Save button.
**Code**: `account_details_screen.dart:42-47`. Server-side re-validation on `profile/update` is
**unconfirmed** (not visible from client code).

## RULE-PROFILE-003 — Editing an already-verified e-mail address resets its verified badge locally

If the saved value differs from the previously on-file (and verified) e-mail, `isEmailVerified` is reset to
`false` client-side immediately on successful save — a verification stamp belongs to the mailbox it
verified, not the account. **Code**: `profile_controller.dart:266-274` — comment cites backend
`identity.py` doing the equivalent reset server-side, so this is mirroring, not inventing, server behavior.

## RULE-PROFILE-004 — E-mail re-verification only offered when the input field exactly matches the on-file value

The "Verify" / "Verified" badge next to the E-Mail field is hidden entirely if the field currently holds an
unsaved edit (`currentInput != onFileEmail`) — verifying a not-yet-saved address would check against a
value the backend doesn't have yet.
**Code**: `account_details_screen.dart:404-410`.

## RULE-PROFILE-005 — A bank account must pass live BAV before a ₹1 verification payment can even start

Per code comment, the backend's `cbank_is_verify` gate blocks `account/verify-bank/penny/initiate` unless
the account already passed `account\verify-bank` (BAV). The client enforces this implicitly by chaining
`BankPennyVerifyScreen` immediately after a successful "Verify & Add", never exposing the ₹1-payment screen
as an independently reachable action for an unverified account.
**Code**: `add_bank_account_sheet.dart:223-241` (chaining); comment reference at
`models/bank_verification_history.dart:141-143`. **Unconfirmed**: whether the backend actually enforces
this server-side (client never attempts to call penny/initiate for an unverified account, so this path is
untested from the client alone).

## RULE-PROFILE-006 — ₹1 verification is never confirmed on the SDK callback alone

Both Cashfree and Razorpay success/error callbacks route to the same `_confirmAndFinish()`, which calls the
server's `.../penny/confirm` endpoint and only treats the account as verified if the server responds
`verified: true`.
**Code**: `bank_penny_verify_screen.dart:137-145` (Cashfree), `188-203` (Razorpay), `207-240`
(`_confirmAndFinish`). Matches `SKILL.md` §2's session-integrity spirit applied to payments.

## RULE-PROFILE-007 — Removing a bank account is a soft-delete; verification history is retained

The confirmation dialog explicitly tells the user "You can add this account again anytime — your
verification history is kept."
**Code**: `bank_details_screen.dart:348-350` (UI copy); `bank_details_service.dart:30-33` (doc comment:
"soft-remove (backend keeps history)"). Backend behavior itself is **unconfirmed** from client code — this
is the client's stated assumption.

## RULE-PROFILE-008 — Account deletion is gated server-side by `is_allowed`; the destructive action is hidden, not just disabled, when not allowed

If `users/delete-account/info` returns `is_allowed: false`, the "Delete My Account" footer button doesn't
render at all (the user only sees the policy content + deletion-scope list, no way to trigger deletion).
**Code**: `delete_account_screen.dart:123-125,205-206`. The actual eligibility rule (e.g. open SIP, non-zero
holdings, pending KYC) is **unconfirmed** — lives entirely in the backend response.

## RULE-PROFILE-009 — Account deletion requires an explicit double-confirmation, then performs the same local data wipe as logout

Tap "Delete My Account" → styled confirm dialog ("Yes, Delete" / "Cancel") → only then is the API called.
On success, local wipe = `SecureStorageService.logout()` + `SharedPreferences.clear()`, identical routine to
a normal logout, not a deletion-specific wipe.
**Code**: `delete_account_screen.dart:38-64` (confirm flow), `66-72` (`_clearAllData`).
**GDPR/IT-Act note** (per `SKILL.md` §5): the client's job here — call the real delete endpoint and wipe
local secrets — is done correctly. Whether the *server* actually purges/anonymizes data (vs. a soft
deactivation) is outside this module's code and **unconfirmed**.

## RULE-PROFILE-010 — RETRACTED (2026-08-24): claimed backslash-escape bug does not reproduce

Original finding claimed `withdrawal_service.dart:106` read `_apiClient.post('account\verify-bank', ...)`
with a `\v` (vertical-tab) escape corrupting the path, and cited a sibling at `withdrawal_service.dart:117`
(`'referrals\reward-balance'`, `\r`). Re-verified 2026-08-24 via byte-level inspection (`cat -A`, confirming
no `^K`/`^M` control characters present) and `git log -p` across recent commits touching this file: both
strings are, and have been, plain forward slashes — `'account/verify-bank'` and
`'referrals/reward-balance'`. Neither bug exists; `account_no`/`ifsc_code` DO get encrypted on the
Add Bank Account call (path correctly matches `AppConfig.encryptedEndpoints`'s `'verify-bank'` entry).
Treat this rule as void — kept here (rather than deleted) only as a record that the claim was checked and
disproven, so it isn't independently "rediscovered" and re-flagged later.

## RULE-PROFILE-011 — DOB is typed as DD/MM/YYYY with auto-inserted separators (added 2026-09-07)

`DobInputFormatter` (`shared/utils/dob_input_formatter.dart`) owns DOB text entry on **both** the
registration screen and Account Details. It inserts the slashes while typing — `19` -> `19/`,
`1906` -> `19/06/`, `19061992` -> `19/06/1992` — so a customer can type straight through with no
separators. Caret re-anchoring follows `AadhaarInputFormatter`'s approach; the trailing separator is
suppressed while deleting, or backspace could never move left past a slash.

**Why the field owns typing.** The "Invalid format." error customers hit came from **Flutter's own**
`showDatePicker` keyboard-entry mode, not from this codebase (the string appears nowhere in `lib/`). That
mode parses by locale — `en_US` => MM/DD/YYYY — so `19061992` was rejected. Both pickers now pass
`initialEntryMode: DatePickerEntryMode.calendarOnly`, removing that path entirely.

Formatting and validation are deliberately split, same as `AadhaarInputFormatter`: the formatter never
rejects an impossible day/month mid-keystroke. `DobInputFormatter.parse()` is the gate — it returns null
for an incomplete value AND for a date that isn't real (`31/02/1990`, which `DateTime` would otherwise
silently roll to 3 March).

**Account Details specifics.** DOB was previously `isEditable: false` (display-only via `hint`); it is now
editable in edit mode with a "Pick" action for the calendar. Two consequences:

- The controller is seeded through `_toDisplayDob()` — the API returns ISO (`2000-12-11`) but the field's
  text is now what the customer reads and edits. `profile/update` accepts **either** shape (backend
  `identity.py`: a `/` in the value parses as `%d/%m/%Y`, otherwise `date.fromisoformat`), so sending
  `19/06/1992` is safe.
- Save-time validation was added (required / valid date / 18+). This is **not optional politeness**:
  `profile/update`'s dob branch swallows a malformed value silently (`except (ValueError, TypeError):
  pass`), so without it the customer would be told "Profile updated successfully" while their DOB was
  quietly dropped.

❌ Re-deriving the DD/MM/YYYY split inline, or relying on the date picker's own keyboard entry.
✅ `DobInputFormatter` for input, `.parse()` for validation, `.formatDate()` for DateTime -> display.

### UI follow-ups (2026-09-07)

- **DOB action is a calendar icon**, not a "Pick" label — `_buildInputField` gained an `actionIcon` param
  for actions better shown as a glyph. Matches RegistrationScreen's own DOB field.
- **The e-mail Verify action lives INSIDE the field**, not beside the label. Account Details uses a new
  `actionWidget` slot (rendered in the value box, and deliberately NOT gated on `isEditable` — the badge
  decides its own state); RegistrationScreen passes `_buildEmailVerifyAction()` as the field's `suffixIcon`.
  That widget must stay wrapped in a constrained container: a bare `Row` inside `suffixIcon` stretches to
  the field's full height and pushes the value text off-centre.
- **The Verify tap target is the whole padded region**, not the word. Both screens wrap it in a
  `GestureDetector` with `behavior: HitTestBehavior.opaque` — without that, transparent padding is not
  hit-testable and only the glyphs respond, which is exactly how it shipped first.
- **Playfair Display digits are forced to lining figures.** `AppTextStyles.digitFeatures`
  (`liningFigures` + `tabularFigures`) is applied to `bodyLarge` and `inputHint` — the two Playfair styles
  used by text inputs. Playfair ships OLDSTYLE figures by default, so digits render at varying heights and
  an e-mail like `sankarguru.8750@...` looked like the numbers were bouncing. Lora (the numeric style)
  already used lining figures and needed nothing. This is a SHARED style, so it changes digit rendering
  anywhere `bodyLarge` is used, not only these two fields.
