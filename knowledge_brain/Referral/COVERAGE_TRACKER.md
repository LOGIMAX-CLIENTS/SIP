# Coverage Tracker — Referral

## Round 1 — Build (2026-08-19)

**Mode**: Build (brain status was ⬜ prior to this round)

**Files read in full**: 4/4 module files (`referral_screen.dart`, `referral_service.dart`,
`referee_list_screen.dart`, `referee_list_service.dart`) + cross-module reads: `app_router.dart`
(referral/referee-list route entries), `registration_screen.dart`, `pin_creation_screen.dart`,
`auth_controller.dart`, `auth_service.dart` (register/register-check), `app_config.dart`
(`encryptedEndpoints`/`sensitiveFields`), `api_interceptor.dart` (encryption-selection logic),
`home_screen.dart`/`profile_screen.dart` (entry-point grep + read of matching lines).

### Weighted Coverage Calculation

| Category | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens documented | 25% | 2 (`ReferralScreen`, `RefereeListScreen`) | 2 | 100% |
| Controller/service public methods documented | 25% | 2 (`ReferralService.fetchReferralData`, `RefereeListService.fetchList`) — no controller layer exists in this module | 2 | 100% |
| Models documented | 15% | 3 (`ReferralData`, `RefereeItem`, `RefereeListData`) | 3 | 100% |
| API endpoints documented | 15% | 2 owned (`users/auth/referral/details`, `referrals/referee-list`) + 2 cross-referenced signup-side (`register-check`, `register`) | 4 | 100% |
| Business rules captured | 10% | 9 rules written (`RULE-REFERRAL-001`..`009`) | — | 95% (one rule, RULE-REFERRAL-003, has an explicitly flagged unconfirmed sub-point re: `register-check` encryption matching) |
| Cross-module deps captured | 10% | `core/network`, `core/config`, `shared/theme`, `shared/widgets` (3 widgets), `features/main`, `features/auth` (full signup loop), `routes/app_router` | — | 100% |

**Weighted total**: (25×1.00) + (25×1.00) + (15×1.00) + (15×1.00) + (10×0.95) + (10×1.00) = **99.5% ≈ 99%**

### Badge: 🟢 (80–99%)

Not awarded 🔵 despite the high score because: (1) one sub-claim in `BUSINESS_RULES.md`
RULE-REFERRAL-003 is explicitly marked unconfirmed (whether `register-check` matches the
`encryptedEndpoints` substring check) rather than verified against a live network capture or backend
source, and (2) the reward-lifecycle backend logic referenced throughout (self-referral guards, reward
thresholds, disbursement triggers) is entirely server-side and out of this Flutter repo's reach — this
brain documents the client's view faithfully but cannot independently verify backend behavior the way a
same-repo module can. Promote to 🔵 once: (a) the `register-check` encryption question is settled, and
(b) a manual spot-check re-read of 2-3 files confirms no drift after any subsequent code change.

### Drift Found vs. `STARTGOLD_DOCUMENTATION.md` §3.35–3.36

The hand-written doc for this module is extremely sparse (2 rows: route + one-line purpose per screen,
`STARTGOLD_DOCUMENTATION.md:739-745`) — not wrong, just far less detailed than the code supports. No
factual contradictions found; every claim in the hand-written doc (routes `/referral` and
`/referee-list`, "Share referral code, view rewards" / "List of referred users + status") is consistent
with the live code. Logged here per `AGENTS.md` §10 rather than silently expanding the hand-written doc.

### New Cross-Module Deps Discovered This Round

- `features/auth/registration/registration_screen.dart` + `features/auth/pin/pin_creation_screen.dart`
  (referral-code entry at signup — not previously documented anywhere, since neither the `Auth` nor
  `Referral` brain existed before this round).
- `features/main/main_screen.dart` (`selectedTabProvider`) — `ReferralScreen`'s back-button logic reset
  path.
- `features/home/home_screen.dart` and `features/profile/profile_screen.dart` as the two UI entry points
  into `/referral`.

### Flagged for Future `_SYSTEM` Synthesis

- **DANGER_ZONES candidate**: the empty-state-on-error pattern (RULE-REFERRAL-006) — if this pattern
  repeats across other modules built later, it's worth a project-wide anti-pattern entry rather than a
  per-module note.
- **DIAGNOSTIC_PLAYBOOK candidate**: "referral code not applied" and "reward stuck on hold" symptoms
  (see `FORENSIC_TEMPLATE.md`) are likely to recur as real support tickets — good candidates for the
  system-wide symptom index once `/build-system-brain` runs.

## Round History

| Round | Date | Coverage | Badge | Notes |
|---|---|---|---|---|
| 1 | 2026-08-19 | 99% | 🟢 | Initial build, full read of all 4 module files + cross-module signup loop |
