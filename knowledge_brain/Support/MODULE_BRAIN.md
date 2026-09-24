---
module: Support
folder: lib/features/support/
brain_status: 🟢 (see COVERAGE_TRACKER.md)
last_updated: 2026-08-19
round: 1
---

# Support — Module Brain

## What this module does

Ticket-based support/enquiry system. Users submit a categorized enquiry (subject + free-text message) and
can view the list of enquiries they've submitted, with a status badge (pending/open/resolved/rejected).
There is also a standalone `SupportScreen` "hub" with a hardcoded FAQ accordion and two non-functional
quick-action buttons — but it is **not reachable from anywhere in the app** (see Top Risks).

## Inventory (4 files, all read)

| File | Role |
|---|---|
| `lib/features/support/enquiry_service.dart` | Models (`SupportTicket`, `Enquiry`) + `EnquiryService` (API calls) + Riverpod providers |
| `lib/features/support/support_screen.dart` | `SupportScreen` — static hub UI, orphan route |
| `lib/features/support/screens/enquiry_form_screen.dart` | `EnquiryFormScreen` — ticket submission form |
| `lib/features/support/screens/enquiry_list_screen.dart` | `EnquiryListScreen` — ticket list/tracking |

No `controller/`, `models/` (separate folder), or `widgets/` subfolders — this module is small enough that
everything lives in the 2 top-level files + `screens/`.

## Route Table

| Screen | Route constant | Path | Registered at | Reachable from |
|---|---|---|---|---|
| `SupportScreen` | `AppRouter.support` | `/support` | `app_router.dart:176` | **Nowhere** — dead route (grep found zero `Navigator.pushNamed(..., AppRouter.support)` call sites) |
| `EnquiryFormScreen` | `AppRouter.enquiryForm` | `/enquiry-form` | `app_router.dart:275-282` | `EnquiryListScreen` (FAB + AppBar icon); `sip/screens/manage_savings_screen.dart:234` (`initial_type: 'Auto Savings'`); `sip/screens/manage_custom_savings_screen.dart:224` (`initial_type: 'Custom SIP'`) |
| `EnquiryListScreen` | `AppRouter.enquiryList` | `/enquiry-list` | `app_router.dart:283` | `profile/profile_screen.dart:288-289` ("Enquiry" side-menu item) |

`EnquiryFormScreen` takes an optional `initialType` constructor param. The router reads it from
`Navigator.pushNamed` arguments as `args['initial_type']` (`app_router.dart:275-281`) — see
`BUSINESS_RULES.md` RULE-SUPPORT-003 for the type-matching bug this produces.

## Screens

### SupportScreen (`support_screen.dart`)
`StatelessWidget`. Renders a search box (non-functional — no `onTap`/`TextField`, just static `Text`
placeholder, `support_screen.dart:88`), two "Quick Assistance" action tiles ("Live Chat", "Call Support" —
both `Container`s with **no `onTap`/`GestureDetector`**, `support_screen.dart:95-118`, i.e. purely
decorative/dead), and 4 hardcoded FAQ items (`_buildFaqItem`, not from any API — contrast with the real
`content/screens/faq_screen.dart` which is API-driven). No Riverpod providers watched, no API calls. See
Top Risks — this whole screen is unreachable via any in-app navigation.

### EnquiryFormScreen (`screens/enquiry_form_screen.dart`)
`ConsumerStatefulWidget`. Fields collected:
- **Type** — chip picker (`_buildTypePicker`, line 267) iterating `kTicketTypes.keys` → 5 chips: Enquiry,
  Support, Review, Auto Savings, Others. Default `_selectedType = 'General'` (line 32) — **not a member of
  `kTicketTypes`**, so no chip is visually selected on first render (RULE-SUPPORT-003).
- **Subject** — required `TextFormField`, non-empty validator (line 148).
- **Message/content** — required multiline (`maxLines: 6`) `TextFormField`, non-empty validator (line 161).

`initialType` (ctor param, nullable `String`) pre-selects a chip in `initState` only if
`kTicketTypes.containsKey(widget.initialType)` (lines 52-55) — silently ignored otherwise.

Submit (`_submit`, line 70): validates form → `ref.read(enquiryServiceProvider).submitEnquiry(type:
kTicketTypes[_selectedType] ?? 1, subject, content)` → on `response['success'] == true`, invalidates
`enquiriesProvider` and shows a success bottom sheet with ticket id/subject/status/submitted-on pulled from
`response['data']`; else shows an `AppToast.show(..., type: ToastType.error)` with the server message or a
generic fallback. Any thrown exception is caught and shown as a generic "Something went wrong" toast — no
`Failure`-type mapping (contrast with `AGENTS.md` §5 guidance).

No screenshot-block/app-lock-suppression logic — this screen carries no sensitive financial/PII field, so
that's consistent with `AGENTS.md` §3 (only PAN/bank/OTP-class screens need it).

### EnquiryListScreen (`screens/enquiry_list_screen.dart`)
`ConsumerWidget`. Watches `enquiriesProvider` (`FutureProvider<List<Enquiry>>`). Three `AsyncValue` states:
- `loading` → centered spinner.
- `error` → error icon + "Could not load enquiries" + Retry button (`ref.refresh(enquiriesProvider)`).
- `data` → empty state (`_buildEmpty`) if list is empty, else `RefreshIndicator` + `ListView.separated` of
  ticket cards (`_buildCard`) with staggered `FadeInAnimation`.

