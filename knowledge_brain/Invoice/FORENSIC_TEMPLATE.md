---
module: invoice
last_updated: 2026-08-19
primary_documentation: true
---

# Invoice — Forensic Template

Symptom → check first → likely suspects, for bug triage in this module.

## 1. "Invoice" button does nothing / spinner never dismisses

**Check first**: is the device actually offline, or is the invoice host unreachable? The blocking
`showDialog` (`transaction_details_screen.dart:357-366` / `sip_transaction_details_screen.dart:279-288`)
is dismissed only inside the `try`/`catch` around `InvoiceService.downloadInvoice` — if that call
somehow never resolves (hangs), the dialog is stuck forever since there's no timeout guard at the
call-site level (the 30s connect / 60s receive timeout is inside `InvoiceService`'s own `Dio`,
`invoice_service.dart:16-18`, so it *should* eventually throw and unwind, but confirm the timeout
actually fired in logs via `SecureLogger`).

**Likely suspects**: `invoice_service.dart:59-77` (the download try block) not throwing as
expected; `context.mounted` guard (`:371,383,389` in both callers) silently swallowing the
pop/toast if the widget was disposed mid-await (e.g. user backed out of the screen while
downloading).

## 2. Invoice shows stale/wrong content on reopen

**Check first**: is this the *same* transaction's invoice, or a different one? Cache is keyed by
URL-derived filename (`invoice_service.dart:43-49`) — if the backend reuses the same URL/filename
for a regenerated invoice (e.g. after a correction), the stale cached file is served
(RULE-INVOICE-002). Confirm by checking the actual `invoiceUrl` string returned by
`transactions/details` / `sip/transaction-details` for that transaction across two calls.

**Likely suspects**: backend invoice-URL generation not being unique per generation; the local
`invoices/` cache directory not being cleared (`clearCache()` has no call site —
RULE-INVOICE-008).

## 3. "Invoice file not found or corrupted" error immediately after a successful download

**Check first**: OS temp-directory eviction under memory pressure — `getTemporaryDirectory()`
(iOS `NSTemporaryDirectory`, Android cache dir) can be cleared by the OS between the download
completing and the viewer screen's `_validateFile()` running, especially on low-end devices or
after a long background period.

**Likely suspects**: `invoice_viewer_screen.dart:39-47` (`_validateFile`) correctly catching this
and showing the error state (this is expected/working behavior, not a bug) vs. a genuine write
failure in `downloadInvoice` (`:75`, `file.writeAsBytes`) that didn't actually throw — check
`SecureLogger.d('Invoice downloaded successfully')` (`:76`) actually logged before the viewer
opened.

## 4. Share/download icon shares an empty or old file

**Check first**: confirm `widget.filePath` passed into `InvoiceViewerScreen` (via route args
`file_path`) matches the file the user expects — `Share.shareXFiles` (`:81-87`) shares exactly
that path, with zero re-validation beyond what already happened in `initState`.

**Likely suspects**: a race where the cache file was deleted (`clearCache()` or OS eviction)
*after* `_validateFile()` passed but *before* the user tapped Share — `Share.shareXFiles` itself
would likely throw a platform exception in that case (unhandled in this code — no try/catch around
the `Share.shareXFiles` call, `:81-87`), which would surface as an uncaught error rather than a
graceful in-app message. Flag as a potential unhandled-exception gap.

## 5. `AppRouter.invoiceViewer` crashes on navigation ("type 'Null' is not a subtype of type 'Map...'")

**Check first**: was `AppRouter.invoiceViewer` reached from anywhere other than `history`'s or
`sip`'s transaction-details screens (e.g. a deep link, a push notification action, or a new call
site added without following the existing `arguments: {'file_path': ..., 'title': ...}` shape)?

**Likely suspects**: `app_router.dart:369-370`'s unguarded cast
`ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>` — any caller that pushes this
route with `null` or a differently-typed arguments object will throw here, before
`InvoiceViewerScreen` even builds (MODULE_BRAIN.md §2).

## 6. Invoice download works on WiFi but fails intermittently on cellular / behind a proxy

**Check first**: is the invoice host on the same cert-pinned domain as the rest of the API? This
module's `Dio()` instance (`invoice_service.dart:15-19`) has **no certificate pinning**
(`CertificatePinning.setup` is only wired onto `core/network/api_client.dart`'s `Dio`,
`api_client.dart:28-30`) — a MITM-capable proxy (corporate/public WiFi) that would be blocked by
pinning on every other API call would succeed (or fail differently) here. This is a genuine
security-relevant asymmetry, not just a UX bug — see RULE-INVOICE-004.

**Likely suspects**: network conditions specific to the invoice host's TLS setup, not exercised by
the rest of the app's pinned traffic.
