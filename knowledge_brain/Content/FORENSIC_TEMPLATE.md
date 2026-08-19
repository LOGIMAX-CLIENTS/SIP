---
module: Content
last_updated: 2026-08-19
round: 1
---

# Content — Forensic Template (Symptom → Suspects)

## Symptom: Terms & Conditions / Privacy / Refund Policy page shows "No content available."

**Check first**: `ContentService._extractContentMap`'s tolerated shapes
(`core/services/content_service.dart:95-113`) against the actual `content/terms|privacy|refund-policy`
response body.

**Likely suspects**:
1. Server response doesn't contain a `content` key under any of the 4 tolerated shapes ({data:{content}},
   {data:{body}}, flat {content}, {data:"string"}) — `_extractContentMap` returns `{}`, and
   `content_screen.dart:127` falls back to the literal string `'<p>No content available.</p>'`. This is
   silent — no error is raised, so the screen looks "successful" but empty.
2. If the page instead shows the **error** state (not "No content available."), the request itself failed
   — `ContentService`'s getters `rethrow` on any exception (`content_service.dart:22-86`), so check network/
   auth/5xx first via Dio logs.

## Symptom: A content page's text has words broken mid-letter or the whole paragraph runs off-screen without wrapping

**Check first**: Whether the affected screen is `ContentScreen` (has `_sanitizeHtml`) or `FaqScreen`'s
answer body (does **not** call `_sanitizeHtml`, only `_injectLoraSpans`) — RULE-CONTENT-003.

**Likely suspects**:
1. If on a Terms/Privacy/About/Refund page: `_sanitizeHtml` (`content_screen.dart:62-88`) should already
   strip `text-align: justify`/`word-break: break-all|break-word`/`white-space: nowrap` — if the bug
   persists there, the server HTML is using a 4th problematic CSS property not yet in the strip list, or an
   `!important` variant the regex doesn't match (regex is case-insensitive but assumes a specific `prop:
   value;` shape).
2. If on the FAQ page: `FaqScreen` never runs `_sanitizeHtml` at all — any of those 3 CSS properties in FAQ
   answer HTML will reproduce the exact bug `ContentScreen` was built to avoid. This is the most likely
   root cause for an FAQ-specific instance of this symptom.

## Symptom: Rupee symbol (₹) or a numeric value renders in the wrong font (should be Lora, shows as Playfair Display or vice versa)

**Check first**: Which screen — `ContentScreen`'s numeric regex is `[\d₹%\.,:/+×]+`
(`content_screen.dart:32`), `FaqScreen`'s is `[\d₹%\.,:/+\-×]+` (`faq_screen.dart:29`, includes an extra
hyphen). A value like a date range or negative percentage with a `-` character will be treated differently
between the two screens.

**Likely suspects**:
1. The numeric run contains a character outside both regexes (e.g. a currency other than ₹, or a comma-less
   large number format) — neither implementation is a full number-format parser, both are best-effort regex.
2. The two implementations have drifted (RULE-CONTENT-004) — if a fix is applied to one file's regex but
   not the other, the two screens will visibly disagree on identical numeric text.

## Symptom: FAQ list is empty or stale every time the screen is opened

**Check first**: Whether "stale" or "empty" — these have different causes given RULE-CONTENT-005's forced
invalidation.

**Likely suspects**:
1. "Empty every time" — `content/faqs` is genuinely returning an empty list/shape `_extractFaqList` doesn't
   recognize (`content_service.dart:119-141`) — since `FaqScreen` force-refetches on every visit
   (`faq_screen.dart:62-64`), staleness is not the explanation; a persistent empty result points at the
   server payload itself.
2. "Was showing FAQs, now suddenly empty after a recent change" — check if someone added `.autoDispose` or
   removed the `initState` invalidation, which would reintroduce caching and could show a stale empty result
   from an earlier failed fetch.

## Symptom: Contact Us page shows almost nothing (just the section header, no cards)

**Check first**: The raw `content/contact-us` response — is it actually populated server-side?

**Likely suspects**:
1. This is very likely **working as designed**, not a bug — RULE-CONTENT-006: `ContactUsScreen` renders
   zero hardcoded fallback content; if the API genuinely returns mostly blank/missing fields, the screen
   legitimately renders mostly empty. Confirm with the actual API response before treating as a client bug.
2. If the API response does contain values but the screen still shows blank, check `_resolve`
   (`contact_us_screen.dart:22-26`) — it requires the value to be a `String` with non-whitespace content
   after `.trim()`; a non-string JSON type (e.g. a nested object) for one of the 11 keys would silently
   resolve to `null` and hide that card.
3. Note there is **no Retry button** on this screen's error state (`contact_us_screen.dart:47-63`) — if the
   symptom is actually a failed fetch (not an empty-but-successful response), the user has no in-screen way
   to retry; they must navigate away and back to re-trigger the `contactUsProvider` fetch.

## Symptom: "About Us" content can't be found / users report no About page in the app

**Check first**: Confirm this is expected given RULE-CONTENT-009 — `/about` is registered
(`app_router.dart:269-272`, `aboutUsProvider` fully wired) but has zero navigation call sites anywhere in
`lib/`.

**Likely suspects**:
1. This is a genuine product gap, not a runtime bug — someone needs to add a
   `Navigator.pushNamed(context, AppRouter.about)` call site (e.g. in `profile_screen.dart`'s side menu,
   alongside the existing Terms/Privacy/Refund/FAQ/Contact items) if About Us should be user-reachable.