Card shows: status badge (color/icon per status: open=blue, resolved=green, rejected=red,
pending/default=amber, `_buildCard` lines 173-191), `createdAt` date, subject, type tag (if non-empty),
ticket id (if non-empty). "New Enquiry" reachable via both a bottom FAB and an AppBar trailing icon, both
push `AppRouter.enquiryForm` then `.then((_) => ref.refresh(enquiriesProvider))` on return.

## State (Riverpod)

| Provider | Type | Defined | Purpose |
|---|---|---|---|
| `enquiryServiceProvider` | `Provider<EnquiryService>` | `enquiry_service.dart:183` | DI for the service |
| `enquiriesProvider` | `FutureProvider<List<Enquiry>>` | `enquiry_service.dart:187` | Fetches ticket list on first watch; comment notes "Token is managed by ApiInterceptor — always fires when screen opens" (no auth gating) |

No `StateNotifier`; form state is local `setState` (`_selectedType`, `_isLoading`) in
`EnquiryFormScreen` — acceptable per `AGENTS.md` §1 ("prefer StateNotifier for non-trivial async" — this
form's only async op is the one-shot submit call, arguably borderline but not flagged as a violation).

## API Surface

| Method | Endpoint | Called by | Encrypted? |
|---|---|---|---|
| POST | `support/create-ticket` | `EnquiryService.submitEnquiry` (`enquiry_service.dart:87`) | No — `support/*` is absent from `AppConfig.encryptedEndpoints` (`core/config/app_config.dart:47+`) |
| POST | `support/list` | `EnquiryService.getEnquiries` (`enquiry_service.dart:98`), empty body `{}`, auth via bearer token only | No |

Response-shape parsing is defensive/tolerant: `getEnquiries` tries root-as-list, then `data` as list, then
`data.{tickets,enquiries,list,items,data,records}` as list, logging every branch via `debugPrint` when
`kDebugMode` (`enquiry_service.dart:95-177`) — strongly suggests the actual backend response shape was
unstable/unconfirmed during development. Treat the real shape as **unconfirmed** — verify against a live
`support/list` response before depending on it.

## Models

- `SupportTicket` (`enquiry_service.dart:15-40`) — **dead code**: constructed nowhere in the codebase
  (grep confirmed only its own definition/factory reference it). Superseded by `Enquiry`.
- `Enquiry` (`enquiry_service.dart:43-74`) — the model actually used by `EnquiryListScreen`. Tolerant
  `fromJson`: `id` accepts int or string; `createdAt` reads `on` (create-ticket response key) falling back
  to `created_at`; `lastUpdate` falls back to `on` then defaults `''` — `lastUpdate` is parsed but **never
  rendered** by `EnquiryListScreen` (unused field).

## Top Risks / Anti-Patterns

1. **`/support` route is dead.** `SupportScreen` is registered in `app_router.dart:176` but no code path
   navigates to it — confirmed via exhaustive grep for `AppRouter.support` across `lib/`. Its "Live Chat"
   and "Call Support" tiles have no `onTap` even if it were reached. Either wire it up or remove it.
2. **Default ticket type silently mismatches the chip picker** (RULE-SUPPORT-003) — `_selectedType`
   defaults to `'General'`, which is not a `kTicketTypes` key, so (a) no chip appears selected on load and
   (b) if the user submits without tapping a chip, the ticket silently posts as `type: 1` ("Enquiry").
3. **`initial_type: 'Custom SIP'`** passed from `manage_custom_savings_screen.dart:225` doesn't match any
   `kTicketTypes` key either — same silent fallback to `type: 1`, meaning the "Get Support" CTA on the
   Custom SIP screen doesn't actually pre-tag tickets as SIP-related despite the caller's evident intent.
4. Response-shape tolerance in `getEnquiries` (6 different key names tried) suggests the backend contract
   was never nailed down — a backend change could silently start returning `[]` with no error shown to the
   user (falls through to the empty state, not the error state).
5. No `Failure`-type error mapping on submit — raw `catch (e)` → generic toast, per `AGENTS.md` §5 this
   should ideally distinguish network/validation/server errors.

## Cross-Module Dependencies (summary — full detail in CROSS_MODULE_MAP.md)

`core/network/api_client.dart` (ApiClient), `shared/widgets/{app_toast,gradient_header,secure_clipboard,
numeric_styled_text,animations}.dart`, `shared/theme/{app_theme,app_text_styles}.dart`, `routes/app_router.dart`.
Inbound callers: `features/sip/screens/manage_savings_screen.dart`,
`features/sip/screens/manage_custom_savings_screen.dart`, `features/profile/profile_screen.dart`.

## Drift vs STARTGOLD_DOCUMENTATION.md §3.37–3.39

The hand-written doc lists exactly 3 screens/routes (Support hub, Enquiry Form, Enquiry List) and is
accurate on route paths. It does **not** mention: the `initial_type` argument mechanism, the dead-route
status of `/support`, the `SupportTicket` dead model, or the type-matching bug (RULE-SUPPORT-003) — all new
findings from this code-grounded pass, not prior drift so much as gaps the hand-written doc never covered.
