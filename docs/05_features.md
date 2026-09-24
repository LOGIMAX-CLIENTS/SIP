# Feature Guide — startGOLD

Detailed breakdown of every feature module in the app. This is your go-to reference when working on or debugging specific features.

---

## 1. Splash Screen

**Path**: `lib/features/splash/`

**Purpose**: Entry point that determines where to route the user based on session state.

**Logic Flow**:
1. Check if app is under maintenance → route to maintenance screen
2. Check if user has seen onboarding → if not, show onboarding
3. Check if user has valid token → if yes, check MPIN
4. Route to appropriate screen (login, MPIN, or home)

**Key File**: `splash_screen.dart`

---

## 2. Onboarding

**Path**: `lib/features/onboarding/`

**Purpose**: First-time user carousel explaining app features.

**Behavior**:
- Shows only once (tracked via `SharedPreferences`)
- After completion, routes to Login screen
- Sets `hasSeenOnboarding = true`

---

## 3. Authentication

**Path**: `lib/features/auth/`

### 3a. Login (`auth/login/`)

- User enters mobile number with country code
- Calls `AuthService.sendOtp()` → `users/auth/generate-otp`
- On success, navigates to OTP screen

### 3b. OTP Verification (`auth/otp/`)

- 6-digit OTP input with auto-focus
- Calls `AuthService.verifyOtp()` → `users/auth/verify-otp`
- Response determines routing:
  - `is_new_user: true` → Registration
  - `is_new_user: false` + MPIN enabled → Home
  - `is_new_user: false` + MPIN not set → PIN Creation

### 3c. Registration (`auth/registration/`)

- New user registration form (name, email, DOB, referral code)
- Pre-validation via `register-check` API
- On success → PIN Creation screen
- Shows `RegistrationSuccessScreen`

### 3d. PIN Creation (`auth/pin/`)

- `PinCreationScreen` — Create 4-digit MPIN
- `PinScreen` — Enter existing MPIN for login
- MPIN is encrypted via RSA before sending to server

**Key Service**: [auth_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/services/auth_service.dart)

---

## 4. MPIN

**Path**: `lib/features/mpin/`

**Purpose**: Quick login & transaction authorization via 4-digit PIN.

**Screens**:
- `MpinScreen` — Enter MPIN for login
- `ChangeMpinScreen` — Change existing MPIN (verify old → set new)

**Contexts** (same screen, different copy):
| Context | Title |
|---------|-------|
| Default (login) | "Quick Login With MPIN" |
| Withdrawal auth | "Authorized Withdrawal" |
| Biometric setup | "Secure Biometric Setup" |

**Key Service**: [mpin_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/services/mpin_service.dart)

---

## 5. Home Dashboard

**Path**: `lib/features/home/`

**Purpose**: Main landing page after login. Shows portfolio summary, live rates, and quick action buttons.

**Key Components**:
- Portfolio summary (total invested, current value, returns)
- Live gold/silver rates with WebSocket updates
- Quick buy buttons (Instant Saving, Daily Savings, SIP)
- Artisanal curations carousel
- "Create Your First SIP" banner for new users

**Key File**: `home_screen.dart` (82KB — largest file in the project)

**Data Providers**:
- `portfolioProvider` — Holdings data
- `marketProvider` — Live rates
- `homeDashboardProvider` — Dashboard aggregation

---

## 6. Main Container

**Path**: `lib/features/main/`

**Purpose**: Bottom navigation wrapper containing Home, Market, Portfolio, and Profile tabs.

**File**: `main_screen.dart`

---

## 7. Market / Live Rates

**Path**: `lib/features/market/`

**Purpose**: Displays live gold and silver market rates with real-time updates.

**Data Source**: WebSocket connection via `NativeSocketService`
- Connects to server WebSocket endpoint
- Receives rate updates in real-time
- Updates `marketProvider` on each tick

---

## 8. Instant Saving (Buy Gold/Silver)

**Path**: `lib/features/instant_saving/`

**Purpose**: Core buy flow — users purchase gold/silver at live market rates.

**Buy Modes**:
| Mode | Description |
|------|-------------|
| Amount-based | User enters ₹ amount, gets equivalent grams |
| Weight-based | User enters grams, pays equivalent ₹ |

**Payment Flow**:
1. User selects gold/silver, enters amount
2. Rate is locked with countdown timer
3. KYC check — if incomplete, redirect to KYC
4. Navigate to `PaymentMethodsScreen`
5. Initiate payment via `savings/initiate` API
6. Launch Cashfree SDK with session data
7. Handle success/failure callback
8. Verify payment via API

**Key Files**:
- `instant_saving_screen.dart` — Main buy UI
- `payment_handler.dart` — Cashfree payment orchestration
- `screens/payment_methods_screen.dart` — Payment method selection

---

## 9. Daily Savings

**Path**: `lib/features/daily_savings/`

**Purpose**: Micro-savings feature for small daily gold purchases.

**File**: `daily_savings_screen.dart`

---

## 10. SIP (Systematic Investment Plan)

**Path**: `lib/features/sip/`

**Purpose**: Automated recurring gold purchases — the core "SIP" feature.

