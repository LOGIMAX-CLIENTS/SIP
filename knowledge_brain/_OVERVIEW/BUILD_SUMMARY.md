---
last_updated: 2026-08-19
---

# Build Summary — startGOLD Mobile Brain

Meta-changelog of the brain itself: what was built each round, current coverage, and any confirmed
inaccuracies found in hand-written docs (`STARTGOLD_DOCUMENTATION.md`, `about startGOLD.md`,
`.agents/AGENTS.md`) by cross-checking against live code.

## Round 0 — Scaffold (2026-08-19)

Ported the `.agents/` + `knowledge_brain/` pattern from the sibling `fintect_application` (Django fintech
backend) repo, adapted for a Flutter/Riverpod mobile app. Built:
- `.agents/`: `AGENTS.md` (master rules), `config.md` (path vars + 24-entry module registry —
  23 feature folders + `core/`), `skills/flutter_fintech_mobile/SKILL.md`, 12 workflow docs + index.
- `CLAUDE.md` at project root (always-loaded short pointer).
- `knowledge_brain/_OVERVIEW/SYSTEM_ARCHITECTURE.md` — derived from `STARTGOLD_DOCUMENTATION.md`,
  `pubspec.yaml`, and a folder scan. Not yet independently verified line-by-line against source — that
  verification happens per-module in Round 1.
- Per-module brain content: not yet built (all 24 entries ⬜ at end of Round 0).

## Round 1 — Module Brains (in progress)

Target: full 8-document brain for all 23 feature modules + `Core`, built by reading actual `.dart` source
per module. Coverage table below updates as each module completes.

### Core — built 2026-08-19

Read all 47 `.dart` files under `lib/core/` in full (no sampling). Produced the largest single brain
(`METHOD_INDEX.md` alone covers every public class/method across all 47 files plus a 30-provider index).
Confirmed the encryption/session/interceptor architecture claimed in `SYSTEM_ARCHITECTURE.md`, but found
it materially incomplete on two points:

1. **`EncryptionService.decrypt()` is a literal no-op passthrough** — it returns the input unchanged, yet
   `ApiSecurityInterceptor` logs `"Response decrypted (AES-256)"` on every response regardless. Nothing is
   actually decrypted client-side today. **Highest-severity finding across the whole brain build** — see
   `_SYSTEM/DANGER_ZONES.md` once synthesized.
2. **Encryption fails open**: if the RSA public key isn't ready when a sensitive request fires, the
   interceptor logs an error but still sends the request with that field in plaintext rather than blocking
   it.

Also resolved the Round-0 `ldui_parser.dart` gap: it's a fully-implemented JSON→Widget renderer with **zero
call sites anywhere in `lib/`** — dead code; the countdown-offer bottom sheet it was written for renders
hardcoded widgets instead. Two more dead-code items found: `network/interceptors.dart`'s `AuthInterceptor`
is never registered on any Dio instance, and `services/device_service.dart` duplicates `DeviceIdService`
with no callers. Four reverse-dependency layering violations found (`core/providers/*` importing
`features/auth`, `features/home`, `features/market` internals). Coverage: 99.4% (weighted) — see
`Core/COVERAGE_TRACKER.md`. Badge: 🟢 (config.md's legend reserves 🔵 for literal 100% + spot-check; the
agent that built this flagged the badge-threshold mismatch between `config.md`'s stated legend and its own
≥95%-based tracker — worth reconciling explicitly, see "Open Items" below).

### Auth — built 2026-08-19

Read all 8 `.dart` files under `lib/features/auth/` in full, plus 15 core dependency files. Confirmed most
of `STARTGOLD_DOCUMENTATION.md` §3.3–3.7's claims but found real drift: the country-codes endpoint is
`POST users/shared/country-codes`, not `GET shared/country-codes`; registration email verification is
**mandatory** (undocumented, gates the Confirm button) and is actually two API calls
(`register-check` then `register`), not the doc's single call.

**Security-relevant finding**: `users/auth/register-check` is absent from `AppConfig.encryptedEndpoints`
(unlike its sibling `register`), so it's sent unencrypted. Also found a PIN-length inconsistency between
two different PIN screens — `MpinNotifier.pinLength = 6` (matches MPIN module's finding) but the separate
`/pin-entry` route's `PinScreen` hardcodes 4 digits, suggesting `/pin-entry` may be dead code (unconfirmed).
Screenshot/recording block is wired only on the OTP screen, not login/registration/PIN-creation, despite
`AGENTS.md` describing broader coverage — flagged for `AGENTS.md` §3 correction. Coverage: 100% weighted —
see `Auth/COVERAGE_TRACKER.md`. Badge: 🟢 (pending a Round-2 spot-check before promotion to 🔵).

### MPIN — built 2026-08-19

Read both module files plus 9 direct dependencies in full. **Confirms Auth's finding**: MPIN is 6-digit
everywhere in this module too (`core/services/mpin_service.dart:151`), contradicting
`STARTGOLD_DOCUMENTATION.md` §3.8–3.9's "4-digit" claim. The doc's "4 modes" claim is also wrong — code
branches on 8 distinct `type` values (adds `verify_only`, `withdrawal_pin`, `authorize_withdrawal`,
`verify_after_reset`); `authorize_withdrawal` has no call site anywhere in `lib/` outside this screen
itself (dead code). API paths have no `users/` prefix (`mpin/validate` not `users/mpin/validate`).

**Possible real bug**: `settings_screen.dart:47-51` navigates to `/mpin` with no `type` argument at all,
but its own comment implies dual setup/unlock behavior that the actual `mpin_screen.dart` code doesn't
support without a `type` — could mean toggling MPIN on from Settings (when none exists yet) hits the wrong
mode. Flagged unconfirmed, needs a live trace. Also: `change_mpin_screen.dart` has no screenshot-block call
unlike `mpin_screen.dart` (inconsistent coverage), and `MpinService.hasMpinSet()` has zero callers anywhere.
Coverage: 93% — see `MPIN/COVERAGE_TRACKER.md`. Badge: 🟢.

### InstantSaving — built 2026-08-19

Read all 10 `.dart` files under `lib/features/instant_saving/` (full or near-full) plus ~14 cross-module
files. **Confirmed 3 live payment gateways**, selected server-side per order via the `payment_gateway`
field in the `savings/initiate` response — Cashfree (Web Checkout), HDFC SmartGateway (Juspay HyperSDK),
Razorpay — routed through `PaymentHandler`/`HdfcPaymentHandler`/`RazorpayPaymentHandler`, not the screen
`STARTGOLD_DOCUMENTATION.md` §3.12 names as live.

**Key finding**: `payment_methods_screen.dart` (the screen §3.12 describes) is explicitly marked `[LEGACY]`
in its own header and is dead code — unreachable via any live navigation, only commented-out call sites
remain. Denomination/config endpoints are all POST (doc says GET) and live at
`users/shared/amount-denominations`/`weight-denominations`, not `savings/denominations/*`. "GST +3%" is a
live server-driven `gst` field from `savings/config`; `3.0` only appears as a pre-load UI fallback — exact
live value unconfirmed from client code alone.

**Two correctness-relevant findings**: (1) rate can silently re-lock during a KYC detour mid-purchase with
no re-confirmation shown to the user (`payment_handler.dart:144-151`); (2) a weight-precision mismatch
between the UI's 6-decimal floor-truncated display and the payload's independently-recomputed 4-decimal
rounded value. Coverage: ~97% — see `InstantSaving/COVERAGE_TRACKER.md`. Badge: 🟢.

### Invoice — built 2026-08-19

No prior hand-written doc coverage — primary documentation. Read both feature files plus both call sites
(`history/screens/transaction_details_screen.dart`, `sip/screens/sip_transaction_details_screen.dart`).
It's a pure download-cache-render utility (`InvoiceService.downloadInvoice()` → `/invoice-viewer` →
`SfPdfViewer.file()`), not a screen users navigate to directly. **Finding**: it instantiates a raw `Dio()`
instead of the shared `ApiClient`, bypassing certificate pinning (RULE-INVOICE-004). `clearCache()` is dead
code. `sip` imports `history`'s `TransactionDetailResponse` model directly — a cross-feature layering
exception, consistent with the same pattern History's own brain documents. Coverage: 100% weighted — see
`Invoice/COVERAGE_TRACKER.md`. Badge: 🟢.

