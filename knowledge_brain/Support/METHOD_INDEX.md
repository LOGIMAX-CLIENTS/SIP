---
module: Support
last_updated: 2026-08-19
round: 1
---

# Support — Method Index

Alphabetical by `Class.method`. Callers listed are in-module unless noted.

## `Enquiry` (`lib/features/support/enquiry_service.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `Enquiry.fromJson(Map<String,dynamic>)` (factory) | `enquiry_service.dart:62` | `EnquiryService.getEnquiries` (maps each list element) |

## `EnquiryFormScreen` / `_EnquiryFormScreenState` (`lib/features/support/screens/enquiry_form_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `initState()` | `enquiry_form_screen.dart:49` | Flutter framework |
| `dispose()` | `enquiry_form_screen.dart:63` | Flutter framework |
| `_submit()` | `enquiry_form_screen.dart:70` | `_buildSubmitButton` `onPressed` |
| `_showSuccessSheet(String, Map)` | `enquiry_form_screen.dart:105` | `_submit` |
| `build(BuildContext)` | `enquiry_form_screen.dart:117` | Flutter framework |
| `_buildHeroCard()` | `enquiry_form_screen.dart:192` | `build` |
| `_buildSectionLabel(String)` | `enquiry_form_screen.dart:254` | `build` (x2) |
| `_buildTypePicker()` | `enquiry_form_screen.dart:267` | `build` |
| `_buildTextField({...})` | `enquiry_form_screen.dart:332` | `build` (subject, message fields) |
| `_buildSubmitButton()` | `enquiry_form_screen.dart:391` | `build` |

## `_SuccessSheet` (private, `enquiry_form_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `build(BuildContext)` | `enquiry_form_screen.dart:452` | Flutter framework (via `showModalBottomSheet`) |
| `_info(String, String, {bool numeric})` | `enquiry_form_screen.dart:575` | `build` (Ticket ID, Subject, Submitted) |
| `_infoStatus(String)` | `enquiry_form_screen.dart:612` | `build` |

## `EnquiryListScreen` (`lib/features/support/screens/enquiry_list_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `build(BuildContext, WidgetRef)` | `enquiry_list_screen.dart:17` | Flutter framework (route target for `AppRouter.enquiryList`) |
| `_buildEmpty(BuildContext)` | `enquiry_list_screen.dart:129` | `build` (empty-state branch) |
| `_buildCard(Enquiry, bool)` | `enquiry_list_screen.dart:168` | `build` (`ListView.separated.itemBuilder`) |

## `EnquiryService` (`lib/features/support/enquiry_service.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `submitEnquiry({required int type, required String subject, required String content})` → `Future<Map<String,dynamic>>` | `enquiry_service.dart:82` | `EnquiryFormScreen._submit` |
| `getEnquiries()` → `Future<List<Enquiry>>` | `enquiry_service.dart:96` | `enquiriesProvider` |

## `SupportScreen` (`lib/features/support/support_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `build(BuildContext)` | `support_screen.dart:12` | Flutter framework (registered at `AppRouter.support` — but **no in-app caller navigates to this route**, see MODULE_BRAIN.md Top Risks #1) |
| `_buildSearchBox(bool)` | `support_screen.dart:75` | `build` |
| `_buildSupportAction(IconData, String, bool)` | `support_screen.dart:95` | `build` (Live Chat, Call Support — non-interactive) |
| `_buildFaqItem(String, String, bool)` | `support_screen.dart:120` | `build` (4 hardcoded FAQ entries) |

## `SupportTicket` (`lib/features/support/enquiry_service.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `SupportTicket.fromJson(Map<String,dynamic>)` (factory) | `enquiry_service.dart:32` | **None found** — dead code, class is never instantiated anywhere in `lib/` |

## Providers (top-level, `enquiry_service.dart`)

| Provider | File:Line | Type | Watched/read by |
|---|---|---|---|
| `enquiryServiceProvider` | `enquiry_service.dart:182` | `Provider<EnquiryService>` | `EnquiryFormScreen._submit` (`ref.read`), `enquiriesProvider` (`ref.read`) |
| `enquiriesProvider` | `enquiry_service.dart:187` | `FutureProvider<List<Enquiry>>` | `EnquiryListScreen.build` (`ref.watch`), invalidated/refreshed by `EnquiryFormScreen._submit` and `EnquiryListScreen`'s FAB/AppBar-icon/`RefreshIndicator`/Retry button |

## Total Public-Surface Counts (for COVERAGE_TRACKER.md)

- Screens: 3 (`SupportScreen`, `EnquiryFormScreen`, `EnquiryListScreen`)
- Service public methods: 2 (`submitEnquiry`, `getEnquiries`)
- Models: 2 (`SupportTicket` — dead, `Enquiry`)
- API endpoints: 2 (`support/create-ticket`, `support/list`)
- Providers: 2 (`enquiryServiceProvider`, `enquiriesProvider`)
