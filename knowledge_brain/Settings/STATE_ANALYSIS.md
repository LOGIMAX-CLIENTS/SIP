# State Analysis — Settings

## Riverpod Providers Consumed (none owned by this module)

| Provider | Owner module | Kind | Usage in Settings | File:line |
|---|---|---|---|---|
| `languageProvider` | `core/localization` | `StateNotifierProvider<LanguageNotifier, LanguageState>` | `ref.watch(languageProvider).currentLocale` for selection highlight; `ref.read(languageProvider.notifier).setLanguage(code)` to change it; `ref.tr(...)` extension (also backed by this provider) for 2 UI strings | `settings_screen.dart:78,86,107,123,186-188` |
| `authControllerProvider` | `features/auth/controller` | `StateNotifierProvider<AuthController, AuthState>` | `ref.read(authControllerProvider).data?['mobile']` — one-shot read, not watched | `settings_screen.dart:42-43` |

This module declares **zero** Riverpod providers of its own — no `settingsProvider`,
no `StateNotifier` for the MPIN switch. The MPIN switch and loading flag are plain `StatefulWidget`
`setState` fields (`_isMpinEnabled`, `_isLoading`, `settings_screen.dart:20-21`).

## Local Widget State

| Field | Type | Default | Set by | File:line |
|---|---|---|---|---|
| `_isMpinEnabled` | `bool` | `false` | `_loadMpinStatus()` on mount; `_toggleMpin()` on user action | `settings_screen.dart:20` |
| `_isLoading` | `bool` | `true` | `_loadMpinStatus()` (flips to `false` once the secure-storage read resolves) | `settings_screen.dart:21` |

## Secure Storage Keys Touched

| Key constant | Raw string | Read | Written | File:line |
|---|---|---|---|---|
| `AppConfig.keyIsMpinEnabled` | `'is_mpin_enabled'` | `_loadMpinStatus()` via `SecureStorageService.isMpinEnabled()` | `_toggleMpin(false)` via `SecureStorageService.setMpinEnabled(false)` (the `true` case is NOT written from this file — see `BUSINESS_RULES.md` RULE-SETTINGS-003) | `secure_storage_service.dart:26-34`; `app_config.dart:22` |

No other secure-storage key is touched by this module. `AppConfig.keyIsBiometricEnabled` (used by
`Profile`, not here) is listed for completeness in `CROSS_MODULE_MAP.md` but is out of this module's
read/write surface.

## Non-Secure Local Persistence (`shared_preferences`)

| Key | Written by | Read by | File:line |
|---|---|---|---|
| `'selected_locale'` | `LanguageNotifier.setLanguage()` (triggered from this screen's language picker) | **Nothing** — `LanguageNotifier._init()` never reads it back; see `BUSINESS_RULES.md` RULE-SETTINGS-005 | `language_provider.dart:29,44-48` |

`LanguageCache` (`core/localization/language_cache.dart`) declares matching keys
(`'selected_locale'`, `'cached_translations_<locale>'`) with proper get/save methods, but the class is
never instantiated anywhere in the codebase — fully dead code, not part of the live data flow.

## Models

**None.** This module has no dedicated model classes — `LanguageState` (`currentLocale`, `translations`,
`isLoading`) is owned by `core/localization/language_provider.dart:4-26`, not by this module. There is no
`SettingsData`/`SettingsState` class anywhere.

## Loading / Error / Empty State Coverage

| Concern | Handling | File:line |
|---|---|---|
| Initial MPIN-status load | `CircularProgressIndicator` while `_isLoading` | `settings_screen.dart:149-150` |
| MPIN toggle failure | Not applicable in the disable path (fire-and-forget secure-storage write, no error surface); in the enable path, any non-`true` result from the pushed MPIN screen (including a thrown exception inside it) is treated identically to "user cancelled" — no distinct error UI | `settings_screen.dart:39-60` |
| Language selector | No loading/error state — `showModalBottomSheet` and `setLanguage()` are synchronous from the UI's perspective (the underlying `SharedPreferences.getInstance()` await is not user-visible as a spinner) | `settings_screen.dart:62-103` |
| Empty state | Not applicable — this screen has no list/collection content | — |
