---
module: invoice
last_updated: 2026-08-19
primary_documentation: true
---

# Invoice — Data Flow

The module itself has no entry point of its own — every flow starts in a **different** module
(`history` or `sip`) that already holds an `invoiceUrl` string on a fetched transaction-detail
model, and ends by handing off to `InvoiceViewerScreen`.

## Flow 1: View invoice from Transaction (History) Details

```
User opens a transaction from History → transaction_details_screen.dart
  → screen watches transactionDetailsProvider(transactionId)   (history_controller.dart:191-198)
      → HistoryService.getTransactionDetails(customerId, transactionId)  (history_service.dart:73-92)
          → POST transactions/details  { id_customer, transaction_id }
          → TransactionDetailResponse.fromJson(response.data.data)       (history_models.dart:128-156)
             invoiceUrl ← root['invoice_url'] ?? ''                      (history_models.dart:148)
  → screen renders "Invoice" OutlinedButton IF details.invoiceUrl.isNotEmpty  (transaction_details_screen.dart:351)
  → user taps "Invoice"
      → showDialog(barrierDismissible:false) — blocking spinner overlay      (:357-366)
      → InvoiceService.downloadInvoice(details.invoiceUrl)                   (:368-370)
          ├─ success → File returned (from cache or fresh download)
          │     → Navigator.pop(context)  // dismiss spinner                 (:372)
          │     → Navigator.pushNamed(context, AppRouter.invoiceViewer,
          │            arguments: {'file_path': file.path, 'title': 'Invoice'})  (:373-380)
          │     → InvoiceViewerScreen renders SfPdfViewer.file(File(filePath))
          ├─ InvoiceException → pop spinner → AppToast.show(context, e.message, error)  (:382-387)
          └─ any other Exception → pop spinner → AppToast.show(context, 'Could not
                open invoice', error)                                         (:388-394)
```

## Flow 2: View invoice from SIP Transaction Details

Structurally identical to Flow 1, different origin API and origin screen:

```
User opens a SIP transaction from SIP history → sip_transaction_details_screen.dart
  → screen watches sipTransactionDetailsProvider(transactionId)   (sip_controller.dart:376)
      → SipService.getSipTransactionDetails(transactionId)        (sip_service.dart:275-292)
          → POST sip/transaction-details  { transaction_id }
          → raw Map returned (no service-level model mapping)
  → screen does: final details = TransactionDetailResponse.fromJson(response['data'])
        (sip_transaction_details_screen.dart:64-66)
        — reuses HISTORY's model class directly, not a sip-owned model (see CROSS_MODULE_MAP.md)
  → same OutlinedButton / dialog / downloadInvoice / pushNamed(AppRouter.invoiceViewer) /
    InvoiceException-vs-generic-error handling as Flow 1
    (sip_transaction_details_screen.dart:274-317 — near-identical code block)
```

## Flow 3: Cache hit (re-opening the same invoice)

```
User taps "Invoice" a second time for the same transaction (same session, same temp dir)
  → InvoiceService.downloadInvoice(url)                                (invoice_service.dart:25-118)
      → builds cache path from URL's last path segment (or hashCode fallback)  (:43-49)
      → File(filePath).existsSync() && file.lengthSync() > 0 → TRUE     (:53)
      → returns cached File immediately — NO network request made      (:54-56)
  → same navigation to InvoiceViewerScreen as Flow 1/2
```
Cache lives at `<getTemporaryDirectory()>/invoices/<filename>.pdf` — OS-managed temp storage, not
`flutter_secure_storage`. It is cleared only by OS temp-dir eviction or a manual call to
`InvoiceService.clearCache()`, which (per METHOD_INDEX.md) has no call site — so in practice the
cache persists for the life of the OS temp directory / app data.

## Flow 4: Download failure (network/HTTP error)

```
InvoiceService.downloadInvoice(url) throws
  ├─ Invalid URL (no scheme / no '.' in host)          → InvoiceException('Invalid invoice URL')          (:31-33)
  ├─ DioException: connectionTimeout/receiveTimeout     → InvoiceException('Connection timed out...')      (:80-83)
  ├─ DioException: connectionError                      → InvoiceException('No internet connection...')   (:86-88)
  ├─ HTTP 404                                           → InvoiceException('Invoice not available...')    (:94-96)
  ├─ HTTP 401/403                                       → InvoiceException('Access denied...')             (:97-100)
  ├─ HTTP 500/502/503                                   → InvoiceException('Server is temporarily...')     (:101-105)
  ├─ other HTTP status                                  → InvoiceException('Unable to download... (Error N)')  (:106-108)
  └─ any other exception                                → InvoiceException('Something went wrong...')      (:113-116)
→ propagates up to the calling screen's catch block → toast e.message, spinner dismissed, user stays
  on the Transaction/SIP Details screen (no navigation to InvoiceViewerScreen happens on failure)
```

## Flow 5: In-viewer render failure (file corrupted/unreadable after download succeeded)

```
InvoiceViewerScreen.initState() → _validateFile()                        (:39-47)
  → File(filePath).existsSync() == false OR .lengthSync() == 0
  → setState(_errorMessage = 'Invoice file not found or corrupted.')
  → build() renders _buildErrorState() instead of SfPdfViewer             (:104-105, 165-232)

— OR, if the file exists but Syncfusion can't parse it —

SfPdfViewer.file(...).onDocumentLoadFailed(details)                       (:119-127)
  → setState(_errorMessage = 'Failed to load PDF: ${details.description}')
  → build() re-renders to _buildErrorState()
```
"Go Back" button in the error state (`:207-226`) is the only recovery action — it just pops the
route; there is no retry/re-download affordance from inside `InvoiceViewerScreen` itself (the user
would have to go back and tap "Invoice" again from the Transaction Details screen).

## Summary table

| Flow | Origin module | API hit | Cache used | Result |
|---|---|---|---|---|
| View invoice (History) | `history` | `POST transactions/details` (upstream, not invoice's own call) + raw `GET <invoiceUrl>` | Write on first fetch | Navigates to `InvoiceViewerScreen` |
| View invoice (SIP) | `sip` | `POST sip/transaction-details` (upstream) + raw `GET <invoiceUrl>` | Write on first fetch | Navigates to `InvoiceViewerScreen` |
| Cache hit | either | None (skipped) | Read | Navigates to `InvoiceViewerScreen` immediately |
| Download failure | either | Raw `GET <invoiceUrl>` fails | N/A | Toast error, stays on Details screen |
| Render failure | `invoice` (viewer itself) | None | Read (already cached) | Error state inside viewer, "Go Back" only |
