---
module: InstantSaving
last_updated: 2026-08-19
---

# InstantSaving — Cross-Module Map

## Dependency Graph

```mermaid
graph TD
    IS[InstantSaving]

    subgraph Core
        NET[core/network/api_client.dart]
        SEC_ENC[core/security/encryption_service.dart]
        SEC_INT[core/security/api_interceptor.dart]
        SEC_ALO[core/security/app_lifecycle_observer.dart]
        SEC_SCR[core/security/screenshot_security_service.dart]
        TIMER[core/providers/timer_provider.dart]
        MARKET[core/providers/market_provider.dart]
        COMMOD[core/providers/commodity_provider.dart]
        SHARED[core/services/shared_service.dart]
        USER[core/providers/user_provider.dart]
        PORTFOLIO[core/providers/portfolio_provider.dart]
        HOMEDASH[core/providers/home_dashboard_provider.dart]
        COUNTDOWN[core/providers/countdown_offer_provider.dart]
        ERR[core/error/failures.dart]
    end

    subgraph Features
        KYC[features/kyc/kyc_flow.dart]
        MAIN[features/main/main_screen.dart]
        WITHDRAWAL_UPI[features/withdrawal/screens/upi_selection_screen.dart]
        PROFILE[features/profile/profile_controller.dart]
    end

    subgraph SDKs
        CASHFREE[flutter_cashfree_pg_sdk]
        HYPERSDK[hypersdkflutter / Juspay]
        RAZORPAY[razorpay_flutter]
    end

    IS -->|all HTTP via| NET
    NET --> SEC_INT
    SEC_INT --> SEC_ENC
    IS -->|rate-lock timer, shared instance type| TIMER
    IS -->|live rate stream, market open/closed| MARKET
    IS -->|commodity selection, id_metal resolution| COMMOD
    IS -->|denominations, commodities list| SHARED
    IS -->|customer id, mobile| USER
    IS -->|suppressAppLock during SDK focus| SEC_ALO
    IS -.->|app-wide only, no per-screen call| SEC_SCR
    IS -->|KYC_REQUIRED gate| KYC
    KYC -->|refresh after KYC completes| PROFILE
    IS -->|on success, "Back to Home"| PORTFOLIO
    IS -->|on success, "Back to Home"| HOMEDASH
    IS -->|"Best Offer" silver reward| COUNTDOWN
    IS -->|nextStep UPI_LIST| WITHDRAWAL_UPI
    IS -->|nav stack clear after purchase| MAIN
    IS -->|error mapping| ERR
    IS -->|Cashfree Web Checkout| CASHFREE
    IS -->|HDFC SmartGateway| HYPERSDK
    IS -->|Razorpay Checkout| RAZORPAY
```

## Dependencies on `core/`

| Core file | What InstantSaving uses it for |
|---|---|
| `core/network/api_client.dart` | Every request (`SavingService`, `PaymentService`) goes through this single `Dio`-based client. |
| `core/security/api_interceptor.dart` | Determines which endpoints get encrypted (`AppConfig.encryptedEndpoints`, substring match) and attaches the auth token. |
| `core/security/encryption_service.dart` | RSA-OAEP-SHA256 field-level encryption of `mobile`/`amount_inr`/`weight` on `savings/check-eligibility` and `savings/initiate`. |
| `core/config/app_config.dart` | `encryptedEndpoints` list, `sensitiveFields` list — both define this module's encryption surface. |
| `core/security/app_lifecycle_observer.dart` | `suppressAppLock` static flag — set `true` by all 3 payment handlers before SDK launch, `false` on every terminal callback. |
| `core/security/screenshot_security_service.dart` | **Not called directly by this module** — relies entirely on the global `AppConfig.enableScreenshotProtection` toggle set once at app startup. |
| `core/providers/timer_provider.dart` | `sellRateTimerProvider` — the rate-lock mechanism (`RateTimerNotifier`), shared class with `withdrawal`'s `buyRateTimerProvider`. |
| `core/providers/market_provider.dart` | `marketRatesStreamProvider` (live socket rates), `marketStatusProvider` (per-commodity open/closed). |
| `core/providers/commodity_provider.dart` | `commodityProvider` (Gold/Silver toggle state), `selectedMetalIdProvider` (resolves real `id_metal` from `commoditiesProvider`). |
| `core/services/shared_service.dart` | `commoditiesProvider`, `amountDenominationsProvider`, `weightDenominationsProvider` — all `POST users/shared/*`. |
| `core/providers/user_provider.dart` | Logged-in `customerId`/`mobile` for eligibility/initiate payloads. |
| `core/providers/portfolio_provider.dart`, `core/providers/home_dashboard_provider.dart` | Invalidated/refetched only from `PurchaseSuccessScreen`'s "Back to Home" button. |
| `core/providers/countdown_offer_provider.dart` | Drives the "Best Offer" free-silver-reward block. |
| `core/error/failures.dart` | `Failure` type — caught in `_handleConfirmOrder` and all 3 payment handlers to show a user-facing message instead of a raw exception. |

