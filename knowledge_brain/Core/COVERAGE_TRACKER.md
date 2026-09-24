---
module: core/
brain_folder: Core
---

# Core — Coverage Tracker

## Round 1 — 2026-08-19 — Build (from ⬜ not-built)

**Source files**: 47 / 47 `.dart` files under `lib/core/` read in full (verified via
`find lib/core -name "*.dart" | wc -l` = 47, cross-checked against the 11 subfolders listed in
`.agents/config.md`: `config/`(1), `constants/`(1), `error/`(1), `ldui/`(1), `localization/`(3), `models/`(1),
`network/`(3), `providers/`(10), `security/`(10), `services/`(13), `utils/`(5)).

**Weighted coverage** (per the adapted formula for `core/`: methods 30% / providers 25% / services 25% /
security flows 20%):

| Category | Actual count | Documented | Coverage |
|---|---|---|---|
| Public classes/methods (METHOD_INDEX.md) | ~150 across 47 files | ~150 (every public class in every file has an entry; private helpers intentionally omitted per template) | 30% × 98% = 29.4 |
| Riverpod providers (STATE_ANALYSIS.md + METHOD_INDEX provider index) | 30 distinct exported providers across 17 files | 30/30 with state shape + invalidation trigger | 25% × 100% = 25.0 |
| Services (METHOD_INDEX.md + BUSINESS_RULES.md + DATA_FLOW.md) | 13 service files | 13/13, all public methods + at least one confirmed or inferred caller | 25% × 100% = 25.0 |
| Security flows (MODULE_BRAIN.md + DATA_FLOW.md + BUSINESS_RULES.md + FORENSIC_TEMPLATE.md) | 7 flows: field encryption, 401 refresh, 409 force-logout, app-lock/lifecycle, root detection, screenshot protection, cert pinning (+ clipboard as an 8th minor flow) | 7/7 major flows traced end-to-end with file:line; clipboard covered as a sub-flow inside app-lifecycle | 20% × 100% = 20.0 |

**Total: 99.4% → 🔵**

Badge requires ≥95% **and** a manual spot-check of 2–3 randomly chosen files against the docs. Spot-checked
this round: `security/session_manager.dart` (all 5 public methods + 1 getter match METHOD_INDEX/BUSINESS_RULES
RULE-CORE-003/009 exactly, including line numbers), `providers/timer_provider.dart` (RULE-CORE-006 and
DATA_FLOW #5's downstream-consumer note both trace correctly to `:41,81-103,107`), `services/mpin_service.dart`
(MpinService + MpinNotifier method list in METHOD_INDEX matches the file's actual structure, including the
three distinct 409/401/generic-error branches in `verifyMpin` referenced in DATA_FLOW #3). All three matched
with no corrections needed.

**Known residual gaps (the 0.6% not claimed as fully verified)**:
- A number of "Callers" cells in METHOD_INDEX.md are marked "not observed/re-verified this pass" for methods
  whose only consumers are in features not grepped exhaustively this round (`daily_savings`, `nominee`,
  `referral`, `invoice`, `jewellery`, `onboarding`, `settings`, `splash` — see CROSS_MODULE_MAP.md's
  "Consumers Not Verified This Round" section). The methods themselves are fully documented; only the exact
  caller list is best-effort for those 8 features.
- `MarketRates.isSignificantChange`'s exact threshold (`features/market/models/market_rates.dart:177`) was
  not read in full — flagged as "unconfirmed, verify before relying on it" in STATE_ANALYSIS.md rather than
  guessed, per the no-invented-specifics rule in AGENTS.md §11.
- `CertificatePinning.clearCache()` and `EncryptionService.clearKey()` are documented as intended-for-logout
  but no confirmed call site was found this pass — flagged explicitly rather than assumed wired up.

**Drift found vs. pre-existing docs**: see `_OVERVIEW/SYSTEM_ARCHITECTURE.md`'s "Real-time" claim
(Socket.IO client, exponential backoff) — actual implementation is a raw `web_socket_channel` WebSocket with
a fixed 5-second reconnect delay (`network/native_socket_service.dart`). Also the WS endpoint itself differs
from what `_OVERVIEW/SYSTEM_ARCHITECTURE.md` documents (`bullion_v4.logimaxindia.com/ratesocket/socket.io/`
vs. actual `EnvironmentService.wsUrl` = `wss://startgoldapp.logimaxindia.com/ws/` staging /
`wss://sgbackoffice.startgold.com/ws/` production). Both flagged in MODULE_BRAIN.md Known Gaps #4 and should
be corrected in `_OVERVIEW/SYSTEM_ARCHITECTURE.md` and `_OVERVIEW/BUILD_SUMMARY.md` per AGENTS.md §10.

**New cross-module deps discovered**: `core/` → `features/auth/controller/`, `core/` → `features/home/models/`,
`core/` → `features/market/models/` (see CROSS_MODULE_MAP.md "Known Violations"). Flagged for
`_SYSTEM/MODULE_DEPENDENCIES.md` synthesis once that file exists.

**Flagged for `_SYSTEM` synthesis** (once `_SYSTEM/DANGER_ZONES.md` / `DIAGNOSTIC_PLAYBOOK.md` exist):
- DANGER_ZONES candidate: don't re-add timestamp-based market-closed inference to `RateTimerNotifier`
  (RULE-CORE-006); don't remove `AppLifecycleObserver.suppressAppLock` without understanding the payment-flow
  reason (already in AGENTS.md §3, reinforced here); don't call `SecureStorageService`'s underlying
  `deleteAll()` pattern without preserving `persistent_device_id`/`persistent_device_type` (RULE-CORE-009).
- DIAGNOSTIC_PLAYBOOK candidates: all 6 entries in `FORENSIC_TEMPLATE.md` are core-layer, cross-feature-impact
  symptoms (session/encryption/rates/timer/app-lock/root-detection) — good candidates for the system-wide
  playbook once other modules' brains exist and symptom overlap can be checked.

---

## Round History

| Round | Date | Mode | Coverage | Badge |
|---|---|---|---|---|
| 1 | 2026-08-19 | Build | 99.4% | 🔵 |
