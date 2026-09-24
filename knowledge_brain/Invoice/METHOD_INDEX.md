---
module: invoice
last_updated: 2026-08-19
primary_documentation: true
---

# Invoice — Method Index

Alphabetical by class, then method. Two classes total; no controller/notifier/model layer exists
in this module (models it depends on, e.g. `TransactionDetailResponse`, are owned by `history` —
see CROSS_MODULE_MAP.md).

## `InvoiceException` (`invoice_service.dart:131-137`)

| Member | Signature | file:line | Notes |
|---|---|---|---|
| constructor | `const InvoiceException(this.message)` | `:133` | Simple `Exception` implementer |
| `message` | `final String message` | `:132` | User-facing, safe to show directly in UI |
| `toString()` | `String toString() => message` | `:136` | |

## `InvoiceService` (static class, `invoice_service.dart:12-128`)

| Method | Signature | file:line | Callers |
|---|---|---|---|
| `downloadInvoice` | `static Future<File> downloadInvoice(String url, {void Function(double progress)? onProgress})` | `:25-118` | `history/screens/transaction_details_screen.dart:368`; `sip/screens/sip_transaction_details_screen.dart:290` |
| `clearCache` | `static Future<void> clearCache()` | `:121-127` | **No call site found anywhere in `lib/`** — likely dead code (unconfirmed) |

Private constructor `InvoiceService._()` (`:13`) — instantiation-blocking only, not called anywhere
by design.

## `InvoiceViewerScreen` (`invoice_viewer_screen.dart:13-25`)

| Member | Signature | file:line | Callers |
|---|---|---|---|
| constructor | `const InvoiceViewerScreen({super.key, required this.filePath, this.title = 'Invoice'})` | `:17-21` | `app_router.dart:371-374` (route builder only — never constructed directly by a feature screen) |
| `createState()` | `State<InvoiceViewerScreen> createState()` | `:24` | Flutter framework (implicit) |

## `_InvoiceViewerScreenState` (`invoice_viewer_screen.dart:27-233`)

| Member | Signature | file:line | Notes / Callers |
|---|---|---|---|
| `_pdfViewerController` | `late final PdfViewerController` (field) | `:28` | Created in `initState`, disposed in `dispose` |
| `_isLoading` | `bool _isLoading = true` (field) | `:29` | Drives the loading overlay; flipped false by `onDocumentLoaded`/`onDocumentLoadFailed` |
| `_errorMessage` | `String? _errorMessage` (field) | `:30` | Set by `_validateFile()` (pre-check) or `onDocumentLoadFailed` (render-time failure) |
| `initState()` | `void initState()` | `:32-37` | Flutter framework. Calls `_validateFile()`. |
| `_validateFile()` | `void _validateFile()` | `:39-47` | Called once from `initState`. Sync existence/non-empty check on `widget.filePath`. |
| `dispose()` | `void dispose()` | `:49-53` | Disposes `_pdfViewerController`. |
| `build(BuildContext)` | `Widget build(BuildContext context)` | `:55-163` | Flutter framework. Renders `AppBar` + `SfPdfViewer.file(...)` or error state. |
| download/share `onPressed` (inline) | `() async { ... Share.shareXFiles([XFile(widget.filePath)], subject: 'startGOLD Invoice') ... }` | `:81-87` | `AppBar` action icon (`Icons.download_rounded`, `:77-88`). Shares the already-local file via `share_plus` — no re-download. |
| `SfPdfViewer.file` `onDocumentLoaded` (inline) | `(details) { if (mounted) setState(() => _isLoading = false); }` | `:114-118` | Syncfusion callback |
| `SfPdfViewer.file` `onDocumentLoadFailed` (inline) | `(details) { if (mounted) setState(() { _isLoading = false; _errorMessage = 'Failed to load PDF: ${details.description}'; }); }` | `:119-127` | Syncfusion callback |
| `_buildErrorState(bool isDark)` | `Widget _buildErrorState(bool isDark)` | `:165-232` | Called from `build()` when `_errorMessage != null`. "Go Back" button pops the route (`:208`). |

## Non-existent (checked, confirmed absent)

- No `invoice_controller.dart` / `InvoiceNotifier` / Riverpod provider anywhere in this module.
- No `invoice_models.dart` — the module has zero model classes of its own; it operates purely on
  `String url` in, `File` out.
- No use of `core/network/api_client.dart` — see MODULE_BRAIN.md §3 for why this is flagged as an
  `AGENTS.md` §4 deviation.
- No `core/security/encryption_service.dart` usage (no request body to encrypt — the download is a
  plain `GET` against a pre-signed/authenticated URL).
