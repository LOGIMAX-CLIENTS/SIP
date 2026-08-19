---
module: kyc
---

# KYC — Forensic Template

Symptom → check first → likely suspects. Each entry cites the code that explains the behavior.

## 1. "I see an 'ENCRYPTION ERROR' log line on every KYC upload, but the request seems to succeed"

**Check first:** `SecureLogger` output around a `kyc/upload` call for a line starting `ENCRYPTION ERROR:`.

**Likely cause (confirmed code path, runtime effect inferred, not yet reproduced):** `KycRepository.uploadKyc()`
/ `_uploadAadhaar()` (`kyc_repository.dart:51-58,152-166`) encrypt sensitive fields themselves before
building `postData`. Because `kyc/upload` is also listed in `AppConfig.encryptedEndpoints`
(`app_config.dart:57`), `ApiSecurityInterceptor.onRequest` (`core/security/api_interceptor.dart:166-182`)
runs `EncryptionService.encryptJson()` on the ENTIRE payload again, recursing into the already-encrypted
`fields` map. RSA-OAEP-SHA256's plaintext-size ceiling is smaller than its own base64 ciphertext output, so
attempting to re-encrypt an already-encrypted field is expected to throw inside `encryptJson` — caught by the
interceptor's `try/catch` (`api_interceptor.dart:178-180`) and logged, not surfaced to the user. Because the
throw happens before `options.data = ...` completes, the ORIGINAL correctly-once-encrypted payload
(built by the repository) is what actually gets sent — so this is very likely cosmetic log noise, not a
functional bug. **If you ever see a genuinely corrupted/undecryptable KYC submission on the backend side,
this is the first place to look** — re-verify the "throws before assignment" assumption with a debugger
rather than trusting this inference. See `BUSINESS_RULES.md` RULE-KYC-011.

## 2. "Aadhaar DigiLocker webview never returns — user is stuck on the webview screen"

**Check first:** Does the consent-page URL the backend generated actually redirect through a path containing
the literal substring `/kyc/digilocker-callback`?

**Likely cause:** `AadhaarDigilockerWebView`'s `NavigationDelegate.onNavigationRequest`
(`widgets/aadhaar_digilocker_webview.dart:47-52`) is the ONLY exit mechanism — it pattern-matches on that
path substring and pops `true` when found. There is **no manual "I've completed verification" fallback
button and no timeout** on this screen (doc comment, lines 14-16: "There is no manual fallback button;
consent-page variants that don't honor redirect_url will never resolve this screen."). If Cashfree/DigiLocker
ever changes their redirect URL shape, or the user's bank/DigiLocker account selection flow dead-ends on an
error page that doesn't redirect, this screen hangs indefinitely with only the system back button as an
escape (which returns `null`, not `true`, so `_onVerifyAadhaar()` correctly skips polling rather than
retrying — see `screens/kyc_screen.dart:234-237` — but the user is left back at the hub with Aadhaar still
unverified, no error shown).

**Secondary suspect:** Android WebView blocks third-party cookies by default; `_enableThirdPartyCookies()`
(lines 68-77) exists specifically because the digilocker.gov.in → Cashfree domain handoff needs cross-domain
cookies. If this silently fails on a given device/WebView version, the consent page can visibly stall after
account selection with no error message — check whether `_controller.platform is AndroidWebViewController`
actually resolves true on the affected device.

## 3. "PAN verification says success but the purchase/SIP/withdrawal is still blocked by KYC_REQUIRED"

**Check first:** Is Aadhaar also APPROVED? Per `RULE-KYC-001`, KYC completion requires BOTH PAN and Aadhaar —
a verified PAN alone will never satisfy `savings/check-eligibility` or the SIP `kycStatus` gate.

**Likely cause:** User completed the PAN card on the hub, saw its "Verified" banner, closed the app or
navigated away before also completing the Aadhaar card, then went straight to a purchase/SIP/withdrawal flow
expecting to be unblocked. `_checkAndHandleCompletion()` (`screens/kyc_screen.dart:267-299`) only runs the
success/profile-name sequence when BOTH are done — PAN-only completion never pops `true` from the KYC screen
and never triggers the `KycVerificationFlow.start()` caller's retry.

**Secondary suspect (SIP specifically):** SIP's proactive gate reads a CACHED `user.kycStatus`
(`sip/screens/auto_savings_screen.dart:1393-1400`) after a fresh `fetchProfileDetails()` call — if that
refresh call itself fails silently (network blip) the check could run against stale data. Confirm the
profile refresh actually completed before concluding this is a KYC-module bug rather than a Profile-module
staleness issue.

## 4. "The pan-verification screen shows 'Verification Sent' but nothing happened on the backend"

**Check first:** Which route did the user land on — `/pan-verification` or `/kyc` (`/kyc-dynamic`)?

**Likely cause:** `/pan-verification` → `PanVerificationScreen` (`screens/pan_verification_screen.dart`) is
an orphaned stub. `_handleVerify()` (lines 32-48) does client-side format validation only, then `await
Future.delayed(const Duration(seconds: 2))` — **there is no `KycRepository` call, no encryption, nothing
sent to the backend at all.** The success dialog is entirely fake. This route is not linked from anywhere in
the current app (grep-confirmed zero `Navigator...panVerification` call sites) — if a user reaches it, it's
via a deep link, push notification payload, or a leftover reference in an old app build. Redirect any such
entry point to `AppRouter.kyc` instead; do not attempt to "fix" this screen by wiring it up unless product
explicitly wants a PAN-only (no Aadhaar) verification path reinstated.

## 5. "KYC step stuck in 'pending' forever, never shows verified even after backend approval"

**Check first:** Confirm which screen is actually rendering — if it's the root `kyc_screen.dart` (not
`screens/kyc_screen.dart`), that's expected: it's hardcoded dead code that never calls any API and can never
show anything but `KycStatus.pending` for all 3 steps. It should not be reachable from `app_router.dart`
(`AppRouter.kyc`/`dynamicKyc` both resolve to `screens/kyc_screen.dart`) — if you find a call site that
somehow renders the root file, that's the actual bug (a rogue direct `MaterialPageRoute` push bypassing the
named-route table, per `AGENTS.md` §1's navigation rule).

**If it IS the live `screens/kyc_screen.dart`:** check whether `_checkAndHandleCompletion()` is even being
invoked — it only runs after a LIVE form submit or Aadhaar approval in the CURRENT session
(`screens/kyc_screen.dart:260-266` doc comment: "Only forms call this, so it can never fire from merely
viewing an already-verified screen"). Merely re-opening the hub screen relies on `_initControllers`/
`_seedAadhaarIfApproved` seeding from the fresh `kycDocumentsProvider` fetch instead — if that provider's
underlying `kyc/document-types` call is returning stale/cached `status`/`already_uploaded` values, the bug is
server-side response accuracy, not this screen's rendering logic.

## 6. "Sensitive KYC field appeared in plaintext in logs or network capture"

**Check first:** Is the field name spelled EXACTLY as listed in `AppConfig.sensitiveFields`
(`core/config/app_config.dart:74-95`)? Encryption is a literal key-name match in `encryptJson`
(`core/security/encryption_service.dart:109-126`) — a field the backend returns as `pan_no` or `panNumber`
instead of `pan_number`/`pan` would silently NOT be encrypted, with no error raised anywhere in this path.
Cross-check the actual field `name` the backend sends in `kyc/document-types`'s `fields[].name` for the PAN
document against the `sensitiveFields` list before assuming encryption "should have" applied.
