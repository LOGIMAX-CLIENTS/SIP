---
module: Withdrawal
last_updated: 2026-08-19
---

# Coverage Tracker — Withdrawal

## Round 1 — 2026-08-19 (Build)

**Mode**: Build (brain status was ⬜ prior to this round).

**Files read**: 9/9 `.dart` files under `lib/features/withdrawal/` (100%), plus `lib/routes/app_router.dart`
(withdrawal route entries), and ~16 cross-referenced files: `core/security/api_interceptor.dart`,
`core/security/encryption_service.dart`, `core/config/app_config.dart`, `core/constants/app_constants.dart`,
`core/providers/timer_provider.dart`, `core/providers/market_provider.dart`,
`core/security/screenshot_security_service.dart`, `mpin/mpin_screen.dart`, `kyc/kyc_flow.dart`,
`sip/screens/bank_account_picker_screen.dart`, `profile/models/bank_account.dart`,
`profile/services/bank_details_service.dart`, `shared/widgets/add_bank_account_sheet.dart`,
`instant_saving/controller/saving_controller.dart`, `instant_saving/instant_saving_screen.dart` (partial —
the UPI_LIST call site), `core/providers/commodity_provider.dart`.

### Weighted Coverage Calculation

| Category | Weight | Score | Basis |
|---|---|---|---|
| Screens documented | 25% | 100% | All 4 screens (`withdrawal_screen`, `upi_selection_screen`, `withdrawal_confirmation_screen`, `withdrawal_success_screen`) fully read and documented in `METHOD_INDEX.md`/`DATA_FLOW.md` |
| Controller/service public methods documented | 25% | 100% | All 4 `WithdrawalNotifier` methods + all 8 `WithdrawalService` methods + `WithdrawalPolicyNotifier` (2) = 14/14 catalogued in `METHOD_INDEX.md`, including 2 confirmed-dead methods flagged rather than omitted |
| Models documented | 15% | 100% | `WithdrawalBalance`, `WithdrawalMethod`, `WithdrawalPolicy` (+ 3 nested classes) all documented in `STATE_ANALYSIS.md` |
| API endpoints documented | 15% | 100% | All 8 distinct endpoints (`withdrawal/withdraw`, `withdrawal/policy`, `withdrawal/eligibility`, `savings/check-eligibility`, `account/verify-upi`, `account/verify-bank`, `profile/accountdetails`, `referrals/reward-balance`) documented with payload shape and encryption status |
| Business rules captured | 10% | 90% | 11 rules captured (`BUSINESS_RULES.md`); 2 sub-points explicitly marked **unconfirmed** pending live-device/backend verification (server-side dedup on retry — RULE-WITHDRAWAL-009; UPI_LIST reachability — FORENSIC #6) |
| Cross-module deps captured | 10% | 95% | Full dependency graph + 3 architecture violations documented (`CROSS_MODULE_MAP.md`); one edge (`instant_saving` → `UpiSelectionScreen`) flagged as needing live confirmation of current reachability |

**Weighted total**: `25(1.00) + 25(1.00) + 15(1.00) + 15(1.00) + 10(0.90) + 10(0.95) = 98.5%`

### Badge: 🔵 (≥95%, all 9 module files read in full — not merely spot-checked)

Spot-check requirement for 🔵 is normally "2-3 files chosen at random matching the docs" — this round exceeds
that bar since all 9 files were read in full rather than sampled, and cross-references were verified against
their actual source (not assumed) for every claim in `BUSINESS_RULES.md` RULE-WITHDRAWAL-006 (encryption)
and RULE-WITHDRAWAL-007 (MPIN gate) specifically, since those are the highest-risk claims in a fintech
cash-out flow.

### Drift Found vs `STARTGOLD_DOCUMENTATION.md` §3.16–3.19

Logged in full in `MODULE_BRAIN.md` §Drift and mirrored to `_OVERVIEW/BUILD_SUMMARY.md`:
1. Endpoint name wrong: `withdraw/initiate` doesn't exist — actual is `withdrawal/withdraw`.
2. Endpoint name wrong: `withdraw/verify-upi` doesn't exist — actual is `account/verify-upi`.
3. Encrypted-field list wrong: doc says `withdrawal_amount, upi_id, bank_details, buy_rate` on the submit
   call; actual encrypted fields on `withdrawal/withdraw` are `amount, weight, buy_rate` — no field is ever
   literally named `withdrawal_amount` or `bank_details` anywhere in this module.
4. UPI payout described as a live dual option; actually disabled in the UI (bank-only), with the UPI add UI
   commented out.
5. "UPI Selection" (§3.17) described as a withdrawal step; the screen that implements it is not reachable
   from the withdrawal flow at all in current routing — it's an Instant Saving purchase-payment step that
   happens to live in the withdrawal module's folder.
6. Confirmed accurate: transaction PIN verification, market-closed guard, rate-lock terminology (buy rate =
   what the user receives when selling).

### Remaining Gaps Before This Could Be Called Fully Verified (not just ≥95% code-grounded)

- Live-device trace of whether `savings/check-eligibility` can still return `next_step: 'UPI_LIST'` for a
  purchase flow, to confirm/deny the `UpiSelectionScreen` misrouting risk is actually reachable in
  production today.
- Backend confirmation of idempotency handling on `withdrawal/withdraw` retries (client has no nonce).
- Confirm with backend team whether `bank_details` / `withdrawal_amount` field names ever existed in a prior
  API version (possible explanation for the hand-written doc's drift being a stale-but-once-accurate
  snapshot rather than a fabrication).

### Next Round Trigger

Refresh this brain if any of the 9 module files, `app_router.dart`'s withdrawal entries, `AppConfig.sensitiveFields`/`encryptedEndpoints`, or `AppConstants` min/max withdrawal constants change — or once UPI payout is re-enabled (would invalidate RULE-WITHDRAWAL-011 and the associated forensic entry).
