---
module: jewellery
last_updated: 2026-08-19
primary_documentation: true
---

# Jewellery — Data Flow

Only one real flow exists: fetch and display promotional images. There is no purchase flow, no
redemption flow, and no cart/checkout flow anywhere in this module (see MODULE_BRAIN.md §1 for the
full reasoning) — this doc includes an explicit "does NOT happen" section so nobody assumes a
richer flow exists.

## Flow 1: Open Jewellery tab → fetch and render promotional images

```
User taps "Jewellery" in the bottom nav (index 4)                    (main_screen.dart:223)
  → _onTabTapped(4)                                                  (main_screen.dart:71-79)
      → index == 4 special-cased: does NOT update selectedTabProvider  (:75-78)
      → Navigator.of(context).pushNamed('/jewellery')                 (:77)
  → AppRouter resolves '/jewellery' → JewelleryScreen()               (app_router.dart:126,376)
  → JewelleryScreen.build() watches jewelleryImagesProvider           (jewellery_screen.dart:25)
      → FutureProvider.autoDispose fires JewelleryService().getJewelleryImages()  (:10-12)
          → ApiClient().post('jewellery/jewellery-image')  — no request body      (jewellery_service.dart:16)
          → response: {success: true, data: [{image_url: "..."}, ...]}
          → filtered/mapped to List<String> of image_url values                  (:20-24)
  → imagesAsync.when(...)                                             (jewellery_screen.dart:77-176)
      loading  → centered CircularProgressIndicator
      data     → GradientHeader + _buildHeroSection() (static "Stay Tuned...!" copy)
                 + one Image.network(url) card per returned URL, each independently
                   loading/erroring (per-image loadingBuilder/errorBuilder)
      error    → error icon + "Failed to load jewellery data" + Retry button
                 → Retry: ref.invalidate(jewelleryImagesProvider) → re-runs the fetch above
  → User taps "Back to Home" FAB (or system back)                      (:46)
      → Navigator.of(context).pop()  → returns to whichever of the first 4 tabs was
        active underneath (bottom-nav selection was never changed — see MODULE_BRAIN.md §5)
```

## Flow 2 (explicitly does NOT happen): Purchase / add-to-cart

There is no `onTap`/`onPressed` anywhere in `jewellery_screen.dart` that navigates to a
product-detail, cart, or payment screen. `Image.network` cards (`:120-172`) are purely decorative —
`ClipRRect` + `Image.network`, no `GestureDetector`/`InkWell` wrapper, no tap handler at all.
Confirmed by full read of both files in the module.

## Flow 3 (explicitly does NOT happen): Redemption / convert digital holdings to physical jewellery

No code path in this module (or in `home`, `withdrawal`, or `core/providers/portfolio_provider.dart`
— repo-wide grep) reads the user's gold/silver holdings balance, calculates a redemption
equivalent, or submits a redemption/conversion request. `JewelleryService` has exactly one method
(`getJewelleryImages`) and it takes no parameters — there is no `weight`, `holdingId`, or
`redemptionAmount` anywhere in its request or response shape. `home`'s `portfolio_provider.dart`
(the module that owns holdings state) has zero references to `jewellery`.

## Summary table

| Flow | Real? | API hit | Persistence | Navigates to |
|---|---|---|---|---|
| Fetch & display promo images | Yes | `POST jewellery/jewellery-image` | None (re-fetched every mount, `autoDispose`) | Stays on `/jewellery`; images render inline |
| Purchase / add-to-cart | **No** — does not exist | — | — | — |
| Redemption of holdings → jewellery | **No** — does not exist | — | — | — |
| Back to Home | Yes | None | None | Pops to whichever underlying tab was active |
