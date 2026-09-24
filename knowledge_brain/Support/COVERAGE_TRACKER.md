---
module: Support
last_updated: 2026-08-19
---

# Support — Coverage Tracker

## Round 1 — Build (2026-08-19)

Full build from scratch (previous brain status: ⬜ not built). All 4 source files under
`lib/features/support/` read in full: `enquiry_service.dart`, `support_screen.dart`,
`screens/enquiry_form_screen.dart`, `screens/enquiry_list_screen.dart`. Cross-referenced
`lib/routes/app_router.dart` (route registration + all inbound `Navigator.pushNamed` call sites via
project-wide grep), `lib/core/config/app_config.dart` (`encryptedEndpoints`), and
`lib/core/security/api_interceptor.dart` (encryption trigger mechanism).

### Weighted Coverage Calculation

| Category | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens documented | 25% | 3 (`SupportScreen`, `EnquiryFormScreen`, `EnquiryListScreen`) | 3 | 25% |
| Controller/service public methods documented | 25% | 2 (`EnquiryService.submitEnquiry`, `.getEnquiries`) | 2 | 25% |
| Models documented | 15% | 2 (`SupportTicket`, `Enquiry`) | 2 | 15% |
| API endpoints documented | 15% | 2 (`support/create-ticket`, `support/list`) | 2 | 15% |
| Business rules captured | 10% | 8 rules (RULE-SUPPORT-001 to 008) | 8 | 10% |
| Cross-module deps captured | 10% | 3 inbound callers + 9 outbound deps, Mermaid graph | all found via exhaustive grep | 10% |
| **Total** | **100%** | | | **100%** |

### Manual Spot-Check (required for 🔵)

Re-verified 3 files against the written docs after drafting:
1. `lib/features/support/screens/enquiry_form_screen.dart` — confirmed `_selectedType` default `'General'`
   mismatch (RULE-SUPPORT-003), `initState` `containsKey` gate (RULE-SUPPORT-004), submit flow, success
   sheet field extraction.
2. `lib/features/support/screens/enquiry_list_screen.dart` — confirmed 4-state status color switch, FAB +
   AppBar dual entry points to `enquiryForm`, `content`/`lastUpdate` fields parsed but unused.
3. `lib/routes/app_router.dart` — confirmed `enquiryForm` route's `args['initial_type']` decode
   (lines 275-282) and that `AppRouter.support`/`AppRouter.about`-style dead-route pattern (zero
   `Navigator.pushNamed(AppRouter.support)` call sites project-wide).

No discrepancies found between docs and code on spot-check.

### Badge: 🔵 100% + verified

## Priorities for Round 2 (if source changes)

- Re-verify `kTicketTypes` / `_typeIcons` if the type picker UI is redesigned — RULE-SUPPORT-001/003/004 all
  hinge on that exact mapping.
- If `SupportScreen` ("/support") is ever wired up to a navigation entry point, re-audit its "Live Chat"/
  "Call Support" tiles and re-classify Top Risk #1 as resolved.
- If the backend's `support/list` response shape is confirmed (e.g. via API contract doc or a captured
  payload), replace the "unconfirmed" language in DATA_FLOW.md Flow 2 and FORENSIC_TEMPLATE.md with the
  confirmed shape, and simplify `EnquiryService.getEnquiries`'s parser accordingly if it's no longer needed.
