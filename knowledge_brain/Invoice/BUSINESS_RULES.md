---
module: invoice
last_updated: 2026-08-19
primary_documentation: true
---

# Invoice — Business Rules

## RULE-INVOICE-001 — Invoice button only shown when an invoice URL exists
Both callers (`history/screens/transaction_details_screen.dart:351`,
`sip/screens/sip_transaction_details_screen.dart:274`) gate the "Invoice" button on
`details.invoiceUrl.isNotEmpty`. The backend controls invoice availability by returning `""` for
`invoice_url` when none exists yet (documented explicitly in `sip/apis.md:695` — "Download URL
(empty if unavailable)"). Status: implemented, consistently in both call sites.

## RULE-INVOICE-002 — Downloaded PDFs are cached by URL-derived filename, keyed for the app session
`InvoiceService.downloadInvoice` derives the cache filename from the URL's last path segment (or a
hash of the URL if no path segments exist), always forcing a `.pdf` suffix if missing
(`invoice_service.dart:43-48`). A second request for the same URL returns the cached file without
a network call (`:53-56`). Status: implemented. Caveat: if the backend ever reuses the same
filename/URL for a *regenerated* invoice (e.g. corrected amounts), the stale cached PDF would be
served instead — unconfirmed whether invoice URLs/filenames are guaranteed unique per
generation on the backend.

## RULE-INVOICE-003 — URL must have a scheme and a dotted host before any download attempt
`downloadInvoice` rejects the URL up front if `Uri.tryParse` fails, or the URI has no scheme, or
the host doesn't contain a `.` (`invoice_service.dart:30-33`) — throws `InvoiceException('Invalid
invoice URL')` before any network I/O. Status: implemented. This is a shallow sanity check (not a
full SSRF/allowlist validation) — it would not reject e.g. `http://evil.com` since it only checks
for a dot in the host, not a specific domain. Given the URL originates from the backend's own API
response (not user input), this is likely sufficient defense-in-depth rather than a security
boundary — unconfirmed whether the backend response is itself validated server-side.

## RULE-INVOICE-004 — Invoice download does not go through the app's shared `ApiClient`
`InvoiceService` uses its own module-local `Dio()` instance (`invoice_service.dart:15-19`),
bypassing `core/network/api_client.dart`'s interceptor chain — no automatic 401 token refresh, no
certificate pinning (`CertificatePinning.setup` only wires onto `ApiClient`'s own `Dio`,
`api_client.dart:28-30`), no field-level encryption path (moot here, no request body). Status:
implemented as designed for a raw file GET, but flagged as a deviation from `AGENTS.md` §4 ("do not
instantiate a raw `Dio()`... in a feature"). Unconfirmed whether the invoice host requires the same
cert pinning as the primary API host.

## RULE-INVOICE-005 — HTTP status codes map to specific, user-actionable error copy
`downloadInvoice`'s catch block (`:78-117`) maps timeout, no-connectivity, 404, 401/403, and
5xx to distinct user-facing strings (see DATA_FLOW.md Flow 4 for the full mapping) rather than
surfacing raw exception text — consistent with `AGENTS.md` §5's error-handling guidance. Status:
implemented, thoroughly.

## RULE-INVOICE-006 — Viewer re-validates the file before rendering, independent of the download step
`InvoiceViewerScreen._validateFile()` (`invoice_viewer_screen.dart:39-47`) re-checks
`existsSync()`/`lengthSync() > 0` on `initState`, even though `InvoiceService.downloadInvoice`
already guaranteed a non-empty file at download time. This guards against the OS evicting the temp
file (or another process touching it) in the window between download and screen build. Status:
implemented, defensive-only (never observed to trigger from this code path in isolation — would
require an external file-system event).

## RULE-INVOICE-007 — Share action shares the local cached file, not a fresh download
The `AppBar` download/share icon (`invoice_viewer_screen.dart:76-88`) calls
`Share.shareXFiles([XFile(widget.filePath)], subject: 'startGOLD Invoice')` against the **already
on-disk** file passed in via route arguments — it does not re-hit `InvoiceService.downloadInvoice`
or the network. Status: implemented. Correct behavior given the file is already local, but the
button icon is `Icons.download_rounded` (suggests "download") while the actual OS behavior is "open
the native share sheet" (which may include a "Save to Files" option depending on platform) — a
naming/icon nuance, not a functional bug.

## RULE-INVOICE-008 — `clearCache()` exists but is never invoked (dead code, unconfirmed)
`InvoiceService.clearCache()` (`invoice_service.dart:121-127`) recursively deletes the entire
`invoices/` cache directory. Repo-wide grep found no call site. Status: **unconfirmed dead code** —
either intended for a future Settings "Clear Cache" action, or should be wired into an existing
account-deletion/logout flow (per `AGENTS.md` §5-adjacent hygiene expectations) and currently isn't.

## Rules explicitly NOT found (checked for, absent)
- No maximum cache size / eviction policy beyond the OS's own temp-dir management.
- No expiry/TTL on cached PDFs — a cached invoice is served indefinitely until the OS clears the
  temp directory or `clearCache()` is manually invoked (which nothing currently does).
- No screenshot-block (`ScreenshotSecurityService`) or app-lock suppression logic in
  `InvoiceViewerScreen` — contrast with `AGENTS.md` §3's guidance for screens showing sensitive
  financial data; unconfirmed whether this omission is intentional.
- No retry/re-download affordance inside the viewer's error state — only "Go Back".
