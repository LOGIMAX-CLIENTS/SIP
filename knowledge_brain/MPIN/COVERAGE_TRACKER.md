---
module: mpin
last_updated: 2026-08-19
---

# COVERAGE_TRACKER — MPIN

## Round 1 — 2026-08-19 — Build (from ⬜ not-built)

**Files read in full**: 11
- `lib/features/mpin/mpin_screen.dart` (970 lines)
- `lib/features/mpin/change_mpin_screen.dart` (365 lines)
- `lib/core/services/mpin_service.dart` (324 lines)
- `lib/core/services/biometric_service.dart` (115 lines)
- `lib/core/security/app_lifecycle_observer.dart` (227 lines)
- `lib/core/security/session_manager.dart` (53 lines)
- `lib/core/security/encryption_service.dart` (147 lines)
- `lib/core/config/app_config.dart` (100 lines)
- `lib/routes/app_router.dart` (relevant sections: imports, route constants, route map, unknown-route fallback)
- `STARTGOLD_DOCUMENTATION.md` §3.8–3.9 (head-start doc)
- Targeted greps/partial reads: `lib/core/security/api_interceptor.dart` (encryption + 409 sections), `lib/core/security/secure_storage_service.dart` (mpin/biometric keys), `lib/core/constants/app_constants.dart` (mpin strings), `lib/shared/widgets/custom_button.dart` (isLoading-disable behavior), `lib/features/settings/settings_screen.dart` (lines 20-60), `lib/features/profile/profile_screen.dart`, `lib/features/withdrawal/screens/withdrawal_confirmation_screen.dart`, `lib/features/auth/otp/otp_screen.dart`, `lib/features/splash/splash_screen.dart`, `lib/core/utils/navigation_utils.dart`, `lib/core/network/api_client.dart`, `lib/core/services/notification_service.dart` (grep-scoped, not full read)

**Weighted coverage computation** (per `build-module-brain.md` §7 weights):

| Component | Weight | Actual count | Documented | Score |
|---|---|---|---|---|
| Screens documented | 25% | 2 screens | 2/2 (`mpin_screen.dart`, `change_mpin_screen.dart`) | 25.0% |
| Controller/service public methods documented | 25% | 11 (`MpinService` ×5 + `MpinNotifier` ×6) | 11/11 in `METHOD_INDEX.md` | 25.0% |
| Models documented | 15% | 0 (module has no `models/` folder — confirmed via directory listing) | N/A — nothing to document, scored as fully covered | 15.0% |
| API endpoints documented | 15% | 5 (`mpin/create`, `mpin/validate`, `mpin/change`, `mpin/reset`, `auth/has-mpin`) | 5/5 in `DATA_FLOW.md`/`METHOD_INDEX.md`, with encryption + response-shape notes | 15.0% |
| Business rules captured | 10% | 13 rules written (`RULE-MPIN-001..013`) | Covers PIN length, encryption, error/session handling, lockout, keypad shuffle, biometric auto-trigger, back-nav, Forgot-PIN visibility, change-PIN validation, FCM registration | 9.0% (2 rules touch unconfirmed server-side behavior — RULE-MPIN-006 lockout persistence, RULE-MPIN-011 server-side reuse check) |
| Cross-module deps captured | 10% | 14 `core/` deps + reverse dep from `AppLifecycleObserver` + 10 inbound navigators + 6 outbound destinations, with Mermaid graph | Thorough, but `auth/has-mpin`'s only caller (`MpinService.hasMpinSet`) has **no confirmed call site anywhere in `lib/`** — flagged unconfirmed, not fully resolved | 9.0% |

**Total: 98.0%** — but capped to reflect **unresolved/unconfirmed findings that require live-app or backend verification**, not further static reading:

1. `settings_screen.dart` untyped-navigation-to-`/mpin` behavior when no MPIN exists yet (FORENSIC_TEMPLATE #5) — reasoned from code but not runtime-verified.
2. `authorize_withdrawal` type — no reachable call site found; genuinely dead code or a gap in this pass's grep coverage.
3. `MpinService.hasMpinSet()` — no call site found anywhere in `lib/`.
4. `api_interceptor.dart` behavior when the last-chance RSA key fetch (`:136-137`) itself fails — not traced to completion in this pass.

**Reported coverage: 93% — 🟢 (mostly complete, not yet 🔵)**

Per `build-module-brain.md` §7, 🔵 requires ≥95% **and** a manual spot-check re-read of 2–3 randomly chosen files confirming the docs match. This round performed a full first-pass read of every module file plus its direct dependencies, but did not yet perform a separate independent spot-check pass — recommend Round 2 spot-check `mpin_screen.dart` `_handleAction` and `MpinNotifier.verifyMpin` against these docs, plus a live-app test of the 4 items above, before upgrading the badge.

**Drift found vs `STARTGOLD_DOCUMENTATION.md` §3.8–3.9**: confirmed on 3 points — PIN length (4-digit claimed vs 6-digit actual), mode count (4 claimed vs 8 actual `type` values), API path prefix (`users/mpin/...` claimed vs bare `mpin/...` actual). See `MODULE_BRAIN.md` §2.

**New cross-module deps discovered**: `core/security/app_lifecycle_observer.dart` as a reverse-dependency trigger (not previously implied by the hand-written doc, which only mentioned "back-press handling per mode" without describing the resume-triggered push); `auth/registration/registration_screen.dart` → `/mpin-creation` → `PinCreationScreen` as a same-named-but-different-module PIN-creation path that must not be confused with this module's `setup` type.

**Flagged for `_SYSTEM` synthesis** (once `_SYSTEM/` docs are built):
- `DANGER_ZONES.md` candidate: "Never add a new sensitive field to an `mpin/*` request body without also adding its key name to `AppConfig.sensitiveFields` — the interceptor's endpoint match alone does not encrypt unlisted fields."
- `DANGER_ZONES.md` candidate: "`change_mpin_screen.dart` has no screenshot-block — do not treat `mpin_screen.dart`'s protection as covering both MPIN screens."
- `DIAGNOSTIC_PLAYBOOK.md` candidates: all 6 entries in `FORENSIC_TEMPLATE.md` (app-lock repeat-trigger, biometric-never-prompts, 409-doesn't-force-logout, encryption-missing, Settings-toggle-fails, Change-MPIN-screenshot-leak).
