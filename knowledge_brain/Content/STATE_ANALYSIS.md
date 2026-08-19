---
module: Content
last_updated: 2026-08-19
round: 1
---

# Content — State Analysis

## Riverpod Providers (all in `core/services/content_service.dart`)

| Provider | Kind | File:Line | Lifecycle |
|---|---|---|---|
| `contentServiceProvider` | `Provider<ContentService>` | `content_service.dart:144-145` | App-lifetime singleton, no `autoDispose` |
| `onboardingContentProvider` | `FutureProvider<List<Map<String,dynamic>>>` | `content_service.dart:147-151` | Cached; `refresh`d by `onboarding_screen.dart`'s Retry button. Not consumed by this module's own screens. |
| `termsProvider` | `FutureProvider<Map<String,dynamic>>` | `content_service.dart:153-155` | Cached until `ref.invalidate(provider)` (`ContentScreen`'s Retry button) |
| `privacyPolicyProvider` | `FutureProvider<Map<String,dynamic>>` | `content_service.dart:157-159` | Same caching pattern as `termsProvider` |
| `faqsProvider` | `FutureProvider<List<dynamic>>` | `content_service.dart:161-163` | **Force-invalidated on every `FaqScreen.initState`** (`faq_screen.dart:62-64`) — effectively no cross-visit caching |
| `aboutUsProvider` | `FutureProvider<Map<String,dynamic>>` | `content_service.dart:165-167` | Cached; consumer route (`/about`) is unreachable in practice (RULE-CONTENT-009) |
| `contactUsProvider` | `FutureProvider<Map<String,dynamic>>` | `content_service.dart:169-171` | Cached; no explicit Retry button on error, so re-fetch only happens via navigating away and back |
| `refundPolicyProvider` | `FutureProvider<Map<String,dynamic>>` | `content_service.dart:173-175` | Same caching pattern as `termsProvider` |

None of these use `.autoDispose` — all persist for the app's lifetime once first watched (until manually
invalidated), meaning terms/privacy/refund/about content, once fetched, is not re-fetched even if the app
sits open for a long session — an `unconfirmed` staleness risk worth flagging if legal content is expected
to update frequently server-side.

## Local Widget State

| Widget | State fields | Notes |
|---|---|---|
| `FaqScreen`/`_FaqScreenState` | None beyond the `initState` post-frame invalidation callback | `ConsumerStatefulWidget` used only to get an `initState` hook — no other local mutable state |
| `_ContactCardState` | `_ctrl`/`_scale` (tap-scale animation) | Local UI-only animation state, disposed correctly |
| `_SocialIconTileState` | `_ctrl`/`_scale` (tap-scale animation) | Same pattern, disposed correctly |
| `ContentScreen` | None (`ConsumerWidget`, stateless itself) | All state lives in the injected `provider` |
| `ContactUsScreen` | None (`ConsumerWidget`, stateless itself) | All state lives in `contactUsProvider` |

## Model Shapes

**No dedicated model classes exist in this module.** All content flows as raw `Map<String,dynamic>` (single
content payloads) or `List<dynamic>` (FAQ list) straight from `ContentService`'s `_extractContentMap`/
`_extractFaqList` helpers into the widget tree — screens read keys directly (`data['content']`,
`faq['question']`, `data['email']`, etc.) with no `fromJson`/typed class layer. This is a deliberate
simplicity choice (content payloads are display-only, no client-side validation/mutation needed) but means
there is zero compile-time safety on key names — a backend key rename (e.g. `content` → `body`) would only
be caught by `_extractContentMap`'s multi-shape tolerance (`content_service.dart:95-113`) or, if that
tolerance doesn't cover it, by a runtime "No content available." fallback with no error surfaced.

### Content payload shape (as consumed by `ContentScreen`)
```
{ "content": "<p>HTML...</p>" }   -- only key actually read (content_screen.dart:127)
```

### FAQ item shape (as consumed by `FaqScreen`)
```
{ "question": "...", "answer": "..." }   -- both read via .toString(), no null-safety beyond ?? '' (faq_screen.dart:107-110)
```

### Contact Us payload shape (as consumed by `ContactUsScreen`)
```
{
  "email": "...", "toll_free": "...", "phone": "...", "whatsapp": "...",
  "office_address": "...", "registered_address": "...", "working_hours": "...",
  "facebook": "...", "twitter": "...", "instagram": "...", "website": "..."
}
```
All 11 keys are optional — `_resolve` treats missing/blank as "don't render" (`contact_us_screen.dart:22-26`).

## Secure Storage

None. This module touches no `flutter_secure_storage` keys, no tokens, no MPIN/biometric state.

## Screenshot/App-Lock Behavior

None applied and none needed — all content here is either public legal text or public contact info, no
PAN/bank/OTP-class sensitive data.
