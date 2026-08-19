---
module: Content
last_updated: 2026-08-19
---

# Content — Coverage Tracker

## Round 1 — Build (2026-08-19)

Full build from scratch (previous brain status: ⬜ not built). All 3 source files under
`lib/features/content/screens/` read in full: `content_screen.dart`, `faq_screen.dart`,
`contact_us_screen.dart`. Also read in full: `lib/core/services/content_service.dart` (this module's entire
data layer, shared with `onboarding`). Cross-referenced `lib/routes/app_router.dart` (all 6 route
registrations + every inbound `Navigator.pushNamed` call site via project-wide grep),
`lib/core/config/app_config.dart` (`encryptedEndpoints`), `pubspec.yaml` (confirmed
`flutter_widget_from_html_core` vs. `webview_flutter` dependency presence), and grepped all `webview_flutter`/
`WebView` usages project-wide to confirm this module doesn't use either.

### Weighted Coverage Calculation

| Category | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens documented | 25% | 3 (`ContentScreen`, `FaqScreen`, `ContactUsScreen`) | 3 | 25% |
| Controller/service public methods documented | 25% | 7 (`ContentService` methods, incl. the 1 shared with onboarding) | 7 | 25% |
| Models documented | 15% | 0 dedicated model classes (deliberate — raw `Map`/`List` throughout); documented as a confirmed architectural choice, not a gap | N/A — fully accounted for | 15% |
| API endpoints documented | 15% | 7 (6 content-scope + 1 shared onboarding endpoint) | 7 | 15% |
| Business rules captured | 10% | 9 rules (RULE-CONTENT-001 to 009) | 9 | 10% |
| Cross-module deps captured | 10% | 6 inbound callers + 10 outbound deps, Mermaid graph, onboarding-sharing noted | all found via exhaustive grep | 10% |
| **Total** | **100%** | | | **100%** |

### Manual Spot-Check (required for 🔵)

Re-verified 3 files against the written docs after drafting:
1. `lib/features/content/screens/content_screen.dart` — confirmed `_sanitizeHtml` strips exactly 3 CSS
   properties + decodes a fixed entity set, `_injectLoraSpans` regex `[\d₹%\.,:/+×]+`, and the
   `data['content'] ?? '<p>No content available.</p>'` fallback.
2. `lib/features/content/screens/faq_screen.dart` — confirmed the forced `ref.invalidate(faqsProvider)` in
   `initState`'s post-frame callback (RULE-CONTENT-005), confirmed `_sanitizeHtml` is **not** called here
   (RULE-CONTENT-003 asymmetry), confirmed the numeric regex differs from `ContentScreen`'s by one
   character (`\-`).
3. `lib/core/services/content_service.dart` — confirmed all 7 providers, confirmed every `getXxx()` method
   `rethrow`s on error (no swallow-to-empty like Support's `getEnquiries`), confirmed
   `_extractContentMap`/`_extractFaqList`'s exact tolerated shapes.

No discrepancies found between docs and code on spot-check.

### Badge: 🔵 100% + verified

## Priorities for Round 2 (if source changes)

- If `_sanitizeHtml` is ever added to `FaqScreen` (closing the RULE-CONTENT-003 gap) or the Lora-injection
  logic is extracted to a shared util (closing the RULE-CONTENT-004 duplication), update MODULE_BRAIN.md's
  Top Risks list and re-verify both files' regexes match.
- If `/about` is ever wired to a navigation entry point, re-audit and reclassify RULE-CONTENT-009 as
  resolved (mirror the same check for Support's `/support`).
- If dedicated model classes are ever introduced for content payloads (replacing the raw `Map`/`List`
  pattern), re-score the "Models documented" category against the new classes rather than "N/A".