### Jewellery — built 2026-08-19

No prior hand-written doc coverage — primary documentation, and this resolves a real open question about
what the feature even is. **Conclusion**: `jewellery` is a **"Coming Soon" marketing placeholder**, not a
purchase catalog and not a gold-to-jewellery redemption feature. `JewelleryService.getJewelleryImages()`
returns only `{success, data: [{image_url}]}` — no price/SKU/weight/redemption fields anywhere in the
contract; the screen's own doc comment says "Coming Soon"; image cards have zero tap handlers;
`assets/jewellery/` contains only a `.gitkeep`. A repo-wide grep for `jewellery`/`redeem` inside `home` and
`portfolio_provider.dart` found zero wiring to convert digital holdings into physical jewellery. Despite
this, it has a prominent bottom-nav placement (see Main's finding below). Housekeeping note: a stray
`lib/features/jewellery.zip` (3.4KB) sits next to the folder — likely a leftover backup, not touched.
Coverage: 100% weighted — see `Jewellery/COVERAGE_TRACKER.md`. Badge: 🟢.

### Home — built 2026-08-19

Read all 9 `.dart` files under `lib/features/home/` (screen + 2 models + 6 widgets) plus 11
cross-referenced `core/` and sibling-feature files to trace every Riverpod provider Home consumes
(`timer_provider.dart`, `market_provider.dart`, `home_dashboard_provider.dart`,
`portfolio_provider.dart`, `commodity_provider.dart`, `countdown_offer_provider.dart`,
`user_provider.dart`, `home_service.dart`, `portfolio_service.dart`, `notification_service.dart`,
`native_socket_service.dart`). Confirmed the hand-written doc's "sell rate lock timer" and
"race-condition guard" claims against live code (`home_screen.dart:97-125`) — both real, traced
line-by-line in `Home/DATA_FLOW.md`. Found 3 layering violations: `home_screen.dart` imports
`instant_saving/controller/saving_controller.dart`, `profile/profile_controller.dart`, and
`main/main_screen.dart` directly (sibling-feature internals, against `AGENTS.md` §1). Coverage:
≈90% (weighted) — see `Home/COVERAGE_TRACKER.md`. Badge: 🟢 (not 🔵 — a few cross-referenced files
were read via grep rather than in full, see tracker's "Open Items").

### DailySavings — built 2026-08-19

Module is a single file (`lib/features/daily_savings/daily_savings_screen.dart`), no controller/
service/model layer. Read in full, plus repo-wide grep confirming the `/daily-savings` route is
never navigated to from any in-app UI (registered in `app_router.dart` but orphaned). Also read
`sip/screens/auto_savings_screen.dart` (first ~620 lines) and `sip/services/sip_service.dart`
(first 80 lines) to establish the daily_savings-vs-sip relationship — **finding: SIP's
`AutoSavingsScreen` already implements a real, backend-integrated "Daily" recurring-purchase
frequency (`frequencyId: 1`, `sip_service.dart:59`) with denominations, duplicate-plan guard,
market-closed guard, and payment hand-off. `daily_savings_screen.dart` is a disconnected UI
prototype for the same concept — its "Proceed to Payment" CTA is a literal no-op
(`onPressed: () {}`, `:90`) and has no API/controller/model wiring at all.** Full detail in
`knowledge_brain/DailySavings/CROSS_MODULE_MAP.md` §0. Coverage: 100% (weighted, per the small
surface actually present) — see `DailySavings/COVERAGE_TRACKER.md`. Badge: 🔵.

### Withdrawal — built 2026-08-19

Read all 9 `.dart` files under `lib/features/withdrawal/` (3 models, 1 provider, 4 screens, 1 service) in
full, plus ~16 cross-referenced files (`core/security/api_interceptor.dart`,
`core/security/encryption_service.dart`, `core/config/app_config.dart` — to verify the actual
`sensitiveFields`/`encryptedEndpoints` lists rather than trust the hand-written doc's claim,
`core/constants/app_constants.dart`, `core/providers/timer_provider.dart`, `core/providers/market_provider.dart`,
`mpin/mpin_screen.dart`, `kyc/kyc_flow.dart`, `sip/screens/bank_account_picker_screen.dart`,
`profile/services/bank_details_service.dart`, `shared/widgets/add_bank_account_sheet.dart`,
`instant_saving/instant_saving_screen.dart`). Confirmed the hand-written doc's rate-lock, market-closed-guard,
and MPIN-verification claims. Found significant drift on endpoint names and encrypted-field names (doc names
don't match any real payload key in this module), and a structural finding: the live withdrawal flow uses
`BankAccountPickerScreen` (a `sip`-module widget) for payout selection, NOT the `UpiSelectionScreen` that
physically lives in `withdrawal/screens/` and is documented in §3.17 — that screen is only reachable from
Instant Saving's purchase flow and appears to mis-navigate back into Withdrawal Confirmation regardless of
caller context (flagged as unconfirmed pending a live-device trace). Full drift table in
`knowledge_brain/Withdrawal/MODULE_BRAIN.md` §Drift. Coverage: 98.5% (weighted) — see
`Withdrawal/COVERAGE_TRACKER.md`. Badge: 🔵 (all 9 files read in full, not sampled).

### Profile — built 2026-08-19

Read all 17 `.dart` files under `lib/features/profile/` (models, screens, services, widgets) in full, plus
4 cross-referenced files in full (`shared/widgets/add_bank_account_sheet.dart`,
`withdrawal/services/withdrawal_service.dart`, `core/providers/user_provider.dart`,
`core/security/api_interceptor.dart` + `core/config/app_config.dart`) and `lib/routes/app_router.dart`,
`core/security/screenshot_security_service.dart`, `core/security/secure_storage_service.dart` (targeted
sections). Confirmed the hand-written doc's Profile/Account Details/Delete Account claims are accurate as
far as they go but cover only 3 of 9 live screens — the entire Bank Account Verification surface (Bank
Details, Bank Verification Hub, BAV History, ₹1 Payment History, Refund History, ₹1 payment screen) is
undocumented there, first documented in this round. Traced the real BAV mechanism: a Cashfree/Razorpay
bank-account-registration call ("verify-bank", legacy `id_payout` response key) followed by a genuine ₹1
debit (not a classic penny-drop) confirmed server-authoritatively, with a separate later refund tracked on
the same backend row. **Found a likely live bug**: the bank-account-creation endpoint path
(`withdrawal_service.dart:106`, `'account\verify-bank'`) is a non-raw Dart string where `\v` is
interpreted as a vertical-tab escape, corrupting the runtime path and also preventing the
`encryptedEndpoints` substring match that would otherwise RSA-encrypt `account_no`/`ifsc_code` — flagged
as RULE-PROFILE-010, unconfirmed at runtime, needs a live capture to close out. Also found 2 cross-feature
internals-import violations (SIP's `BankAccountPickerScreen` importing Profile's provider/model directly;
`kyc/kyc_flow.dart` importing Profile's controller directly). Coverage: 100% (weighted) — see
`Profile/COVERAGE_TRACKER.md`. Badge: 🔵 (all 17 in-module files read in full, plus a manual 3-claim
spot-check against source).

### KYC — built 2026-08-19

Read all 10 `.dart` files under `lib/features/kyc/` in full, plus ~18 cross-referenced files
(`app_router.dart`, `core/utils/kyc_validator.dart`, `core/error/failures.dart`,
`core/security/api_interceptor.dart`, `core/security/encryption_service.dart`, `core/config/app_config.dart`,
and the KYC-gating call sites in `instant_saving_screen.dart`, `saving_service.dart`, `saving_models.dart`,
`withdrawal_screen.dart`, `withdrawal_service.dart`, `sip/screens/auto_savings_screen.dart`,
`profile_controller.dart`, `profile_screen.dart`). **Key findings**: (1) the module contains two parallel KYC
UIs — a live, API-backed unified PAN+Aadhaar hub (`screens/kyc_screen.dart`, routed at both `/kyc` and
`/kyc-dynamic`) and a dead, hardcoded 3-step (PAN/Aadhaar/Bank) screen at the folder root
(`kyc_screen.dart` + `providers/kyc_provider.dart` + `models/kyc_step.dart`) that is never reached from
`app_router.dart`; (2) `controllers/kyc_controller.dart` and `providers/kyc_provider.dart` have their
expected contents inverted — the "controller" file holds the live Riverpod providers, the "providers" file
holds the legacy StateNotifier controller; (3) `/pan-verification` is a registered, reachable route to a
non-functional stub screen (`Future.delayed` fake success, no API call, no encryption); (4) `kyc/upload`
payloads pass through `EncryptionService.encryptJson()` twice (once in `KycRepository`, once again via
`ApiSecurityInterceptor` since the endpoint is also listed in `AppConfig.encryptedEndpoints`) — traced as
likely-harmless (a caught, logged exception on the redundant pass) but not runtime-confirmed; (5)
`core/utils/kyc_validator.dart` is dead code, zero importers; (6) confirmed the cross-module eligibility gate
used by InstantSaving/Withdrawal (`savings/check-eligibility` → `next_step: KYC_REQUIRED`) and SIP (same
signal plus a proactive `user.kycStatus == 1` client-side check) — all three route through the single
`KycVerificationFlow.start()` entry point in `kyc_flow.dart`. Full detail in `knowledge_brain/KYC/MODULE_BRAIN.md`
and `knowledge_brain/KYC/COVERAGE_TRACKER.md`. Coverage: ~97% (weighted). Badge: 🟢 (two backend-contract
details — PAN's real `id_document` value, and whether `submit-kyc`/`update-kyc` are truly dead endpoints —
remain unconfirmed against the live server).

### Notifications — built 2026-08-19

Read the module's single screen file (`lib/features/notifications/notifications_screen.dart`) plus
the two core-layer files that actually own the model/state/service (`core/services/notification_service.dart`)
and push transport (`core/services/fcm_service.dart`) in full, plus cross-referenced
`home/home_screen.dart` (badge consumer), `mpin/mpin_screen.dart` and `auth/pin/pin_creation_screen.dart`
(FCM token registration triggers), `core/config/app_config.dart` (confirmed no notifications endpoint
is in `encryptedEndpoints`), `core/security/secure_storage_service.dart` (FCM token key). Confirmed
the hand-written doc's 5-endpoint table is accurate but incomplete — it omits
`users/notifications/register-token` and the entire FCM push-delivery mechanism (foreground manual
display, background/terminated tap → trigger-only navigation). Key architectural finding: unlike
every other module built so far, this module's ENTIRE state/model/service layer lives in `core/`
rather than under `features/notifications/` — a deliberate exception (not a violation) so `Home` can
depend on the badge count without reaching into a feature folder; documented as the accepted pattern
in `Notifications/CROSS_MODULE_MAP.md`. Also found unread-count has two independent write paths
(client-list-derived vs. server-authoritative `fetchUnreadCount`) that can disagree — RULE-NOTIFICATIONS-003.
Coverage: 100% (weighted) — see `Notifications/COVERAGE_TRACKER.md`. Badge: 🟢 96% (native
platform FCM wiring — AndroidManifest/build.gradle/google-services.json — not independently verified,
Dart-side only).

### Nominee — built 2026-08-19

Read all 4 `.dart` files under `lib/features/nominee/` (controller, model, screen, service) in full,
plus cross-referenced `core/config/app_config.dart` and `core/security/api_interceptor.dart` (to
verify the real encrypted-field mechanics rather than trust the hand-written doc's one-line
"Encrypted" claim), `app_router.dart`, and `profile/profile_screen.dart` (entry point) plus a targeted
read of the cross-imported `checkPincode` call site. Confirmed the hand-written doc's route and
"`users/nominee/update` — Encrypted" claim are both correct, but incomplete/imprecise: the doc omits
`users/nominee/details` (fetch) and `users/nominee/relationships` (dynamic list with hardcoded
fallback), and "Encrypted" actually means only the `mobile` field within the payload gets RSA-OAEP
transformed — `id_number` (which can hold an Aadhaar/PAN/Passport number depending on the selected ID
type) ships in **plaintext**, since it doesn't match any key in `AppConfig.sensitiveFields`
(RULE-NOMINEE-003 — a genuine PII-exposure gap, not just a doc-drift note). Also found: (1) a direct
`features/nominee` → `features/profile` cross-import (`nominee_screen.dart:16`,
`profile_controller.dart`) for pincode lookup — an `AGENTS.md` §1 architecture violation; (2) the
form has no UI to actually set the ID-proof type/number even though the model/submit payload carry
them (`_buildDropdownField` is dead code, `RULE-NOMINEE-006`). Coverage: 100% (weighted) — see
`Nominee/COVERAGE_TRACKER.md`. Badge: 🟢 96% (a few unused/possibly-planned symbols —
`hasNomineeProvider`, `NomineeDetails.copyWith` — have no confirmed caller in the files read).

### SIP — built 2026-08-19

Read all 18 `.dart` files under `lib/features/sip/` (2 controllers/providers file, 3 model files,
11 screens, 2 services, 1 widget) — 11 read in full line-by-line (`auto_savings_screen.dart` in
full despite 2367 lines: creation flow, both regular and Custom SIP, KYC gate, payment-method
selection, weekly/monthly/custom date pickers), the remaining 4 large history/overview/detail/
filter screens read to partial depth plus full structural grep (every method/API-call/navigation
site enumerated — see `SIP/COVERAGE_TRACKER.md` "Open Items"). Also read the `DailySavings` brain
(already built) for the daily_savings-vs-sip relationship rather than re-deriving it, and 6
cross-referenced `core/` files (`app_config.dart`, `encryption_service.dart`,
`api_interceptor.dart`, `market_provider.dart`, `failures.dart`) plus 3 files each from `kyc`,
`profile`, `instant_saving`, `history` for cross-module verification.

**Key findings**:
1. Two distinct backend products share one creation UI: regular SIP (`SIPScheme`, Daily/Weekly/
   Monthly, one active plan per frequency+commodity) and Custom SIP (`CustomSIPScheme`, arbitrary
   day-of-month set, uniqueness per date not per frequency). Both funnel through the same
   `SipCreateResponse` shape and the same `SipPaymentScreen` gateway launcher.
2. **Confirmed cancellation lock-in**: SIP cannot be cancelled within 24h of creation. Server
   computes `cancel_eligible_at`/`can_cancel_now`, client only displays it
   (`sip_cancel_screen.dart:55-58`). `STARTGOLD_DOCUMENTATION.md` §3.21-3.26 doesn't mention this
   at all — drift, logged below.
3. **New security-gap finding**: `AppConfig.encryptedEndpoints` covers `sip/create`/`sip/cancel`/
   `sip/pause` but **not** `sip/resume` or any `sip/custom/*` endpoint — confirmed by the
   interceptor's substring-match logic never matching `'sip/custom/create'` against `'sip/create'`.
   Custom SIP's `amount` and eMandate bank fields (both in `AppConfig.sensitiveFields`) are sent
   without RSA-OAEP field-level encryption, unlike regular SIP. Flagged as
   `SIP/BUSINESS_RULES.md` RULE-SIP-011 — unconfirmed whether intentional; candidate for
   `_SYSTEM/DANGER_ZONES.md`.
4. Two payment gateways are genuinely both live (Cashfree Subscription Checkout, Razorpay
   AutoPay in two sub-modes) — selected per-request by the backend, not a fixed client choice.
5. No client-side per-installment trigger exists anywhere — once a mandate is `ACTIVE`, recurring
   debits are entirely gateway/server-side; the app is registration + monitoring only.

Coverage: 95% (weighted) — see `SIP/COVERAGE_TRACKER.md`. Badge: 🟢 (not 🔵 — no distinct
spot-check pass performed; 3 files recommended for a Round 2 spot-check are listed in the
tracker).

### Support — built 2026-08-19

Read all 4 `.dart` files under `lib/features/support/` (`enquiry_service.dart`, `support_screen.dart`,
`screens/enquiry_form_screen.dart`, `screens/enquiry_list_screen.dart`) in full, plus cross-referenced
`app_router.dart` (route registration + exhaustive project-wide grep for every `AppRouter.support`/
`.enquiryForm`/`.enquiryList` call site) and `core/config/app_config.dart` (`encryptedEndpoints`, confirmed
`support/*` is absent — no field-level encryption applies). **Key findings**: (1) `/support`
(`SupportScreen`) is a registered but completely unreachable route — zero in-app navigation call sites
found; its "Live Chat"/"Call Support" tiles have no `onTap` even if reached; (2) confirmed bug —
`EnquiryFormScreen`'s default ticket type `'General'` is not a member of the `kTicketTypes` enum map used
by the chip picker, so no chip shows selected by default and an un-tapped submit silently files as type 1
("Enquiry") — this also causes `sip/screens/manage_custom_savings_screen.dart`'s `initial_type: 'Custom
SIP'` navigation argument to be silently dropped (only `manage_savings_screen.dart`'s `'Auto Savings'`
matches an actual key); (3) `SupportTicket` model class is dead code, never instantiated anywhere in
`lib/`. Coverage: 100% (weighted) — see `Support/COVERAGE_TRACKER.md`. Badge: 🔵 (all 4 files read in
full, plus a manual 3-file spot-check against source).

### Content — built 2026-08-19

Read all 3 screen files under `lib/features/content/screens/` (`content_screen.dart`, `faq_screen.dart`,
`contact_us_screen.dart`) plus `core/services/content_service.dart` (this module's entire data layer,
shared with `onboarding`) in full. Cross-referenced `app_router.dart` (all 6 route registrations +
exhaustive project-wide grep for every inbound call site), `pubspec.yaml` and a project-wide grep for
`WebView`/`webview_flutter` usage. **Key findings**: (1) confirmed all content (terms/privacy/about/
refund/FAQ/contact) is **server-fetched via `ApiClient.post`, never bundled** — no local asset/JSON
fallback exists anywhere in `content_service.dart`, answering the open question left unstated by
`STARTGOLD_DOCUMENTATION.md` §3.40; (2) confirmed rendering uses `flutter_widget_from_html_core`'s
`HtmlWidget`, **not** `webview_flutter` — the latter is a pubspec dependency but used only by `kyc`'s
DigiLocker webview and `home`'s promotional-offer webview (0 hits inside `features/content/`); (3) `/about`
(`ContentScreen` w/ `aboutUsProvider`) is, like Support's `/support`, a registered but completely
unreachable route; (4) the Lora-numeric-font-injection logic is duplicated near-identically between
`ContentScreen` and `FaqScreen` with a one-character regex drift between them; (5) `FaqScreen` force-
invalidates its provider on every screen entry (bypassing normal caching) while the other content screens
don't — undocumented as an intentional choice. Coverage: 100% (weighted) — see `Content/COVERAGE_TRACKER.md`.
Badge: 🔵 (all files read in full, plus a manual 3-file spot-check against source).

### Market — built 2026-08-19

`lib/features/market/` itself is a single model file (`market_rates.dart`) — the real live-rate
architecture lives entirely in `core/` (`native_socket_service.dart`, `market_provider.dart`,
`commodity_provider.dart`, `timer_provider.dart`, `environment_service.dart`), so this brain
documents that core architecture in full and cross-references from the consumer modules. Read all
files in full: `market_rates.dart`, `native_socket_service.dart`, `market_provider.dart`,
`commodity_provider.dart`, `timer_provider.dart`, `environment_service.dart`; targeted reads of
`app_lifecycle_observer.dart` and `shared_service.dart` (`Commodity` model + `commoditiesProvider`);
grepped-with-context all 6 consumer screens (`home_screen.dart`, `instant_saving_screen.dart`,
`payment_methods_screen.dart`, `withdrawal_screen.dart`, `withdrawal_confirmation_screen.dart`,
`auto_savings_screen.dart`).

**Key finding — the WebSocket protocol in `STARTGOLD_DOCUMENTATION.md` §4 is substantially
wrong**, not just imprecise: the doc claims Socket.IO transport, endpoint
`ws://bullion_v4.logimaxindia.com/ratesocket/socket.io/`, event name `market_rates`, and a
combined rate-frame format `3|goldBuy|goldSell|silverBuy|silverSell|...`. Live code uses a raw
`web_socket_channel` connection (no Socket.IO framing at all) to `wss://startgoldapp.
logimaxindia.com/ws/` (staging) / `wss://sgbackoffice.startgold.com/ws/` (production), and the
real rate-frame format is one line **per commodity**, ID-keyed:
`3|<commodity_id>|<unused>|<buy>|<sell>|...`. Reconnection is a flat 5-second retry, not
"exponential backoff" as claimed. Full drift table in `Market/COVERAGE_TRACKER.md`. Also found: a
1-second grace-period heuristic that infers "market closed" from silence + zero rates (undocumented
anywhere), and `MarketRates.fromJson`/`MarketRates.initial()` are both dead code (no call sites).
Coverage: 100% (weighted) — see `Market/COVERAGE_TRACKER.md`. Badge: 🔵 (all core-owned files read
in full).

### History — built 2026-08-19

Read all 8 `.dart` files under `lib/features/history/` (controller, 3 models, service, 3 screens)
in full, plus targeted cross-reads of the `sip` module's transaction-history equivalent
(`sip_transaction_history_screen.dart` imports, `sip_controller.dart`'s `SipHistoryNotifier`,
`sip_service.dart`'s `getSipTransactions`) to confirm the cross-module model-reuse relationship,
and `app_router.dart`/`main_screen.dart` for route/tab-shell integration. No factual drift found
against `STARTGOLD_DOCUMENTATION.md` §3.27-3.28 — its claims are all accurate, just far less
detailed than the real implementation (server-side pagination + lazy-load-on-scroll, a fully
backend-driven filter-option system, manual-refresh-only tab behavior, and the SIP/general split
are all undocumented there). **Key finding**: SIP has its own separate transaction-history screen,
controller, and endpoint (`POST sip/transactions`) but explicitly imports and reuses this module's
`TransactionItem`/`HistoryResponse`/`FilterOption` models (confirmed via `sip_service.dart`'s own
doc comment: "Reuses the same HistoryResponse model from the history module") — a narrow,
intentional, one-directional exception to `AGENTS.md` §1's feature-isolation rule. Also flagged:
`TransactionItem.soType` is parsed but consumed nowhere in the UI (unconfirmed purpose). Coverage:
100% (weighted) — see `History/COVERAGE_TRACKER.md`. Badge: 🔵 (all 8 files read in full).

### Splash, Onboarding, Maintenance, Main — built 2026-08-19

Four modules flagged "low complexity" in `_OVERVIEW/LOW_COMPLEXITY_MODULES.md` — each is a
single-file screen with no `controller/`/`services/`/`models/` subfolder. Built together since
they form one connected app-init/navigation story (splash gates → onboarding/login/mpin/
maintenance → main tab shell). Read all 4 module-owned screen files in full
(`splash_screen.dart` 298 lines, `onboarding_screen.dart` 256 lines, `maintenance_screen.dart`
253 lines, `main_screen.dart` 272 lines), plus 13 cross-referenced `core/`/`shared/`/`routes/`
files in full to verify every routing/polling/provider claim rather than trust
`STARTGOLD_DOCUMENTATION.md` §3.1/3.2/3.41/3.42: `core/security/session_manager.dart`,
`core/security/secure_storage_service.dart`, `core/services/app_control_service.dart`,
`core/models/app_control_model.dart`, `core/providers/app_control_provider.dart`,
`core/services/content_service.dart`, `shared/widgets/app_update_dialog.dart`,
`shared/widgets/maintenance_gate.dart`, `shared/widgets/app_control_wrapper.dart`,
`shared/widgets/custom_button.dart` and `animations.dart` (targeted), `main.dart` (entry route +
`AppControlWrapper` wiring), and `routes/app_router.dart` (full route table for these 4 modules).

**Key findings**:
1. **Onboarding is an orphaned route**, same class of finding as `daily_savings`. A repo-wide
   grep for every `Navigator.push*Named(..., AppRouter.onboarding, ...)` call site returns zero
   results — `splash_screen.dart` never calls `SessionManager.hasSeenOnboarding()` and no other
   file navigates there. The screen itself is fully functional if reached; it's simply never
   invoked. See `Onboarding/MODULE_BRAIN.md` §0.
2. **No skip button exists in Onboarding**, contradicting both `STARTGOLD_DOCUMENTATION.md` §3.2
   ("skip button") and the general onboarding-carousel convention — confirmed via full read plus
   a case-insensitive grep for "skip" (zero matches). The only interactive element pages forward
   one slide at a time.
3. **`Main`'s tab list has drifted significantly from `STARTGOLD_DOCUMENTATION.md` §3.42.** Doc
   claims "Home, Invest, Market, Profile" (4 tabs). Live code has 5 nav items — Home, Invest,
   **History** (not Market — market data lives inside `HomeScreen`), Profile, and **Jewellery** —
   and Jewellery is architecturally a pushed route (`Navigator.pushNamed('/jewellery')`), not an
   `IndexedStack` member like the other four. See `Main/MODULE_BRAIN.md` §0.
4. **Maintenance auto-resume is confirmed pure-polling, no manual retry control** — a 30s
   screen-local timer (`AppControlNotifier.startMaintenancePolling()`) plus a pre-existing 60s
   app-wide timer (from `AppControlWrapper`, which wraps the whole `MaterialApp`) both drive the
   same `appControlProvider` state; the screen's `build()` watches it and auto-navigates once
   `isMaintenance` flips false. The visible "Checking status automatically…" row has no `onTap`.
5. **`resumeRoute` is inconsistent across the 3 call sites that push `/maintenance`.**
   `splash_screen.dart` preserves the session-aware login/mpin decision, but both
   `shared/widgets/maintenance_gate.dart` and `shared/widgets/app_control_wrapper.dart` (the
   mid-session global redirect) hardcode `resumeRoute: AppRouter.login` — a logged-in user
   interrupted by maintenance mid-session resumes at `/login`, not back in the app, despite a
   still-valid session token. Unconfirmed whether intentional. See
   `Maintenance/BUSINESS_RULES.md` RULE-MAINTENANCE-005.
6. **`MaintenanceGate.check()` — the pre-transaction maintenance gate `AGENTS.md` §2 describes for
   payment/withdrawal/SIP — has zero call sites anywhere in `lib/`** besides its own definition.
   Fully implemented, never invoked. Candidate for `_SYSTEM/DANGER_ZONES.md`.
7. Splash's update dialog hardcodes `forceUpdate: true` regardless of the server's actual
   `AppVersionInfo.forceUpdate`/`minVersion` distinction — every detected update is a hard block
   on splash, even though the model/logic to do soft-vs-hard correctly already exists in
   `core/providers/app_control_provider.dart` for other consumers. See
   `Splash/BUSINESS_RULES.md` RULE-SPLASH-007.
8. `AppRouter.home` and `AppRouter.main` are two separate route constants that both resolve to
   the same `MainScreen()` widget — not a bug, but worth knowing before repointing either one.

Coverage: Splash 100% 🔵, Onboarding 100% 🔵, Maintenance 100% 🔵, Main 93% 🟢 (Main's
cross-module provider internals — `homeDashboardProvider`, `portfolioProvider`, etc. — were
identified and cited by file:line but their own implementations are each owning module's brain
to verify, not re-read line-by-line here). See each module's own `COVERAGE_TRACKER.md`.

### Referral — built 2026-08-19

Read all 4 `.dart` files under `lib/features/referral/` (`referral_screen.dart`, `referral_service.dart`,
`referee_list_screen.dart`, `referee_list_service.dart`) in full — no `controller/`/`models/`/`services/`
subfolder split exists, model + service classes live inline. Also read the full signup-time half of the
referral loop, owned by `auth`: `features/auth/registration/registration_screen.dart`,
`features/auth/pin/pin_creation_screen.dart`, `core/services/auth_service.dart` (`register`/`registerCheck`),
plus `core/config/app_config.dart` (`encryptedEndpoints`/`sensitiveFields`) and
`core/security/api_interceptor.dart` to confirm how the registration payload (carrying `referral_code`) gets
transport-encrypted, and grepped `home_screen.dart`/`profile_screen.dart` for the module's two UI entry
points. **Key findings**: (1) both `ReferralService.fetchReferralData()` and `RefereeListService.fetchList()`
catch every exception internally and return an empty-shaped model rather than propagating a `Failure` — a
network error renders identically to a legitimate "0 referrals" state, and makes `RefereeListScreen`'s
otherwise-real error/retry UI effectively dead code in practice (`RULE-REFERRAL-006`); (2) all reward
calculation/disbursement is server-side — this module performs zero client-side reward math, just string
passthrough/formatting; (3) the referral-code entry point lives entirely in `auth`/registration, not in this
module, and no shared provider/model connects the two — traced end-to-end in `CROSS_MODULE_MAP.md`;
(4) `ReferralData.shareLink` and `RefereeItem.statusCode` are both parsed from the API response but never
read anywhere in the UI — dead fields client-side. Coverage: 99% (weighted) — see
`Referral/COVERAGE_TRACKER.md`. Badge: 🟢 (one sub-claim about `register-check`'s encryption-endpoint match
left explicitly unconfirmed).

### Settings — built 2026-08-19

Read the module's single file (`lib/features/settings/settings_screen.dart`, 267 lines) in full, plus full
reads of every core dependency named in the task brief: `core/localization/language_cache.dart`,
`core/localization/language_provider.dart`, `core/localization/language_service.dart`,
`core/services/biometric_service.dart` (read specifically to confirm it is **not** actually used by this
module), `core/security/secure_storage_service.dart`, `lib/main.dart` (MaterialApp/locale/theme config), and
`shared/theme/app_theme.dart` (confirmed `darkTheme` getter exists but is unwired). Cross-referenced
`features/profile/profile_screen.dart`'s "Account" section and `lib/routes/app_router.dart` (full-tree grep
for reachability). **Key findings, all significant**: (1) `/settings` is a registered route with **no
discovered in-app navigation call site anywhere** — the biometric toggle, MPIN-change, logout, and
delete-account UI a user actually reaches lives in `features/profile/profile_screen.dart`'s "Account" section
instead (`RULE-SETTINGS-007`); (2) contrary to `config.md`'s module-registry description, **biometric toggle
is not part of this module at all** — `settings_screen.dart` never imports `BiometricService`
(`RULE-SETTINGS-008`); (3) language switching only ever changes the stored locale code and Flutter's
built-in Material/Cupertino widget locale — the app's own custom UI copy is never translated, because
`LanguageState.translations` is permanently `{}` and `LanguageService.fetchMegaTranslations()`'s entire body
is commented out with an explicit "English by default for now" comment (`RULE-SETTINGS-004`); (4) the Tamil
and Telugu labels in the language picker (`'????? (Tamil)'`, `'?????? (Telugu)'`) are confirmed at the byte
level to be literal ASCII `?` characters, not real Tamil/Telugu script and not a display-encoding artifact;
(5) selected language does not survive an app restart — `LanguageNotifier._init()` hardcodes `'en'` on every
cold start rather than reading back the saved `SharedPreferences` value (`RULE-SETTINGS-005`); a whole
`LanguageCache` class exists to do exactly this and is never called anywhere; (6) "Push Notifications" and
"Dark Mode" settings tiles are fully decorative — no `onTap`, no wiring — and Dark Mode has nothing live to
toggle to anyway, since `MaterialApp` hardcodes `themeMode: ThemeMode.light` with no `darkTheme:` parameter
set at all (`RULE-SETTINGS-006`). Coverage: 99% (weighted) — see `Settings/COVERAGE_TRACKER.md`. Badge: 🟢
(two edges deferred to the not-yet-built `MPIN` module brain and an unverified deep-link possibility for the
orphaned route).

## Coverage Table

| Module | Round 0 | Round 1 |
|---|---|---|
| Core | ⬜ | 🟢 99.4% (2026-08-19) |
| Auth | ⬜ | 🟢 100% weighted (2026-08-19) |
| MPIN | ⬜ | 🟢 93% (2026-08-19) |
| KYC | ⬜ | 🟢 ~97% (2026-08-19) |
| Home | ⬜ | 🟢 ≈90% |
| InstantSaving | ⬜ | 🟢 ~97% (2026-08-19) |
| DailySavings | ⬜ | 🔵 100% |
| SIP | ⬜ | 🟢 95% (2026-08-19) |
| Withdrawal | ⬜ | 🔵 98.5% |
| Profile | ⬜ | 🔵 100% (Round 1, 2026-08-19) |
| Notifications | ⬜ | 🟢 96% (2026-08-19) |
| Nominee | ⬜ | 🟢 96% (2026-08-19) |
| Referral | ⬜ | 🟢 99% (2026-08-19) |
| Settings | ⬜ | 🟢 99% (2026-08-19) |
| Support | ⬜ | 🔵 100% (2026-08-19) |
| Content | ⬜ | 🔵 100% (2026-08-19) |
| Market | ⬜ | 🔵 100% (2026-08-19) |
| History | ⬜ | 🔵 100% (2026-08-19) |
| Splash | ⬜ | 🔵 100% (2026-08-19) |
| Onboarding | ⬜ | 🔵 100% (2026-08-19) |
| Maintenance | ⬜ | 🔵 100% (2026-08-19) |
| Main | ⬜ | 🟢 93% (2026-08-19) |
| Invoice | ⬜ | 🟢 100% weighted (2026-08-19) |
| Jewellery | ⬜ | 🟢 100% weighted (2026-08-19) |

Round 1 complete: 24/24 modules built. 12 at 🔵 (100% + spot-checked), 12 at 🟢 (mostly complete,
pending a Round-2 spot-check pass — none below 90%).

## Open Inaccuracies Found in Hand-Written Docs

- **`STARTGOLD_DOCUMENTATION.md` §3.3–3.7 (Login/OTP/Registration/PIN Creation)**: country-codes endpoint
  is `POST users/shared/country-codes`, not `GET shared/country-codes`. Registration is undocumented as
  requiring mandatory email verification and is really two API calls (`register-check` then `register`),
  not one. **Security-relevant**: `register-check` isn't in `AppConfig.encryptedEndpoints` unlike its
  sibling `register`, so it ships unencrypted. See `knowledge_brain/Auth/COVERAGE_TRACKER.md`.
- **`STARTGOLD_DOCUMENTATION.md` §3.8–3.9 (MPIN)**: says "4-digit"; live code is 6-digit everywhere
  (confirmed independently by both the Auth and MPIN module builds). Doc's "4 modes" claim is also wrong —
  code branches on 8 distinct `type` values, one of which (`authorize_withdrawal`) is dead code. See
  `knowledge_brain/MPIN/COVERAGE_TRACKER.md`.
- **`STARTGOLD_DOCUMENTATION.md` §3.11–3.12 (Instant Saving / Payment Methods)**: `payment_methods_screen.dart`,
  the screen §3.12 describes as live, is explicitly marked `[LEGACY]` in its own header and is dead code —
  three gateways (Cashfree/HDFC-Juspay/Razorpay) are actually selected server-side and routed through a
  different handler chain. Denomination/config endpoints are POST, not GET as documented, and live at
  different paths than claimed. See `knowledge_brain/InstantSaving/MODULE_BRAIN.md`.
- **Not a hand-written-doc discrepancy — critical security finding**: `core/security/encryption_service.dart`'s
  `decrypt()` method is a no-op passthrough; `ApiSecurityInterceptor` logs "Response decrypted (AES-256)" on
  every response regardless. Nothing is actually decrypted client-side today. Additionally, encryption
  **fails open**: if the RSA public key isn't ready when a sensitive request fires, the field is sent in
  plaintext rather than the request being blocked. Highest-severity finding in this brain build — see
  `Core/MODULE_BRAIN.md` and the forthcoming `_SYSTEM/DANGER_ZONES.md`.
- **`STARTGOLD_DOCUMENTATION.md` §3.10 (Home Screen)**: two of the three listed API integrations are
  wrong — doc says `POST users/portfolio`, live code calls `POST portfolio/summary`
  (`core/services/portfolio_service.dart:12`); doc says `GET users/home/dashboard`, live code calls
  `POST home/dashboard` (`core/services/home_service.dart:11`). The "Sell Rate Timer", "Market
  Status" socket protocol, "Race Condition Guard", and "Tab Refresh" technical-logic claims were all
  **confirmed accurate**. The doc also omits an entire feature present in live code: the "100-Day
  Grand Launch" countdown offer (`home/countdown-offer` endpoint,
  `features/home/widgets/countdown_offer_*.dart`) — likely added after the doc was last updated. See
  `knowledge_brain/Home/MODULE_BRAIN.md` §8 for the full drift table.
- **`STARTGOLD_DOCUMENTATION.md` §3.15 (Daily Savings Screen)**: describes the route as
  "Configure daily micro-investment settings" with no caveat. Live code shows the screen is a
  non-functional UI stub — no API integration, no controller, and its submit button is a no-op.
  The doc doesn't claim it's broken, so this is a coverage gap in the hand-written doc rather
  than a factual error, but it's misleading by omission: a reader would assume this route works
  like the other screens documented in the same section (e.g. §3.16 Withdrawal, which lists real
  API integrations). See `knowledge_brain/DailySavings/MODULE_BRAIN.md` §0 for the full verdict.
  **Correction**: §3.16 Withdrawal's own "real API integrations" turned out to have wrong endpoint names and
  wrong encrypted-field names — see the Withdrawal entry above. The API integrations are real, just
  documented inaccurately.
- **`STARTGOLD_DOCUMENTATION.md` §3.16 (Withdrawal Screen)**: `POST withdraw/initiate` does not exist —
  actual submit endpoint is `POST withdrawal/withdraw` (`withdrawal/services/withdrawal_service.dart:45`).
  `POST withdraw/verify-upi` does not exist — actual is `POST account/verify-upi` (`:90`). Claimed encrypted
  fields `withdrawal_amount, upi_id, bank_details, buy_rate` do not match the real payload — actual encrypted
  fields on the submit call are `amount, weight, buy_rate` (verified against `AppConfig.sensitiveFields` +
  `encryptedEndpoints`, `core/config/app_config.dart:47-99`); no field named `withdrawal_amount` or
  `bank_details` exists anywhere in this module. "Transaction PIN verification" and "Market closed →
  withdrawal blocked" fintech-risk bullets are confirmed accurate.
- **`STARTGOLD_DOCUMENTATION.md` §3.17 (UPI Selection)**: described as a withdrawal step. Live code: UPI
  payout is implemented but disabled in the UI (bank-account-only, `withdrawal/screens/upi_selection_screen.dart:471-484`);
  the `UpiSelectionScreen` itself is not reachable from the withdrawal flow at all in current routing — its
  only live caller is Instant Saving's purchase-payment UPI step (`instant_saving_screen.dart:1654`), and its
  submit action hardcodes navigation into Withdrawal Confirmation regardless of the caller's original intent.
  See `knowledge_brain/Withdrawal/FORENSIC_TEMPLATE.md` #6 — flagged as the highest-value item to verify on a
  live device before this brain can be considered fully closed-out.

- **`STARTGOLD_DOCUMENTATION.md` §3.29–3.31 (Profile Module)**: lists only 3 screens (Profile, Account
  Details, Delete Account). Live code has 9 screens — Bank Details, Bank Verification Hub, BAV History,
  ₹1 Payment Verification History, Refund Verification History, and the ₹1 payment screen itself are all
  absent from the hand-written doc, added after its 2026-05-20 date. The 3 documented screens' purposes are
  accurate as far as they go, just incomplete. See `knowledge_brain/Profile/MODULE_BRAIN.md` §1.
- **Possible live bug, not a hand-written-doc discrepancy**: `withdrawal/services/withdrawal_service.dart:106`
  passes the bank-account-creation API path as `'account\verify-bank'` — a non-raw Dart string literal in
  which `\v` is the real vertical-tab escape sequence, corrupting the runtime path to
  `"account" + U+000B + "erify-bank"`. This also means the request never matches `'verify-bank'` in
  `AppConfig.encryptedEndpoints`, so `account_no`/`ifsc_code` (both in `AppConfig.sensitiveFields`) would
  ship unencrypted if the request reaches the backend at all. This is the sole bank-account-creation call
  for both Profile's Bank Details screen and SIP's bank-account picker. See
  `knowledge_brain/Profile/BUSINESS_RULES.md` RULE-PROFILE-010 — flagged **unconfirmed at runtime**, needs
  a live network capture or the `withdrawal`/`sip` module brains to corroborate. A sibling instance of the
  same escape-bug pattern exists at `withdrawal_service.dart:117` (`'referrals\reward-balance'`).

- **`STARTGOLD_DOCUMENTATION.md` §3.13-3.14 (KYC Screen / PAN Verification)**: `POST users/kyc/upload` and
  `POST users/submit-kyc` do not exist — actual live endpoints are `kyc/document-types` (fetch),
  `kyc/upload` (submit, no `users/` prefix), and `kyc/update-profile-name`. "Document upload capability" is
  claimed but the live flow is text-field-only — no `image_picker`/`image_cropper` usage anywhere in the
  module despite a `KycImagesRequirement` (front/back) model shaped for one. `/pan-verification` is described
  as a working standalone screen; live code shows it's an orphaned, non-functional stub (fake delay, no
  backend call). PAN-RSA-encryption and RBI KYC/PMLA compliance-framing claims are confirmed accurate. See
  `knowledge_brain/KYC/COVERAGE_TRACKER.md` "Drift Found" table.

- **`STARTGOLD_DOCUMENTATION.md` §3.33 (Notifications Screen)**: the 5-endpoint API table is accurate
  as far as it goes but omits `users/notifications/register-token` (FCM device-token registration) and
  the entire FCM push-delivery mechanism (`core/services/fcm_service.dart`) — coverage gap, not a
  factual error. See `knowledge_brain/Notifications/MODULE_BRAIN.md` §8.
- **`STARTGOLD_DOCUMENTATION.md` §3.34 (Nominee Screen)**: route and "`POST users/nominee/update` —
  Encrypted" are both correct but imprecise/incomplete — omits `users/nominee/details` (fetch) and
  `users/nominee/relationships` (dynamic list), and "Encrypted" is doc-shorthand for "only the
  `mobile` field within the payload is RSA-encrypted," not the whole payload. See
  `knowledge_brain/Nominee/MODULE_BRAIN.md` §8.
- **Possible live PII-exposure gap, not a hand-written-doc discrepancy**: Nominee's `id_number` field
  (used for Aadhaar/PAN/Passport/Voter-ID/Driving-License numbers per the `idType` selector) is sent
  to `POST users/nominee/update` in plaintext — it does not match `aadhaar_number`, `pan`, or
  `pan_number` in `AppConfig.sensitiveFields` (`core/config/app_config.dart:74-99`), even though the
  endpoint itself is flagged as encrypted. Only `mobile` gets transformed. See
  `knowledge_brain/Nominee/BUSINESS_RULES.md` RULE-NOMINEE-003. Note: currently low real-world impact
  since the nominee form has no UI to actually populate `id_number` (see next finding), but the gap
  would become live the moment that UI is added without also updating `sensitiveFields`.
- **Architecture violation, not a hand-written-doc discrepancy**: `features/nominee/screens/nominee_screen.dart`
  imports `features/profile/profile_controller.dart` directly (`:16`) to reuse `checkPincode` — a
  direct feature-to-feature internals import, against `AGENTS.md` §1. See
  `knowledge_brain/Nominee/CROSS_MODULE_MAP.md` "Known Violations" for two remediation options.
- **Incomplete feature, not a hand-written-doc discrepancy**: Nominee's ID-proof type/number fields
  exist end-to-end in the model and submit payload but the form has no widget to set them
  (`_buildDropdownField` at `nominee_screen.dart:838` is defined but never called). See
  `knowledge_brain/Nominee/BUSINESS_RULES.md` RULE-NOMINEE-006.

- **`STARTGOLD_DOCUMENTATION.md` §3.20-3.26 (Auto Savings / SIP)**: §3.20 lists only
  `POST sip/create` with encrypted field `amount`, which is accurate but drastically incomplete —
  19 live endpoints exist across two distinct backend products (regular `SIPScheme` and
  `CustomSIPScheme`), not surfaced at all. §3.21-3.26 lists 8 screens as a bare route table with
  one-line purposes; live code has 11 routed screens plus 2 unrouted widgets, and omits entirely:
  the 24-hour cancellation lock-in (`cancel_eligible_at`/`can_cancel_now`, see
  `SIP/BUSINESS_RULES.md` RULE-SIP-001), the Custom SIP product as a distinct concept from
  Daily/Weekly/Monthly, the dual Cashfree/Razorpay payment-gateway selection, and the KYC gate on
  creation. Also: Custom SIP's `sip/custom/*` endpoints are absent from
  `AppConfig.encryptedEndpoints`, so `amount`/bank fields on that path ship without the
  field-level RSA encryption regular SIP's `sip/create` gets — see `SIP/BUSINESS_RULES.md`
  RULE-SIP-011, a `_SYSTEM/DANGER_ZONES.md` candidate. Full detail in
  `knowledge_brain/SIP/MODULE_BRAIN.md`.

- **`STARTGOLD_DOCUMENTATION.md` §3.37–3.39 (Support Module)**: the 3-screen/3-route table (Support hub,
  Enquiry Form, Enquiry List) is accurate on names/paths, but is gap-heavy — it doesn't mention the
  `initial_type` navigation-argument mechanism, that `/support` is a dead/unreachable route, the dead
  `SupportTicket` model, or the default-ticket-type bug (RULE-SUPPORT-003/004). See
  `knowledge_brain/Support/MODULE_BRAIN.md` "Drift vs STARTGOLD_DOCUMENTATION.md".
- **`STARTGOLD_DOCUMENTATION.md` §3.40 (Content Screens)**: the 6-screen/route/provider table is accurate,
  but leaves unstated whether content is server-fetched or bundled (now confirmed: server-fetched, see the
  Content build-round note above) and doesn't mention the HTML rendering mechanism
  (`flutter_widget_from_html_core`, not a WebView), the `/about` dead route, or the duplicated
  Lora-font-injection logic between `ContentScreen` and `FaqScreen`. See
  `knowledge_brain/Content/MODULE_BRAIN.md` "Drift vs STARTGOLD_DOCUMENTATION.md".
- **Confirmed bug, not a hand-written-doc discrepancy**: `features/support/screens/enquiry_form_screen.dart`'s
  default ticket type (`'General'`) is not a member of the `kTicketTypes` map the chip picker/submit logic
  both use — no chip shows as selected by default, and an un-tapped submit silently files as type 1
  ("Enquiry"). Also causes `sip/screens/manage_custom_savings_screen.dart`'s `initial_type: 'Custom SIP'`
  argument to be silently ignored. See `knowledge_brain/Support/BUSINESS_RULES.md` RULE-SUPPORT-003/004 — a
  `_SYSTEM/DANGER_ZONES.md`/product-ticket candidate, not just a brain artifact.
- **Two dead routes found, not hand-written-doc discrepancies**: `/support` (`SupportScreen`) and `/about`
  (`ContentScreen` w/ `aboutUsProvider`) are both registered in `app_router.dart` with zero in-app
  navigation call sites (confirmed via exhaustive project-wide grep). Both screens are otherwise fully
  functional if reached — this looks like leftover scaffolding from a redesign rather than a runtime bug.
  Worth flagging as a systemic pattern for `_SYSTEM/DANGER_ZONES.md` given it's now been found twice.

- **`STARTGOLD_DOCUMENTATION.md` §4 (WebSocket Integration)**: substantially wrong, not just
  imprecise. Claims Socket.IO transport at `ws://bullion_v4.logimaxindia.com/ratesocket/
  socket.io/` with event `market_rates` and reconnection via "exponential backoff"; live code
  (`core/network/native_socket_service.dart`) uses a raw `web_socket_channel` connection (no
  Socket.IO framing) to `wss://startgoldapp.logimaxindia.com/ws/` (staging) /
  `wss://sgbackoffice.startgold.com/ws/` (production), no named events, and a flat 5-second
  reconnect delay with no backoff. The claimed rate-frame format
  `3|goldBuy|goldSell|silverBuy|silverSell|...` also doesn't exist — the real format is one line
  per commodity, ID-keyed (`3|<commodity_id>|<unused>|<buy>|<sell>|...`). The market-status
  claim ("Message type 5 with open/close flag") is directionally correct but omits that it's
  per-commodity, not global. See `knowledge_brain/Market/COVERAGE_TRACKER.md` for the full
  drift table and `Market/MODULE_BRAIN.md` for the verified protocol.
- **`STARTGOLD_DOCUMENTATION.md` §3.27–3.28 (Transaction History & Details)**: no factual
  drift — claims are accurate but thin (4 lines) versus the real surface: server-side
  pagination + lazy-load-on-scroll, a fully backend-driven filter-option system
  (`transactions/filter-options`), manual-refresh-only tab behavior, and the SIP module's
  separate-but-model-reusing transaction-history implementation are all undocumented. See
  `knowledge_brain/History/MODULE_BRAIN.md`.

- **`STARTGOLD_DOCUMENTATION.md` §3.1 (Splash Screen)**: routing bullets match code closely
  (maintenance → update → mpin → login), but the doc doesn't capture that maintenance strictly
  outranks the update dialog (the version check is skipped entirely when maintenance is on), nor
  that the update dialog hardcodes `forceUpdate: true` regardless of the server's real force/soft
  distinction. See `knowledge_brain/Splash/MODULE_BRAIN.md`.
- **`STARTGOLD_DOCUMENTATION.md` §3.2 (Onboarding Screen)**: claims "Multi-page carousel, skip
  button, proceed to login." No skip button exists in live code (confirmed via grep), and the doc
  doesn't note the screen is currently unreachable from any in-app navigation path (orphaned
  route — see the daily_savings precedent). See `knowledge_brain/Onboarding/MODULE_BRAIN.md` §0.
