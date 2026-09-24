---
module: InstantSaving
last_updated: 2026-08-19
---

# InstantSaving — Coverage Tracker

## Round 1 — Build (2026-08-19)

**Mode**: Build (brain status was ⬜ per `.agents/config.md` module registry at start of this round).

**Files read**: 10/10 module files under `lib/features/instant_saving/` (full or near-full — see caveats
below), plus `lib/routes/app_router.dart` (grepped + relevant sections read), plus ~14 core/cross-module
files read in full or targeted detail: `core/config/app_config.dart`, `core/security/api_interceptor.dart`
(full), `core/security/encryption_service.dart` (key sections), `core/security/app_lifecycle_observer.dart`
(key section), `core/security/screenshot_security_service.dart` (full), `core/providers/timer_provider.dart`
(full), `core/providers/commodity_provider.dart` (full), `core/services/shared_service.dart` (full),
`core/providers/market_provider.dart` (targeted), `core/providers/countdown_offer_provider.dart` (full),
`features/kyc/kyc_flow.dart` (full). Also cross-checked `STARTGOLD_DOCUMENTATION.md` §3.11–3.12 and the
existing `knowledge_brain/Withdrawal/MODULE_BRAIN.md` (for the shared `UpiSelectionScreen` finding
cross-confirmation).

### Weighted Coverage Computation

| Category | Weight | Found | Documented | Notes |
|---|---|---|---|---|
| Screens documented | 25% | 3 screens (`instant_saving_screen.dart`, `payment_methods_screen.dart` legacy, `purchase_success_screen.dart`) + 1 bottom-sheet widget (`payment_method_sheet.dart`) | 4/4 | All 4 fully characterized; `payment_methods_screen.dart` and `purchase_success_screen.dart` had large pure-styling sections read via targeted grep + partial line reads rather than exhaustive line-by-line (see Caveats). |
| Controller/service public methods documented | 25% | ~35 (SavingService×5, PaymentService×3, PaymentHandler×7, HdfcPaymentHandler×6, RazorpayPaymentHandler×6, saving_controller providers/notifier×~4, key screen methods×~6) | ~35/35 | Full method-level index in `METHOD_INDEX.md`, including 3 confirmed-dead methods (`cancelOrder`, `createOrder`, `verifyPaymentStatus`). |
| Models documented | 15% | 5 (`SavingConfig`, `PaymentMethod`, `PaymentOrder`, `EligibilityResponse`, `PurchaseInitiateResponse`) | 5/5 | Field-by-field in `STATE_ANALYSIS.md`. |
| API endpoints documented | 15% | 11 (`savings/config`, `savings/check-eligibility`, `savings/initiate`, `savings/confirm-payment`, `savings/cancel_order`, `payments/methods`, `payments/create-order`, `payments/status`, `users/shared/commodities`, `users/shared/amount-denominations`, `users/shared/weight-denominations`) | 11/11 | Method (all POST — corrects the hand-written doc's GET claims), payload shape, and encrypted-field list captured per endpoint in `DATA_FLOW.md`. |
| Business rules captured | 10% | — | 10 rules (RULE-INSTANTSAVING-001..010) | GST formula (both modes), min/max source, rate-lock duration source, weight-precision mismatch, rate-mid-flow risk, gateway-selection rule, best-offer formula. |
| Cross-module deps captured | 10% | — | Full | KYC gate, 3 payment SDKs, 8 `core/providers`/`core/security` files, 1 reused Withdrawal-owned screen — `CROSS_MODULE_MAP.md` with Mermaid graph. |

**Weighted score**: 0.25×(4/4) + 0.25×(35/35) + 0.15×(5/5) + 0.15×(11/11) + 0.10×(10/10, judged complete for
the risk surface identified) + 0.10×(complete) = **~97%**

### Caveats (why not 100%/🔵)

- `instant_saving_screen.dart` (1958 lines): ~1300+ lines read directly (init, all conversion/GST/validation
  logic, eligibility/KYC/payment orchestration, breakdown sheet, truncation helpers); the remaining ~650
  lines are pure widget-styling code (gradient tabs, denomination chip decoration, trend-line painter, dashed
  divider) — spot-checked via grep for any additional API calls, encryption, or `suppressAppLock` references
  (none found) rather than read line-by-line in full.
- `payment_methods_screen.dart` (1059 lines, legacy/dead): ~600 lines read directly, covering all
  API/SDK/state logic; the remainder (~450 lines) is UI styling for the now-unreachable screen, confirmed via
  grep to contain no additional security-relevant code.
- `purchase_success_screen.dart` (544 lines): ~300 lines read directly (data formatting, navigation, the
  critical "Back to Home" refresh logic); the remainder is card-layout styling for success/failure states,
  confirmed via grep to contain no additional `ref.read`/`ref.invalidate`/navigation calls beyond what's
  documented.
- **GST %, `sellRateLockSeconds` exact value**: confirmed as server-driven fields with the correct source
  (`savings/config`), but the actual live numeric values were not observed (no live API call was made during
  this review — static code analysis only). `BUSINESS_RULES.md` and `MODULE_BRAIN.md` explicitly flag these
  as unconfirmed rather than stating a guessed number.
- Manual spot-check performed: re-read `payment_methods_screen.dart`'s header comment and route registration
  together with `instant_saving_screen.dart`'s commented-out `Navigator.pushNamed(AppRouter.paymentMethods...)`
  call sites to independently verify the "legacy/dead route" claim before writing it as fact; cross-confirmed
  the `UpiSelectionScreen` cross-module-reuse finding against the pre-existing `Withdrawal/MODULE_BRAIN.md`.

### Badge: 🟢 (97% — mostly complete)

Next round to reach 🔵 (100% + verified) would require: (1) full line-by-line read of the remaining styling
code in the two large legacy/success-screen files, (2) capturing one live `savings/config` API response to
confirm the actual GST %, min/max, and rate-lock-second values instead of leaving them as "server-driven,
unconfirmed."

## Drift Log (also mirrored into MODULE_BRAIN.md §Drift and should be copied into
`knowledge_brain/_OVERVIEW/BUILD_SUMMARY.md`'s "Open Inaccuracies" section on next `/build-system-brain` run)

1. All `savings/*` and `users/shared/*` endpoints are `POST`, not `GET` as `STARTGOLD_DOCUMENTATION.md`
   §3.11's API table states.
2. Denomination endpoints are `users/shared/amount-denominations` / `.../weight-denominations`, not
   `savings/denominations/amount` / `.../weight` as documented.
3. §3.12 "Payment Methods Screen" describes dead code (`payment_methods_screen.dart` — explicitly marked
   `[LEGACY]` in its own header, unreachable from any live navigation call). The live gateway-launch logic is
   `payment_handler.dart` + its two delegate handlers, invoked directly from `instant_saving_screen.dart`,
   never via the `/payment-methods` route.
4. The doc implies Cashfree/Razorpay only for this screen; live code confirms **three** gateways (Cashfree,
   HDFC/Juspay HyperSDK, Razorpay), selected per-order by the backend.
5. "GST calculation (+3%)" is presented as if fixed; live code sources GST from `savings/config`'s `gst`
   field, with `3.0` appearing only as a pre-load UI fallback constant.
