# Method Index — Settings

Alphabetical by method. The module is a single `ConsumerStatefulWidget` with no public API surface —
every method is private (`_`-prefixed); all are listed since the module has no controller/service layer
to hold business logic separately from the widget.

---

### `_SettingsScreenState._buildLangOption(BuildContext, String title, String code, bool isDark)` → `Widget`
- **File:line**: `settings_screen.dart:105-127`
- **Purpose**: Renders one row in the language-selector bottom sheet. Reads `ref.watch(languageProvider).currentLocale`
  to determine `isSelected` (line 107) and styles the row accordingly (bold + checkmark icon if selected).
  On tap: `ref.read(languageProvider.notifier).setLanguage(code)` then closes the sheet (`Navigator.pop`).
- **Callers**: `_showLanguageSelector()` — called 3× with `('English','en')`, `('????? (Tamil)','ta')`,
  `('?????? (Telugu)','te')` (`settings_screen.dart:94-96`)

### `_SettingsScreenState._buildSectionTitle(String title, bool isDark)` → `Widget`
- **File:line**: `settings_screen.dart:209-218`
- **Purpose**: Uppercased section header text ("SECURITY", "APP PREFERENCES"), pure layout, no logic.
- **Callers**: `build()` (`settings_screen.dart:158,172`)

### `_SettingsScreenState._buildSettingTile({icon, title, subtitle, trailing, isDark})` → `Widget`
- **File:line**: `settings_screen.dart:220-266`
- **Purpose**: Shared card layout for every settings row. Takes a `trailing` widget as a parameter —
  callers decide whether that's a live `Switch` (MPIN) or a decorative `Icon` (Push Notifications, Dark
  Mode) — the tile itself has no `onTap`; interactivity, if any, is added by the **caller** wrapping the
  returned widget in a `GestureDetector` (only done for the Language tile, `settings_screen.dart:182-193`).
- **Callers**: `build()`, 4× (`settings_screen.dart:160,174,184,194`)

### `_SettingsScreenState._loadMpinStatus()` → `Future<void>`
- **File:line**: `settings_screen.dart:29-37`
- **Purpose**: Reads `SecureStorageService.isMpinEnabled()` and sets `_isMpinEnabled`/`_isLoading` on the
  widget state. No error handling — `SecureStorageService.isMpinEnabled()` itself cannot throw in a way
  that would propagate here (it returns `false` for any non-`'true'` stored value, including a missing
  key, per `secure_storage_service.dart:26-29`).
- **Callers**: `initState()` (`settings_screen.dart:26`)

### `_SettingsScreenState._showLanguageSelector(BuildContext)` → `void`
- **File:line**: `settings_screen.dart:62-103`
- **Purpose**: Opens a `showModalBottomSheet` with a `Consumer` inside (so it can `ref.watch` for live
  selection state without rebuilding the whole screen) containing 3 hardcoded `_buildLangOption` rows —
  English, Tamil, Telugu (labels partially broken, see `MODULE_BRAIN.md` risk #4).
- **Callers**: `GestureDetector.onTap` on the Language tile (`settings_screen.dart:183`)

### `_SettingsScreenState._toggleMpin(bool value)` → `Future<void>`
- **File:line**: `settings_screen.dart:39-60`
- **Purpose**: The `Switch.adaptive.onChanged` handler for the MPIN toggle.
  - `value == true` (enabling): reads `authControllerProvider`'s `state.data?['mobile']` (defaults to
    `''` if absent), then `Navigator.pushNamed(context, AppRouter.mpin, arguments: {'mobile': mobile})`
    and awaits a `bool?` result — only sets `_isMpinEnabled = true` locally if the pushed screen
    returns exactly `true`. Does not itself call `SecureStorageService.setMpinEnabled(true)` — that write
    is presumed to happen inside the MPIN-setup screen itself (not re-verified in this brain — MPIN
    module not yet built; cross-reference when it is).
  - `value == false` (disabling): directly `await SecureStorageService.setMpinEnabled(false)`, no
    confirmation dialog, no re-authentication step, then `setState(() => _isMpinEnabled = false)`.
- **Callers**: `Switch.adaptive` `onChanged` (`settings_screen.dart:166`)

### `_SettingsScreenState.build(BuildContext)` → `Widget`
- **File:line**: `settings_screen.dart:129-207`
- **Purpose**: Top-level layout. Reads `Theme.of(context).brightness == Brightness.dark` (line 131) to
  pick colors — **always evaluates to light** in the current build because `MaterialApp.themeMode` is
  hardcoded to `ThemeMode.light` with no `darkTheme` set (`main.dart:93-94`) — so every `isDark`-gated
  branch in this file is effectively dead code under the app's current configuration, not just this
  screen's own choice.
- **Callers**: Framework (widget tree)

### `_SettingsScreenState.initState()` → `void`
- **File:line**: `settings_screen.dart:24-27`
- **Purpose**: Kicks off `_loadMpinStatus()`.
- **Callers**: Framework (`State` lifecycle)

---

## Coverage Note

All methods in the module's single file are documented above. No `controller/`, `service/`, or `model/`
files exist for this module (see `_OVERVIEW/LOW_COMPLEXITY_MODULES.md`, correctly predicted).
