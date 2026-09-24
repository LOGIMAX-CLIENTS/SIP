---
module: jewellery
last_updated: 2026-08-19
primary_documentation: true
---

# Jewellery — Method Index

Alphabetical by class, then method. Two classes total; no model layer exists (the module's only
data shape is a bare `List<String>` of image URLs, not a dedicated model class).

## `JewelleryService` (`jewellery_service.dart:8-33`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `getJewelleryImages` | `Future<List<String>> getJewelleryImages()` | `:14-32` | `jewelleryImagesProvider` (`jewellery_screen.dart:11`) — the only call site in the repo |

Instance field: `_apiClient` (`final ApiClient _apiClient = ApiClient()`, `:9`) — uses the shared
singleton `ApiClient` (unlike `invoice`, which instantiates its own raw `Dio()` — see
CROSS_MODULE_MAP.md for the contrast).

## `jewelleryImagesProvider` (top-level, `jewellery_screen.dart:10-12`)

| Member | Signature | file:line | Notes |
|---|---|---|---|
| `jewelleryImagesProvider` | `final jewelleryImagesProvider = FutureProvider.autoDispose<List<String>>((ref) => JewelleryService().getJewelleryImages())` | `:10-12` | `autoDispose` — refetches every time the screen mounts. Watched at `:25`, invalidated at `:102` (Retry button). |

## `JewelleryScreen` (`jewellery_screen.dart:19-264`)

`ConsumerWidget` (stateless) — no `State` class, no local fields.

| Method | Signature | file:line | Callers |
|---|---|---|---|
| constructor | `const JewelleryScreen({super.key})` | `:20` | `app_router.dart:376` (route builder); constructed only via that route registration |
| `build(BuildContext, WidgetRef)` | `Widget build(BuildContext context, WidgetRef ref)` | `:22-182` | Flutter framework |
| "Back to Home" FAB `onPressed` (inline) | `() => Navigator.of(context).pop()` | `:46` | `floatingActionButton` (`:28-65`) |
| Retry `onPressed` (inline) | `() => ref.invalidate(jewelleryImagesProvider)` | `:102` | `TextButton.icon` in the `error:` branch (`:83-109`) |
| `_buildHeroSection(bool isDark)` | `Widget _buildHeroSection(bool isDark)` | `:185-263` | Called once from `build()`'s `data:` branch (`:116`) |
| `Image.network` `loadingBuilder` (inline) | `(context, child, loadingProgress) { ... }` | `:130-153` | Per-image, Flutter `Image` widget callback |
| `Image.network` `errorBuilder` (inline) | `(_, __, ___) => Container(...)` | `:154-169` | Per-image fallback — generic `Icons.diamond_rounded` placeholder |

## Non-existent (checked, confirmed absent)

- No `jewellery_controller.dart` / `JewelleryNotifier` / `StateNotifier` — the only state
  management is the single `FutureProvider.autoDispose`.
- No `jewellery_models.dart` or any model class (`JewelleryProduct`, `JewelleryItem`,
  `RedemptionRequest`, etc. do not exist anywhere in this codebase).
- No purchase/cart/checkout method anywhere in this module.
- No redemption/conversion method (e.g. `redeemGoldForJewellery`, `convertHoldings`) anywhere in
  this module or in `home`/`withdrawal` (repo-wide grep for `redeem`/`Redeem` inside
  `lib/features/` returns zero matches touching jewellery).
- No `core/security/encryption_service.dart` usage — endpoint carries no request body and is not
  in `encryptedEndpoints`.
- No local/bundled image assets consumed by this screen beyond the two static ones noted in
  MODULE_BRAIN.md §8 — all catalog-style imagery is fetched live from the API.
