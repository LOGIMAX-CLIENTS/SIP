---
module: jewellery
last_updated: 2026-08-19
primary_documentation: true
---

# Jewellery — State Analysis

## Riverpod providers/notifiers

Exactly one provider, module-local, defined inline in the screen file rather than a separate
`providers/` file:

```dart
final jewelleryImagesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return JewelleryService().getJewelleryImages();
});
```
(`jewellery_screen.dart:10-12`)

| Property | Value | Notes |
|---|---|---|
| Type | `FutureProvider.autoDispose<List<String>>` | No family/parameter — same fetch every time |
| Disposal | `autoDispose` | State is discarded when `JewelleryScreen` is popped; a fresh fetch happens every time the tab is re-entered (consistent with it being a pushed route each time, not a kept-alive `IndexedStack` page — MODULE_BRAIN.md §5) |
| Watched | `jewellery_screen.dart:25` | `ref.watch(jewelleryImagesProvider)` |
| Invalidated | `jewellery_screen.dart:102` | Retry button in the error state |

`JewelleryService()` is instantiated fresh inside the provider body each time (`JewelleryService`
has no constructor state — it just wraps `ApiClient()`, itself a singleton via factory constructor,
`core/network/api_client.dart:8-12`) — no meaningful duplication cost.

## Model shapes owned by this module

**None.** No `models/` subfolder, no custom class. The provider's data type is a bare
`List<String>` (raw image URLs) — the simplest possible shape, reflecting that the feature has no
structured product/catalog data today (MODULE_BRAIN.md §1).

## Secure storage keys touched

**None.** No `flutter_secure_storage`/`SecureStorageService` usage anywhere in this module —
confirmed via grep, zero matches.

## Local/persistent state

**None beyond the in-memory provider cache for the lifetime of the screen.** No `shared_preferences`,
no filesystem writes (contrast with `invoice`, which caches downloaded PDFs to the temp
directory — `jewellery` never writes to disk; `Image.network` relies on Flutter's own in-memory/
disk image cache, which is framework-managed and not something this module controls or reads
directly).

## Threading / async notes

Single async call per screen mount (`getJewelleryImages()`), no concurrency concerns — no parallel
requests, no debouncing, no cancellation token (Riverpod's `autoDispose` handles cleanup if the
widget is disposed mid-fetch, standard framework behavior, not custom logic in this module).
