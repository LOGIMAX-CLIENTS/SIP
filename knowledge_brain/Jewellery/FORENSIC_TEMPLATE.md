---
module: jewellery
last_updated: 2026-08-19
primary_documentation: true
---

# Jewellery — Forensic Template

Symptom → check first → likely suspects, for bug triage in this module.

## 1. Jewellery tab shows a blank screen below the hero text

**Check first**: is `POST jewellery/jewellery-image` returning `data: []` (a genuinely empty list,
which is a valid 200 response) versus a malformed shape that got silently coerced to `[]`
(`jewellery_service.dart:26-27`)? Both look identical in the UI — no distinct "no images yet"
messaging exists (RULE-JEWELLERY-003). Check `SecureLogger.e` output for `'JewelleryImages:
unexpected response format'` to distinguish the two.

**Likely suspects**: backend returning an empty promotional-image set intentionally (expected,
not a bug); or a backend response-shape change (e.g. renamed `image_url` to `imageUrl`) that the
client's shape check (`item['image_url'] != null`, `:22`) now silently filters out entirely.

## 2. Jewellery tab shows the error state ("Failed to load jewellery data")

**Check first**: is this a genuine network/HTTP failure, or a non-2xx response that `ApiClient`'s
interceptor chain (`core/security/api_interceptor.dart`) converted into a thrown exception before
`JewelleryService` even saw the response body? Confirm via `SecureLogger.e('JewelleryImages
error: ...')` output (`jewellery_service.dart:29`) for the actual exception type/message.

**Likely suspects**: standard network/auth failure paths shared with every other module using
`ApiClient` (401→refresh, 409→force logout, connectivity) — nothing jewellery-specific here since
this module doesn't deviate from the shared client (contrast with `invoice`).

## 3. Individual image card shows a diamond placeholder icon instead of the actual image

**Check first**: is this a single bad URL (dead link, expired signed URL, wrong content-type) or
every image failing? `errorBuilder` (`jewellery_screen.dart:154-169`) fires per-`Image.network`
widget independently — one bad URL among several good ones will show exactly one placeholder, which
is expected/working behavior, not a systemic bug.

**Likely suspects**: backend-served image URLs pointing to expired/signed URLs with a short TTL, or
a CDN/hosting issue outside this module's control — this module does no URL validation or retry of
its own beyond what `Image.network`'s built-in loading does.

## 4. Tapping "Jewellery" in the bottom nav does nothing / navigates to the wrong screen

**Check first**: confirm `_onTabTapped`'s `index == 4` special case (`main_screen.dart:76-77`)
still matches the Jewellery nav item's actual index in `_buildNavItem` calls (`:219-223`) — these
are two separately-maintained integer literals (the special-case check and the nav item list order)
with no shared constant/enum tying them together. If a nav item is ever reordered or added without
updating both spots, this silently breaks (wrong tab pushed as a route, or Jewellery gets treated
as an `IndexedStack` page it was never built to be).

**Likely suspects**: nav-bar reordering elsewhere in `main_screen.dart` without a corresponding
update to the `index == 4` literal.

## 5. Someone reports "I couldn't buy the jewellery I saw in the app" / "how do I redeem gold for jewellery"

**Check first**: this is almost certainly a support/product question, not a bug — per
MODULE_BRAIN.md §1, there is genuinely no purchase or redemption flow implemented anywhere in the
codebase. Before treating this as an app bug, confirm with product/support whether this is expected
(the "Coming Soon" framing is honest about this) or whether there's a customer-facing expectation
mismatch (e.g. marketing material implying a live feature).

**Likely suspects**: none in code — this is a product/communication question, not an engineering
defect, given the current implementation.

## 6. Retry button on the error state doesn't seem to refetch

**Check first**: `ref.invalidate(jewelleryImagesProvider)` (`jewellery_screen.dart:102`) should
force a rebuild of the `FutureProvider.autoDispose`. Confirm the underlying `ApiClient` call is
actually re-firing (check network logs) versus the UI simply not re-rendering the loading state
briefly enough to notice before immediately re-erroring (e.g. backend is consistently down, so the
retry "appears" to do nothing because it fails again quickly).

**Likely suspects**: transient backend outage masking the retry actually working; no code-level
bug found in the invalidate wiring itself.
