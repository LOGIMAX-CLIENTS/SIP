---
module: Support
last_updated: 2026-08-19
round: 1
---

# Support — Business Rules

## RULE-SUPPORT-001: Ticket type is an integer enum, mapped client-side from a label

The API's `type` field is an `int` (1=Enquiry, 2=Support, 3=Review, 4=Others, 5=Auto Savings), defined in
`kTicketTypes` (`lib/features/support/enquiry_service.dart:6-12`). The UI shows human labels; the label is
translated to the integer only at submit time (`enquiry_form_screen.dart:75`). There is no "General",
"Payment", "Technical", or "Account" integer mapping even though `_typeIcons`
(`enquiry_form_screen.dart:36-46`) defines icons for those 4 extra labels — they are dead entries, never
rendered as chips because the chip `Wrap` iterates `kTicketTypes.keys`, not `_typeIcons.keys`
(`enquiry_form_screen.dart:271`).

## RULE-SUPPORT-002: Subject and message are both mandatory, no length limits enforced client-side

`_formKey.currentState!.validate()` requires non-empty (after `.trim()`) subject and content
(`enquiry_form_screen.dart:148-149`, `161-162`). No max-length `TextFormField.maxLength`/validator exists —
any length constraint, if present, is server-side and unconfirmed.

## RULE-SUPPORT-003: Default ticket type ('General') does not match any submittable type — BUG

`_selectedType` initializes to `'General'` (`enquiry_form_screen.dart:32`), but `kTicketTypes` has no
`'General'` key. Consequences, both observed directly in the code (not runtime-tested — flag as
**unconfirmed at runtime, confirmed by static analysis**):
1. On screen load with no `initialType` (or an `initialType` that doesn't match a `kTicketTypes` key), the
   chip picker renders 5 chips (Enquiry/Support/Review/Auto Savings/Others) and **none of them show the
   selected style** (`enquiry_form_screen.dart:280-287` compares `selected = _selectedType == label`,
   which is always false for `_selectedType == 'General'`).
2. If the user submits without ever tapping a chip, `kTicketTypes[_selectedType] ?? 1` (line 75) falls back
   to `1` (Enquiry) — the ticket is silently filed as "Enquiry" with no visual indication that a default was
   applied.

## RULE-SUPPORT-004: `initial_type` argument must exactly string-match a `kTicketTypes` key or it is silently dropped

`app_router.dart:275-281` passes `args['initial_type']` straight through as `EnquiryFormScreen.initialType`;
`initState` only honors it via `kTicketTypes.containsKey(widget.initialType)`
(`enquiry_form_screen.dart:52-55`) — no fuzzy matching, no logging on mismatch. Confirmed working case:
`manage_savings_screen.dart:236` passes `'Auto Savings'` (exact match). Confirmed broken case:
`manage_custom_savings_screen.dart:225` passes `'Custom SIP'` (no matching key) — falls through to
RULE-SUPPORT-003's default-type bug. Any future caller adding a new `initial_type` string must add a
matching entry to `kTicketTypes` in the same commit, or the pre-selection silently does nothing.

## RULE-SUPPORT-005: Ticket status vocabulary (client-observed)

`EnquiryListScreen._buildCard` (`enquiry_list_screen.dart:168-191`) switches on
`enquiry.status.toLowerCase()` with 4 recognized values: `open` (blue), `resolved` (green), `rejected`
(red), and a `pending`/default fallback (amber). `Enquiry.fromJson` defaults `status` to `'pending'` if the
field is absent (`enquiry_service.dart:69`). Any other server-sent status string renders with the
pending/amber styling by default — not validated against a fixed server-side enum, so this list should be
treated as **client-observed, not authoritative**.

## RULE-SUPPORT-006: `support/*` endpoints carry no field-level encryption

Neither `support/create-ticket` nor `support/list` appears in `AppConfig.encryptedEndpoints`
(`core/config/app_config.dart:47+`) — consistent with the payload containing no PII/financial data (just
type/subject/free-text content). This is expected behavior, not a gap, per `AGENTS.md` §3's scope (encrypt
only password/otp/mpin/pan/aadhaar/bank/upi/amount-bearing fields).

## RULE-SUPPORT-007: `enquiriesProvider` fetches unconditionally, no auth-state gate

The provider's own comment states the token is handled entirely by `ApiInterceptor`, so the list fetch
fires on every widget build/watch regardless of any local auth-state provider
(`enquiry_service.dart:185-186`). If the interceptor's token were ever missing/expired, the resulting
error surfaces as the `error` `AsyncValue` branch (network/401), not a distinguishable "not logged in"
state.

## RULE-SUPPORT-008 (informational): `/support` hub screen is unreachable

`SupportScreen` (registered at `AppRouter.support`, `app_router.dart:176`) has zero in-app navigation call
sites — see MODULE_BRAIN.md Top Risks #1. Not a business rule violation per se, but any FAQ content baked
into it (4 hardcoded Q&As, `support_screen.dart:58-67`) is currently invisible to end users; the real,
API-driven FAQ surface is `content/screens/faq_screen.dart` (see `Content` module brain).
