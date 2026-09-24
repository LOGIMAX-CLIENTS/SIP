---
module: Support
last_updated: 2026-08-19
round: 1
---

# Support — Forensic Template (Symptom → Suspects)

## Symptom: "New Enquiry" chip picker shows no chip highlighted when the form first opens

**Check first**: `EnquiryFormScreen._selectedType` initial value (`enquiry_form_screen.dart:32`) and whether
the `initialType` passed by the caller exactly matches a `kTicketTypes` key.

**Likely suspects**:
1. `_selectedType` defaults to `'General'`, which is not in `kTicketTypes` — RULE-SUPPORT-003. This is
   expected/reproducible behavior when no `initialType` is passed or the passed value doesn't match.
2. A new caller added `initial_type: '<SomeNewLabel>'` without also adding `'<SomeNewLabel>'` to
   `kTicketTypes` (`enquiry_service.dart:6-12`) — RULE-SUPPORT-004.

## Symptom: A ticket submitted from a contextual "Get Support" button (e.g. Custom SIP) shows up in the list tagged "Enquiry" instead of the expected category

**Check first**: The exact string literal passed as `initial_type` at the calling site vs. the exact key
strings in `kTicketTypes`.

**Likely suspects**:
1. `manage_custom_savings_screen.dart:225` passes `'Custom SIP'`, which has no `kTicketTypes` entry — falls
   back to `type: 1` (Enquiry) at submit time (RULE-SUPPORT-004). This is a known, confirmed-by-static-read
   mismatch, not a hypothesis.
2. If a *different* caller shows the same symptom, check that its string matches
   `kTicketTypes` case-and-spelling-exactly (comparison is `==`, no normalization).

## Symptom: Enquiry list shows "No Enquiries Yet" but the user insists they submitted a ticket

**Check first**: `EnquiryService.getEnquiries()`'s debug logs (`kDebugMode` only,
`enquiry_service.dart:101-172`) — specifically the logged response body shape.

**Likely suspects**:
1. Backend response shape changed and no longer matches any of the 6 tolerated shapes
   (`enquiry_service.dart:114-168`) — the method returns `[]` silently (not an error) in that case, so the
   UI shows the empty state, not the error state. This is the most likely root cause given how defensively
   the parser is written (a strong signal the shape was already unstable during development).
2. `response['success'] == false` — also silently returns `[]` (line 126-130), no toast/error surfaced to
   the list screen.
3. Network/auth failure inside the `try` — caught at line 174, also returns `[]`, again indistinguishable
   from "genuinely zero tickets" from the UI's perspective. **Any bug report of "list is empty" needs the
   debug log output to disambiguate these 3 cases** — the current code cannot distinguish them from the UI
   alone.

## Symptom: Tapping "Live Chat" or "Call Support" on the Support hub does nothing

**Check first**: Whether the user actually reached `/support` at all — first confirm via navigation logs
which screen preceded it, since `/support` has no known in-app entry point (MODULE_BRAIN.md Top Risk #1).

**Likely suspects**:
1. `_buildSupportAction` tiles have no `onTap`/`GestureDetector` wrapper at all
   (`support_screen.dart:95-118`) — this is not a regression, the tiles were never wired up.
2. If the user reports reaching `/support` via deep link or a route not yet found in this codebase's grep
   scope, re-verify — the screen itself is otherwise fully functional (just its 2 action tiles and search
   box are decorative).

## Symptom: "Submit Enquiry" fails with a generic "Something went wrong" toast, no specifics

**Check first**: Network tab / Dio logs for the actual `support/create-ticket` response — the client-side
catch block (`enquiry_form_screen.dart:95-99`) swallows all exception detail into one generic message.

**Likely suspects**:
1. Server 4xx/5xx on `support/create-ticket` — no `Failure`-type mapping exists in this module to
   distinguish validation errors from server errors (contrast with `AGENTS.md` §5 guidance).
2. `response['success']` present but `false` — handled separately (shows `response['message']` via toast,
   `enquiry_form_screen.dart:88-94`), so if the user saw the *generic* message specifically, the request
   itself likely threw (network/timeout/parse), not a server-side rejection.

## Symptom: Ticket "Ticket #<id>" shown in the list card doesn't match what the success sheet showed at submission time

**Check first**: Compare `data['id']` from the `create-ticket` response (used by `_SuccessSheet`,
`enquiry_form_screen.dart:453`) against `json['id']`/`json['enquiry_id']` from the subsequent `support/list`
response (used by `Enquiry.fromJson`, `enquiry_service.dart:64-65`).

**Likely suspects**:
1. Backend uses different id fields/formats between the create-ticket and list endpoints — both are
   defensively `.toString()`'d client-side but no cross-validation exists.
2. `enquiriesProvider` wasn't actually invalidated/refetched before the list re-rendered (check that
   `ref.invalidate(enquiriesProvider)` at `enquiry_form_screen.dart:83` actually ran — it only runs inside
   the `success == true` branch).
