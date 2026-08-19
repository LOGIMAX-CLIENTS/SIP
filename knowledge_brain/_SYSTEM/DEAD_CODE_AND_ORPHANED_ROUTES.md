---
last_updated: 2026-08-19
source: Synthesized from all 24 Round-1 module brains — added beyond the original 8-doc template because this pattern recurred often enough (10+ independent instances across 8+ modules) to warrant its own catalog rather than being buried across module brains.
---

# Dead Code & Orphaned Routes

Two related but distinct patterns found repeatedly during Round 1:
- **Dead code**: a class/method/screen is fully implemented but has zero callers/importers anywhere in
  `lib/`.
- **Orphaned route**: a route is registered in `app_router.dart` and its screen is fully functional if
  reached, but no in-app `Navigator` call anywhere actually navigates to it (confirmed via exhaustive
  repo-wide grep per module, not assumption).

Given how often this surfaced independently across unrelated module builds, treat it as a systemic pattern
worth a deliberate cleanup pass — each instance below needs one of three decisions: remove it, wire it up,
or explicitly document it as intentionally-reserved (e.g. for a planned future feature).

## Orphaned Routes (registered, zero in-app navigation found)

| Route | Screen | Module | Note |
|---|---|---|---|
| `/daily-savings` | `DailySavingsScreen` | DailySavings | Submit button is also a no-op (`onPressed: () {}`) — this route is doubly dead: unreachable AND non-functional if reached. Real "Daily" recurring purchase now lives in SIP's `AutoSavingsScreen`. |
| `/onboarding` | `OnboardingScreen` | Onboarding | Splash never calls `SessionManager.hasSeenOnboarding()`. Screen itself is fully functional (carousel), just never invoked. Also has no skip button despite the hand-written doc claiming one. |
| `/support` | `SupportScreen` | Support | "Live Chat"/"Call Support" tiles have no `onTap` even if reached. |
| `/about` | `ContentScreen` (aboutUsProvider) | Content | Same class of finding as `/support` — server-fetched content, fully functional, just unreachable. |
| `/settings` | `SettingsScreen` | Settings | The functionality users actually reach (biometric toggle*, change MPIN, logout, delete account) lives in `Profile`'s "Account" section instead. *Biometric toggle is NOT actually in Settings at all — see Settings' own finding. |

## Dead Code (zero callers/importers)

| Symbol | File | Module | Note |
|---|---|---|---|
| `EncryptionService.decrypt()` behavior | `core/security/encryption_service.dart` | Core | Not literally dead (it's called), but is a no-op — see `_SYSTEM/DANGER_ZONES.md` DZ-001. |
| `ldui_parser.dart` (entire file) | `core/ldui/` | Core | Fully-implemented JSON→Widget renderer; countdown-offer sheet it was built for renders hardcoded widgets instead. |
| `AuthInterceptor` | `core/network/interceptors.dart` | Core | Never registered on any Dio instance. |
| `AppLogger` | `core/utils/logger.dart` | Core | No live callers except the unused `AuthInterceptor`. |
| `DeviceService` | `core/services/device_service.dart` | Core | Unused duplicate of `DeviceIdService`. |
| `KycValidator` (entire file) | `core/utils/kyc_validator.dart` | Core / KYC | Zero importers anywhere. |
| Root-level `kyc_screen.dart` + `providers/kyc_provider.dart` + `models/kyc_step.dart` | `features/kyc/` | KYC | A second, hardcoded 3-step KYC UI that's never reached from `app_router.dart` — the live one is `screens/kyc_screen.dart`. |
| `MaintenanceGate.check()` | `shared/widgets/maintenance_gate.dart` | Maintenance | Fully built pre-transaction gate, zero call sites. |
| `SupportTicket` model | `features/support/` | Support | Never instantiated anywhere. |
| `ReferralData.shareLink`, `RefereeItem.statusCode` | `features/referral/` | Referral | Parsed from API but never read in UI. |
| `MarketRates.fromJson`, `MarketRates.initial()` | `features/market/models/market_rates.dart` | Market | No call sites. |
| `LanguageCache` (entire class) | `core/localization/language_cache.dart` | Settings | Built specifically to persist language across restarts; never called — language resets to `'en'` on every cold start (`LanguageNotifier._init()` hardcodes it) despite this class existing to fix exactly that. |
| `InvoiceService.clearCache()` | `features/invoice/invoice_service.dart` | Invoice | No callers. |
| `nominee_screen.dart`'s `_buildDropdownField` | `features/nominee/` | Nominee | Model/payload carry ID-proof type/number end-to-end but no UI widget sets them. |
| `MpinService.hasMpinSet()` | `core/services/mpin_service.dart` | MPIN | No callers anywhere in `lib/`. |
| `mpin_screen.dart`'s `authorize_withdrawal` type branch | `features/mpin/mpin_screen.dart` | MPIN | No call site passes this `type` value. |
| `/pan-verification` route's screen logic | `features/kyc/` (or wherever it resolves) | KYC | Registered and reachable, but the screen is a non-functional stub — `Future.delayed` fake success, zero real API call. Different from the other entries here (reachable but fake, not unreachable). |
| `payment_methods_screen.dart` | `features/instant_saving/screens/` | InstantSaving | Explicitly marked `[LEGACY]` in its own header; unreachable, only commented-out call sites remain. |

## Why This Matters

Several of these overlap with security gaps (dead validators, a fail-silent encryption path) or product
bugs (a route users might expect to reach but can't, per the hand-written doc's claims). None of these were
fixed during Round 1 brain-building — per `AGENTS.md` §0, documentation-only agents don't modify app code.
This catalog is the punch list for whoever picks up cleanup next; `/module-bug-audit` can be run per-module
against this list.
