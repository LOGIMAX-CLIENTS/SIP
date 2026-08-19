---
module: Support
last_updated: 2026-08-19
round: 1
---

# Support — State Analysis

## Riverpod Providers

| Provider | Kind | File:Line | Lifecycle |
|---|---|---|---|
| `enquiryServiceProvider` | `Provider<EnquiryService>` | `enquiry_service.dart:182-183` | App-lifetime singleton, no `autoDispose` |
| `enquiriesProvider` | `FutureProvider<List<Enquiry>>` | `enquiry_service.dart:187-189` | No `autoDispose` — stays cached across screen pop/push until explicitly `invalidate`d or `refresh`d. Invalidated by `EnquiryFormScreen._submit` on success; `refresh`d by `EnquiryListScreen`'s pull-to-refresh, Retry button, and FAB/AppBar "New Enquiry" `.then()` callback. |

No `StateNotifier`/`AsyncNotifier` in this module — both screens with async work use plain `FutureProvider`
(list) or local `setState` (form submit-in-flight flag). This is consistent with the module's small surface
area; `AGENTS.md` §1's "prefer StateNotifier for non-trivial async" guidance is arguably under-applied for
the form (submit has loading + success + error branches) but not egregiously so — no shared/cross-screen
state is at stake.

## Local Widget State

| Widget | State fields | Notes |
|---|---|---|
| `_EnquiryFormScreenState` | `_selectedType` (`String`, default `'General'` — see RULE-SUPPORT-003), `_isLoading` (`bool`), `_formKey` (`GlobalKey<FormState>`), `_subjectController`/`_contentController` (`TextEditingController`), `_fadeCtrl`/`_fadeAnim` (entrance animation) | All local `setState`; disposed correctly in `dispose()` (`enquiry_form_screen.dart:62-68`) |
| `EnquiryListScreen` | None (`ConsumerWidget`, stateless itself) | All state lives in `enquiriesProvider` |
| `SupportScreen` | None (`StatelessWidget`) | Fully static |

## Model Shapes

### `Enquiry` (`enquiry_service.dart:43-74`)
```dart
class Enquiry {
  final String enquiryId;   // json['id']?.toString() ?? json['enquiry_id']?.toString() ?? ''
  final String type;        // json['type'] ?? ''
  final String subject;     // json['subject'] ?? ''
  final String content;     // json['content'] ?? ''   -- parsed but never rendered by EnquiryListScreen
  final String status;      // json['status'] ?? 'pending'
  final String createdAt;   // json['on'] ?? json['created_at'] ?? ''
  final String lastUpdate;  // json['last_update'] ?? json['on'] ?? ''  -- parsed but never rendered
}
```
`content` and `lastUpdate` are dead fields from the UI's perspective — populated by `fromJson` but not read
by any `_buildCard`/`_buildEmpty` code path. Confirm with product whether the list card is intentionally
summary-only or missing a "view detail" screen that would consume them.

### `SupportTicket` (`enquiry_service.dart:15-40`) — dead model, never constructed anywhere.
```dart
class SupportTicket {
  final String id, submittedOn, type, subject, content, status;
}
```

### `kTicketTypes` (`enquiry_service.dart:6-12`) — not a model but the type-enum source of truth:
```dart
const Map<String, int> kTicketTypes = {
  'Enquiry': 1, 'Support': 2, 'Review': 3, 'Auto Savings': 5, 'Others': 4,
};
```
Note the non-sequential int assignment (4 and 5 swapped relative to insertion order) — mirrors a
server-side enum; do not "clean up" the ordering without confirming against the backend.

## Secure Storage

None. This module touches no `flutter_secure_storage` keys, no MPIN/biometric state, no tokens directly —
auth is fully delegated to `ApiInterceptor` via `ApiClient`.

## Screenshot/App-Lock Behavior

None applied and none needed — no PAN/bank/OTP-class sensitive data is displayed or entered in this module.
`EnquiryFormScreen`'s text fields do disable the system context menu (`contextMenuBuilder:
SecureClipboard.none`, `autocorrect: false`, `enableSuggestions: false`) — a lighter-weight clipboard/
autocorrect hardening, not the full `FLAG_SECURE` screenshot block.