## Dependencies on other features

| Feature | Relationship |
|---|---|
| `features/kyc/` (`kyc_flow.dart` → `KycVerificationFlow.start`) | Pushed when `check-eligibility` returns `next_step=='KYC_REQUIRED'`. Passes `request_from:'instant'` and `extraData` (amount, metal_id, rate, buy_type, weight) so the KYC hub can round-trip context back if needed. This is the documented cross-module KYC gate — **being documented in parallel per the build brief**; InstantSaving's brain treats `KycScreen` internals as out of scope and only documents the entry/exit contract (`Future<bool>`, `true` only when both PAN+Aadhaar approved). |
| `features/profile/` (`profile_controller.dart`) | `KycVerificationFlow.start` best-effort refreshes `profileProvider` after KYC completes; `PurchaseSuccessScreen` also invalidates `profileProvider` on "Back to Home". |
| `features/withdrawal/screens/upi_selection_screen.dart` | Reused by InstantSaving for the `next_step=='UPI_LIST'` branch (`Navigator.pushNamed(AppRouter.upiSelection, ...)`, `instant_saving_screen.dart:1654`). The Withdrawal module brain independently confirms this screen physically lives under `withdrawal/screens/` but its only live caller is InstantSaving, not any withdrawal flow — cross-confirmed finding, not re-derived here. |
| `features/main/main_screen.dart` | `selectedTabProvider` — switched to Home/Invest tab after purchase; `MainScreen`'s tab shell is what `AppRouter.main` resolves to after the success screen clears the nav stack. Also read directly on the Instant Saving screen's own header back-button to decide `Navigator.pop` vs switching tabs (`instant_saving_screen.dart:389-396`). |

## Payment SDK Dependencies

| SDK | Package | Used by |
|---|---|---|
| Cashfree | `flutter_cashfree_pg_sdk` | `payment_handler.dart` (live), `screens/payment_methods_screen.dart` (legacy/dead) |
| HDFC SmartGateway (Juspay) | `hypersdkflutter` | `hdfc_payment_handler.dart` |
| Razorpay | `razorpay_flutter` | `razorpay_payment_handler.dart` |

All three are gated on the **backend's** `payment_gateway` field from `savings/initiate` — see
`BUSINESS_RULES.md` RULE-INSTANTSAVING-010. No compile-time or config-time choice exists; a single install of
the app can route different orders (even for the same user) through different gateways.

## Known Violations / Notable Architecture Facts

- **Cross-feature screen reuse via named route (not a direct import)**: `Navigator.pushNamed(AppRouter
  .upiSelection, ...)` reaches a screen that lives in `withdrawal/screens/`. This is compliant with the
  "route through `AppRouter`, don't import another feature's internals directly" rule (AGENTS.md §1) — no
  `import '../../withdrawal/...'` was found in `instant_saving/`. Flagged here only because it means
  `UpiSelectionScreen`'s actual owner-by-usage is InstantSaving, not Withdrawal, despite its folder location —
  worth correcting if the codebase is ever reorganized.
- **Dead legacy screen still registered in the central route table**: `AppRouter.paymentMethods` →
  `PaymentMethodsScreen` remains in `app_router.dart`'s `routes` map (`app_router.dart:249-260`) even though
  no live code path navigates to it. It is not a violation of the layering rules, but it is a maintenance
  hazard — see `MODULE_BRAIN.md` risk #4.
- **`instant_saving_screen.dart` imports `../kyc/kyc_flow.dart` directly** (a cross-feature import) —
  acceptable because `kyc_flow.dart` is explicitly designed as the shared cross-module entry point (its own
  doc comment says "Single entry point ... across SIP, Withdrawal, and Investment"), not an internal
  `kyc/controller` or `kyc/services` file. This matches the "shared logic belongs in a designated shared
  entry point" allowance rather than being a violation.
- **No `lib/shared/` widget dependency map was found to be unusual** — this module uses standard shared UI
  (`GradientHeader`, `AppToast`, `CustomButton`, `NumericStyledText`, `SecureClipboard`, loaders) from
  `lib/shared/widgets/` and `lib/shared/theme/`, consistent with every other module's usage pattern.
