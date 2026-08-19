---
last_updated: 2026-08-19
source: Endpoints confirmed by module brains during Round 1 reads — NOT an exhaustive grep of every endpoint in the app, see "Known Incomplete" below
---

# API Endpoint Map (Partial — Confirmed During Round 1)

This is a byproduct of module-brain building, not a dedicated endpoint sweep. Each module's own
`MODULE_BRAIN.md`/`METHOD_INDEX.md` has the complete list for that module; this file collects only the ones
that came up as notable (either because they drifted from `STARTGOLD_DOCUMENTATION.md`, or because they're
central to a cross-module flow).

| Method | Path | Module | Encrypted Fields | Note |
|---|---|---|---|---|
| POST | `users/shared/country-codes` | Auth | — | Doc wrongly said `GET shared/country-codes` |
| POST | `users/auth/register-check` | Auth | none (gap) | Not in `encryptedEndpoints` unlike its sibling |
| POST | `users/auth/register` | Auth | referral_code, others | — |
| POST | `mpin/validate`, `mpin/create`, `mpin/change`, `mpin/reset` | MPIN | mpin fields | No `users/` prefix, unlike doc's claim |
| POST | `kyc/document-types`, `kyc/upload`, `kyc/update-profile-name` | KYC | pan/aadhaar fields | Doc wrongly said `users/kyc/upload`, `users/submit-kyc` |
| POST | `portfolio/summary` | Home | — | Doc wrongly said `POST users/portfolio` |
| POST | `home/dashboard` | Home | — | Doc wrongly said `GET users/home/dashboard` |
| POST | `home/countdown-offer` | Home | — | Undocumented feature ("100-Day Grand Launch") |
| POST | `users/shared/amount-denominations`, `weight-denominations` | InstantSaving | — | Doc wrongly said `savings/denominations/*` GET |
| POST | `savings/check-eligibility` | InstantSaving/Withdrawal/SIP | — | Shared KYC-gating signal (`next_step`) |
| POST | `savings/initiate` | InstantSaving | amount, weight | Returns `payment_gateway` selection |
| POST | `sip/create`, `sip/cancel`, `sip/pause` | SIP | amount, bank fields | Encrypted |
| POST | `sip/resume`, `sip/custom/*` | SIP | amount, bank fields | **NOT encrypted** — DZ-003 |
| POST | `sip/transactions` | SIP | — | Reuses History's response models |
| POST | `withdrawal/withdraw` | Withdrawal | amount, weight, buy_rate | Doc wrongly said `withdraw/initiate` |
| POST | `account/verify-upi` | Withdrawal | upi_id | Doc wrongly said `withdraw/verify-upi` |
| ??? | `account\verify-bank` (literal, buggy) | Profile/Withdrawal | account_no, ifsc_code intended | Path corrupted by Dart escape bug — DZ-005 |
| POST | `users/nominee/update`, `details`, `relationships` | Nominee | mobile only (gap: id_number) | — |
| POST | `users/notifications`, `read`, `read-all`, `delete`, `unread-count`, `register-token` | Notifications | — | Doc omitted `register-token` |
| POST | `content/...` (terms/privacy/about/refund/faq/contact) | Content | — | Server-fetched, not bundled |
| POST | `transactions/filter-options` | History | — | Backend-driven filters |
| POST | `jewellery/jewellery-image` | Jewellery | — | Returns only image URLs — confirms "Coming Soon" placeholder |
| WS | `wss://startgoldapp.logimaxindia.com/ws/` (staging) / `wss://sgbackoffice.startgold.com/ws/` (prod) | Market/Core | N/A | Doc wrongly claimed Socket.IO at a different host entirely |

## Known Incomplete

This is not the full API surface of the app — many endpoints per module (especially in larger modules like
SIP with 19 confirmed endpoints, or Profile's 9-screen bank-verification surface) are documented in full
only in their own module's `MODULE_BRAIN.md`/`METHOD_INDEX.md`, not repeated here. A dedicated
`/build-system-brain` grep sweep (per `build-system-brain.md` step 5: grep every distinct endpoint string
across `lib/`) would produce a complete map; this file only captures what surfaced as noteworthy during
Round 1's per-module builds.
