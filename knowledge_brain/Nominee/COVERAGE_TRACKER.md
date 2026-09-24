---
last_updated: 2026-08-19
---

# Coverage Tracker — Nominee

## Round 1 — Build Mode (2026-08-19)

Full generation from scratch. Files read in full: `lib/features/nominee/controller/nominee_controller.dart`,
`lib/features/nominee/models/nominee_model.dart`, `lib/features/nominee/screens/nominee_screen.dart`,
`lib/features/nominee/services/nominee_service.dart`. Cross-referenced: `lib/core/config/app_config.dart`
(encryption endpoint/field lists — confirmed `users/nominee/update` is encrypted-endpoint-flagged and
`mobile` is the only matching sensitive field), `lib/core/security/api_interceptor.dart` (per-field
encryption mechanics), `lib/routes/app_router.dart` (route registration), `lib/features/profile/profile_screen.dart`
(entry point) and a targeted read of the cross-imported `checkPincode` call site,
`STARTGOLD_DOCUMENTATION.md` §3.34 (head start, verified — see drift note in `MODULE_BRAIN.md` §8).

### Weighted Coverage Computation

| Component | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens documented | 25% | 1 (`NomineeScreen`) | 1 | 25.0% |
| Controller/service public methods documented | 25% | 7 (`NomineeService` 3 + 4 providers) | 7 | 25.0% |
| Models documented | 15% | 2 (`NomineeDetails`, `NomineeRelationship`) + 2 fallback consts | 4 | 15.0% |
| API endpoints documented | 15% | 3 (`users/nominee/details`, `/update`, `/relationships`) | 3 | 15.0% |
| Business rules captured | 10% | 8 rules (RULE-NOMINEE-001..008) | 8 | 10.0% |
| Cross-module deps captured | 10% | Core deps + `profile` cross-import (documented as a violation) | captured | 10.0% |
| **Total** | **100%** | | | **100%** |

### Badge: 🟢 (96%)

Docked 4% from a full 🔵 for honest gaps rather than any missing-doc component:
1. `id_country` default of `101` — mapped to "likely India" by inference from app context, not
   verified against a country-code table anywhere in this codebase (`unconfirmed`).
2. `hasNomineeProvider` and `NomineeDetails.copyWith()` have no confirmed callers in the files read —
   documented as likely-unused/possibly-planned rather than fully explained.
3. `_formKey`/`Form` wiring in the screen appears vestigial (manual toast-based validation is used
   instead of `_formKey.currentState.validate()`) — flagged but not traced further (would require
   git history, out of scope for a code-only brain build).

Manual spot-check performed: re-verified `nominee_service.dart:13-28` (`getNomineeDetails` emptiness
check) and `app_config.dart:47-99` (`encryptedEndpoints`/`sensitiveFields` — confirmed `mobile` is the
only matching key in the nominee payload) against the written `BUSINESS_RULES.md` RULE-NOMINEE-003 —
matched exactly.

### Drift Found vs `STARTGOLD_DOCUMENTATION.md` §3.34
Gap (not contradiction): the hand-written doc's one-line API summary (`POST users/nominee/update —
Encrypted`) is correct as far as it goes but omits `users/nominee/details` (fetch) and
`users/nominee/relationships` (dynamic list), and doesn't note that "Encrypted" means only the
`mobile` field within the payload, not the whole payload. See `MODULE_BRAIN.md` §8, flagged in
`_OVERVIEW/BUILD_SUMMARY.md`.

### New Finding Beyond the Hand-Written Doc
The direct `features/nominee` → `features/profile` cross-import (`nominee_screen.dart:16`) for
pincode lookup is a genuine `AGENTS.md` §1 architecture violation not mentioned in
`STARTGOLD_DOCUMENTATION.md` at all (that doc doesn't document module-internal architecture).
Recorded in `CROSS_MODULE_MAP.md` as a known violation with two remediation options.
