---
module: Content
last_updated: 2026-08-19
round: 1
---

# Content — Business Rules

## RULE-CONTENT-001: All content is server-fetched, never bundled with the app

Every content surface (terms, privacy, about, refund, FAQ, contact) goes through a `FutureProvider` →
`ContentService` → `ApiClient.post('content/<endpoint>')` chain (`core/services/content_service.dart:22-86`).
There is no local asset JSON/Markdown file backing any of these screens, and no cached-fallback-on-error
path — a failed request always surfaces the `error` `AsyncValue` branch, never silently falls back to
bundled copy. This directly answers the task brief's open question: **server-fetched, not bundled.**

## RULE-CONTENT-002: HTML rendering goes through `flutter_widget_from_html_core`, not a WebView

`ContentScreen` and `FaqScreen`'s answer bodies both use `HtmlWidget` from `flutter_widget_from_html_core`
(`content_screen.dart:4`, `faq_screen.dart:4`). `webview_flutter` is a pubspec dependency
(`pubspec.yaml:66-68`) but is used exclusively by `features/kyc/widgets/aadhaar_digilocker_webview.dart`
and `features/home/widgets/offer_webview_screen.dart` — confirmed via project-wide grep, zero hits inside
`features/content/`. Any future content requiring JS execution or full browser chrome (rather than a
Flutter-widget-tree HTML render) would need a new screen, not a `ContentScreen` variant.

## RULE-CONTENT-003: Server HTML is sanitized before rendering — 3 known problematic CSS properties are stripped

`ContentScreen._sanitizeHtml` (`content_screen.dart:62-88`) strips `text-align: justify` (caused mid-word
line breaks), `word-break: break-all`/`break-word` (broke words mid-letter), and `white-space: nowrap`
(prevented wrapping) from inline `style=""` attributes, because `flutter_widget_from_html_core` doesn't
process `<style>` blocks and these 3 properties visibly broke rendering. It also decodes a fixed set of
HTML entities (`&#39;`, `&#x27;`, `&#34;`, `&#x22;`, `&amp;`, `&lt;`, `&gt;`, `&nbsp;`, `&#8377;` → `₹`).
**`FaqScreen` does NOT apply `_sanitizeHtml`** — only `_injectLoraSpans` with its own narrower entity
decode (`&#8377;` only, `faq_screen.dart:46`). If FAQ answer HTML from the backend ever contains
`text-align: justify` or `word-break`, it will render with the same visual bug `ContentScreen` was built to
avoid — this is an unconfirmed but plausible gap, not yet observed in production.

## RULE-CONTENT-004: Numeric text (digits, ₹, %, punctuation) always renders in Lora; body text renders in Playfair Display

Enforced by regex-based post-processing that wraps numeric runs in `<span style="font-family: Lora,
serif;">` before handing HTML to `HtmlWidget`, and by `NumericStyledText` for plain (non-HTML) text like
FAQ questions and contact card values. Two independent implementations exist:
`ContentScreen._injectLoraSpans`/`_wrapNumericsInText` (`content_screen.dart:40-99`, numeric regex
`[\d₹%\.,:/+×]+`) and `FaqScreen._injectLoraSpans`/`_wrapNumericsInText` (`faq_screen.dart:29-54`, numeric
regex `[\d₹%\.,:/+\-×]+` — note the extra `\-` hyphen character not present in `ContentScreen`'s regex, a
small but real inconsistency). A typography rule change must be applied in both places.

## RULE-CONTENT-005: FAQ content is force-refetched on every screen visit; other content screens cache normally

`FaqScreen.initState` unconditionally calls `ref.invalidate(faqsProvider)` in a post-frame callback
(`faq_screen.dart:59-65`) — every navigation to `/faq` triggers a fresh `content/faqs` API call, discarding
any previously cached result. `ContentScreen` and `ContactUsScreen` have no equivalent — their providers
retain Riverpod's default cache-until-invalidated behavior, so re-visiting `/terms` (for example) within the
same app session does not refetch. No comment in the code explains why FAQ is treated differently; treat
this as an intentional-but-undocumented product decision, not a bug, unless proven otherwise.

## RULE-CONTENT-006: Contact Us shows a field only if the API actually returned it — no hardcoded fallback values

`ContactUsScreen._resolve` (`contact_us_screen.dart:22-26`) returns `null` for missing/blank string values;
every contact card and social icon is wrapped in an `if (_resolve(data, key) != null) ...` spread
(`contact_us_screen.dart:148-242`). Explicitly documented in the code's own doc comment ("no hardcoded
fallback" — line 21). This means the Contact Us screen can legitimately render as almost empty (just the
"Help & Support" section label) if the backend returns a mostly-empty payload — there is no minimum
guaranteed content.

## RULE-CONTENT-007: `content/*` and `users/content/onboarding` endpoints carry no field-level encryption

None of `content/terms`, `content/privacy`, `content/faqs`, `content/about-us`, `content/contact-us`,
`content/refund-policy`, or `users/content/onboarding` appear in `AppConfig.encryptedEndpoints`
(`core/config/app_config.dart:47+`) — expected, since none of these calls send or receive PII/financial
data (all are unauthenticated-style content reads, no request body beyond the implicit POST).

## RULE-CONTENT-008: `content_service.dart` is shared infrastructure between `content` and `onboarding` features

`core/services/content_service.dart` hosts 7 providers; 6 belong to this module's screens and 1
(`onboardingContentProvider`, backed by `getOnboardingContent()` → `users/content/onboarding`) is consumed
exclusively by `features/onboarding/onboarding_screen.dart`. This is a deliberate `core/`-layer sharing
pattern, not a layering violation — see `AGENTS.md` §1 ("cross-feature reuse goes through ... `lib/core/`").

## RULE-CONTENT-009 (informational): `/about` route is registered but unreachable

`ContentScreen(title: 'About Us', provider: aboutUsProvider)` is wired to `AppRouter.about` (`/about`,
`app_router.dart:269-272`) but has zero `Navigator.pushNamed(..., AppRouter.about)` call sites anywhere in
`lib/` (exhaustive grep). The About Us content is fully functional if reached (same rendering pipeline as
Terms/Privacy/Refund) — it is simply never linked from any menu, button, or onboarding flow found in the
codebase. Same class of finding as Support's `RULE-SUPPORT-008` (`/support` dead route).
