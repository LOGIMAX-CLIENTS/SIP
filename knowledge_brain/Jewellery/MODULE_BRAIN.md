---
module: jewellery
brain_status: 🟢 (≥80%, not yet manually spot-checked for 🔵)
last_updated: 2026-08-19
source_files_read: 2/2 feature files + 3 cross-module context files
primary_documentation: true
---

# Jewellery Module Brain

> **This is primary documentation.** `STARTGOLD_DOCUMENTATION.md` does not cover `jewellery` at all
> (newest module, added after that doc was written, per `.agents/config.md`). Every claim below is
> grounded directly in live code.

## 1. Conclusion First — What This Feature Actually Is

**`jewellery` is a marketing "Coming Soon" placeholder screen. It is NOT a product catalog for
purchasing physical jewellery, and NOT a redemption feature for converting digital gold/silver
holdings into physical jewellery.** This conclusion is based on tracing every line of both files in
the module, not on the folder/tab name:

- The screen's own doc comment calls it a **"Jewellery 'Coming Soon' screen"**
  (`jewellery_screen.dart:14`).
- The hero content, verified by direct read (`_buildHeroSection`, `:184-263`), is purely
  promotional copy: **"Stay Tuned...!"** and **"Right Route for Bright Jewellery Solutions"** — no
  price, no SKU, no "Buy", "Add to Cart", "Redeem", or "Convert" call-to-action anywhere in the
  file.
- The only interactive element besides scrolling is a **"Back to Home"** floating action button
  (`:29-64`) that calls `Navigator.of(context).pop()` — there is no purchase flow, no navigation to
  a checkout/payment screen, no navigation to `withdrawal` or any redemption screen.
- `JewelleryService.getJewelleryImages()` (`jewellery_service.dart:14-32`) calls
  `POST jewellery/jewellery-image` and returns a flat `List<String>` of `image_url` values — the
  response shape (`{success, data: [{image_url: "..."}]}`) has **no price field, no product ID, no
  weight, no inventory/stock field, no redemption-eligibility field** — it is structurally
  incapable of representing a shoppable catalog or a redemption calculator. It is exactly what the
  screen renders it as: a scrollable list of decorative promotional images
  (`jewellery_screen.dart:120-172`, `Image.network` in a `ClipRRect`, `BoxFit.cover`).
- `lib/features/home/` (the portfolio/holdings module) has **zero references** to `jewellery`,
  `Jewellery`, `redeem`, or `Redeem` anywhere (repo-wide grep, zero matches) — confirming there is
  no holdings-to-jewellery conversion/redemption wiring anywhere in the app today.

In short: **jewellery is an unbuilt future feature, currently represented only by a static
"stay tuned" landing page whose sole dynamic content is a set of backend-served promotional
images.** Any richer functionality (catalog, redemption, cart) does not exist in the codebase as of
this brain's build date — this is new information for the project team, since the module name and
its bottom-nav placement (alongside Home/Invest/History/Profile) could easily suggest a fully-built
feature to someone who hasn't read the code.

## 2. Files

| File | Lines | Role |
|---|---|---|
| `jewellery_screen.dart` | 264 | `ConsumerWidget` — the entire UI: hero text, "Back to Home" FAB, and a scrollable list of API-fetched promotional images. |
| `jewellery_service.dart` | 33 | Single-method service: `getJewelleryImages()` calls `POST jewellery/jewellery-image` via the shared `ApiClient` and returns the `image_url` list. |

No `screens/`, `controller/`, `models/`, or `widgets/` subfolders — same flat 2-file shape as
`invoice`.

## 3. Housekeeping Flag — `jewellery.zip`

`lib/features/jewellery.zip` (3,451 bytes, sits as a sibling to the `jewellery/` folder, not inside
it) exists alongside the live module. **Not extracted or touched** per task scope — flagging its
existence only. It is most plausibly a stray backup/leftover from whoever last edited this module
(zip file dated same day as the folder per filesystem listing) and is very likely safe to delete,
but that decision belongs to the project owner, not this brain-build.

## 4. Screen/Route Table

| Route constant | Path | Screen | Registered | Entry point |
|---|---|---|---|---|
| `AppRouter.jewellery` | `/jewellery` | `JewelleryScreen` | `lib/routes/app_router.dart:126,376` | Bottom-nav "Jewellery" tab (index 4) in `main_screen.dart:76-77,223` — see §5 |

## 5. Navigation Mechanics (notable — differs from the other 4 tabs)

