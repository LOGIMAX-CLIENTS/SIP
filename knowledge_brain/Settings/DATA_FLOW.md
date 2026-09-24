# Data Flow — Settings

4 end-to-end flows, each with file:line citations at every hop. No flow in this module touches the
network — everything is local device storage or in-memory Riverpod state.

---

## Flow 1 — Screen load: MPIN status check

```
SettingsScreen mounts
  → initState() [settings_screen.dart:24-27]
      → _loadMpinStatus() [settings_screen.dart:29-37]
          → SecureStorageService.isMpinEnabled() [secure_storage_service.dart:26-29]
              → FlutterSecureStorage.read(key: AppConfig.keyIsMpinEnabled /* 'is_mpin_enabled' */)
              → returns true only if the stored string value is exactly 'true'
          → setState(_isMpinEnabled = <result>, _isLoading = false)
  → build() [settings_screen.dart:129] — while _isLoading: CircularProgressIndicator (line 150)
                                         — after load: full settings list, Switch.adaptive reflects _isMpinEnabled
```

## Flow 2 — Enabling MPIN from Settings

```
User flips the "Enable MPIN" switch ON
  → Switch.adaptive.onChanged → _toggleMpin(true) [settings_screen.dart:39-54,166]
  → ref.read(authControllerProvider) [settings_screen.dart:42]  (owned by `auth` module)
      → mobile = authState.data?['mobile'] ?? ''
  → Navigator.pushNamed(context, AppRouter.mpin, arguments: {'mobile': mobile}) [settings_screen.dart:47-51]
      → pushes the MPIN screen (features/mpin module — not built/verified in this round; the actual
        SecureStorageService.setMpinEnabled(true) write is presumed to happen there, not in this file)
  → await result
      result == true  → setState(_isMpinEnabled = true) [settings_screen.dart:52-54]
      result != true  → switch silently reverts to its prior (false) state on next rebuild — no explicit
                         error toast shown from this file for a cancelled/failed MPIN setup
```

## Flow 3 — Disabling MPIN from Settings

```
User flips the "Enable MPIN" switch OFF
  → Switch.adaptive.onChanged → _toggleMpin(false) [settings_screen.dart:39,55-59]
  → await SecureStorageService.setMpinEnabled(false) [secure_storage_service.dart:31-34]
      → FlutterSecureStorage.write(key: 'is_mpin_enabled', value: 'false')
  → setState(_isMpinEnabled = false)
  ── No confirmation dialog. No re-authentication (MPIN/biometric) prompt. No navigation. Instant.
```

## Flow 4 — Changing language

```
User taps the "Language" tile
  → GestureDetector.onTap → _showLanguageSelector(context) [settings_screen.dart:62-103,183]
  → showModalBottomSheet renders 3 rows via _buildLangOption [settings_screen.dart:94-96,105-127]
      each row watches languageProvider.currentLocale to show the checkmark on the active one
  → User taps a row (say Tamil, code='ta')
      → ref.read(languageProvider.notifier).setLanguage('ta') [language_provider.dart:44-48]
          → SharedPreferences.setString('selected_locale', 'ta')
          → state = state.copyWith(currentLocale: 'ta')     // translations map is NOT touched — stays {}
      → Navigator.pop(context)  (closes the sheet)
  → MaterialApp [main.dart:87,97] watches languageProvider → locale: Locale('ta')
      → Flutter's built-in Material/Cupertino widgets now localize to Tamil (date pickers, system
        dialog button labels, etc. — GlobalMaterialLocalizations supports 'ta'/'te' out of the box)
      → The app's OWN custom UI text (every ref.tr('key', fallback: '...') call across the app,
        including this very screen's 'languageTitle'/'languageSubtitle' strings, settings_screen.dart:186-188)
        continues to render its English `fallback` value, because LanguageState.translations is always
        {} (language_provider.dart:9,37-41) and LanguageService.fetchMegaTranslations() — the only method
        that would ever populate it — is fully commented out (language_service.dart:5-29).
  ── Net effect: selecting Tamil/Telugu changes the *stored preference* and a handful of native-widget
     locales, but does not visibly translate any app-authored copy anywhere in the app, including this
     screen. There is also no persistence read-back at app startup wired into this flow specifically —
     LanguageNotifier._init() [language_provider.dart:35-41] hardcodes 'en' on every cold start rather
     than reading back the previously saved SharedPreferences value, so a user's language selection does
     not survive an app restart (LanguageCache.getLocale()/saveLocale() exist in
     core/localization/language_cache.dart:8-16 but are never called from LanguageNotifier — dead code).
```
