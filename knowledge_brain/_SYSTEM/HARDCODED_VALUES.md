---
last_updated: 2026-08-19
source: Synthesized from findings across module brains — not an exhaustive grep sweep, see "Known Incomplete" below
---

# Hardcoded Values

Values found hardcoded client-side where the surrounding architecture implies they should be (or already
partially are) server-driven — worth checking before assuming client behavior matches server intent.

| Value | File | Should be | Note |
|---|---|---|---|
| `forceUpdate: true` | Splash's update dialog | Server's real `AppVersionInfo.forceUpdate`/`minVersion` split | Correct soft/hard logic already exists in `app_control_provider.dart` for other consumers — this one path just doesn't use it. RULE-SPLASH-007. |
| `resumeRoute: AppRouter.login` | `maintenance_gate.dart`, `app_control_wrapper.dart` | Session-aware (mpin vs login) like Splash's own path does | RULE-MAINTENANCE-005. |
| `3.0` (GST fallback) | InstantSaving purchase screen | Live `gst` field from `savings/config` | Only a pre-load fallback, not the primary path — but worth re-checking if GST ever changes server-side. |
| `'en'` on every cold start | `LanguageNotifier._init()` | Persisted `SharedPreferences` value via `LanguageCache` | `LanguageCache` class exists specifically to fix this and is never called — RULE-SETTINGS-005. |
| `ThemeMode.light` (no `darkTheme:`) | `main.dart` `MaterialApp` | N/A — "Dark Mode" toggle in Settings is decorative with nothing to switch to | RULE-SETTINGS-006. |
| Literal `'?????'`/`'??????'` Tamil/Telugu labels | Settings language picker | Real Tamil/Telugu script | Confirmed at byte level, not a display-encoding artifact. |
| `'General'` default ticket type | `EnquiryFormScreen` | A key present in `kTicketTypes` | Causes a silent miscategorization bug, not just a style issue — see DANGER_ZONES DZ-011. |

## Known Incomplete

This list was built from what surfaced during Round 1's per-module reads, not a dedicated repo-wide grep for
hardcoded-value patterns (e.g. magic numbers, inline color/string literals that should be theme/config
tokens). A proper `/build-system-brain` re-run with an explicit hardcoded-value sweep step (per
`.agents/workflows/build-system-brain.md` step 7) would likely find more, especially UI-layer magic numbers
not flagged here because they weren't security/business-logic relevant to the agents building each brain.