`main_screen.dart`'s bottom nav has 5 items: Home(0), Invest(1), History(2), Profile(3),
Jewellery(4). The first four are `IndexedStack` pages swapped via `selectedTabProvider`
(`main_screen.dart:23`). **Jewellery is explicitly excluded from that pattern** — the code comment
says it directly: *"Jewellery is a separate route, not in IndexedStack — navigate without changing
tab index"* (`main_screen.dart:75`). Tapping the Jewellery nav item does
`Navigator.of(context).pushNamed('/jewellery')` (`:77`) and **returns immediately** without
touching `selectedTabProvider` — so the bottom nav's visual "selected" state never actually
switches to Jewellery; whichever of the first 4 tabs was active stays highlighted underneath, and
the pushed route sits on top of it. Backing out (via the FAB or the system back gesture) pops back
to that same underlying tab, not to a dedicated Jewellery tab state.

## 6. `JewelleryService.getJewelleryImages()` (`jewellery_service.dart:14-32`)

- Calls `_apiClient.post('jewellery/jewellery-image')` — **no request body** (`:16`).
- Expects `{success: true, data: [{image_url: "..."}, ...]}` (`:13` doc comment, `:17-19` shape
  check).
- Filters the list to only items that are a `Map` with a non-null `image_url`
  (`:21-22`), maps to `List<String>`.
- On unexpected shape (missing `success`/`data`, or `data` not a `List`): logs via
  `SecureLogger.e` and returns an **empty list** (`:26-27`) rather than throwing — the screen's
  `data:` branch would then just render zero image cards (no explicit "no data" empty state
  distinct from "zero images returned").
- On any thrown exception (network error, parse error): logs and **rethrows** (`:28-31`) — this is
  what actually reaches the screen's Riverpod `error:` branch.

No encryption: `jewellery/jewellery-image` is confirmed absent from
`AppConfig.encryptedEndpoints` (`core/config/app_config.dart:47+`) — consistent with the doc
comment "This is public display data — NO encryption required" (`jewellery_service.dart:7`).

## 7. `JewelleryScreen` (`jewellery_screen.dart:19-264`)

`ConsumerWidget` (stateless, Riverpod-aware) watching a single module-local provider:

```dart
final jewelleryImagesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return JewelleryService().getJewelleryImages();
});
```
(`:10-12`) — `autoDispose` means the fetch re-runs every time the screen is pushed (consistent with
it being a pushed route, not a kept-alive `IndexedStack` tab).

`build()` renders, top to bottom: `GradientHeader(title: 'Jewellery')` (shared widget, same as
other feature headers) → an `AsyncValue.when` over `jewelleryImagesProvider`:
- `loading` → centered spinner.
- `error` → icon + "Failed to load jewellery data" + a "Retry" button that calls
  `ref.invalidate(jewelleryImagesProvider)` (`:83-109`).
- `data` → `_buildHeroSection()` (static promotional text/asset) followed by one `Image.network`
  card per URL returned (`:110-176`), each with its own loading placeholder and an
  `errorBuilder` fallback (a generic diamond icon, `:154-169`) if an individual image fails to
  load.

A floating "Back to Home" button (`:29-64`, green-gradient pill, `AppTheme.greenGradient`) pops the
route.

## 8. `assets/jewellery/` — Confirmed Empty

`pubspec.yaml:92` declares `assets/jewellery/` as an asset directory, but the actual folder
contains only a `.gitkeep` placeholder (verified via directory listing) — **no bundled images**.
This confirms the module does not ship a local/offline image catalog; all visual content is fetched
live from the backend via `getJewelleryImages()` (§6). The only *local* jewellery-related asset
actually used is `assets/images/jewellery-bottomline.png` (a decorative underline graphic,
`jewellery_screen.dart:216`) and the two bottom-nav icons `assets/footer/jewelley-green.svg` /
`assets/footer/jewelley-grey.svg` (note: **misspelled "jewelley" in both filenames**, consistently,
referenced from `main_screen.dart:223` — a real filename typo in the codebase, not a rendering bug
since both nav-icon files share the same misspelling and are referenced consistently).

## 9. Top Risks / Open Questions

1. **Feature is unbuilt** — the "Coming Soon" framing is explicit in code, but a user landing here
   from the bottom nav gets no indication of *when* or *what* the eventual feature will be beyond
   the hero copy.
2. **Bottom-nav selection state doesn't reflect the Jewellery tab being active** (§5) — a UX
   nuance, not a crash risk.
3. **Empty-images vs. failed-fetch are visually different but both silently "fine"** — an empty
   `data: []` array renders a blank scroll area below the hero section with no explicit "nothing to
   show yet" messaging (only the `error:` branch has messaging); unconfirmed whether product intends
   a distinct empty state.
4. **No relationship to portfolio/holdings whatsoever** — confirmed absence, worth stating plainly
   so nobody assumes a redemption feature exists here.
5. **`jewellery.zip` stray file** (§3) — housekeeping only.

## 10. Related Docs

`METHOD_INDEX.md` · `DATA_FLOW.md` · `BUSINESS_RULES.md` · `CROSS_MODULE_MAP.md` ·
`STATE_ANALYSIS.md` · `FORENSIC_TEMPLATE.md` · `COVERAGE_TRACKER.md` (this folder).
