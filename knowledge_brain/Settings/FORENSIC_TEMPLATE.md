# Forensic Template — Settings

"Symptom → check first → likely suspects" entries for triaging bug reports in this module.

---

### Symptom: "I can't find the Settings screen anywhere in the app"

**Check first**:
1. This may not be a bug — per `BUSINESS_RULES.md` RULE-SETTINGS-007, no screen in the app currently
   navigates to `AppRouter.settings` / `/settings`. Confirm the reporter isn't actually looking for
   Profile's "Account" section (`features/profile/profile_screen.dart:300-338`), which is where
   biometric toggle / Change MPIN / Logout / Delete Account actually live.
2. Check for a recent regression — search git history for `AppRouter.settings` usages that may have been
   removed (a menu item that used to link here could have been deleted or repointed to Profile).
3. Check any deep-link / push-notification-tap routing config for a `/settings` target not visible in
   `lib/routes/app_router.dart`'s static route table (e.g. platform-native shortcuts) — not investigated
   as part of this brain build.

**Likely suspects**:
- Working as currently built — the screen is orphaned, not broken. This is a product/design question
  (should a menu entry point to it, or should the module be retired in favor of Profile's Account
  section?) more than an engineering bug.

---

### Symptom: User selects Tamil or Telugu but the app doesn't visibly change language

**Check first**:
1. Confirm which strings the reporter expected to change — Flutter's built-in Material/Cupertino widgets
   (date pickers, system dialog buttons) DO localize correctly for `ta`/`te`
   (`main.dart:98-107`, `supportedLocales`). App-authored copy (screen titles, button labels, etc.) does
   NOT, because `LanguageState.translations` is permanently empty — see `BUSINESS_RULES.md`
   RULE-SETTINGS-004. This is expected behavior given the current code, not a runtime bug — the feature
   is incomplete/disabled, not malfunctioning.
2. Confirm the selection itself persisted for the current session — `ref.watch(languageProvider).currentLocale`
   should update immediately and the language-selector checkmark should move to the newly selected row
   (`settings_screen.dart:107,119-121`) even though visible copy doesn't change.

**Likely suspects**:
- `LanguageService.fetchMegaTranslations()` being commented out (`language_service.dart:5-29`) is the
  root cause, not a bug to fix in `settings_screen.dart` — this is a `core/localization` completeness gap
  that this module surfaces but doesn't own.

---

### Symptom: User selects Tamil/Telugu, force-closes and reopens the app, language reverts to English

**Check first**:
1. This is expected given `LanguageNotifier._init()` hardcoding `currentLocale: 'en'` on every cold start
   (`language_provider.dart:35-41`) without reading back the `SharedPreferences` value that
   `setLanguage()` did save (`language_provider.dart:44-48`) — see `BUSINESS_RULES.md` RULE-SETTINGS-005.
2. Confirm this is a cold start (full process kill), not just backgrounding — Riverpod provider state
   naturally survives simple backgrounding without a process kill, so the symptom should only reproduce
   after a genuine app restart.

**Likely suspects**:
- `LanguageNotifier._init()` not calling `LanguageCache.getLocale()` (or reading `SharedPreferences`
  directly) — straightforward, already-diagnosed root cause, not a mystery to investigate further.

---

### Symptom: Tamil/Telugu labels in the language picker show as question marks (`?????`)

**Check first**:
1. This is confirmed to be **broken source text**, not a device font/encoding issue — the literal bytes
   in `settings_screen.dart:95-96,188` are ASCII `0x3F` (`?`) repeated, not a mis-decoded UTF-8 sequence
   for Tamil/Telugu script (verified at the byte level during this brain's build). No amount of device
   font configuration will fix this — the source strings themselves need to be replaced with actual
   Tamil/Telugu script.
2. Not worth further runtime investigation — this is a straightforward content fix, not a logic bug.

**Likely suspects**:
- Source content defect. Fix = replace the literal `'?????'`/`'??????'` strings in
  `settings_screen.dart:95-96,188` with correct Tamil/Telugu script for "Tamil"/"Telugu".

---

### Symptom: User disabled MPIN without meaning to (e.g. accidental tap), and there was no confirmation

**Check first**:
1. Confirm this is the Settings-module MPIN switch (`settings_screen.dart:160-170`), not Profile's
   biometric switch or "Change MPIN" flow — they are different UI elements with different code paths.
2. Confirm no confirmation dialog exists by design — per `BUSINESS_RULES.md` RULE-SETTINGS-002, the
   disable path is a single unconditional secure-storage write with no dialog/re-auth gate.

**Likely suspects**:
- Not a bug in the technical sense (the code does exactly what it's written to do) — this is a UX/product
  question about whether disabling the app's primary lock mechanism should require confirmation or
  re-authentication, worth raising with product owners rather than "fixing" unilaterally.

---

### Symptom: MPIN switch shows "enabled" in Settings but MPIN isn't actually being prompted anywhere in
### the app (or vice versa — some other screen says MPIN is off but Settings shows it on)

**Check first**:
1. Confirm both surfaces are reading the same secure-storage key — `AppConfig.keyIsMpinEnabled`
   (`'is_mpin_enabled'`). Settings reads/writes it directly via `SecureStorageService`
   (`settings_screen.dart:30,57`); confirm whatever app-lock-gating logic exists elsewhere
   (`core/security/app_lifecycle_observer.dart` per `AGENTS.md` §3) reads the *same* key rather than a
   different flag.
2. Check for the specific gap in RULE-SETTINGS-003: this screen's "enable" path never itself writes
   `setMpinEnabled(true)` — it relies entirely on the pushed `AppRouter.mpin` screen doing that write
   internally. If that screen has a code path that returns `true` to the caller without actually
   persisting the flag (or vice versa — persists it but doesn't return `true`), the two surfaces would
   desync. Not yet verified — `MPIN` module brain not built as of this round.

**Likely suspects**:
- A mismatch between what `AppRouter.mpin`'s screen actually persists and what it returns to the caller
  — investigate once the `MPIN` module brain exists.
