---
module: Content
last_updated: 2026-08-19
round: 1
---

# Content — Data Flows

## Flow 1: Static/legal content (Terms, Privacy, About Us, Refund Policy) — generic `ContentScreen`

```
User navigates to /terms | /privacy | /about | /refund-policy
  (e.g. profile side-menu, registration/login "Terms" link tap — see MODULE_BRAIN.md Route Table)
  → app_router.dart wires the matching FutureProvider (termsProvider / privacyPolicyProvider /
    aboutUsProvider / refundPolicyProvider) into ContentScreen(title, provider)
  → ContentScreen.build (content_screen.dart:104) → ref.watch(provider)
  → provider (core/services/content_service.dart:153-175) → ref.watch(contentServiceProvider)
      .getTermsAndConditions() / .getPrivacyPolicy() / .getAboutUs() / .getRefundPolicy()
  → ApiClient.post('content/terms' | 'content/privacy' | 'content/about-us' | 'content/refund-policy')
      (no field-level encryption — 'content/*' absent from AppConfig.encryptedEndpoints)
  → ContentService._extractContentMap(response.data) (content_service.dart:95-113)
      tolerates: {data:{content:...}}, {data:{body:...}}, {content:...} flat, {data:"<html>"} string
  → on success: contentAsync.when(data: (data) => ...)
      rawHtml = data['content'] ?? '<p>No content available.</p>'
      processedHtml = _injectLoraSpans(_sanitizeHtml(rawHtml))   (content_screen.dart:126-132)
      → HtmlWidget(processedHtml, customStylesBuilder: ...) renders it
  → on error (any exception — ContentService methods rethrow, no swallow):
      error icon + "Failed to load content" + Retry button → ref.invalidate(provider) refetches
```

## Flow 2: FAQ screen — forced-fresh fetch, per-item HTML answers

```
User navigates to /faq (profile side-menu "FAQ" item, profile_screen.dart:279-283)
  → FaqScreen.initState (faq_screen.dart:59) schedules a post-frame callback:
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.invalidate(faqsProvider))
      — this forces a fresh 'content/faqs' call on every screen entry, bypassing Riverpod's normal
        cache-and-reuse behavior (contrast with ContentScreen, which has no equivalent forced invalidation)
  → FaqScreen.build → ref.watch(faqsProvider)
  → faqsProvider (content_service.dart:161-163) → ContentService.getFAQs()
  → ApiClient.post('content/faqs')
  → ContentService._extractFaqList(response.data) (content_service.dart:119-141)
      tolerates: root array, {data:[...]}, {data:{faqs:[...]}}, {data:{data:[...]}}
  → faqsAsync.when:
      data: [] → "No FAQs currently available."
      data: non-empty → ListView.builder → per item: {question, answer} extracted as .toString()
          _buildFaqItem(question, answer, isDark) → ExpansionTile
              title: NumericStyledText(question)   -- auto Playfair/Lora split
              children: [HtmlWidget(_injectLoraSpans(answer), ...)]  -- same numeric-span pattern as
                  ContentScreen, independently re-implemented (faq_screen.dart:29-54)
      error: error icon + "Failed to load FAQs" + Retry (ref.invalidate(faqsProvider))
```

## Flow 3: Contact Us — conditional field rendering, no hardcoded fallback

```
User navigates to /contact (home screen contact tile home_screen.dart:927, or
  profile side-menu "Contact Us" profile_screen.dart:291-295)
  → ContactUsScreen.build (contact_us_screen.dart:29) → ref.watch(contactUsProvider)
  → contactUsProvider (content_service.dart:169-171) → ContentService.getContactUs()
  → ApiClient.post('content/contact-us') → _extractContentMap(response.data)
  → contactInfoAsync.when:
      data: (data) => _buildBody(context, data, isDark) (contact_us_screen.dart:71)
          for each of: email, toll_free, phone, whatsapp, office_address, registered_address,
            working_hours, facebook, twitter, instagram, website
          → _resolve(data, key) returns non-empty trimmed String or null (contact_us_screen.dart:22-26)
          → each field is rendered ONLY if _resolve(...) != null — no field ever shows a hardcoded
            fallback value; entirely dependent on what the API returns
          → tappable cards launch: mailto:<email> | tel:<toll_free/phone digits> |
            https://wa.me/<whatsapp digits> (LaunchMode.platformDefault)
          → social icon tiles launch the raw URL (LaunchMode.externalApplication) via url_launcher
      error: "Failed to load contact info." (no explicit Retry button here, unlike ContentScreen/FaqScreen
        — user must navigate away and back to retry)
```
