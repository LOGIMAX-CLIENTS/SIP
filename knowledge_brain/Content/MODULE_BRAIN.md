---
module: Content
folder: lib/features/content/
brain_status: 🟢 (see COVERAGE_TRACKER.md)
last_updated: 2026-08-19
round: 1
---

# Content — Module Brain

## What this module does

Renders static/legal/informational content that is **entirely server-fetched**, not bundled in the app.
Covers Terms & Conditions, Privacy Policy, About Us, Refund Policy (all via one generic `ContentScreen` that
renders server HTML), a dedicated FAQ screen (accordion, API-driven Q&A), and a dedicated Contact Us screen
(conditionally-rendered contact cards + social links, all values API-driven). The data-fetch layer
(`ContentService` + its Riverpod providers) lives in `core/services/content_service.dart` — **not** inside
`lib/features/content/` — because it's shared with the `onboarding` feature (`onboardingContentProvider`).

## Inventory (3 screen files read, + 1 shared core service)

| File | Role |
|---|---|
| `lib/features/content/screens/content_screen.dart` | Generic `ContentScreen` — HTML content renderer (terms/privacy/about/refund) |
| `lib/features/content/screens/faq_screen.dart` | `FaqScreen` — API-driven FAQ accordion |
| `lib/features/content/screens/contact_us_screen.dart` | `ContactUsScreen` — contact cards + social links |
| `lib/core/services/content_service.dart` | `ContentService` (all `content/*` API calls) + 7 Riverpod providers — shared with `onboarding` |

No `controller/`, `models/`, or `widgets/` subfolders inside `features/content/` — this module has no
feature-owned service layer at all; it consumes `core/services/content_service.dart` directly from every
screen (a deliberate exception documented in `CROSS_MODULE_MAP.md`, not a layering violation since it's a
`core/` service).

## How content is sourced — server-fetched, not bundled (verified)

Every one of the 6 content surfaces goes through a `FutureProvider` that calls `ContentService`, which calls
`ApiClient.post('content/<endpoint>')` (Dio, `core/network/api_client.dart`). **No local asset/JSON bundle
is used anywhere in this module** — confirmed by reading `content_service.dart` in full: every getter
(`getTermsAndConditions`, `getPrivacyPolicy`, `getFAQs`, `getAboutUs`, `getContactUs`, `getRefundPolicy`)
makes a live POST call with `try { ... } catch (e) { rethrow; }` (no cached/hardcoded fallback content).
This confirms and extends `STARTGOLD_DOCUMENTATION.md` §3.40, which names the providers but doesn't say
whether they're server- or asset-backed.

## Rendering mechanism — `flutter_widget_from_html_core`, NOT `webview_flutter`

`ContentScreen` and `FaqScreen`'s answer bodies both render server HTML via `HtmlWidget` from
`flutter_widget_from_html_core` (`pubspec.yaml:65`), **not** `webview_flutter` (`pubspec.yaml:66-68`).
`webview_flutter` **is** a pubspec dependency but this module doesn't use it — it's used elsewhere
(`features/kyc/widgets/aadhaar_digilocker_webview.dart` for DigiLocker KYC, `features/home/widgets/
offer_webview_screen.dart` for promotional offers) — confirmed via project-wide grep for `WebView`/
`webview_flutter`, 9 hits total, none inside `features/content/`.

`ContentScreen` does substantial HTML pre-processing before handing off to `HtmlWidget`
(`content_screen.dart:40-99`):
1. `_sanitizeHtml` strips `text-align: justify`, `word-break: break-all/break-word`, `white-space: nowrap`
   inline styles (these caused layout bugs — mid-word breaks / no-wrap) and decodes HTML entities
   (`&#39;`, `&amp;`, `&nbsp;`, `&#8377;` → `₹`, etc).
2. `_injectLoraSpans` wraps every numeric run (regex `[\d₹%\.,:/+×]+`) in a `<span style="font-family:
   Lora, serif;">` — implements a house typography rule: body text renders in Playfair Display, numerics
   (amounts, %, dates) render in Lora. `FaqScreen` re-implements the identical pattern independently
   (`faq_screen.dart:29-54`) — duplicated logic, not shared via a common util (tech-debt candidate).
3. `customStylesBuilder` applies explicit font-size/weight/color per HTML tag (`h1`/`h2`/`h3`/`strong`/`b`/
   `li`/`p`) since `flutter_widget_from_html_core` doesn't process `<style>` blocks.

## Screens

### ContentScreen (`content_screen.dart`) — generic, parameterized by `title` + `provider`
`ConsumerWidget` taking `title: String` and `provider: FutureProvider<Map<String, dynamic>>` constructor
params. Used 4 times from `app_router.dart` with different providers (terms/privacy/about/refund — see
Route Table). `contentAsync.when(...)`: loading spinner, error state with Retry (`ref.invalidate(provider)`
), data state extracts `data['content']` (defaulting to `'<p>No content available.</p>'`) and pipes it
through `_sanitizeHtml` → `_injectLoraSpans` → `HtmlWidget`.

### FaqScreen (`faq_screen.dart`)
`ConsumerStatefulWidget`. `initState` posts a frame callback that unconditionally calls
`ref.invalidate(faqsProvider)` (line 62-64) — **forces a fresh API call every time the screen is entered**,
bypassing Riverpod's normal caching (contrast with `ContentScreen`, which does no such forced invalidation
and would reuse a cached result on re-entry). Renders each FAQ as an `ExpansionTile`: question via
`NumericStyledText` (auto-splits Playfair/Lora per numeric-run), answer via the same `HtmlWidget` +
Lora-span-injection pattern as `ContentScreen`. Empty state: "No FAQs currently available."; error state:
Retry button.

