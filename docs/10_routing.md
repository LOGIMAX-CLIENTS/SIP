# Routing Guide — startGOLD

All navigation in startGOLD uses **named routes** defined centrally in `AppRouter`.

---

## Route Definitions

**File**: [app_router.dart](file:///e:/Projects/Mobileapp/SIP/lib/routes/app_router.dart)

### Complete Route Map

| Route Constant | Path | Screen | Auth Required |
|---------------|------|--------|:---:|
| `splash` | `/splash` | `SplashScreen` | ❌ |
| `onboarding` | `/onboarding` | `OnboardingScreen` | ❌ |
| `login` | `/login` | `LoginScreen` | ❌ |
| `otp` | `/otp` | `OtpScreen` | ❌ |
| `registration` | `/registration` | `RegistrationScreen` | ❌ |
| `registrationSuccess` | `/registration-success` | `RegistrationSuccessScreen` | ❌ |
| `mpinCreation` | `/mpin-creation` | `PinCreationScreen` | ❌ |
| `pinEntry` | `/pin-entry` | `PinScreen` | ❌ |
| `mpin` | `/mpin` | `MpinScreen` | ✅ |
| `changeMpin` | `/change-mpin` | `ChangeMpinScreen` | ✅ |
| `main` | `/main` | `MainScreen` | ✅ |
| `home` | `/home` | `MainScreen` | ✅ |
| `profile` | `/profile` | `ProfileScreen` | ✅ |
| `accountDetails` | `/accountdetails` | `AccountDetailsScreen` | ✅ |
| `instantSaving` | `/instant-saving` | `InstantSavingScreen` | ✅ |
| `dailySavings` | `/daily-savings` | `DailySavingsScreen` | ✅ |
| `autoSavings` | `/auto-savings` | `AutoSavingsScreen` | ✅ |
| `sipManage` | `/sip-manage` | `ManageSavingsScreen` | ✅ |
| `sipCancel` | `/sip-cancel` | `SipCancelScreen` | ✅ |
| `sipPayment` | `/sip-payment` | `SipPaymentScreen` | ✅ |
| `sipSuccess` | `/sip-success` | `SipSuccessScreen` | ✅ |
| `sipFailure` | `/sip-failure` | `SipFailureScreen` | ✅ |
| `sipTransactions` | `/sip-transactions` | `SipTransactionHistoryScreen` | ✅ |
| `sipTransactionDetails` | `/sip-transaction-details` | `SipTransactionDetailsScreen` | ✅ |
| `sipOverview` | `/sip-overview` | `SipOverviewScreen` | ✅ |
| `withdrawal` | `/withdrawal` | `WithdrawalScreen` | ✅ |
| `withdrawalConfirmation` | `/withdrawal-confirmation` | `WithdrawalConfirmationScreen` | ✅ |
| `upiSelection` | `/upi-selection` | `UpiSelectionScreen` | ✅ |
| `withdrawalSuccess` | `/withdrawal-success` | `WithdrawalSuccessScreen` | ✅ |
| `kyc` | `/kyc` | `KycScreen` | ✅ |
| `dynamicKyc` | `/kyc-dynamic` | `KycScreen` | ✅ |
| `panVerification` | `/pan-verification` | `PanVerificationScreen` | ✅ |
| `paymentMethods` | `/payment-methods` | `PaymentMethodsScreen` | ✅ |
| `transactionHistory` | `/transaction-history` | `TransactionHistoryScreen` | ✅ |
| `transactionDetails` | `/transaction-details` | `TransactionDetailsScreen` | ✅ |
| `support` | `/support` | `SupportScreen` | ✅ |
| `enquiryForm` | `/enquiry-form` | `EnquiryFormScreen` | ✅ |
| `enquiryList` | `/enquiry-list` | `EnquiryListScreen` | ✅ |
| `referral` | `/referral` | `ReferralScreen` | ✅ |
| `refereeList` | `/referee-list` | `RefereeListScreen` | ✅ |
| `settings` | `/settings` | `SettingsScreen` | ✅ |
| `notifications` | `/notifications` | `NotificationsScreen` | ✅ |
| `terms` | `/terms` | `ContentScreen` | ✅ |
| `privacy` | `/privacy` | `ContentScreen` | ✅ |
| `about` | `/about` | `ContentScreen` | ✅ |
| `faq` | `/faq` | `FaqScreen` | ✅ |
| `contact` | `/contact` | `ContactUsScreen` | ✅ |
| `refundPolicy` | `/refund-policy` | `ContentScreen` | ✅ |
| `nominee` | `/nominee` | `NomineeScreen` | ✅ |
| `deleteAccount` | `/delete-account` | `DeleteAccountScreen` | ✅ |
| `maintenance` | `/maintenance` | `MaintenanceScreen` | ❌ |

---

## Navigation Patterns

### Simple Navigation (no arguments)

```dart
Navigator.pushNamed(context, AppRouter.home);
```

### Navigation with Arguments

```dart
Navigator.pushNamed(
  context,
  AppRouter.otp,
  arguments: {
    'mobile': '9876543210',
    'countryCode': '+91',
    'idCountry': '101',
    'otpReferenceId': 'ref-123',
  },
);
```

### Replace Current Route

```dart
Navigator.pushReplacementNamed(context, AppRouter.main);
```

### Clear Stack & Navigate (e.g., after login)

```dart
Navigator.pushNamedAndRemoveUntil(
  context,
  AppRouter.main,
  (route) => false,  // Removes ALL previous routes
);
```

---

## Routes Requiring Arguments

| Route | Required Arguments |
|-------|-------------------|
| `otp` | `mobile`, `countryCode`, `idCountry`, `otpReferenceId` |
| `mpinCreation` | `mobile`, `fullName`, `email`, `dob`, `referralCode`, `tempToken` |
| `pinEntry` | `mobile` |
| `registration` | `mobile`, `tempToken` |
| `registrationSuccess` | `fullName` |
| `kyc` / `dynamicKyc` | `request_from` (optional: `'instant'`, `'withdrawal'`, `'sip'`) |
| `paymentMethods` | `amount`, `metal_id`, `rate`, `coupon_code`, `buy_type`, `weight` |
| `transactionDetails` | Full transaction `Map<String, dynamic>` |
| `sipManage` | `subscription_id` |
| `sipCancel` | `subscription_id` |
| `sipPayment` | Payment data `Map<String, dynamic>` |
| `sipSuccess` / `sipFailure` | Result data `Map<String, dynamic>` |
| `withdrawalSuccess` | Withdrawal data `Map<String, dynamic>` |
| `maintenance` | `resumeRoute` |
| `enquiryForm` | `initial_type` (optional) |

---

## Unknown Route Handling

When an unknown route is requested, `onGenerateRoute` handles it:

```
Unknown route requested
    │
    ▼
Show loading spinner
    │
    ▼
Check authentication state
    │
    ├── Authenticated + MPIN enabled → Navigate to /mpin
    └── Not authenticated → Navigate to /login
```

This prevents users from ever seeing a "Page Not Found" screen.

---

## Navigation Flow Diagram

```
/splash
   │
   ├── Not seen onboarding ──▶ /onboarding ──▶ /login
   │
   ├── No token ──▶ /login ──▶ /otp
   │                              │
   │                    ┌─────────┼──────────────┐
   │                    │         │              │
   │                    ▼         ▼              ▼
   │              /registration  /mpin-creation  /main
   │                    │              │
   │                    ▼              ▼
   │              /registration-success ──▶ /main
   │
   ├── Has token + MPIN ──▶ /mpin ──▶ /main
   │
   └── Maintenance ──▶ /maintenance
```

---

## Adding a New Route

1. **Add route constant** in `AppRouter`:
   ```dart
   static const String myNewScreen = '/my-new-screen';
   ```

2. **Add route mapping** in the `routes` getter:
   ```dart
   myNewScreen: (context) => const MyNewScreen(),
   ```

3. **If route needs arguments**, extract them:
   ```dart
   myNewScreen: (context) {
     final args = ModalRoute.of(context)!.settings.arguments
         as Map<String, dynamic>? ?? {};
     return MyNewScreen(id: args['id'] ?? '');
   },
   ```

4. **Navigate to the new route**:
   ```dart
   Navigator.pushNamed(context, AppRouter.myNewScreen, arguments: {'id': '123'});
   ```
