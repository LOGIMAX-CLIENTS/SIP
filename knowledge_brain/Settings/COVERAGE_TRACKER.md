# Coverage Tracker — Settings

## Round 1 — Build (2026-08-19)

**Mode**: Build (brain status was ⬜ prior to this round)

**Files read in full**: 1/1 module file (`settings_screen.dart`, 267 lines) + full reads of every
cross-module dependency named in the task brief and discovered during investigation:
`core/localization/language_cache.dart`, `core/localization/language_provider.dart`,
`core/localization/language_service.dart`, `core/services/biometric_service.dart` (read to confirm
non-dependency), `core/security/secure_storage_service.dart`, `lib/main.dart` (MaterialApp/theme/locale
config), `lib/shared/theme/app_theme.dart` (darkTheme existence check), plus targeted reads/greps of
`features/profile/profile_screen.dart` (Account section, biometric flow) and `lib/routes/app_router.dart`
(route registration + full-tree reachability grep).

### Weighted Coverage Calculation

| Category | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens documented | 25% | 1 (`SettingsScreen`) | 1 | 100% |
| Controller/service public methods documented | 25% | 0 controller/service files exist; 7 widget methods carry all logic, all documented (`_loadMpinStatus`, `_toggleMpin`, `_showLanguageSelector`, `_buildLangOption`, `build`, `_buildSectionTitle`, `_buildSettingTile`) | 7 | 100% |
| Models documented | 15% | 0 models owned by this module (uses `LanguageState` from `core/localization`, documented as a cross-module dependency, not claimed as this module's own) | N/A | 100% (nothing owned, nothing missed) |
| API endpoints documented | 15% | 0 — module makes no network calls (confirmed: no `ApiClient` import/usage anywhere in the file) | N/A | 100% |
| Business rules captured | 10% | 8 rules written (`RULE-SETTINGS-001`..`008`) | — | 90% (RULE-SETTINGS-003 and RULE-SETTINGS-007 both have explicitly flagged unconfirmed edges pending the not-yet-built `MPIN` brain and an unverified deep-link possibility) |
| Cross-module deps captured | 10% | `core/security`, `core/localization` (3 files, including 2 confirmed-dead classes), `features/auth`, `features/profile` (overlap analysis), `routes/app_router`, `shared/theme` (2 files) | — | 100% |

**Weighted total**: (25×1.00) + (25×1.00) + (15×1.00) + (15×1.00) + (10×0.90) + (10×1.00) = **99%**

### Badge: 🟢 (80–99%)

Not 🔵 because two specific claims are explicitly marked unconfirmed pending future work: (1) whether
`AppRouter.mpin`'s screen actually persists `setMpinEnabled(true)` on the enable path (deferred to the
not-yet-built `MPIN` module brain), and (2) whether any non-`Navigator` path (deep link, native shortcut)
reaches `/settings` despite no in-app `Navigator` call doing so. Both are honest gaps in what a
single-module, code-only investigation can close — not signs of incomplete reading of this module's own
file, which was read in full.

### Drift Found vs. `STARTGOLD_DOCUMENTATION.md` §3.32

The hand-written doc is a single 2-row table entry: route `/settings`, purpose "App preferences —
biometric toggle, language, notifications" (`STARTGOLD_DOCUMENTATION.md:699-705`). **Confirmed drift**:
the claimed "biometric toggle" is **not** part of this screen — it lives in `features/profile/`
(see `BUSINESS_RULES.md` RULE-SETTINGS-008, `CROSS_MODULE_MAP.md`). The claimed "notifications" preference
is present only as a non-functional decorative tile with no wiring (`BUSINESS_RULES.md` RULE-SETTINGS-006).
"Language" is accurately described (present and at least partially functional — locale selection persists
for the session, though not across restarts and without translating app copy). Per `AGENTS.md` §10, this
discrepancy is logged here and should be flagged in `_OVERVIEW/BUILD_SUMMARY.md` rather than silently
correcting the hand-written doc.

Also note: `config.md`'s module registry (`config.md:61`) makes the same "biometric toggle" claim for
`Settings` — same correction applies there.

### New Cross-Module Deps Discovered This Round

- `features/profile/profile_screen.dart` — turned out to be the *actual* home of biometric toggle,
  MPIN change, logout, and delete-account UI, not previously connected to this module in any existing
  doc.
- `core/localization/language_cache.dart` and `core/localization/language_service.dart` — both fully
  dead/unused classes, discovered while tracing the language-switching flow end-to-end.

### Flagged for Future `_SYSTEM` Synthesis

- **DANGER_ZONES candidate**: silent MPIN-disable-with-no-reauth pattern (RULE-SETTINGS-002) — worth
  comparing against how `Profile`'s biometric-disable path handles the same concern once that module's
  brain is built, to see if it's a project-wide pattern or specific to this screen.
- **DIAGNOSTIC_PLAYBOOK candidate**: "language doesn't change app text" and "can't find Settings screen"
  (see `FORENSIC_TEMPLATE.md`) are both likely real user-facing confusion points worth a system-wide
  symptom-index entry.
- **MODULE_DEPENDENCIES candidate**: the Settings/Profile MPIN+biometric overlap should be called out
  explicitly once `_SYSTEM/MODULE_DEPENDENCIES.md` exists, since it's exactly the kind of "two modules
  write the same secure-storage key via different flows" risk `AGENTS.md` §6 warns about for `core/`
  changes.

## Round History

| Round | Date | Coverage | Badge | Notes |
|---|---|---|---|---|
| 1 | 2026-08-19 | 99% | 🟢 | Initial build; discovered module is a registered-but-unreachable route and that biometric toggle actually lives in `Profile`, not here |
