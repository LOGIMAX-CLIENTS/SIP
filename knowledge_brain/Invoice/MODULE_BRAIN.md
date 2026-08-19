---
module: invoice
brain_status: 🟢 (≥80%, not yet manually spot-checked for 🔵)
last_updated: 2026-08-19
source_files_read: 2/2 feature files + 4 cross-module call-site/router/model files
primary_documentation: true
---

# Invoice Module Brain

> **This is primary documentation.** `STARTGOLD_DOCUMENTATION.md` does not cover `invoice` at all
> (module added after that doc was written, per `.agents/config.md`). There is nothing to
> cross-check or find drift against — every claim below is grounded directly in live code, not
> verified against a prior written spec.

## 1. Purpose & Scope

`lib/features/invoice/` is a **utility module, not a screen users navigate to directly**. It has
exactly **2 files** and no `screens/`, `controller/`, `models/`, or `widgets/` subfolders:

| File | Lines | Role |
|---|---|---|
| `invoice_service.dart` | 138 | Static-method service: downloads a PDF from a URL via Dio, caches it in the device temp dir, maps failures to a typed `InvoiceException`. |
| `invoice_viewer_screen.dart` | 234 | Full-screen `StatefulWidget` that renders an already-downloaded local PDF file using `syncfusion_flutter_pdfviewer`'s `SfPdfViewer.file()`. Also offers a share/download action via `share_plus`. |

The module does **not** generate invoices, does not know about transactions, and does not call any
transaction/order API. It is a generic "fetch a PDF by URL, cache it, show it" pair, consumed by
other modules that already know a PDF URL exists.

## 2. Screen/Route Table

| Route constant | Path | Screen | Registered | Arguments consumed |
|---|---|---|---|---|
| `AppRouter.invoiceViewer` | `/invoice-viewer` | `InvoiceViewerScreen` | `lib/routes/app_router.dart:368-374` | `file_path` (String, required — local path to a **cached** PDF, not the invoice URL), `title` (String, optional, defaults to `'Invoice'`) |

Route handler (`app_router.dart:368-374`) casts `ModalRoute.of(context)!.settings.arguments` to
`Map<String, dynamic>` with no null/type guard — a caller that omits `file_path` or navigates here
directly (deep link, wrong-typed args) will throw at route-build time. In practice both current
call sites (see §4) always populate both keys, so this is unconfirmed as a live risk, only a
structural fragility.

The screen is **never reachable from a menu, tab, or direct link** — it only exists as the second
hop after `InvoiceService.downloadInvoice()` succeeds (see DATA_FLOW.md).

## 3. `InvoiceService` (static class, `invoice_service.dart:12`)

No instance state; `InvoiceService._()` is a private unnamed constructor purely to prevent
instantiation — every member is `static`.

- `downloadInvoice(String url, {void Function(double)? onProgress}) → Future<File>`
  (`:25-118`). Validates the URL has a scheme and a host containing `.` (`:31`), builds a cache
  path under `<tempDir>/invoices/<lastPathSegment-or-hash>.pdf` (`:36-49`), returns the cached file
  immediately if it already exists and is non-empty (`:53-56`), otherwise downloads via a
  module-local `Dio` instance (`:15-19`, 30s connect / 60s receive timeout,
  `ResponseType.bytes`) with progress callback support, and writes the bytes to disk (`:75`).
- `clearCache() → Future<void>` (`:121-127`). Deletes the entire `<tempDir>/invoices/` directory
  recursively. **No call site found anywhere in `lib/`** — unconfirmed whether this is dead code,
  intended for a future "clear cache" settings action, or invoked from a place outside static grep
  coverage.

Error mapping (`:78-117`) is thorough and user-facing-safe: connection/receive timeout → "Connection
timed out..."; `connectionError` → "No internet connection..."; HTTP 404 → "Invoice not available.
It may not have been generated yet."; 401/403 → "Access denied. Please log in again and retry.";
500/502/503 → "Server is temporarily unavailable..."; any other status → generic
"Unable to download invoice (Error N)."; any other exception → generic "Something went wrong."
All are wrapped in `InvoiceException` (`:131-137`), a simple `Exception` implementer with a
`message` field, so callers can catch it specifically and show `e.message` directly in a toast
(both current call sites do exactly this — see DATA_FLOW.md).