- **`STARTGOLD_DOCUMENTATION.md` §3.41 (Maintenance Screen)**: "auto-resume route" claim is
  directionally correct but provides no mechanism detail. Now documented precisely: pure polling
  (30s screen-local + 60s app-wide timers), zero manual retry control, and a real inconsistency in
  `resumeRoute` across the 3 call sites that can push this screen (only splash's path preserves
  session state; the other two hardcode `/login`). See
  `knowledge_brain/Maintenance/MODULE_BRAIN.md`.
- **`STARTGOLD_DOCUMENTATION.md` §3.42 (Main Screen)**: significant drift — doc claims 4 tabs
  ("Home, Invest, Market, Profile"). Live code has 5 nav items: Home, Invest, **History** (not
  Market), Profile, **Jewellery** — and Jewellery is a pushed route, not an `IndexedStack` tab
  like the other four. No "Market" tab exists in this file at all (market data lives inside
  `HomeScreen`). See `knowledge_brain/Main/MODULE_BRAIN.md` §0.
- **Unused pre-transaction gate, not a hand-written-doc discrepancy**:
  `shared/widgets/maintenance_gate.dart`'s `MaintenanceGate.check()` — the client-side
  pre-transaction maintenance/alert gate `AGENTS.md` §2 describes as the pattern for payment/
  withdrawal/SIP — has zero call sites anywhere in `lib/` outside its own file. Fully built,
  never invoked. See `knowledge_brain/Maintenance/MODULE_BRAIN.md` §3 Top Risk #2 — a
  `_SYSTEM/DANGER_ZONES.md` candidate.