### ContactUsScreen (`contact_us_screen.dart`)
`ConsumerWidget`, watches `contactUsProvider`. Every field is conditionally rendered via a `_resolve`
helper that returns `null` for missing/blank values — **no hardcoded fallback contact info** anywhere in
this screen (a deliberate design choice per the doc comment at line 21). Contact cards (if present in the
API response): email (`mailto:`), toll_free (`tel:`), phone (`tel:`), WhatsApp (`https://wa.me/<digits>`),
office_address, registered_address, working_hours. Social links (if present): Facebook, X (Twitter),
Instagram, Website — each rendered with a hand-drawn `CustomPainter` icon (no icon-font/SVG asset) and
opened via `url_launcher`. Uses `LaunchMode.platformDefault` for contact-card taps but
`LaunchMode.externalApplication` for social-icon taps (inconsistent launch mode — minor, likely harmless).

## Route Table

| Screen instance | Route constant | Path | Provider | Registered at | Reachable from |
|---|---|---|---|---|---|
| `ContentScreen(title: 'Terms & Conditions')` | `AppRouter.terms` | `/terms` | `termsProvider` | `app_router.dart:261-264` | `auth/registration/registration_screen.dart:52`, `auth/login/login_screen.dart:47`, `profile/profile_screen.dart:265` |
| `ContentScreen(title: 'Privacy Policy')` | `AppRouter.privacy` | `/privacy` | `privacyPolicyProvider` | `app_router.dart:265-268` | `auth/login/login_screen.dart:50`, `profile/profile_screen.dart:271` |
| `ContentScreen(title: 'About Us')` | `AppRouter.about` | `/about` | `aboutUsProvider` | `app_router.dart:269-272` | **Nowhere** — dead route (exhaustive grep for `AppRouter.about` found zero call sites) |
| `ContentScreen(title: 'Refund Policy')` | `AppRouter.refundPolicy` | `/refund-policy` | `refundPolicyProvider` | `app_router.dart:357-360` | `profile/profile_screen.dart:277` |
| `FaqScreen` | `AppRouter.faq` | `/faq` | `faqsProvider` | `app_router.dart:273` | `profile/profile_screen.dart:283` |
| `ContactUsScreen` | `AppRouter.contact` | `/contact` | `contactUsProvider` | `app_router.dart:274` | `home/home_screen.dart:927`, `profile/profile_screen.dart:295` |

## State (Riverpod, all in `core/services/content_service.dart`)

7 `FutureProvider`s, all thin wrappers over `ContentService` methods via `contentServiceProvider`:
`onboardingContentProvider` (consumed by `features/onboarding/`, not `features/content/`), `termsProvider`,
`privacyPolicyProvider`, `faqsProvider`, `aboutUsProvider`, `contactUsProvider`, `refundPolicyProvider`.
None use `autoDispose` — all cache indefinitely except `faqsProvider`, which `FaqScreen` force-invalidates
on every entry (see above).

## Top Risks / Anti-Patterns

1. **`/about` route is dead** — same pattern as Support's `/support` (see `Support/MODULE_BRAIN.md`). About
   Us content is fetched-and-ready (`aboutUsProvider` wired) but unreachable from any UI.
2. **Duplicated Lora-span-injection logic** between `ContentScreen` and `FaqScreen` (near-identical regex +
   algorithm, not extracted to a shared util) — a typography rule change requires editing 2 places.
3. **Inconsistent Riverpod caching semantics** — `FaqScreen` force-refetches every visit;
   `ContentScreen`/`ContactUsScreen` don't. Likely intentional (FAQ content changes more often?) but
   undocumented as a deliberate choice anywhere in the code — flagged as unconfirmed intent.
4. **Response-shape tolerance in `ContentService`** (`_extractContentMap`, `_extractFaqList`) mirrors the
   same defensive multi-shape parsing seen in Support's `EnquiryService.getEnquiries` — another signal the
   backend response contract wasn't nailed down at implementation time across multiple modules.
5. All `getXxx()` methods in `ContentService` `rethrow` on error (unlike `EnquiryService.getEnquiries`,
   which swallows to `[]`) — inconsistent error-handling philosophy between the two sibling modules; here
   it correctly surfaces to the screen's `error` `AsyncValue` branch.

## Cross-Module Dependencies (summary — full detail in CROSS_MODULE_MAP.md)

`core/services/content_service.dart` (the entire data layer), `core/network/api_client.dart`,
`shared/widgets/{gradient_header,numeric_styled_text}.dart`, `shared/theme/app_theme.dart`, `url_launcher`
(social/contact links). Inbound callers: `features/auth/{registration,login}/`, `features/profile/
profile_screen.dart`, `features/home/home_screen.dart`, and `features/onboarding/onboarding_screen.dart`
(shares `content_service.dart` but not the `features/content/` screens).

## Drift vs STARTGOLD_DOCUMENTATION.md §3.40

The hand-written doc's table (screen/route/provider) is accurate on names and routes. It does **not**
mention: the server-fetched-not-bundled confirmation, the HTML rendering mechanism
(`flutter_widget_from_html_core`, not a WebView), the `/about` dead route, or the duplicated Lora-injection
logic — all new findings from this pass, filling gaps rather than correcting errors.