Note: **this is not through `core/network/api_client.dart`** — it instantiates its own `Dio()`
directly (`:15-19`), which is an explicit deviation from `AGENTS.md` §4 ("do not instantiate a raw
`Dio()`... in a feature"). This is defensible here because the PDF endpoint is a plain authenticated
file download (`response.data['success']`-style JSON envelope doesn't apply to raw PDF bytes,
`ResponseType.bytes`), but it also means this request bypasses `ApiClient`'s interceptor chain
entirely — no field-level encryption (not applicable, no request body), no automatic 401 refresh,
no certificate pinning (`CertificatePinning.setup` is only wired onto `ApiClient`'s `Dio` instance in
`api_client.dart:28-30`, not this module's). **Flagged as an anti-pattern candidate for
`_SYSTEM/DANGER_ZONES.md`**: if the invoice URL's host requires the same cert pinning as the rest
of the API surface, this module silently doesn't enforce it. Unconfirmed whether the invoice URL is
served from the same pinned domain as `AppConfig.baseUrl`.

## 4. `InvoiceViewerScreen` (`invoice_viewer_screen.dart:13`)

`StatefulWidget` taking `filePath` (required) and `title` (defaults `'Invoice'`) as constructor
params — these come straight from the route arguments (§2), not fetched independently.

- `initState()` (`:32-37`) creates a `PdfViewerController` and calls `_validateFile()`.
- `_validateFile()` (`:39-47`) synchronously checks `File(filePath).existsSync()` and
  `.lengthSync() > 0`; if either fails, sets `_errorMessage` and shows the error state instead of
  the viewer — this is a **defensive re-check**, since `InvoiceService.downloadInvoice` already
  validated the file existed at download time, guarding against the file having been evicted from
  the OS temp dir between download and screen build.
- `build()` renders `SfPdfViewer.file(File(filePath), ...)` (`:108-128`) inside a `Stack` with a
  loading overlay driven by `onDocumentLoaded`/`onDocumentLoadFailed` callbacks, plus an app bar
  with a green-gradient background (`:91-100`, same gradient constants as `GradientHeader` — see
  CROSS_MODULE_MAP) and a download/share `IconButton` (`:76-88`) that calls
  `Share.shareXFiles([XFile(filePath)], subject: 'startGOLD Invoice')` via `share_plus` — this
  shares/exports the **already-downloaded local file**, it does not re-download.
- Error state (`_buildErrorState`, `:165-232`) shows a "Go Back" button that just pops the route.

No Riverpod provider is watched or read anywhere in this screen — it is pure `StatefulWidget` local
state (`_isLoading`, `_errorMessage`), consistent with the module having no `controller/`
subfolder.

**Security surface**: no field-level encryption applies (no request payload — the screen doesn't
make any network call itself, the download already happened before navigation). No explicit
`ScreenshotSecurityService`/`FLAG_SECURE` call in this file — unconfirmed whether an invoice PDF
(which can contain the customer's name, order amount, and transaction ID) should be treated as
sensitive per `AGENTS.md` §3's "PAN, bank account, OTP" screenshot-block guidance; invoices are
financial documents the user explicitly wants to share (the screen's own primary action is
"Share"), so the omission may be intentional rather than an oversight — flagged as unconfirmed, not
asserted as a bug.

## 5. Who Navigates Here (upstream callers)

`invoice` has **zero outbound dependencies on other features** but **two known inbound callers**,
both of which import `InvoiceService` directly (not through `core/` or `shared/`):

| Caller | File | Trigger |
|---|---|---|
| Transaction Details (History) | `lib/features/history/screens/transaction_details_screen.dart:351-395` | "Invoice" `OutlinedButton` shown only if `details.invoiceUrl.isNotEmpty` |
| SIP Transaction Details | `lib/features/sip/screens/sip_transaction_details_screen.dart:274-317` | Same pattern, same button label, same code shape (looks copy-pasted) |

Both call sites are byte-for-byte near-identical: show a blocking loading dialog →
`InvoiceService.downloadInvoice(details.invoiceUrl)` → on success, pop the dialog and
`Navigator.pushNamed(context, AppRouter.invoiceViewer, arguments: {'file_path': file.path, 'title':
'Invoice'})` → on `InvoiceException`, pop the dialog and toast `e.message` → on any other exception,
pop the dialog and toast a generic "Could not open invoice". Full trace in `DATA_FLOW.md`.

`details.invoiceUrl` in both cases is the same shared model, `TransactionDetailResponse` (owned by
the **`history`** module, `lib/features/history/models/history_models.dart:91-157`,
`invoiceUrl` field at `:104`, populated from `root['invoice_url'] ?? ''`) — the `sip` module imports
this model directly (`sip_transaction_details_screen.dart:15`) rather than owning its own copy. See
CROSS_MODULE_MAP.md for why this is worth flagging.

## 6. Top Risks / Open Questions

1. **Raw `Dio()` bypasses `ApiClient`'s cert-pinning/interceptor chain** (§3) — unconfirmed whether
   this matters in practice (depends on whether the invoice host is the pinned host).
2. **`clearCache()` appears to be dead code** — no call site found.
3. **Route argument cast has no null/type safety** (`app_router.dart:369-370`) — only safe today
   because both callers are disciplined about the args shape.
4. **No screenshot/app-lock treatment on a screen showing financial PDF content** — unconfirmed
   whether this is a gap or an intentional decision given the screen's own "Share" affordance.
5. **Two independent, drifting copies of the same call-site code** (history's and sip's transaction
   details screens) — a bug fix in one (e.g. adding a retry, changing the toast copy) has no
   mechanism forcing it into the other.

## 7. Related Docs

`METHOD_INDEX.md` · `DATA_FLOW.md` · `BUSINESS_RULES.md` · `CROSS_MODULE_MAP.md` ·
`STATE_ANALYSIS.md` · `FORENSIC_TEMPLATE.md` · `COVERAGE_TRACKER.md` (this folder).