- **`STARTGOLD_DOCUMENTATION.md` §3.35–3.36 (Referral Module)**: the 2-row route table (routes,
  one-line purposes) is factually accurate as far as it goes but omits everything about mechanics —
  no mention that reward math is 100% server-side, that both service methods swallow every error into
  an empty-state model (making `RefereeListScreen`'s built error/retry UI effectively dead code), or
  that the referral-code entry point lives entirely in `auth`/registration with no shared state
  connecting the two modules. See `knowledge_brain/Referral/MODULE_BRAIN.md` and
  `Referral/BUSINESS_RULES.md`.
- **`STARTGOLD_DOCUMENTATION.md` §3.32 (Settings Screen)**: claims biometric toggle, language, and
  notifications preferences all live on this screen. **Confirmed drift**: biometric toggle is not part
  of this module at all — it lives in `features/profile/profile_screen.dart`'s "Account" section
  (`config.md`'s module registry made the same incorrect claim, corrected in this round). Push
  Notifications is a fully decorative, non-functional tile. Language selection works for locale-code
  persistence but does not translate any of the app's own UI copy (only built-in Flutter widget
  locales), and the Tamil/Telugu labels in the picker are literal `?????`/`??????` placeholder text at
  the byte level, not real script. Most significantly: **`/settings` itself appears to be a registered
  but unreachable route** — no in-app navigation call site was found anywhere in `lib/`. See
  `knowledge_brain/Settings/MODULE_BRAIN.md` and `Settings/BUSINESS_RULES.md`
  RULE-SETTINGS-004..008.

## Round 2 — System Synthesis (2026-08-19)

All 24 module brains complete; ran `/build-system-brain` to synthesize `knowledge_brain/_SYSTEM/`:
`DANGER_ZONES.md` (11 numbered hard-stop entries), `DIAGNOSTIC_PLAYBOOK.md` (10 symptom→suspect rules),
`DEAD_CODE_AND_ORPHANED_ROUTES.md` (added beyond the original template — the pattern recurred often enough
across independent module builds, 5 orphaned routes + 17 dead-code instances, to warrant its own catalog
rather than being scattered), `MODULE_DEPENDENCIES.md`, `SHARED_SERVICES.md`, `SYSTEM_COVERAGE.md`, plus
partial-coverage `API_ENDPOINT_MAP.md`/`VALIDATION_GAPS.md`/`HARDCODED_VALUES.md`/`PERFORMANCE_RISKS.md`
(each explicitly marked incomplete — built from incidental findings, not a dedicated sweep).

Also consolidated `config.md`'s Module Registry and this file's Coverage Table — 16 concurrent module-brain
agents writing to these two shared files raced each other and 4 badge updates + 6 changelog entries were
silently dropped (last-write-wins on concurrent file edits). Fixed by cross-referencing each agent's own
completion report. **Process note for future rounds**: either serialize writes to `config.md`/
`BUILD_SUMMARY.md` behind a single coordinating step, or have each module agent write its status to its own
`COVERAGE_TRACKER.md` only and have a dedicated consolidation step aggregate from there — don't have N
parallel agents append to the same 2 shared files.

**Highest-severity findings surfaced across the whole build** (see `_SYSTEM/DANGER_ZONES.md` for full
detail): client-side response decryption is a no-op (DZ-001); encryption fails open when the RSA key isn't
ready (DZ-002); a Dart string-escape bug corrupts a bank-account-creation API path and its encryption match
(DZ-005); Custom SIP's encrypted fields miss the endpoint substring match (DZ-003); Nominee's `id_number`
(Aadhaar/PAN/Passport) ships in plaintext (DZ-004). None of these were fixed during Round 1/2 — brain-
building is documentation-only per `AGENTS.md` §0; they're the punch list for the next work session.

## Priorities for Next Round

1. ~~Build `Core` first~~ — done.
2. ~~Build the security/money-critical modules~~ — done.
3. ~~Then the remaining modules, then `/build-system-brain`~~ — done (this round).
4. **Runtime verification** of the "unconfirmed" findings in `_SYSTEM/DANGER_ZONES.md` (DZ-003, DZ-004,
   DZ-005, the MPIN/Settings `type`-argument question) via a live network capture or debugger session.
5. **Decide and act on** the dead-code/orphaned-route catalog in
   `_SYSTEM/DEAD_CODE_AND_ORPHANED_ROUTES.md` — each entry needs one of: remove, wire up, or document as
   intentionally-reserved.
6. Round-2 spot-checks to promote the 12 🟢 modules to 🔵 (see `_SYSTEM/SYSTEM_COVERAGE.md`).
7. Consider whether the encryption gaps (DZ-001, DZ-002, DZ-003, DZ-005) and the PII gap (DZ-004) warrant
   immediate fixes outside the normal backlog given this is a live fintech app — that's a product/security
   call, not a brain-building call.
