# Module Brain — Settings

> **Built**: 2026-08-19 | **Round**: 1 | **Complexity**: Low (1 file, 267 lines, no `controller/`,
> `models/`, or `services/` subfolder — confirmed by `_OVERVIEW/LOW_COMPLEXITY_MODULES.md`'s prediction)

---

## 1. Module Overview

The Settings module is a single screen, `SettingsScreen` (`lib/features/settings/settings_screen.dart`),
registered at route `/settings`. It renders two sections — "Security" (an MPIN enable/disable switch)
and "App Preferences" (Push Notifications, Language, Dark Mode tiles) — but **only the MPIN switch and
the Language tile are actually wired to any logic**. Push Notifications and Dark Mode are static,
non-interactive `Container`s with a decorative chevron icon and no `onTap`/`GestureDetector` at all
(`settings_screen.dart:174-201` — contrast with the Language tile at `182-193`, which *is* wrapped in a
`GestureDetector`).

**The most consequential finding this round**: `/settings` is a **registered but unreachable route** —
grepping the entire `lib/` tree for `AppRouter.settings` or the literal string `'/settings'` finds only
the constant declaration and the route-table registration in `lib/routes/app_router.dart:80,178`; no
screen anywhere calls `Navigator.pushNamed(context, AppRouter.settings)` or an equivalent. The actual
biometric toggle, MPIN change, logout, and account-deletion UI that a user interacts with lives in
`features/profile/profile_screen.dart`'s "Account" section instead (`profile_screen.dart:300-338`) — see
`CROSS_MODULE_MAP.md` for the full overlap analysis. This module may be superseded/in-progress work, or
reachable only via a currently-absent menu entry or deep link. Flagged, not fixed — see
`FORENSIC_TEMPLATE.md`.

### File Map

| File | Lines | Purpose |
|---|---|---|
| `lib/features/settings/settings_screen.dart` | 267 | The entire module: MPIN toggle, language-selector bottom sheet, and 2 dead UI tiles |

### Route

| Route constant | Path | Screen | Registered at | Reachable from? |
|---|---|---|---|---|
| `AppRouter.settings` | `/settings` | `SettingsScreen` | `app_router.dart:80,178` | **No confirmed in-app entry point** (grep-verified — see above) |

### API Surface

**None.** `settings_screen.dart` makes zero `ApiClient`/network calls. Every piece of state it touches
is either local device storage (`SecureStorageService`, `flutter_secure_storage`-backed) or an in-memory
Riverpod provider (`languageProvider`, backed by `shared_preferences` for the locale code only).

### State (Riverpod / Local)

| Source | Kind | Purpose | File:line |
|---|---|---|---|
| `_isMpinEnabled` / `_isLoading` | `State` fields (plain `setState`) | Drives the MPIN `Switch.adaptive` and the initial loading spinner | `settings_screen.dart:20-21` |
| `SecureStorageService.isMpinEnabled()` / `.setMpinEnabled()` | Core secure storage | Source of truth for the MPIN switch — read on `initState`, written on disable | `secure_storage_service.dart:26-34`, called from `settings_screen.dart:30,57` |
| `languageProvider` (`core/localization/language_provider.dart`) | `StateNotifierProvider<LanguageNotifier, LanguageState>` | Current locale code (`en`/`ta`/`te`) + (always-empty) translation map | `language_provider.dart:74-77`, watched at `settings_screen.dart:107` |
| `authControllerProvider` | `StateNotifierProvider` (owned by `auth` module) | Reads the logged-in user's mobile number to pass into the MPIN-setup navigation | `settings_screen.dart:42-43` |

No dedicated Settings-module Riverpod provider exists — the screen is entirely `setState` + reads from
providers owned by other modules (`auth`, `core/localization`).

### Top Risks / Notable Findings

1. **`/settings` route appears unreachable from any UI** (see above) — the single biggest structural
   finding for this module. Confirm with a full-text search of the compiled route table / any deep-link
   config before assuming it's truly dead; unconfirmed whether a deep link or a future release wires it
   in.
2. **Biometric toggle does NOT live in this module**, despite `AGENTS.md`'s module registry describing
   `Settings` as covering "biometric toggle" (`config.md:61`). The actual biometric enable/disable UI is
   in `features/profile/profile_screen.dart:303-315`, using `core/services/biometric_service.dart`
   directly. `SettingsScreen` never imports `BiometricService` at all (grep-confirmed). This brain
   documents the module as it actually is — see `CROSS_MODULE_MAP.md` for the correction.
3. **Language switching does not translate any of the app's own custom strings.** `LanguageNotifier._init()`
   hardcodes `translations: {}` "as per user request" (`language_provider.dart:35-41`, comment at line
   36), and the one method that would populate real translations,
   `LanguageService.fetchMegaTranslations()`, has its entire body commented out with the note "English
   by default for now" (`language_service.dart:5-29`). Practical effect: `ref.tr('key', fallback: '...')`
   (`language_provider.dart:79-89`) always falls back to the English `fallback` string, regardless of
   which locale is selected, because `state.translations[key]` is always `null`. Only Flutter's *built-in*
   Material/Cupertino widgets (date pickers, "OK"/"Cancel" system dialogs, etc.) actually localize via
   `supportedLocales: [en, ta, te]` (`main.dart:103-107`) — the app's own UI copy does not.
4. **The Tamil and Telugu labels in the language picker are literally the ASCII string `?????`/`??????`**,
   not real Tamil/Telugu script — confirmed at the byte level (`0x3F` repeated, not a multi-byte UTF-8
   sequence): `settings_screen.dart:95-96` (`'????? (Tamil)'`, `'?????? (Telugu)'`) and the subtitle at
   line 188 (`'English / ????? / ??????'`). This is broken source text, not a font-rendering/encoding
   display artifact — a native Tamil/Telugu speaker would see literal question marks in the language
   selector for their own language's name.
5. **"Push Notifications" and "Dark Mode" tiles are fully decorative** — no `onTap`, no wired state, no
   corresponding provider or navigation (`settings_screen.dart:174-181,194-201`). Compounding this, dark
   mode has no live implementation to toggle even if the tile were wired: `MaterialApp` in `main.dart:89-107`
   passes `theme: AppTheme.lightTheme` and hardcodes `themeMode: ThemeMode.light` with **no `darkTheme:`
   parameter set at all** — `AppTheme.darkTheme` exists as a getter (`shared/theme/app_theme.dart:92`)
   but is never referenced by `MaterialApp`, i.e. dead code on both ends.
6. **MPIN enable navigates to a separate screen; MPIN disable is instant with no re-auth.** Enabling MPIN
   pushes `AppRouter.mpin` (PIN setup flow) and only flips `_isMpinEnabled` locally if that flow returns
   `true` (`settings_screen.dart:44-54`). Disabling MPIN is a single `SecureStorageService.setMpinEnabled(false)`
   call with **no confirmation dialog and no re-authentication prompt** (`settings_screen.dart:56-59`) —
   contrast with the biometric-disable path in Profile, which does not appear to require re-auth either,
   but MPIN is the primary app-lock mechanism per `AGENTS.md` §3, so a silent one-tap disable is worth
   flagging as a UX/security consideration (not asserted as a bug — no explicit rule in `AGENTS.md`
   mandates re-auth to disable, so this is a "worth confirming intent" item, not a certain defect).

### Business Rules

See `BUSINESS_RULES.md` for the full RULE-SETTINGS-NNN set (8 rules).

### Cross-Module Impact

See `CROSS_MODULE_MAP.md`. Headline: depends on `core/security/secure_storage_service.dart` (MPIN flag),
`core/localization/language_provider.dart` (locale state), `features/auth/controller/auth_controller.dart`
(mobile number for MPIN setup nav), and `routes/app_router.dart`. Notably does **not** depend on
`core/services/biometric_service.dart` — that dependency belongs to `features/profile/`, not this module,
correcting the task brief's assumption.

### Anti-Patterns Register

*(none logged yet — populate after the first bug-fix round on this module)*
