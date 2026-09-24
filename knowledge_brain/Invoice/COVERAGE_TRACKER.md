---
module: invoice
last_updated: 2026-08-19
---

# Invoice — Coverage Tracker

> **Primary documentation, no prior hand-written doc to cross-check.**
> `STARTGOLD_DOCUMENTATION.md` does not cover `invoice` (module added after that doc was written —
> confirmed via `.agents/config.md` §"Pre-Existing Documentation"). Round 1 below is a from-scratch
> code read, not a verification pass against an existing spec. There is no "drift found" section
> because there is nothing pre-existing to drift from.

## Round 1 — 2026-08-19 (Build, from scratch)

**Files read (2/2 = 100% of feature files)**:
- `lib/features/invoice/invoice_service.dart` (138 lines) — full read
- `lib/features/invoice/invoice_viewer_screen.dart` (234 lines) — full read

**Cross-module files read for context (4)**:
- `lib/routes/app_router.dart` (route registration + arg-passing, lines ~125-126, 368-374)
- `lib/features/history/screens/transaction_details_screen.dart` (call site, lines ~320-420)
- `lib/features/sip/screens/sip_transaction_details_screen.dart` (call site + import list, lines
  1-317)
- `lib/features/history/models/history_models.dart` (`TransactionDetailResponse`/`invoiceUrl`
  field, lines 60-157)
- `lib/features/history/services/history_service.dart`,
  `lib/features/sip/services/sip_service.dart` (endpoint confirmation, spot-read)
- `lib/features/sip/apis.md` (existing SIP-module API doc, used to confirm `invoice_url` response
  field shape — not authored by this brain-build)
- `lib/core/network/api_client.dart`, `lib/core/config/app_config.dart` (confirmed no
  `encryptedEndpoints` entry applies, confirmed raw `Dio()` deviation)
- `pubspec.yaml` (confirmed `syncfusion_flutter_pdfviewer: ^28.2.7` is the only PDF-render
  dependency, and this module is its only consumer — grep-verified)

**Weighted coverage computation**:

| Component | Weight | Actual count | Documented | Score |
|---|---|---|---|---|
| Screens documented | 25% | 1 screen (`InvoiceViewerScreen`) | 1/1 | 25% |
| Controller/service public methods documented | 25% | 2 (`downloadInvoice`, `clearCache`) — `InvoiceViewerScreen` has no controller layer, its own methods covered under "screens" | 2/2 | 25% |
| Models documented | 15% | 0 models owned by this module (only `InvoiceException`, a control-flow exception, documented anyway) | N/A — vacuously 15% (nothing to miss) | 15% |
| API endpoints documented | 15% | 0 endpoints owned by this module (it consumes an opaque URL, not a named endpoint) — the 2 *upstream* endpoints that produce the URL (`transactions/details`, `sip/transaction-details`) are documented for context in DATA_FLOW.md/CROSS_MODULE_MAP.md though owned by other modules | 15% (context fully captured) | 15% |
| Business rules captured | 10% | 8 rules (RULE-INVOICE-001 through 008) | 8/8 | 10% |
| Cross-module deps captured | 10% | 2 inbound callers (`history`, `sip`) + 2 violation flags + upstream endpoint provenance | Fully captured | 10% |

**Total: 100%**

Badge: 🟢 (≥80%) — **not yet 🔵** because 🔵 requires "a manual spot-check that the docs match a
fresh read of 2–3 files chosen at random" per the workflow's Step 7, which has not been performed
as a separate pass in this round (the files were each read once, carefully, but not re-verified
against the written docs in a second independent pass).

**Drift found vs STARTGOLD_DOCUMENTATION.md**: N/A — module not covered by that doc (see banner
above).

**New cross-module deps discovered**:
- `sip_transaction_details_screen.dart` imports `history/models/history_models.dart` directly
  (feature-to-feature model reuse) — flagged in CROSS_MODULE_MAP.md as a violation candidate.
- Both `history` and `sip` import `invoice_service.dart` directly rather than through
  `shared/`/`core/` — flagged as the same class of issue, lower severity (utility, not a data
  model).

**Flagged for `_SYSTEM` synthesis** (not yet built — `_SYSTEM/` doesn't exist in this repo as of
this writing per the folder listing):
- DANGER_ZONES candidate: raw `Dio()` bypassing cert pinning in `InvoiceService`
  (RULE-INVOICE-004).
- DANGER_ZONES candidate: unencrypted PDF cache sitting in OS temp dir indefinitely
  (STATE_ANALYSIS.md "Filesystem state" section).
- DIAGNOSTIC_PLAYBOOK candidate: FORENSIC_TEMPLATE.md item 5 (unguarded route-argument cast) as a
  general "check the route arg shape first" pattern likely repeated at other `Map<String,
  dynamic>`-argument routes in `app_router.dart` — not verified for other routes in this pass.
