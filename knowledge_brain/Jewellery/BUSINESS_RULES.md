---
module: jewellery
last_updated: 2026-08-19
primary_documentation: true
---

# Jewellery — Business Rules

Because this module is a placeholder screen (see MODULE_BRAIN.md §1), most entries below document
the *absence* of expected e-commerce/redemption rules alongside the few rules that genuinely exist.

## RULE-JEWELLERY-001 — This is a "Coming Soon" placeholder, not a live catalog or redemption feature
Explicit in the screen's own doc comment: *"Jewellery 'Coming Soon' screen"*
(`jewellery_screen.dart:14`), backed by hero copy "Stay Tuned...!" / "Right Route for Bright
Jewellery Solutions" (`:189-259`) and the total absence of any purchase, cart, or redemption code
path. Status: confirmed by full code read. This is the module's single most important fact and the
one most likely to surprise someone reasoning from the module/tab name alone.

## RULE-JEWELLERY-002 — Promotional images are entirely backend-controlled, no local fallback catalog
`JewelleryService.getJewelleryImages()` fetches `POST jewellery/jewellery-image` with no request
parameters and returns whatever URLs the backend supplies (`jewellery_service.dart:14-32`).
`assets/jewellery/` (declared in `pubspec.yaml:92`) contains only a `.gitkeep` — no bundled/offline
images exist. Status: implemented as designed; if the backend endpoint is down, no images render
except the error-state UI (RULE-JEWELLERY-003).

## RULE-JEWELLERY-003 — API failure shows a retry-capable error state; malformed response shows silently-empty content
Two distinct failure modes are handled differently:
- **Thrown exception** (network error, non-2xx, parse failure) → `rethrow`
  (`jewellery_service.dart:30`) → surfaces as the Riverpod `error:` branch → explicit "Failed to
  load jewellery data" + Retry button (`jewellery_screen.dart:83-109`).
- **200 response with unexpected shape** (missing `success`/`data`, or `data` not a `List`) → logs
  via `SecureLogger.e` and returns `[]` (`jewellery_service.dart:26-27`) → this is **not** an
  error to the Riverpod provider — it's a successful `data: []` — so the screen renders the hero
  section with zero image cards below it and no explicit "nothing here yet" messaging. Status:
  implemented; the two failure modes are visually distinguishable to a developer reading logs but
  **not** to the end user (both a genuinely-empty catalog and a malformed response look identical
  in the UI — blank space below the hero text).

## RULE-JEWELLERY-004 — No encryption on this endpoint (by design, public display data)
`jewellery/jewellery-image` is confirmed absent from `AppConfig.encryptedEndpoints`
(`core/config/app_config.dart:47+`), consistent with the service's own doc comment: *"This is
public display data — NO encryption required"* (`jewellery_service.dart:7`). Status: implemented,
and correctly scoped — there is no sensitive field (no PII, no financial amount) in either the
request (none) or response (image URLs only).

## RULE-JEWELLERY-005 — Bottom-nav tab selection does not visually switch to Jewellery
Tapping the Jewellery nav item pushes `/jewellery` as a new route without updating
`selectedTabProvider` (`main_screen.dart:71-79`, explicit code comment at `:75`: *"Jewellery is a
separate route, not in IndexedStack — navigate without changing tab index"*). Status: implemented
intentionally (per the comment), but worth flagging as a UX nuance — the nav bar's highlighted item
stays on whatever tab was active before the tap.

## RULE-JEWELLERY-006 (informational) — No relationship to portfolio/holdings exists in code today
Repo-wide grep for `jewellery`/`Jewellery`/`redeem`/`Redeem` inside `lib/features/home/` and
`lib/core/providers/portfolio_provider.dart` returns zero matches. Status: confirmed absence — if
the product intent is eventually "redeem digital gold for physical jewellery," none of that
wiring exists yet; this module today is purely a static teaser fetch-and-display screen.

## Rules explicitly NOT found (checked for, absent)
- No minimum/maximum order rules (there is no order).
- No pricing/rate logic, no `timer_provider.dart` rate-lock usage (contrast with
  `instant_saving`/`sip`/`withdrawal` per `AGENTS.md` §2) — there is nothing to price.
- No GST/tax handling — no transaction exists to tax.
- No screenshot-block or app-lock suppression logic in `jewellery_screen.dart` — consistent with
  the screen showing no sensitive data (public promotional images only), so this is not a gap per
  `AGENTS.md` §3's guidance (which is scoped to PAN/bank/OTP-bearing screens).
- No tap handler on any image card — images are purely decorative, not clickable
  product tiles.
