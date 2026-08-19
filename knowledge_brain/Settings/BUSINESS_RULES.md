# Business Rules — Settings

Plain-English rule + the code that implements (or fails to implement) it. Numbered RULE-SETTINGS-NNN.

---

### RULE-SETTINGS-001 — MPIN enabled/disabled state is a plain string flag in secure storage, not a
### boolean type
`SecureStorageService.isMpinEnabled()` compares the stored value to the literal string `'true'`; any
other value (including a missing key, `'false'`, `'1'`, or garbage) evaluates to `false`.
- **Code**: `core/security/secure_storage_service.dart:26-34`, `AppConfig.keyIsMpinEnabled = 'is_mpin_enabled'`
  (`core/config/app_config.dart:22`).

### RULE-SETTINGS-002 — Disabling MPIN requires no confirmation and no re-authentication
Flipping the switch off performs a single secure-storage write with no dialog, no biometric/MPIN
re-check, and no undo.
- **Code**: `settings_screen.dart:55-59` (`_toggleMpin`, `value == false` branch).
- Compare to enabling, which at least requires successfully completing the MPIN-setup screen
  (`AppRouter.mpin`) before the local flag flips (`settings_screen.dart:44-54`) — the asymmetry (hard to
  enable, trivial to disable) is worth confirming against product intent.

### RULE-SETTINGS-003 — This screen does not itself persist "MPIN enabled = true"; it only reflects a
### result
`_toggleMpin(true)` never calls `SecureStorageService.setMpinEnabled(true)` directly — it only updates
local widget state (`_isMpinEnabled = true`) after the pushed `AppRouter.mpin` screen returns `true`.
- **Code**: `settings_screen.dart:47-54`.
- The actual secure-storage write for the "enabled" case is presumed to happen inside the MPIN module
  itself (not yet built/verified — `MPIN` brain status is ⬜ per `config.md`). Unconfirmed until that
  brain exists; flagged here so a future MPIN-brain author can close the loop.

### RULE-SETTINGS-004 — Three languages are supported at the Flutter-framework level; app-authored text
### is not actually translated
`MaterialApp.supportedLocales` is exactly `[Locale('en'), Locale('ta'), Locale('te')]` (`main.dart:103-107`),
matching the hand-written doc's "en/ta/te" claim (`STARTGOLD_DOCUMENTATION.md` didn't explicitly list them
but `AGENTS.md`'s task brief assumed them — confirmed correct). However, `LanguageState.translations` is
permanently `{}` — set once in `LanguageNotifier._init()` (`language_provider.dart:35-41`) and never
populated by anything else, because `LanguageService.fetchMegaTranslations()`, the only method that would
fetch/populate real translation strings, has its entire implementation commented out
(`language_service.dart:5-29`, with an explicit in-code comment "English by default for now"). Every
`WidgetRef.tr(key, fallback: ...)` call across the whole app (not just this module) therefore always
renders its English `fallback` argument.
- **Code**: `language_provider.dart:35-41,50-71,79-89`; `language_service.dart:5-29`; `main.dart:103-107`.

### RULE-SETTINGS-005 — Selected language does not survive an app restart
`LanguageNotifier.setLanguage()` writes the chosen locale to `SharedPreferences` under key
`'selected_locale'` (`language_provider.dart:29,44-48`), but `LanguageNotifier._init()` — run once per
app cold start — hardcodes `currentLocale: 'en'` unconditionally and never reads that stored key back
(`language_provider.dart:35-41`, comment: "Current locale is English by default as per user request").
A separate `LanguageCache` class (`core/localization/language_cache.dart`) exists with exactly the
matching `getLocale()`/`saveLocale()`/cached-translation methods that *would* close this loop, but it is
never instantiated or called anywhere in the codebase (grep-confirmed) — dead code.
- **Code**: `language_provider.dart:35-41`; `language_cache.dart` (entire file, unused).

### RULE-SETTINGS-006 — "Push Notifications" and "Dark Mode" settings tiles have no behavior
Both tiles are built via the same `_buildSettingTile()` helper as the interactive tiles, but neither is
wrapped in a `GestureDetector`/`InkWell`, has an `onTap`, or is bound to any provider/persisted value —
tapping them does nothing.
- **Code**: `settings_screen.dart:174-181` (Push Notifications), `194-201` (Dark Mode).
- Dark Mode additionally has no live theme to switch to even if wired: `MaterialApp` never sets a
  `darkTheme:` parameter (`main.dart:89-107`); `AppTheme.darkTheme` (`shared/theme/app_theme.dart:92`) is
  defined but unreferenced anywhere in the app.

### RULE-SETTINGS-007 — `/settings` is registered as a named route but has no discovered UI entry point
`AppRouter.settings` (`app_router.dart:80`) is wired into the route table (`app_router.dart:178`), but no
other screen in the app calls `Navigator.pushNamed(context, AppRouter.settings)` or the literal
`'/settings'` string (grep-verified across all of `lib/`). The equivalent user-facing functionality
(biometric toggle, change MPIN, logout, delete account) lives instead in `features/profile/profile_screen.dart`'s
"Account" section (`profile_screen.dart:300-338`).
- **Code**: `app_router.dart:80,178`; absence confirmed by full-tree grep for `AppRouter.settings` and
  `'/settings'`.
- This is the single most consequential finding for this module — see `FORENSIC_TEMPLATE.md` and
  `MODULE_BRAIN.md` for triage guidance. Not asserted as "the screen is unused" with certainty — a deep
  link, a platform-specific settings-app-shortcut integration, or an in-progress menu wiring elsewhere
  could still reach it; only the in-app `Navigator` path was verified absent.

### RULE-SETTINGS-008 — Biometric authentication is not part of this module's surface, contrary to the
### module registry's description
`config.md`'s module registry (`config.md:61`) describes `Settings` as covering "biometric toggle" — but
`settings_screen.dart` never imports or references `core/services/biometric_service.dart` or
`SecureStorageService.isBiometricEnabled()`/`.setBiometricEnabled()` anywhere (grep-confirmed). That
functionality is fully owned by `features/profile/profile_screen.dart` (`profile_screen.dart:9,33-103,303-315`).
- **Code**: absence confirmed by grep; actual ownership at `profile_screen.dart:9,42-103,303-315`.
- Flagged for `config.md`'s owner to correct the module registry description — out of scope for this
  brain to edit `config.md` itself beyond noting the discrepancy (see `COVERAGE_TRACKER.md` "Drift Found").
