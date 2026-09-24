---
module: invoice
last_updated: 2026-08-19
primary_documentation: true
---

# Invoice — State Analysis

## Riverpod providers/notifiers

**None.** Repo-wide grep for `Provider`/`StateNotifier`/`AsyncNotifier` inside
`lib/features/invoice/` returns no matches. `InvoiceViewerScreen` is a plain `StatefulWidget`
(`invoice_viewer_screen.dart:13`), not a `ConsumerWidget`/`ConsumerStatefulWidget` — it never
imports `flutter_riverpod`. All state is local `setState`-driven:

| State field | Type | Owner | Lifecycle |
|---|---|---|---|
| `_isLoading` | `bool` | `_InvoiceViewerScreenState` | Starts `true`; flipped `false` by `onDocumentLoaded` or `onDocumentLoadFailed` |
| `_errorMessage` | `String?` | `_InvoiceViewerScreenState` | `null` unless `_validateFile()` or `onDocumentLoadFailed` sets it |
| `_pdfViewerController` | `PdfViewerController` | `_InvoiceViewerScreenState` | Created `initState`, disposed `dispose` — Syncfusion's own controller, not app state |

Because there's no provider, invoice-viewing state does not survive navigation away and back — a
fresh `InvoiceViewerScreen` instance re-validates the file from scratch every time it's pushed.

## Model shapes owned by this module

**None.** `invoice` has no `models/` subfolder and defines no data class beyond the
control-flow-only `InvoiceException` (`invoice_service.dart:131-137`, a `message` string wrapper,
not a JSON-serializable model — no `fromJson`/`toJson`).

The `invoiceUrl` string this module consumes is a field on a model it does **not** own
(`TransactionDetailResponse`, `history/models/history_models.dart:91-157` — see
CROSS_MODULE_MAP.md).

## Secure storage keys touched

**None.** No `flutter_secure_storage` / `SecureStorageService` usage anywhere in this module —
confirmed via grep for `secure_storage`/`SecureStorageService` inside
`lib/features/invoice/`, zero matches.

## Filesystem state (the module's actual persistence layer)

Unlike most modules, `invoice`'s durable state is **plain filesystem**, not secure storage or a
provider:

| Location | Written by | Read by | Notes |
|---|---|---|---|
| `<getTemporaryDirectory()>/invoices/<filename>.pdf` | `InvoiceService.downloadInvoice()` (`:75`) | `InvoiceService.downloadInvoice()` cache-hit check (`:53`), `InvoiceViewerScreen._validateFile()` (`:41`), `SfPdfViewer.file()` (`:109`) | OS temp dir — not guaranteed to persist across app restarts/OS memory pressure; not encrypted at rest beyond whatever the OS/platform provides for its temp partition |

This is a meaningful deviation from the app's general "sensitive data → `flutter_secure_storage`"
posture (`AGENTS.md` §3) — an invoice PDF (containing name, amount, transaction ID) sits in
plaintext in the OS-shared temp directory for as long as the OS keeps it around, since
`clearCache()` (the only code path that would delete it early) has no call site
(`BUSINESS_RULES.md` RULE-INVOICE-008). Flagged as unconfirmed risk, not asserted as a confirmed
vulnerability — temp-directory sandboxing on iOS/Android generally restricts access to the owning
app, but this is still weaker than the app's stated secure-storage discipline for other sensitive
data.

## Threading / async notes

`downloadInvoice`'s `onReceiveProgress` callback (`:63-67`) is available for progress reporting but
**no call site passes an `onProgress` callback** — both `history` and `sip` call
`InvoiceService.downloadInvoice(details.invoiceUrl)` with no second argument
(`transaction_details_screen.dart:368-370`, `sip_transaction_details_screen.dart:290-292`) — so the
blocking spinner dialog shown during download has no progress indication, just an indeterminate
`CircularProgressIndicator`. The `onProgress` parameter is unused dead capability, not a bug.
