---
module: Content
last_updated: 2026-08-19
round: 1
---

# Content — Method Index

Alphabetical by `Class.method`. `ContentService` and its providers live in `core/services/content_service.dart`
(shared with `onboarding`), not inside `features/content/` — included here since it's this module's entire
data layer.

## `ContactUsScreen` (`lib/features/content/screens/contact_us_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `_launchUrl(String)` | `contact_us_screen.dart:14` | `_buildBody`'s `onTap` callbacks (email/toll_free/phone/whatsapp) |
| `_resolve(Map<String,dynamic>, String)` | `contact_us_screen.dart:22` | `_buildBody` (called per field: email, toll_free, phone, whatsapp, office_address, registered_address, working_hours, facebook, twitter, instagram, website) |
| `build(BuildContext, WidgetRef)` | `contact_us_screen.dart:29` | Flutter framework (route target for `AppRouter.contact`) |
| `_buildBody(BuildContext, Map, bool)` | `contact_us_screen.dart:71` | `build` (data branch) |

## `_ContactCardState` (private, `contact_us_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `initState()` / `dispose()` | `contact_us_screen.dart:330/339` | Flutter framework |
| `build(BuildContext)` | `contact_us_screen.dart:344` | Flutter framework |

## `_SocialIconTileState` (private, `contact_us_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `_launchUrl(String)` | `contact_us_screen.dart:457` | `build`'s `onTapUp` |
| `initState()` / `dispose()` | `contact_us_screen.dart:465/474` | Flutter framework |
| `build(BuildContext)` | `contact_us_screen.dart:479` | Flutter framework |

## `ContentScreen` (`lib/features/content/screens/content_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `_injectLoraSpans(String)` (static) | `content_screen.dart:40` | `build` (data branch, wraps `_sanitizeHtml` output) |
| `_sanitizeHtml(String)` (static) | `content_screen.dart:62` | `build` (applied before `_injectLoraSpans`) |
| `_wrapNumericsInText(String)` (static) | `content_screen.dart:92` | `_injectLoraSpans` (per text node between HTML tags) |
| `build(BuildContext, WidgetRef)` | `content_screen.dart:104` | Flutter framework (route target for `AppRouter.{terms,privacy,about,refundPolicy}`, parameterized by `title`/`provider`) |

## `FaqScreen` / `_FaqScreenState` (`lib/features/content/screens/faq_screen.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `_injectLoraSpans(String)` (static) | `faq_screen.dart:32` | `_buildFaqItem` (applied to each FAQ answer) |
| `_wrapNumericsInText(String)` (static) | `faq_screen.dart:44` | `_injectLoraSpans` |
| `initState()` | `faq_screen.dart:59` | Flutter framework — schedules `ref.invalidate(faqsProvider)` post-frame |
| `build(BuildContext)` | `faq_screen.dart:68` | Flutter framework (route target for `AppRouter.faq`) |
| `_buildFaqItem(String, String, bool)` | `faq_screen.dart:171` | `build`'s `ListView.builder.itemBuilder` |

## `ContentService` (`lib/core/services/content_service.dart`)

| Method | File:Line | Callers |
|---|---|---|
| `getOnboardingContent()` → `Future<List<Map<String,dynamic>>>` | `content_service.dart:8` | `onboardingContentProvider` (consumed by `features/onboarding/onboarding_screen.dart`, not this module) |
| `getTermsAndConditions()` → `Future<Map<String,dynamic>>` | `content_service.dart:22` | `termsProvider` |
| `getPrivacyPolicy()` → `Future<Map<String,dynamic>>` | `content_service.dart:33` | `privacyPolicyProvider` |
| `getFAQs()` → `Future<List<dynamic>>` | `content_service.dart:44` | `faqsProvider` |
| `getAboutUs()` → `Future<Map<String,dynamic>>` | `content_service.dart:55` | `aboutUsProvider` |
| `getContactUs()` → `Future<Map<String,dynamic>>` | `content_service.dart:66` | `contactUsProvider` |
| `getRefundPolicy()` → `Future<Map<String,dynamic>>` | `content_service.dart:77` | `refundPolicyProvider` |
| `_extractContentMap(dynamic)` (static helper) | `content_service.dart:95` | `getTermsAndConditions`, `getPrivacyPolicy`, `getAboutUs`, `getContactUs`, `getRefundPolicy` |
| `_extractFaqList(dynamic)` (static helper) | `content_service.dart:119` | `getFAQs` |

## Providers (top-level, `core/services/content_service.dart`)

| Provider | File:Line | Type | Endpoint | Watched/read by |
|---|---|---|---|---|
| `contentServiceProvider` | `content_service.dart:144` | `Provider<ContentService>` | — | Every provider below (`ref.watch`) |
| `onboardingContentProvider` | `content_service.dart:147` | `FutureProvider<List<Map<String,dynamic>>>` | `users/content/onboarding` | `features/onboarding/onboarding_screen.dart` (not `features/content/`) |
| `termsProvider` | `content_service.dart:153` | `FutureProvider<Map<String,dynamic>>` | `content/terms` | `ContentScreen` (via `AppRouter.terms`) |
| `privacyPolicyProvider` | `content_service.dart:157` | `FutureProvider<Map<String,dynamic>>` | `content/privacy` | `ContentScreen` (via `AppRouter.privacy`) |
| `faqsProvider` | `content_service.dart:161` | `FutureProvider<List<dynamic>>` | `content/faqs` | `FaqScreen` |
| `aboutUsProvider` | `content_service.dart:165` | `FutureProvider<Map<String,dynamic>>` | `content/about-us` | `ContentScreen` (via `AppRouter.about` — dead route) |
| `contactUsProvider` | `content_service.dart:169` | `FutureProvider<Map<String,dynamic>>` | `content/contact-us` | `ContactUsScreen` |
| `refundPolicyProvider` | `content_service.dart:173` | `FutureProvider<Map<String,dynamic>>` | `content/refund-policy` | `ContentScreen` (via `AppRouter.refundPolicy`) |

## Total Public-Surface Counts (for COVERAGE_TRACKER.md)

- Screens: 3 (`ContentScreen` — used 4x with different providers, `FaqScreen`, `ContactUsScreen`)
- Service public methods: 7 (`getOnboardingContent`, `getTermsAndConditions`, `getPrivacyPolicy`,
  `getFAQs`, `getAboutUs`, `getContactUs`, `getRefundPolicy`) — 6 in this module's scope + 1
  (`getOnboardingContent`) belonging to `onboarding`'s data flow but co-located in the same shared file
- Models: 0 dedicated model classes — all content is raw `Map<String,dynamic>`/`List<dynamic>` passed
  straight from `ContentService` to the widget tree (see STATE_ANALYSIS.md)
- API endpoints: 6 in this module's scope (`content/terms`, `content/privacy`, `content/faqs`,
  `content/about-us`, `content/contact-us`, `content/refund-policy`) + 1 shared with onboarding
  (`users/content/onboarding`)
- Providers: 7 total in `content_service.dart`, 6 consumed by this module's screens
