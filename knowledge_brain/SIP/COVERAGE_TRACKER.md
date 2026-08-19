---
module: sip
last_updated: 2026-08-19
---

# SIP — Coverage Tracker

Badges: ⬜ 0% (not built) · 🟡 1–79% (partial) · 🟢 80–99% (mostly complete) · 🔵 100% + verified.

## Round 1 — 2026-08-19

| Dimension | Weight | Actual count | Documented | Score |
|---|---|---|---|---|
| Screens | 25% | 15 screen/widget files (11 routed screens + `BankDetailsSheet`, `_SipHistoryTabView`, `_SipTransactionFilterSheet` internal widgets, `AutoSavingsScreen`) | All 15 inventoried; 11 fully read line-by-line (`sip_controller.dart`-adjacent screens, `auto_savings_screen.dart` in full despite 2367 lines, `sip_payment_screen.dart`, cancel/manage/success/failure/bank-picker/bank-details-sheet); 4 large history/overview/details/filter screens read to ~40-60% line coverage + full structural grep (all `Future<void>`/`Widget _build*`/API-call/navigation sites enumerated) — no functional logic left unexamined, only repetitive UI-styling code skipped | 90% |
| Controller/service public methods | 25% | `SipService` 13, `CustomSipService` 6, `SipNotifier` 9, `SipHistoryNotifier` 5, `SipState` 3 = 36 | 36/36 read and documented in METHOD_INDEX.md | 100% |
| Models | 15% | 10 classes in `sip_models.dart` + `SipTransactionFilter` + `SipTransactionFilterOptions` = 12 | 12/12 fields and factory logic documented in STATE_ANALYSIS.md | 100% |
| API endpoints | 15% | 19 (`sip/config, sip/gold-denominations, sip/silver-denominations, sip/create, sip/details, sip/manage-details, sip/pause, sip/resume, sip/cancel, sip/confirm, sip/transactions, sip/transaction-filter-options, sip/transaction-details, sip/custom/create, sip/custom/list, sip/custom/{id}/pause, sip/custom/{id}/resume, sip/custom/{id}/cancel, sip/custom/{id}/status`) | 19/19 documented with method/endpoint/caller in METHOD_INDEX.md | 100% |
| Business rules | 10% | Cancellation-eligibility (primary requested focus), duplicate-plan guards (both products), amount/frequency validation, KYC gate, payment-method/eMandate rules, encryption-coverage gap, cancel-reason enum, force-refresh pattern | 13 rules (RULE-SIP-001 to -013) captured with file:line | 90% |
| Cross-module deps | 10% | core (network/security/providers/error), kyc, profile, instant_saving, history, invoice, support, nominee (disabled), daily_savings (confirmed unrelated), routes | All captured with Mermaid graph and a "who depends on sip" reverse check; one dependency (`withdrawal` reusing `BankAccountPickerScreen`) is `unconfirmed`, sourced from a doc comment only, not independently re-verified against the `withdrawal` module's own source (out of scope for this pass) | 85% |

**Weighted total**: 0.25×90 + 0.25×100 + 0.15×100 + 0.15×100 + 0.10×90 + 0.10×85
= 22.5 + 25 + 15 + 15 + 9 + 8.5 = **95%**

**Badge**: 🟢 (80–99%). Not 🔵 — that requires ≥95% **and** a separate manual spot-check pass
re-reading 2-3 randomly chosen files against the finished docs; this round's 95% was reached
through careful first-pass reading (all claims cite file:line, checked against source as written)
but no distinct second-pass spot-check was performed. Recommend a Round 2 spot-check of
`sip_transaction_history_screen.dart`, `sip_overview_screen.dart`, and `sip_transaction_filter_sheet.dart`
(the three least-deeply-read files) before promoting to 🔵.

## What would raise the score

1. Read the remaining ~40-60% of `sip_transaction_history_screen.dart` (917 lines),
   `sip_overview_screen.dart` (811 lines), `sip_transaction_details_screen.dart` (682 lines), and
   `sip_transaction_filter_sheet.dart` (623 lines) line-by-line rather than structurally-grepped —
   none of the functional logic in these files is believed to be missing (grep covered every
   `Future<void>`/`Widget _build*`/API-call/navigation site), but a full read would catch any
   subtle UI-conditional business logic (e.g. an inline validation) that a grep pass could miss.
2. Independently verify the `withdrawal` module actually reuses `BankAccountPickerScreen` (§3 of
   `CROSS_MODULE_MAP.md`) rather than trusting the doc comment.
3. Confirm with backend whether RULE-SIP-011 (Custom SIP's missing field encryption) is intentional
   or a genuine gap — currently a code-grounded but backend-intent-`unconfirmed` finding.
4. Cross-check `STARTGOLD_DOCUMENTATION.md` §3.20-3.26 line-by-line once more after this brain is
   finalized, and log the drift found (24h cancel lock omission, Custom SIP not mentioned as a
   distinct product, payment-gateway duality not mentioned) into
   `knowledge_brain/_OVERVIEW/BUILD_SUMMARY.md` per `AGENTS.md` §10 (not yet done in this pass —
   verify `_OVERVIEW/BUILD_SUMMARY.md`'s existence/format before appending).