**Screens**:
| Screen | Purpose |
|--------|---------|
| `auto_savings_screen.dart` | Create new SIP plan |
| `manage_savings_screen.dart` | View/manage active SIP |
| `sip_cancel_screen.dart` | Cancel an active SIP |
| `sip_payment_screen.dart` | Process SIP payment |
| `sip_success_screen.dart` | Payment success |
| `sip_failure_screen.dart` | Payment failure |
| `sip_transaction_history_screen.dart` | SIP transaction list |
| `sip_transaction_details_screen.dart` | Individual SIP transaction detail |
| `sip_overview_screen.dart` | SIP portfolio overview |

**Structure**:
```
sip/
├── controller/     # SIP business logic
├── models/         # SipSubscription, SipTransaction models
├── screens/        # All SIP screens listed above
└── services/       # SIP API calls (create, cancel, pause, etc.)
```

**SIP API Endpoints** (encrypted):
- `sip/create` — Create new subscription
- `sip/cancel` — Cancel subscription
- `sip/pause` — Pause subscription

---

## 11. Withdrawal (Sell Gold)

**Path**: `lib/features/withdrawal/`

**Purpose**: Users sell their gold/silver holdings and receive money.

**Flow**:
1. User enters withdrawal amount (in grams)
2. Rate is locked with countdown timer
3. KYC + MPIN verification required
4. Select UPI ID for receiving funds
5. Confirm withdrawal
6. Success/failure screen

**Screens**:
- `withdrawal_screen.dart` — Enter amount, select metal
- `upi_selection_screen.dart` — Choose UPI for payout
- `withdrawal_confirmation_screen.dart` — Final review
- `withdrawal_success_screen.dart` — Success confirmation

**Limits**:
- Minimum: 0.001g
- Maximum: 100g
- Decimal precision: 4 digits

---

## 12. KYC Verification

**Path**: `lib/features/kyc/`

**Purpose**: Mandatory identity verification before transactions.

**Architecture** — Dynamic KYC:
The KYC flow is **server-driven**. The server returns the list of required KYC steps dynamically:
- PAN verification
- Aadhaar verification
- Bank account verification
- Photo upload

**Structure**:
```
kyc/
├── controllers/    # Step-by-step KYC validation
├── models/         # KycStep, KycField, etc.
├── providers/      # KYC state management
├── repositories/   # Data layer
├── screens/        # KYC form screens
│   ├── pan_verification_screen.dart
│   └── kyc_screen.dart (dynamic orchestrator)
└── kyc_screen.dart # Entry point
```

**Key Behavior**:
- `request_from` parameter tells KYC what triggered it (`instant`, `withdrawal`, `sip`)
- After KYC completion, returns to the calling feature

---

## 13. Transaction History

**Path**: `lib/features/history/`

**Purpose**: View past buy/sell transactions.

**Screens**:
- `transaction_history_screen.dart` — Paginated list of all transactions
- `transaction_details_screen.dart` — Individual transaction detail view

---

## 14. Profile & Account

**Path**: `lib/features/profile/`

**Purpose**: User profile management.

**Screens**:
- `profile_screen.dart` — Main profile page (photo, name, KYC status)
- `account_details_screen.dart` — Detailed account information
- `screens/delete_account_screen.dart` — Account deletion flow

**Features**:
- Profile photo upload (camera + gallery via `image_picker`)
- Photo cropping (`image_cropper`)
- PII masking for display (phone, PAN)

---

## 15. Nominee Management

**Path**: `lib/features/nominee/`

**Purpose**: Add/update nominee for the user's holdings.

**API**: `users/nominee/update` (encrypted)

---

## 16. Referral Program

**Path**: `lib/features/referral/`

**Purpose**: Users share referral codes and track referrals.

**Screens**:
- `referral_screen.dart` — Share referral code
- `referee_list_screen.dart` — List of people who signed up via referral

---

## 17. Settings

**Path**: `lib/features/settings/`

**Purpose**: App settings (language, biometric toggle, etc.)

---

## 18. Support

**Path**: `lib/features/support/`

**Purpose**: Customer support with enquiry submission.

**Screens**:
- `support_screen.dart` — Support hub
- `screens/enquiry_form_screen.dart` — Submit new enquiry
- `screens/enquiry_list_screen.dart` — View past enquiries

---

## 19. Content (CMS)

**Path**: `lib/features/content/`

**Purpose**: Display server-managed content pages.

**Screens**:
- `content_screen.dart` — Generic HTML content renderer
- `faq_screen.dart` — FAQ display
- `contact_us_screen.dart` — Contact information

**Content Types**: Terms & Conditions, Privacy Policy, About Us, Refund Policy

---

## 20. Notifications

**Path**: `lib/features/notifications/`

**Purpose**: Display push notification history.

**File**: `notifications_screen.dart`

---

## 21. Maintenance Mode

**Path**: `lib/features/maintenance/`

**Purpose**: Displayed when server is under maintenance.

**Behavior**:
- Controlled by `AppControlWrapper` checking remote config
- Shows maintenance message with estimated resume time
- Blocks all navigation until server is back online
