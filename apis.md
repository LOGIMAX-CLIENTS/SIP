# StartGold App API Specification

This document summarizes the complete set of API endpoints required for the StartGold mobile application, organized by feature.

---

## ðŸ” GLOBAL SECURITY ARCHITECTURE

1.  **Transport Encryption:** All communication is strictly via **HTTPS (TLS 1.2+)**. 
2.  **Field-Level Encryption (AES-256-CBC):**
    *   Sensitive fields (e.g., `password`, `otp`, `pin`, `aadhaar`, `pan`, `upi_id`, `bank_details`) are encrypted client-side using **AES-256** before being sent in the JSON payload.
    *   This ensures data remains unreadable even if the proxy is compromised.
3.  **Central API Interceptor:**
    *   **Auto-Authentication:** Injects `Authorization: Bearer <token>` into all requests.
    *   **Auto-Encryption:** Detects sensitive endpoints and encrypts payloads on-the-fly.
    *   **Auto-Decryption:** Decrypts server responses before they reach the UI logic.
4.  **Secure Logger (Anti-Leakage):**
    *   All terminal/console logs are sanitized.
    *   Sensitive data is automatically replaced with `[REDACTED]` to prevent developers/testers from accidentally seeing private user info.
5.  **Offline Handling:** 
    *   API calls are blocked if no internet is detected to prevent state corruption.
    *   Standardized errors: `Network connection lost` or `Server unavailable`.
6.  **Socket Security:**
    *   Endpoint: `ws://bullion_v4.logimaxindia.com/ocket/socket.io/`.
    *   **Auto-Reconnect:** Enabled for continuous market data flow.
    *   **Restricted Scope:** Socket is used EXCLUSIVELY for market rates; NO sensitive data is sent via WS.
7.  **Device Integrity:** 
    *   Pass `device_id` on login and sensitive actions.
    *   Environment checks (Root/Jailbreak detection) prevent the app from running on insecure hardware.
8.  **RSA Key Exchange (`crypto/public-key`):**
    *   On first launch (or when cache is empty), the app calls `GET crypto/public-key` to retrieve the server's **RSA-OAEP-SHA256** public key.
    *   The key is persisted in `FlutterSecureStorage` and reused for the session.
    *   If the endpoint is unreachable, the app transparently falls back to **AES-256-CBC** so the user experience is never broken.
    *   The private key is **never exposed** to the client; sensitive fields are encrypted one-way with RSA before transmission.
9.  **SSL Certificate Pinning (Dynamic):**
    *   All HTTPS connections validate the server certificate's SHA-256 fingerprint against a trusted list.
    *   **Hardcoded fallback:** Shipped in the APK for first-install / offline scenarios.
    *   **Server-managed pins:** The `app/control` API returns a `certificate_pins` array. These are cached in encrypted storage and used for all subsequent connections.
    *   **Certificate renewal without app republish:** Server adds the new fingerprint to `certificate_pins` before renewal â†’ apps auto-cache â†’ cert is renewed â†’ zero downtime.

---

## 0. ðŸ”‘ Encryption Key Exchange

### 0.1 Fetch Server RSA Public Key
*   **Endpoint:** `GET crypto/public-key`
*   **Authorization:** None (public endpoint â€“ called before login)
*   **Purpose:** Retrieves the server's RSA-OAEP-SHA256 public key used to encrypt sensitive fields client-side before transmission.
*   **Trigger:** Called automatically by `ApiSecurityInterceptor` on app startup. Result is cached in `FlutterSecureStorage`.
*   **Response (Success):**
    ```json
    {
      "success": true,
      "data": {
        "algorithm": "RSA-OAEP-SHA256",
        "public_key": "\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA..."
      }
    }
    ```
*   **Failure Handling:**
    *   If the endpoint is unavailable (network error, server down, timeout) the app **silently falls back** to AES-256-CBC encryption.
    *   The error is logged via `SecureLogger` but the user is never shown an error for this background call.
    *   On the next app launch the fetch is retried automatically.

---

## 0.2 ðŸŒ App Runtime Control

### 0.2.1 Fetch App Control Data
*   **Endpoint:** `POST app/control`
*   **Authorization:** None (public endpoint â€” called before login and periodically while app is open)
*   **Purpose:** Central runtime control gate. Returns current version info (with platform-specific popups), live global alerts, and maintenance status.
*   **Polling:** App polls this endpoint every **5 minutes** while active to pick up live alert changes without requiring a restart.
*   **Request Body:**
    ```json
    {
      "platform": "android"
    }
    ```

| Field | Type | Required | Description |
|---|---|---|---|
| `platform` | String | Yes | `"android"` or `"ios"` â€” sent so the server can return platform-specific version info, alerts, and maintenance status |

*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "version": {
          "force_update": false,
          "android": {
            "latest_version": "2.1.0",
            "min_version": "1.5.0",
            "store_url": "https://play.google.com/store/apps/details?id=com.startgold",
            "title": "New Update Available",
            "message": "We've added exciting new features. Update now for the best experience.",
            "button_text": "Update Now"
          },
          "ios": {
            "latest_version": "2.0.0",
            "min_version": "1.3.0",
            "store_url": "https://apps.apple.com/app/startgold/id123456",
            "title": "Update Available",
            "message": "A new version of StartGold is available on the App Store.",
            "button_text": "Go to App Store"
          }
        },
        "alert": {
          "is_active": true,
          "type": "warning",
          "title": "Scheduled Maintenance",
          "message": "Our servers will be down for maintenance on Apr 2, 2:00â€“4:00 AM IST.",
          "action_url": null,
          "action_label": null
        },
        "maintenance": {
          "is_enabled": false,
          "title": "Under Maintenance",
          "subtitle": "We're upgrading our systems for a better experience. Please check back soon.",
          "expected_resume": "We'll be back by 4:00 AM IST"
        },
        "certificate_pins": [
          "F3:AB:FB:70:B3:D0:A7:F2:CB:EF:02:8A:2C:C4:95:62:55:D8:FC:35:71:E5:32:0E:7F:04:D7:00:47:10:86:AC"
        ]
      }
    }
    ```

#### Version Update Logic (Client-Side)
| Condition | Behaviour |
|---|---|
| `current < android.min_version` (or `ios.min_version`) | **Force update** â€” dialog shown, app unusable until updated |
| `current < android.latest_version` (or `ios.latest_version`) | **Optional update** â€” dialog with "Later" skip option |
| `current >= platform.latest_version` | No popup shown |

#### Alert `type` Values
| Value | Color | Dismissible |
|---|---|---|
| `info` | Blue | âœ… Yes |
| `warning` | Amber | âœ… Yes |
| `maintenance` | Indigo | âŒ No |

#### `certificate_pins` â€” Dynamic SSL Pinning

| Field | Type | Required | Description |
|---|---|---|---|
| `certificate_pins` | Array\<String\> | No | List of pins the app should trust. Supports **two formats** (can be mixed in the same array). |

**Supported Pin Formats:**

| Format | Example | Changes on cert renewal? |
|---|---|---|
| **Certificate fingerprint** (colon-hex) | `"F3:AB:FB:70:B3:D0:..."` | âœ… Yes â€” new cert = new fingerprint |
| **Public key pin** (Base64 SPKI SHA-256) | `"hEdBgpqZW1U6x1XwUf+0UfNg4zu2oy/OwkIOGCppqXs="` | âŒ **No** â€” stable if same key pair is reused |

> **Recommendation:** Use **public key pins** for production. They don't change on cert renewals (as long as server reuses the same key pair), so no app/API update is needed.

**Example response with both formats:**
```json
"certificate_pins": [
  "F3:AB:FB:70:B3:D0:A7:F2:CB:EF:02:8A:2C:C4:95:62:55:D8:FC:35:71:E5:32:0E:7F:04:D7:00:47:10:86:AC",
  "hEdBgpqZW1U6x1XwUf+0UfNg4zu2oy/OwkIOGCppqXs="
]
```
The app auto-detects the format (colon = cert fingerprint, no colon = public key pin).

**How it works:**
*   On every `app/control` fetch, the app reads `certificate_pins` and caches them in encrypted local storage.
*   These cached pins are used for SSL validation on all subsequent HTTPS connections.
*   If `certificate_pins` is missing or empty, the app falls back to hardcoded pins shipped with the APK.

**Certificate Renewal Workflow (No App Republish Needed):**
1.  **2 weeks before renewal:** Add the NEW certificate's fingerprint to the array (keep old one too).
2.  All active apps will auto-fetch and cache both fingerprints within their next poll cycle.
3.  **Renew the certificate** on the server.
4.  Remove the old fingerprint from the array.
5.  Result: Zero downtime, zero app store update.

> If using public key pins and the server reuses the same key pair, **no changes are needed at all** during cert renewal.

**How to get the pins:**
```bash
# Certificate fingerprint (colon-hex)
echo | openssl s_client -connect vaptapi.startgold.com:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256

# Public key pin (Base64 SPKI SHA-256) â€” RECOMMENDED
echo | openssl s_client -connect vaptapi.startgold.com:443 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | openssl enc -base64
```

*   **Failure Handling:** If this endpoint is unavailable, the app continues normally with no update/alert/maintenance popup.

#### Maintenance Mode Behaviour
| `is_enabled` | Client Behaviour |
|---|---|
| `true` at launch | `initialRoute` â†’ `/maintenance` (blocks all normal routing) |
| `true` while in-app | `AppControlWrapper` redirects to `/maintenance` on next poll |
| `false` (lifted) | `MaintenanceScreen` auto-navigates to the original `resumeRoute` |

*   **Polling during maintenance:** Every **2 minutes** (faster than normal 5-min alert poll)
*   **Back press on maintenance screen:** Exits app (Android) / no-op (iOS)
*   **No AppBar back button** on maintenance screen

---

## 1. Onboarding & Shared Data

### 1.1 Fetch Onboarding Carousel
*   **Page Name:** `OnboardingScreen`
*   **Endpoint:** `POST users/content/onboarding`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "slides": [
          { "id": 1, "image": "https://cdn.gold.com/slides/1.png", "title": "Buy 24K Gold", "desc": "Start with just â‚¹10." }
        ]
      }
    }
    ```

### 1.2 Country & Prefix Selection
*   **Page Name:** `LoginScreen`
*   **Endpoint:** `POST users/shared/country-codes`
*   **Response:** Returns ISO codes, phone prefixes, and flag icons.

### 1.3 Fetch Commodities
*   **Endpoint:** `POST users/shared/commodities`
*   **Response:**
    ```json
    {
      "success": true,
      "data": [
        {
          "id_metal": "1",
          "web_soc_id": 91,
          "name": "Gold 24KT"
        },
        {
          "id_metal": 2,
          "web_soc_id": 98,
          "name": "Silver 999"
        }
      ]
    }
    ```

### 1.4 Fetch Amount Denominations
*   **Endpoint:** `POST users/shared/amount-denominations`
*   **Request Body:**
    ```json
    {
      "id_metal": "1"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": [
        {
          "value": 10,
          "is_popular": 0
        },
        {
          "value": 50,
          "is_popular": 0
        },
        {
          "value": 100,
          "is_popular": 1
        }
      ]
    }
    ```

### 1.5 Fetch Weight Denominations
*   **Endpoint:** `POST users/shared/weight-denominations`
*   **Request Body:**
    ```json
    {
      "id_metal": "1"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": [
        {
          "value": 1,
          "is_popular": 0
        },
        {
          "value": 2,
          "is_popular": 0
        },
        {
          "value": 5,
          "is_popular": 1
        },
        {
          "value": 10,
          "is_popular": 0
        }
      ]
    }
    ```


### 1.4 Fetch All Translations (Mega)
*   **Endpoint:** `POST users/shared/all-translations`
*   **Description:** Fetches the entire translation repository for all supported languages. This is called once at app startup and stored locally to avoid repeated API calls.
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "homeTitle": {
          "en": "Home",
          "ta": "à®®à¯à®•à®ªà¯à®ªà¯",
          "te": "à°¹à±‹à°®à±"
        },
        "loginTitle": {
          "en": "Secure Login",
          "ta": "à®ªà®¾à®¤à¯à®•à®¾à®ªà¯à®ªà®¾à®© à®‰à®³à¯à®¨à¯à®´à¯ˆà®µà¯"
        }
      }
    }
    ```

### 1.5 Pincode Check
*   **Endpoint:** `POST users/shared/check-pincode`
*   **Description:** Validates a 6-digit pincode and retrieves corresponding State and City.
*   **Request Body:**
    ```json
    {
      "pincode": "641012"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "state": "Tamilnadu",
        "city": "Coimbatore"
      }
    }
    ```

---


## 2. Authentication Flow

### 2.1 Generate OTP (Send OTP)
*   **Page Name:** `LoginScreen`, `OtpScreen`, `MpinScreen`
*   **Reason:** To initiate or re-trigger the verification process for:
    *   **New Customer**: First-time registration.
    *   **Existing Customer**: Standard login.
    *   **Forgot PIN**: Verification before reset.
    *   **Resend**: Re-sending code during a session.
*   **Endpoint:** `POST users/auth/generate-otp`
*   **Request Body:**
    ```json
    {
      "mobile": "9876543210",
      "country_code": "+91",
      "id_country": "101",
      "type": "LOGIN / REGISTRATION / FORGOT_PIN / RESEND",
      "device_id": "uuid-123",
      "device_type": "android",
      "appVersion": "1.0.0"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "otp_reference_id": "OTP_REF_789"
      }
    }
    ```

### 2.2 Verify OTP
*   **Page Name:** `OtpScreen`
*   **Endpoint:** `POST users/auth/verify-otp`
*   **Request Body:**
    ```json
    {
      "mobile": "9876543210",
      "otp": "123456",
      "otp_reference_id": "OTP_REF_789"
    }
    ```
*   **Response (Existing Customer):**
    ```json
    {
      "success": true,
      "message": "Login successful",
      "data": {
        "is_new_user": false,
        "access_token": "JWT_ACCESS_F930AEE813F04A22B45A80360B7F97BF",
        "refresh_token": "REFRESH_8CDFE907AB3846CC90A625FAA0D031C8",
        "mpin_enabled": true,
        "user": {
          "id_customer": "C101",
          "name": "John Doe",
          "mobile": "2545534232",
          "email": "john.doe@example.com"
        }
      }
    }
    ```
*   **Response (New Customer):**
    ```json
    {
      "success": true,
      "message": "OTP verified. Proceed to registration.",
      "data": {
        "is_new_user": true,
        "temp_token": "TEMP_REG_TOKEN_507d6305",
        "mobile": "3545465786"
      }
    }
    ```
    ```json
    {
      "success": true,
      "message": "User not registered",
      "data": {
        "is_new_user": true,
        "temp_token": "TEMP_REG_TOKEN",
        "mobile": "9876543210"
      }
    }
    ```

### 2.3 User Registration (Profile Creation)
*   **Page Name:** `RegistrationScreen`
*   **Reason:** To create a new profile for a first-time users.
*   **Endpoint:** `POST users/auth/register`
*   **Request Body:**
    ```json
    {
      "mobile": "9876543210",
      "full_name": "Lord Alexander",
      "email": "alex@gold.com",
      "temp_token": "TEMP_REG_TOKEN"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Registration successful",
      "data": {
        "access_token": "JWT_TOKEN",
        "refresh_token": "REF_TOKEN",
        "user": {
          "id_customer": "C101",
          "name": "Lord Alexander"
        }
      }
    }
    ```

### 2.3.1 Pre-Validate Registration Fields
*   **Page Name:** `RegistrationScreen`
*   **Reason:** Validates the registration form data (name, email, DOB, referral code) on the server before navigating to PIN creation. Ensures data is unique, correctly formatted, and the temp_token is still valid â€” without actually creating the account yet.
*   **Trigger:** User taps "Confirm" on the Personal Information screen (after agreeing to T&C).
*   **Endpoint:** `POST users/auth/register-check`
*   **Authorization:** None (uses temp_token from OTP verification)
*   **Request Body:**
    ```json
    {
      "mobile": "9876543210",
      "full_name": "Lord Alexander",
      "email": "alex@gold.com",
      "dob": "15/06/1995",
      "referral_code": "KSU8Y314",
      "temp_token": "TEMP_REG_TOKEN_507d6305",
      "device_id": "uuid-123",
      "device_type": "android"
    }
    ```
*   **Fields:**

    | Field | Type | Required | Description |
    |-------|------|----------|-------------|
    | `mobile` | String | Yes | User's mobile number |
    | `full_name` | String | Yes | Full name as on PAN card |
    | `email` | String | Yes | Valid email address |
    | `dob` | String | Yes | Date of birth in `DD/MM/YYYY` format |
    | `referral_code` | String | No | Optional referral code |
    | `temp_token` | String | Yes | Temporary token received from OTP verification |
    | `device_id` | String | Yes | Unique device identifier |
    | `device_type` | String | Yes | `"android"` or `"ios"` |

*   **Response (Success â€” fields are valid):**
    ```json
    {
      "success": true,
      "message": "Validation passed. Proceed to MPIN creation."
    }
    ```
*   **Response (Error â€” validation failed):**
    ```json
    {
      "success": false,
      "error": {
        "message": "Email already registered with another account."
      }
    }
    ```
*   **App Behaviour:**

    | `success` | Action |
    |-----------|--------|
    | `true` | Navigate to MPIN creation screen (`/mpin-creation`) with all registration fields |
    | `false` | Show error in `AppToast` (error type), stay on same page |

*   **Error Scenarios:**
    - Invalid or expired `temp_token`
    - Email already in use
    - Invalid date of birth format
    - Invalid referral code
    - Server-side validation failures

---

### 2.4 Refresh Access Token
*   **Trigger:** Called automatically by `ApiSecurityInterceptor` when any API returns `401 Unauthorized`.
*   **Endpoint:** `POST users/auth/token/refresh`
*   **Authorization:** None (public endpoint)
*   **Request Body:**
    ```json
    {
      "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Token refreshed successfully.",
      "data": {
        "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
        "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
      }
    }
    ```
*   **On Success:** New `access` + `refresh` tokens are persisted; original failed request is retried transparently.
*   **On Failure:** `SessionManager.logout()` is called, user is redirected to login.

---



### 3.1 MPIN Lifecycle Scenarios (The 5 Core Flows)
1. **Registration Flow:** Customer creates profile, then prompted to establish PIN -> Calls **`POST /mpin/create`**
2. **App Session (Cold Start):** Returning customer unlocks application -> Calls **`POST /mpin/validate`** 
3. **Change MPIN:** Customer updates PIN from Profile settings -> Calls **`POST /mpin/change`**
4. **Biometric Enablement:** Enabling fingerprint/FaceID requires PIN confirmation -> Calls **`POST /mpin/validate`**
5. **Withdrawal / Money Transfer:** Confirming financial action requires PIN verification -> Calls **`POST /mpin/validate`** (followed by `POST /account/withdraw` passing `transaction_pin`)

### 3.2 Create Secure MPIN
*   **Page Name:** `MpinScreen` (Setup Mode)
*   **Endpoint:** `POST /mpin/create`
*   **Authorization:** `Bearer Token`
*   **Request:** `{ "mpin": "1234" }`

### 3.3 Validate MPIN (App Unlock / Biometrics / Transfers)
*   **Page Name:** `MpinScreen` (Unlock/Verify Mode)
*   **Endpoint:** `POST /mpin/validate`
*   **Authorization:** `Bearer Token`
*   **Request:** `{ "mpin": "1234" }`

### 3.4 Check MPIN Status
*   **Reason:** To check if the user has already set an MPIN (usually called on app start).
*   **Endpoint:** `POST /auth/has-mpin`
*   **Authorization:** `Bearer Token`
*   **Response:** `{ "success": true, "hasMpin": true }`

### 3.4 Forgot PIN (Recovery)
*   **Step 1:** Call `Generate OTP` (Section 2.1) with `type: "FORGOT_PIN"`.
*   **Step 2:** Call `Verify OTP` (Section 2.2).
*   **Step 3:** On success, call `POST /mpin/reset` with:
    ```json
    {
      "temp_token": "TEMP_VERIFY_TOKEN",
      "new_mpin": "5678"
    }
    ```

### 3.5 Change MPIN
*   **Reason:** Allows an already authenticated user to change their MPIN in the application profile settings.
*   **Page Name:** `ChangeMpinScreen`
*   **Endpoint:** `POST /mpin/change`
*   **Authorization:** `Bearer Token`
*   **Request Body:**
    ```json
    {
      "old_mpin": "1234",
      "new_mpin": "5678"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "MPIN changed successfully."
    }
    ```

---

## 4. Home Dashboard

### 4.1 Fetch Home Dashboard Blocks
*   **Page Name:** `HomeScreen`
*   **Endpoint:** `POST /home/dashboard`
*   **Description:** Retrieves dynamic blocks for the home screen, including rate history, investment banners, and learning content.
*   **Request Body:**
    ```json
    {
      "id_metal": "1"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "rate_history": {
          "title": "Gold on a Growth Streak",
          "start_year": "2020",
          "start_rate": 4865,
          "end_year": "2026",
          "end_rate": 16446,
          "highlight_text": "Gold value has grown Over 4X in 5 years"
        },
        "invest_sections": {
          "title": "Invest Smart, Earn Big",
          "blocks": [
            {
              "type": "micro_saving",
              "title": "Micro Savings, Mega Rewards",
              "image": "assets/images/banner1.png",
              "cta": "Swipe"
            },
            {
              "type": "safe_secure",
              "title": "Safe & Secure",
              "subtitle": "Your assets are safely stored in 100% insured digital vaults."
            }
          ]
        },
        "learning_sections": {
          "title": "Learn Something New",
          "banners": [
            {
              "id": 1,
              "image": "assets/images/learn1.png",
              "title": "How Digital Gold Works",
              "url": "https://startgold.com/learn/how-it-works"
            }
          ]
        },
        "footer_info": {
          "title": "Your savings are 100% secure with StartGOLD!",
          "subtitle": "Your hard-earned precious metal is securely stored in vaults and can be withdrawn at any time.",
          "compliance": [
            { "icon": "assets/icons/iso.png", "label": "ISO 27001 Certified" },
            { "icon": "assets/icons/bis.png", "label": "BIS 24K Hallmark" }
          ],
          "office_address": "477-482, Anna Salai, 1st Floor, Khivraj Complex-1, Chennai 600 035, Tamil Nadu, India"
        }
      }
    }
    ```

---

## 5. Market & Portfolio
*   **Page Name:** `HomeScreen` / `MarketScreen`
*   **Endpoint:** `POST /market/rates/live`
*   **Response:** `{ "buy_price": 6250.5, "sell_price": 6120.25, "currency": "INR", "timestamp": "2024-03-02..." }`

### 4.2 Portfolio Summary
*   **Endpoint:** `POST /portfolio/summary`
*   **Request:**
    ```json
    {
      "id_metal": "1"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Portfolio summary retrieved",
      "data": {
        "total_holdings_grams": 0.500000,
        "current_value_inr": 3125.25,
        "total_invested": 2900,
        "growth_percentage": 7.7
      }
    }
    ```

---

## 5. Other Modules

### 5.1 Profile & KYC
*   `POST /profile/customer_details`: Fetches user profile data (name, email, address, etc.).
*   `POST /profile/update`: Edits user profile (Page: `ProfileScreen`).
*   `POST /customer/update-profile-photo`: Uploads/updates the customer's profile picture.
*   `POST /kyc/status`: Fetches current verification state.
*   `POST /kyc/initiate`: Triggers the verification process (Page: `KycScreen`).

### 5.2 Transactions & Financials
*   `POST /statements/list`: Fetches all logs/reports.
*   `POST /statements/download/{id}`: Downloads specific PDF report (Page: `StatementsScreen`).

### 5.3 Support & Contact
*   `POST /support/ticket`: Submits a query or chat request (Page: `SupportScreen`).

### 5.4 Referrals

#### 5.4.1 Fetch Referral Data
*   **Page Name:** `ReferralScreen`
*   **Endpoint:** `POST /users/auth/referral/details`
*   **Description:** Returns user's referral code, sharing link, and earning statistics. Called every time the Refer & Earn screen is opened.
*   **Authorization:** `Bearer Token`
*   **Request Body:**
    ```json
    {}
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Referral data fetched successfully",
      "data": {
        "referral_code": "KSU8Y314",
        "total_referrals": 1,
        "total_earned": "100.00",
        "reward_amount": "100.00",
        "share_link": "https://startgold.com/refer/KSU8Y314",
        "title": "Invite a friend and earn â‚¹100 worth of Gold.",
        "bullet_points": [
          { "content": "Share the link with friends, family, and relatives." },
          { "content": "Both you and your friend get â‚¹100 worth of gold." },
          { "content": "Reward is credited automatically after your friend's first purchase." }
        ]
      }
    }
    ```
*   **Fields:**
    | Field | Type | Description |
    |-------|------|-------------|
    | `referral_code` | String | Unique code for the customer to share |
    | `total_referrals` | Integer | Number of friends who joined using this code |
    | `total_earned` | String | Total reward amount earned via referrals |
    | `reward_amount` | String | Per-referral reward value (e.g. `"100.00"`) |
    | `share_link` | String | Deep link URL for sharing |
    | `title` | String | **Dynamic** hero heading shown in the Refer & Earn screen header |
    | `bullet_points` | Array | **Dynamic** list of `{ content: String }` objects rendered as bullet points |

> [!IMPORTANT]
> `title` and `bullet_points` are required for the UI to render dynamically.
> If omitted by the server, the app falls back to composed text using `reward_amount`.


#### 5.4.2 Claim Referral Reward
*   **Endpoint:** `POST /referral/claim`
*   **Description:** Claims pending referral rewards.
*   **Authorization:** `Bearer Token`
*   **Page:** `ReferralScreen`

#### 5.4.3 Fetch Referral Reward Balance
*   **Page Name:** `WithdrawalScreen`
*   **Endpoint:** `POST referrals/reward-balance`
*   **Description:** Returns the referral reward balance available for the selected metal. Called on the Withdrawal screen whenever it loads or the user switches between Gold / Silver tabs.
*   **Authorization:** `Bearer Token`
*   **Provider:** `rewardBalanceProvider` (auto-dispose, rebuilds on commodity change)
*   **Request Body:**
    ```json
    {
      "id_metal": "1"
    }
    ```
    > `id_metal` is resolved dynamically via `selectedMetalIdProvider` (`"1"` = Gold, `"2"` = Silver).

*   **Response:**
    ```json
    {
      "success": true,
      "message": "Reward balance fetched successfully",
      "data": {
        "reward_balance": 250.00
      }
    }
    ```
*   **Fields:**

    | Field | Type | Description |
    |-------|------|-------------|
    | `reward_balance` | Double | Available referral reward balance for the selected metal |

*   **UI Behaviour:**
    - If `reward_balance > 0` â†’ a green **"Referral Reward Balance â€” â‚¹XXX.XX â€” Available"** chip is shown inside the withdrawal input card, below the current holding row.
    - If `reward_balance == 0` or API fails â†’ chip is hidden silently (no error shown).

### 5.5 Session Termination
*   `POST /auth/logout`: Invalidate session on server-side.

---

---

## 6. Instant Saving (Buy Flow)

### 6.1 Fetch Saving Configuration
*   **Endpoint:** `POST /savings/config`
*   **Description:** Retrieves global limits and timer lock durations.
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "min_amount": 10.0,
        "max_amount": 200000.0,
        "sell_rate_lock_seconds": 10,
        "buy_rate_lock_seconds": 10,
        "gst": "3",
        "type": "inclusive"
      }
    }
    ```

### 6.2 Check Saving Eligibility
*   **Page Name:** `InstantSavingScreen`
*   **Reason:** Check whether customer can proceed directly to payment or must complete KYC before purchase.
*   **Endpoint:** `POST /savings/check-eligibility`
*   **Request Body:**
    ```json
    {
      "id_customer": "C101",
      "id_metal": "1",
      "mobile": "9876543210",
      "amount_inr": 100,
      "rate_per_gram": 15248.95,
      "device_id": "device-id-placeholder",
      "coupon_code": null,
      "request_from": "instant"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Eligibility checked successfully",
      "data": {
        "next_step": "KYC_REQUIRED / PAYMENT / UPI_LIST"
      }
    }
    ```

### 6.3 Initiate Instant Purchase
*   **Page Name:** `PaymentMethodsScreen`
*   **Reason:** Starting a spot purchase for Gold/Silver. This call happens AFTER eligibility is checked (and KYC if needed) and a payment method is selected.
*   **Endpoint:** `POST /savings/initiate`
*   **Request Body:**
    ```json
    {
      "id_customer": "1",
      "id_metal": "1",
      "buy_type": "AMOUNT",
      "mobile": "1234567890",
      "amount_inr": 100.0,
      "rate_per_gram": 6250.5,
      "coupon_code": "SECONDJAR",
      "device_id": "uuid-123",
      "request_from": "instant"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "transaction_id": "TXN_123456",
        "payment_token": "PG_TOKEN_XYZ",
        "order_amount": 100.0,
        "grams_locked": 0.016000,
        "expiry_seconds": 600
      }
    }
    ```

### 6.4 Validate Coupon
*   **Endpoint:** `POST /savings/validate-coupon`
*   **Request Body:** `{ "code": "SECONDJAR", "amount": 100.0 }`
*   **Response:** `{ "valid": true, "discount_amount": 5.0, "message": "Coupon applied!" }`

### 6.5 Confirm Payment
*   **Endpoint:** `POST /savings/confirm-payment`
*   **Reason:** Verifying the payment status with the backend after the mobile SDK (Cashfree) returns a callback.
*   **Request Body:**
    ```json
    {
      "order_id": "ORD2T20260325122541"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Order ORD2T20260325122541 has been successfully paid.",
      "data": {
        "status": "SUCCESS",
        "transaction_id": "CF_123456",
        "credited_weight": 0.007000
      }
    }
    ```

### 6.6 Cancel Order
*   **Endpoint:** `POST /savings/cancel_order`
*   **Reason:** Explicitly cancelling an order when the user backs out of the payment confirmation or bottom sheet.
*   **Request Body:**
    ```json
    {
      "order_id": "ORD2T20260325122541"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "order has been canceled"
    }
    ```

---

## 7. Dynamic KYC Flow

### 7.1 Fetch KYC Document Types
*   **Page Name:** `KycScreen`
*   **Endpoint:** `POST /kyc/document-types`
*   **Description:** Retrieves dynamic form configuration for different documents based on the request source.
*   **Request Body:**
    ```json
    {
      "id_customer": "1",
      "request_from": "instant / withdrawal / profile_update / scheme_join"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "KYC document types retrieved successfully",
      "data": {
        "documents": [
          {
            "id_document": "2",
            "document_name": "PAN",
            "code": "PAN",
            "mandatory": true,
            "fields": [
              {
                "name": "pan",
                "label": "PAN Number",
                "type": "text",
                "regex": "^[A-Z]{5}[0-9]{4}[A-Z]{1}$"
              }
            ]
          }
        ]
      }
    }
    ```

### 7.2 Upload KYC Data
*   **Endpoint:** `POST /kyc/upload`
*   **Content-Type:** `application/json`
*   **Description:** Uploads KYC document details.
*   **Request Body:**
    ```json
    {
      "id_document": "1",
      "request_from": "instant / withdraw",
      "fields": {
        "pan": "ABCPV1234D",
        "name": "John Doe"
      }
    }
    ```
*   **Security:** Field values (like PAN numbers) must be encrypted before sending (AES-256).
*   **Response:**
    ```json
    {
      "success": true,
      "message": "KYC submitted successfully",
      "data": {
         "status": "PENDING / APPROVED / REJECTED"
      }
    }
    ```

---

## 8. Payment Gateway Flow

### 8.1 Fetch Payment Methods
*   **Endpoint:** `POST /payments/methods`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "methods": [
          { "id": "1", "name": "cashfree", "icon": "cashfree icon","description":"For testing Credit Card Debit Card Net Banking."
           },
        
        ]
      }
    }
    ```

### 8.2 Create Payment Order
*   **Endpoint:** `POST /payments/create-order`
*   **Request Body:**
    ```json
    {
      "amount": 100.0,
      "method_id": "upi",
      "transaction_id": "TXN_123456"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "payment_url": "https://gateway.com/pay/abc",
        "order_id": "ORDER_789"
      }
    }
    ```

### 8.3 Verify Payment Status
*   **Endpoint:** `POST /payments/status`
*   **Request Body:** `{ "order_id": "ORDER_789" }`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "status": "SUCCESS / FAILED / PENDING",
        "new_balance": 0.050000
      }
    }
    ```

---

### 9.1 Check Redemption Eligibility
*   **Page Name:** `WithdrawalScreen`
*   **Endpoint:** `POST /savings/check-eligibility`
*   **Payload:**
    ```json
    {
      "id_customer": "C101",
      "id_metal": "1",
      "mobile": "9876543210",
      "amount_inr": 100,
      "request_from": "withdraw"
    }
    ```
*   **Response:**
    ```json
    { "success": true, "data": { "next_step": "KYC_REQUIRED / UPI_LIST" } }
    ```

---

## 10. Informational Content

### 10.1 Terms and Conditions
*   **Endpoint:** `POST users/content/terms`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "title": "Terms and Conditions",
        "content": "Full terms and conditions text..."
      }
    }
    ```

### 10.2 Privacy Policy
*   **Endpoint:** `POST users/content/privacy`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "title": "Privacy Policy",
        "content": "Full privacy policy text..."
      }
    }
    ```

### 10.3 Frequently Asked Questions (FAQ)
*   **Endpoint:** `POST users/content/faqs`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "faqs": [
          { "question": "What is StartGold?", "answer": "StartGold is a digital gold savings platform." }
        ]
      }
    }
    ```

### 10.4 About Us
*   **Endpoint:** `POST users/content/about-us`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "title": "About Us",
        "content": "Company history and vision..."
      }
    }
    ```

### 10.5 Contact Us
*   **Endpoint:** `POST users/content/contact-us`
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Contact us fetched successfully",
      "data": {
        "email": "support@startgold.com",
        "toll_free": "1800-XXX-XXXX",
        "phone": "+91-89390 89393",
        "whatsapp": "+91-89390 89393",
        "office_address": "477-482, Anna Salai, 1st Floor (Right Wing), Khivraj Complex - 2, Chennai 600 035, Tamil Nadu, India",
        "registered_address": "No.158, Gulecha Tower, Inspire OfficeSpace, 2nd Floor, Arcot Road, Vadapalani, Chennai - 600 026, Tamil Nadu, India",
        "working_hours": "10 AM - 7 PM",
        "facebook": "https://www.facebook.com/StartGoldIndia",
        "twitter": "https://x.com/Startgoldapp",
        "instagram": "https://www.instagram.com/start_goldapp/",
        "website": "https://startgold.com/"
      }
    }
    ```
*   **Fields:**

    | Field | Type | Description |
    |-------|------|-------------|
    | `email` | String? | Support email address *(row hidden if absent)* |
    | `toll_free` | String? | Toll-free helpline number *(row hidden if absent)* |
    | `phone` | String? | Support phone number â€” "Call Us" *(row hidden if absent)* |
    | `whatsapp` | String? | WhatsApp support number â€” opens `wa.me` link *(row hidden if absent)* |
    | `office_address` | String? | Corporate / branch office address *(row hidden if absent)* |
    | `registered_address` | String? | Registered office address *(row hidden if absent)* |
    | `working_hours` | String? | Business hours display string *(row hidden if absent)* |
    | `facebook` | String? | Facebook page URL *(optional â€” icon hidden if absent)* |
    | `twitter` | String? | X (Twitter) profile URL *(optional â€” icon hidden if absent)* |
    | `instagram` | String? | Instagram profile URL *(optional â€” icon hidden if absent)* |
    | `website` | String? | Official website URL *(optional â€” icon hidden if absent)* |

*   **Note:** **All fields are optional.** The app renders each contact card row and social icon tile **only** when the corresponding field is present and non-empty in the API response. If a field is `null`, missing, or an empty string, that row/icon is **not shown** â€” no fallback or placeholder is displayed.

---

## 11. Support Enquiries

### 11.1 Submit Enquiry
*   **Endpoint:** `POST users/support/submit`
*   **Payload:**
    ```json
    {
      "id_customer": "123",
      "mobile": "9876543210",
      "subject": "Payment Issue",
      "message": "My payment was deducted but not reflect in portfolio.",
      "category": "PAYMENT / TECHNICAL / GENERAL"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Enquiry submitted successfully. Ticket ID: #TK12345",
      "data": {
        "enquiry_id": "TK12345",
        "status": "OPEN",
        "created_at": "2024-03-18 11:00 AM"
      }
    }
    ```

### 11.2 Enquiry Listing
*   **Endpoint:** `POST users/support/list`
*   **Payload:**
    ```json
    {
      "id_customer": "123",
      "mobile": "9876543210"
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "enquiries": [
          {
            "enquiry_id": "TK12345",
            "subject": "Payment Issue",
            "status": "RESOLVED",
            "created_at": "2024-03-15",
            "last_update": "2024-03-16"
          },
          {
            "enquiry_id": "TK12346",
            "subject": "Gold Rate Query",
            "status": "OPEN",
            "created_at": "2024-03-18",
            "last_update": "2024-03-18"
          }
        ]
      }
    }
    ```
---

## 12. ðŸš€ PRODUCTION READINESS CHECKLIST

Before deploying the application to the Production Environment (Play Store / App Store), the following changes **MUST** be implemented in `lib/core/config/app_config.dart` and the server infrastructure:

### 12.1 Backend Environment
- **Base URL:** Change from `.../test/api/mock_api/` to the production endpoint (e.g., `https://mxhedge.logimaxindia.com/api/v1/`).
- **Trailing Slashes:** Ensure all production URLs match the backend routing rules (consistent trailing slashes).

### 12.2 SSL & Security (Level 1: Transport)
- **HTTPS Enforcement:** Verify that NO `http://` URLs remain in the app.
- **SSL Pinning:** Implement Certificate Pinning using the SHA-256 fingerprint in `AppConfig.allowedCertFingerprints`.

### 12.3 Data Protection (Level 2: Information)
- **Field-Level Encryption:** Activate AES-256-CBC for all fields in `sensitiveFields` (Aadhaar, PAN, UPI IDs, Bank details).
- **Secure Storage:** Ensure all tokens and keys are ONLY stored in `FlutterSecureStorage` using Hardware-backed Enclaves (automatic on iOS/Android).
- **Secure Logger:** Ensure `SecureLogger` is scrubbing logs in the Release build.

### 12.4 Device Protection (Level 3: Physical)
- **Root/Jailbreak Detection:** Mandatory check at app launch; block sensitive transactions if detected.
- **Screenshot Protection:** Enable `ScreenProtector.preventScreenshotOn()` to block screenshots and screen recordings app-wide.
- **App Switcher Masking:** Use lifecycle events to blur or black out the app preview in the Task Manager (Recent Apps).
- **Biometric Unlock:** (Future Update) Integrate `local_auth` for FaceID/Fingerprint unlock on app resume.

### 12.5 API Performance & Availability
- **Connection Timeouts:** Change `connectTimeout` from 60s to 30s for better mobile reliability.
- **ProGuard/R8:** Add rules to `android/app/proguard-rules.pro` to prevent reverse-engineering of encryption logic.
- **App Integrity:** Verify Android 'Play Integrity API' and iOS 'App Attest' settings on the store consoles.

### 12.5 Socket.io
- **Production Event Names:** Confirm that the socket events (`market_rates`, `gold_rate`) match the production bullion server's definitions.
- **Auto-Reconnect:** Verify heartbeat intervals to maintain stable connections on mobile networks (3G/4G/5G).

### 12.6 Logging & Analytics
- **SecureLogger:** Double-check that `SecureLogger` is suppressing `[REDACTED]` fields in Release mode.
- **Analytics:** Enable production-level analytics (Firebase/AppCenter) to monitor transaction success rates and app stability.

---

## 13. âš™ï¸ AUTOMATION: SYNC RELEASE INFO

To avoid manually editing 10+ platform-specific files, use the integrated sync script.

### 13.1 Global Configuration
Edit the **`release_config.json`** file at the root of the project to change the app name or bundle identifier globally:
```json
{
    "app_name": "Start Gold",
    "bundle_id": "com.startgold.app",
    "version": "0.0.1",
    "build_number": 1
}
```

### 13.2 Running the Sync
Run the following command from the project root to apply the changes to Android Manifest, Gradle, Info.plist, and Kotlin sources:
```powershell
python scripts/update_release_info.py
```

### 13.3 What the script updates:
1.  **Android Label**: `AndroidManifest.xml` (the name on the home screen).
2.  **Android ID**: `build.gradle.kts` (`applicationId` & `namespace`).
3.  **Kotlin Package**: Moves `MainActivity.kt` and updates the `package` declaration.
4.  **iOS Label**: `Info.plist` (`CFBundleDisplayName`).
5.  **iOS Bundle ID**: `project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`).

---

## 14. ðŸ’¸ WITHDRAWAL APIs

### 14.1 Fetch Saved Accounts
Lists all saved UPI handles and bank accounts. First item is auto-selected in UI when only one exists.

- **Endpoint:** `POST profile/accountdetails`
- **Request:**
```json
{
  "id_customer": "1234",
  "mobile": "9876543210"
}
```
- **Response:**
```json
{
  "success": true,
  "message": "Account details fetched successfully",
  "data": {
    "accounts": [
      { "id_payout": "1", "upi_id": "user@okaxis", "upi_handle": "user@okaxis" },
      { "id_payout": "2", "bank_name": "SBI", "holder_name": "John Doe", "account_no": "012345678901", "ifsc_code": "SBIN0001234" }
    ]
  }
}
```

---

### 14.2 Verify & Add UPI Handle
- **Endpoint:** `POST account/verify-upi`
- **Encryption:** `upi_id` â†’ AES-256
- **Request:**
```json
{ "id_customer": "1234", "mobile": "9876543210", "upi_id": "<encrypted>" }
```
- **Response (success):**
```json
{ "success": true, "message": "UPI ID verified and saved successfully", "data": { "id_payout": "3", "upi_id": "user@okaxis", "status": "verified" } }
```
- **Response (failure):**
```json
{ "success": false, "message": "Invalid UPI ID. Please check and try again." }
```

---

### 14.3 Verify & Add Bank Account
- **Endpoint:** `POST account/verify-bank`
- **Encryption:** `account_no`, `ifsc_code` â†’ AES-256
- **Request:**
```json
{ "id_customer": "1234", "mobile": "9876543210", "account_holder": "John Doe", "account_no": "<encrypted>", "ifsc_code": "<encrypted>" }
```
- **Response (success):**
```json
{ "success": true, "message": "Bank account verified and saved", "data": { "id_payout": "4", "bank_name": "SBI", "holder_name": "John Doe", "account_no": "XXXX8901", "ifsc_code": "SBIN0001234", "status": "verified" } }
```
- **Response (failure):**
```json
{ "success": false, "message": "Bank account verification failed. Please check details." }
```

---

### 14.4 Submit Withdrawal
- **Endpoint:** `POST withdraw`
- **Encryption:** `withdrawal_amount`, `upi_id`, `transaction_pin` â†’ AES-256
- **Request:**
```json
{ "id_customer": "1234", "mobile": "9876543210", "withdrawal_amount": "<encrypted>", "upi_id": "<encrypted>", "transaction_pin": "<encrypted>" }
```
- **Response:**
```
{ "success": true, "message": "Withdrawal request submitted", "data": { "transaction_id": "TXN20240324001", "amount": 5000, "status": "PROCESSING", "estimated_time": "1-2 business days" } }
```

---

## 15. Transaction History & Details

### 15.1 Fetch Transaction History
- **Endpoint:** `POST transactions/history`
- **Request Body:**
```json
{
  "id_customer": "C101",
  "metal_type": "1", // General filter
  "page": 1,
  "limit": 20
}
```
- **Response:**
```json
{
  "success": true,
  "message": "Transactions retrieved successfully",
  "data": {
    "grouped_transactions": {
      "11 Mar 2026": [
        {
          "transaction_id": "TXN_11MAR_01",
          "title": "Instant Saving",
          "type": "purchase",
          "status": "Success",
          "amount": 10.00,
          "weight_grams": 0.000500,
          "metal_name": "Gold",
          "display_date": "11 Mar '26, 01:03pm"
        },
        {
          "transaction_id": "TXN_11MAR_02",
          "title": "Withdrawal",
          "type": "withdrawal",
          "status": "Success",
          "amount": 9.64,
          "weight_grams": 0.000600,
          "metal_name": "Gold",
          "display_date": "11 Mar '26, 11:07am"
        }
      ],
      "05 Feb 2025": [
        {
          "transaction_id": "TXN_05FEB_01",
          "title": "Instant Saving",
          "type": "purchase",
          "status": "Success",
          "amount": 10.00,
          "weight_grams": 0.001100,
          "metal_name": "Gold",
          "display_date": "05 Feb '25, 11:03am"
        }
      ]
    }
  }
}
```

---

### 15.2 Fetch Transaction Details
- **Endpoint:** `POST transactions/details`
- **Request Body:**
```json
{
  "id_customer": "C101",
  "transaction_id": "TXN_11MAR_01"
}
```
- **Response:**
```json
{
  "success": true,
  "message": "Transaction details retrieved successfully",
  "data": {
    "transaction_id": "TXN_11MAR_01",
    "title": "Instant Saving",
    "subtitle": "Gold purchased",
    "amount": 10.00,
    "weight_grams": 0.000500,
    "metal_name": "Gold",
    "timeline": [
      {
        "step_name": "Payment",
        "status": "Success",
        "time": "11 Mar '26, 01:03 PM"
      },
      {
        "step_name": "Gold order",
        "status": "Success",
        "time": "11 Mar '26, 01:03 PM"
      },
      {
        "step_name": "Gold purchase",
        "status": "Success",
        "time": "11 Mar '26, 01:03 PM"
      }
    ],
    "footer_message": "Gold has been added to your Jar locker.",
    "price_breakdown": {
      "gold_quantity": "0.000500 gm",
      "gold_rate": "₹16,577.19/gm",
      "gold_value": "â‚¹9.76",
      "gst": "â‚¹0.24",
      "total_amount": "â‚¹10"
    },
    "technical_details": {
      "transaction_id_display": "........4e9b64a",
      "gold_transaction_id": "........3DZ8B45",
      "placed_on": "11 Mar '26, 01:03 PM",
      "paid_via": "UPI"
    }
  }
}
```

---

### 15.3 Fetch SIP Transaction History
- **Page Name:** `SipTransactionHistoryScreen`
- **Endpoint:** `POST sip/transactions`
- **Authorization:** `Bearer Token`
- **Description:** Retrieves all SIP transaction history. Response structure is identical to `POST transactions/history`.
- **Request Body:** `{}` (empty — user identified from token)
- **Response:**
```json
{
  "success": true,
  "message": "SIP transactions retrieved successfully",
  "data": {
    "grouped_transactions": {
      "15 May 2026": [
        {
          "transaction_id": "SIP_15MAY_01",
          "title": "Auto Savings",
          "type": "purchase",
          "so_type": 1,
          "status": "Success",
          "amount": 100.00,
          "weight_grams": 0.006500,
          "metal_name": "Gold",
          "display_date": "15 May '26, 09:00am"
        }
      ]
    }
  }
}
```

---

### 15.4 Fetch SIP Transaction Details
- **Page Name:** `SipTransactionDetailsScreen`
- **Endpoint:** `POST sip/transaction-details`
- **Authorization:** `Bearer Token`
- **Description:** Fetches details for a single SIP transaction. Response structure is identical to `POST transactions/details`.
- **Request Body:**
```json
{
  "transaction_id": "SIP_15MAY_01"
}
```
- **Response:**
```json
{
  "success": true,
  "message": "SIP transaction details retrieved successfully",
  "data": {
    "transaction_id": "SIP_15MAY_01",
    "title": "Auto Savings",
    "subtitle": "Gold purchased via SIP",
    "amount": 100.00,
    "weight_grams": 0.006500,
    "metal_name": "Gold",
    "timeline": [
      {
        "step_name": "Payment",
        "status": "Success",
        "time": "15 May '26, 09:00 AM"
      },
      {
        "step_name": "Gold order",
        "status": "Success",
        "time": "15 May '26, 09:00 AM"
      },
      {
        "step_name": "Gold purchase",
        "status": "Success",
        "time": "15 May '26, 09:00 AM"
      }
    ],
    "footer_message": "Gold has been added to your Jar locker.",
    "price_breakdown": {
      "gold_quantity": "0.006500 gm",
      "gold_rate": "₹15,384.62/gm",
      "gold_value": "₹97.09",
      "gst": "₹2.91",
      "total_amount": "₹100"
    },
    "technical_details": {
      "transaction_id_display": "........abc1234",
      "gold_transaction_id": "........XYZ5678",
      "placed_on": "15 May '26, 09:00 AM",
      "paid_via": "Auto Debit"
    },
    "scheme_info": {
      "scheme_id": 1,
      "label": "Daily Gold SIP",
      "frequency": "Daily",
      "amount": "100",
      "total_saved": "3000",
      "cycles_done": 30,
      "status": "Active"
    }
  }
}
```

---

## Support / Enquiry

### Create Support Ticket
*   **Endpoint:** `POST support/create-ticket`
*   **Authorization:** Bearer token required
*   **Request Payload:**
    ```json
    {
      "type": 1,
      "subject": "Payment query",
      "content": "I have a question about my last payment."
    }
    ```

#### `type` Values
| Value | Label |
|---|---|
| `1` | General |
| `2` | Payment |
| `3` | Technical |
| `4` | Account |

*   **Response:**
    ```json
    {
      "success": true,
      "message": "Support request submitted successfully.",
      "data": {
        "id": 3,
        "on": "01/04/2026 05:59 am",
        "type": "Enquiry",
        "subject": "Payment query",
        "content": "I have a question about my last payment.",
        "status": "pending"
      }
    }
    ```

#### Status Values
| Value | Meaning |
|---|---|
| `pending` | Ticket received, awaiting review |
| `open` | Under investigation |
| `resolved` | Ticket closed |

---

### List My Tickets
*   **Endpoint:** `POST support/list`
*   **Authorization:** Bearer token required
*   **Payload:** `{}` (empty body â€” user identified from token)
*   **Response:**
    ```json
    {
      "success": true,
      "data": [
        {
          "id": 3,
          "on": "01/04/2026 05:59 am",
          "type": "Enquiry",
          "subject": "Payment query",
          "content": "I have a question about my last payment.",
          "status": "pending"
        }
      ]
    }
    ```

> **Note:** The client tries multiple response shapes:
> `data` as array â†’ `data.tickets` â†’ `data.enquiries` â†’ `data.data` â†’ `data.list`

---

## 12. ðŸ”” Notifications

> **Design Rule:** FCM push notifications are a **trigger only** â€” not a data source.
> The app ALWAYS fetches fresh data from the API when the notification screen opens.
> FCM payload is never rendered directly in the UI.

---

### 12.1 Get Notification List
*   **Page Name:** `NotificationsScreen`
*   **Endpoint:** `POST users/notifications`
*   **Authorization:** `Bearer Token`
*   **Trigger:** Called every time the Notifications screen opens (FCM tap or in-app navigation).
*   **Request Body:** `{}` (empty â€” user identified from token)
*   **Response:**
    ```json
    {
      "success": true,
      "data": [
        {
          "id": 1,
          "title": "Gold Price Alert",
          "message": "Gold increased â‚¹50 today. Check your portfolio!",
          "type": "market",
          "is_read": false,
          "created_at": "2026-04-17"
        },
        {
          "id": 2,
          "title": "Purchase Successful",
          "message": "You bought 0.0689g of Gold for â‚¹500.",
          "type": "transaction",
          "is_read": true,
          "created_at": "2026-04-16"
        }
      ]
    }
    ```
*   **`type` Values:**

    | Value | Icon | Colour |
    |---|---|---|
    | `market` | Chart icon | Blue |
    | `transaction` | Receipt icon | Green |
    | `kyc` | Shield icon | Purple |
    | `withdrawal` | Wallet icon | Amber |
    | `offer` | Tag icon | Pink |
    | *(default)* | Bell icon | Green |

*   **`is_read` Behaviour:**
    - `false` â†’ Card shown with **green dot badge** + **bold title** + light green background.
    - `true` â†’ Card shown in normal white/dark background, no badge.

---

### 12.2 Mark Notification as Read
*   **Page Name:** `NotificationsScreen` (triggered on item tap)
*   **Endpoint:** `POST users/notifications/read`
*   **Authorization:** `Bearer Token`
*   **Request Body:**
    ```json
    {
      "notification_id": 1
    }
    ```
*   **Response:**
    ```json
    {
      "success": true,
      "message": "Marked as read"
    }
    ```
*   **Client Behaviour:**
    - Optimistic update â€” UI is updated **immediately** on tap before the API call completes.
    - If the API call fails, the UI retains the optimistic state (next reload from `GET /notifications` corrects it).

---

### 12.3 Get Unread Notification Count (Badge)
*   **Usage:** Nav bar badge, home screen indicator.
*   **Endpoint:** `POST users/notifications/unread-count`
*   **Authorization:** `Bearer Token`
*   **Request Body:** `{}` (empty)
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "count": 3
      }
    }
    ```
*   **Client Provider:** `unreadCountProvider` â€” consumed by the navigation bar to show the red badge number.

---

### 12.4 FCM Push Notification Flow

```
Server sends FCM push
        â”‚
        â”œâ”€ App FOREGROUND  â†’ flutter_local_notifications shows heads-up banner
        â”‚
        â””â”€ User TAPS notification (any app state)
                 â”‚
                 â–¼
        Navigate to /notifications  (AppRouter.notifications)
                 â”‚
                 â–¼
        NotificationsScreen opens â†’ calls POST users/notifications
                 â”‚
                 â–¼
        Renders fresh list from API
                 â”‚
                 â–¼
        User taps item â†’ POST users/notifications/read
                 â”‚
                 â–¼
        Optimistic UI update (green dot removed)
```

*   **FCM Token Registration:** After login, retrieve `FcmService.getToken()` and send it to your backend so the server can push to this specific device.
*   **Token Refresh:** Listen to `FcmService.onTokenRefresh` and update the backend whenever the token changes.
*   **Background Handler:** `_firebaseMessagingBackgroundHandler` â€” top-level function, logs only. Does NOT navigate.

---

### 12.5 Notification Data Security Rules

| Rule | Detail |
|---|---|
| FCM payload | **Display only** â€” never contains financial data |
| Sensitive data | **Never** sent via push notification payload |
| Navigation | Always triggered by notification **tap** not by payload content |
| Data source | Always fetched **fresh from API**, never from FCM payload |

---

## 16. ðŸ—‘ï¸ Delete Account

> **Security Note:** Both endpoints require a valid `Authorization: Bearer <token>`. No sensitive fields are encrypted (policy info and the `confirm` flag carry no PII). Data wipe happens server-side on success.

### 16.1 Fetch Delete Account Info
- **Page Name:** `DeleteAccountScreen`
- **Endpoint:** `POST delete-account/info`
- **Authorization:** `Bearer Token`
- **Trigger:** Called automatically on page load.
- **Request Body:**
  ```json
  {}
  ```
- **Response:**
  ```json
  {
    "success": true,
    "data": {
      "content": "Deleting your account will permanently remove all data including your portfolio, transaction history, and referral rewards. This action cannot be undone.",
      "is_allowed": true
    }
  }
  ```
- **Fields:**

  | Field | Type | Description |
  |-------|------|-------------|
  | `content` | String | Policy / warning text rendered in the info card on screen |
  | `is_allowed` | Boolean | Controls visibility of the "Delete My Account" confirm button |

- **`is_allowed` UI Behaviour:**

  | Value | Client Behaviour |
  |---|---|
  | `true` | "Delete My Account" button shown in the footer |
  | `false` | Footer button **completely hidden** â€” user cannot proceed |

- **On API Error:** Screen shows an error state with a **Retry** button; no destructive action is possible.

---

### 16.2 Confirm Account Deletion
- **Page Name:** `DeleteAccountScreen` (triggered after user confirms the dialog)
- **Endpoint:** `POST delete-account`
- **Authorization:** `Bearer Token`
- **Trigger:** Called only after:
  1. `is_allowed == true` (from 16.1)
  2. User taps the "Delete My Account" button
  3. User confirms "Yes, Delete" in the confirmation dialog
- **Request Body:**
  ```json
  {
    "confirm": true
  }
  ```
- **Response (Success):**
  ```json
  {
    "success": true,
    "message": "Account deleted successfully."
  }
  ```
- **Response (Failure):**
  ```json
  {
    "success": false,
    "message": "Unable to delete account. Please contact support."
  }
  ```

#### Client Behaviour on Success
All local data is cleared in this order before navigating away:

| Storage Layer | Action |
|---|---|
| `FlutterSecureStorage` | `SecureStorageService.logout()` â†’ `deleteAll()` |
| `SharedPreferences` | `prefs.clear()` |
| Navigation | `Navigator.pushNamedAndRemoveUntil('/login', (route) => false)` |

#### Client Behaviour on Failure
- Error `AppToast` shown with the server's `message`.
- **No data is cleared.**
- Button is re-enabled; user can retry or navigate away.

#### Confirmation Dialog
A `showGeneralDialog` dialog with a scale+fade animation is shown **before** the API call:

> *"Are you sure you want to delete your account?"*  
> *"All data will be permanently erased and cannot be recovered."*

- **Cancel** â†’ dismisses dialog, no API call made.
- **Yes, Delete** â†’ proceeds to call `POST delete-account`.

---
---

# Content â€“ Refund Policy API

## 10. Refund Policy

### `POST /content/refund-policy`

Fetches the refund policy content for the application.

**Request:** No body required (POST with empty payload or `{}`).

**Response:**
```json
{
  "success": true,
  "data": {
    "content": "Refund Policy content text goes here. This can include HTML or plain text as returned by the backend."
  }
}
```

| Field | Type | Description |
|---|---|---|
| `content` | String | The refund policy text/HTML content to display |

> **Note:** This API follows the same pattern as `POST /content/terms`, `POST /content/privacy`, and `POST /content/about-us`. The app renders the `content` field as plain text in a scrollable view.

---
---

# Nominee Management APIs

## 13. Nominee

### 13.1 Fetch Nominee Relationship List (Dynamic)

*   **Endpoint:** `POST users/nominee/update/relationships`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Fetches the list of valid nominee relationships dynamically from the server. This replaces the previously hardcoded relationship list and allows the backend to control relationship options.
*   **Request Body:**
    ```json
    {}
    ```
*   **Response (Success):**
    ```json
    {
      "success": true,
      "data": {
        "relationships": [
          {
            "id": 1,
            "name": "Father"
          },
          {
            "id": 2,
            "name": "Mother"
          },
          {
            "id": 3,
            "name": "Spouse"
          },
          {
            "id": 4,
            "name": "Son"
          },
          {
            "id": 5,
            "name": "Daughter"
          },
          {
            "id": 6,
            "name": "Brother"
          },
          {
            "id": 7,
            "name": "Sister"
          },
          {
            "id": 8,
            "name": "Other"
          }
        ]
      }
    }
    ```
*   **Response (Error):**
    ```json
    {
      "success": false,
      "message": "Unable to fetch relationship list"
    }
    ```

| Field | Type | Description |
|---|---|---|
| `relationships` | Array | List of relationship objects |
| `relationships[].id` | Integer | Unique identifier for the relationship type |
| `relationships[].name` | String | Display name of the relationship (used in the dropdown) |

*   **Client Usage:**
    - Called once when the Nominee form screen is opened.
    - Populates the "Relationship" dropdown dynamically.
    - Falls back to a hardcoded list if the API fails, ensuring the form remains functional.
*   **Client Provider:** `nomineeRelationshipsProvider` â€” fetches and caches the relationship list.

---

### 13.2 Fetch Nominee Details

*   **Endpoint:** `POST user/nominee/details`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Retrieves the currently saved nominee details for the logged-in user.
*   **Request Body:**
    ```json
    {}
    ```
*   **Response (Success â€” nominee exists):**
    ```json
    {
      "success": true,
      "data": {
        "name": "John Doe",
        "relationship": "Father",
        "dob": "1970-05-15",
        "mobile": "9876543210",
        "email": "john@example.com",
        "address": "123 Main Street",
        "city": "Mumbai",
        "state": "Maharashtra",
        "pincode": "400001"
      }
    }
    ```
*   **Response (Success â€” no nominee):**
    ```json
    {
      "success": true,
      "data": {}
    }
    ```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | String | Yes | Full name of the nominee |
| `relationship` | String | Yes | Relationship with the user (from relationship list) |
| `dob` | String | Yes | Date of birth in `yyyy-MM-dd` format |
| `mobile` | String | Yes | 10-digit mobile number |
| `email` | String | No | Email address |
| `address` | String | No | Street address |
| `city` | String | No | City name (auto-filled from pincode) |
| `state` | String | No | State name (auto-filled from pincode) |
| `pincode` | String | No | 6-digit pincode |

*   **Client Provider:** `nomineeDetailsProvider` â€” auto-fetched when NomineeScreen loads.

---

### 13.3 Create / Update Nominee

*   **Endpoint:** `POST users/nominee/update`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Creates or updates the nominee details for the logged-in user.
*   **Request Body:**
    ```json
    {
      "name": "John Doe",
      "relationship": "Father",
      "relationship_id": 1,
      "dob": "1970-05-15",
      "mobile": "9876543210",
      "email": "john@example.com",
      "address": "123 Main Street",
      "city": "Mumbai",
      "state": "Maharashtra",
      "pincode": "400001",
      "id_city": 456,
      "id_state": 78,
      "id_country": 101
    }
    ```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | String | Yes | Full name of the nominee |
| `relationship` | String | Yes | Relationship name (e.g. "Father") |
| `relationship_id` | Int | No | Relationship ID from `/relationships` API |
| `dob` | String | Yes | Date of birth in `yyyy-MM-dd` format |
| `mobile` | String | Yes | 10-digit mobile number |
| `email` | String | No | Email address |
| `address` | String | No | Street address |
| `city` | String | No | City name (auto-filled via pincode check) |
| `state` | String | No | State name (auto-filled via pincode check) |
| `pincode` | String | No | 6-digit pincode |
| `id_city` | Int | No | City ID from pincode check |
| `id_state` | Int | No | State ID from pincode check |
| `id_country` | Int | No | Country ID (default: 101 for India) |

*   **Response (Success):**
    ```json
    {
      "success": true,
      "message": "Nominee updated successfully"
    }
    ```
*   **Response (Error):**
    ```json
    {
      "success": false,
      "message": "Failed to update nominee"
    }
    ```
*   **Client Action:** On success, invalidates `nomineeDetailsProvider` to refetch and switches back to view mode.

---

## 14. Notifications

### 14.1 Fetch Notifications List
*   **Page Name:** `NotificationsScreen`
*   **Endpoint:** `POST users/notifications`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Retrieves the full list of notifications for the logged-in user.
*   **Request Body:** `{}`
*   **Response:**
    ```json
    {
      "success": true,
      "data": [
        {
          "id": 1,
          "title": "Gold Purchase Successful",
          "message": "Your purchase of 0.5g Gold has been confirmed.",
          "type": "transaction",
          "is_read": false,
          "created_at": "2026-05-20T10:30:00Z"
        },
        {
          "id": 2,
          "title": "KYC Approved",
          "message": "Your KYC verification is now complete.",
          "type": "kyc",
          "is_read": true,
          "created_at": "2026-05-19T14:00:00Z"
        }
      ]
    }
    ```
*   **Fields:**

    | Field | Type | Description |
    |-------|------|-------------|
    | `id` | Int | Unique notification identifier |
    | `title` | String | Notification heading |
    | `message` | String | Notification body text |
    | `type` | String | Category (e.g. `transaction`, `kyc`, `promo`, `system`) |
    | `is_read` | Bool/Int | `true` / `1` = read, `false` / `0` = unread |
    | `created_at` | String | ISO 8601 timestamp |

*   **Client Provider:** `notificationProvider` â€” `StateNotifier` that holds the full list + unread count.

---

### 14.2 Mark Notification as Read
*   **Page Name:** `NotificationsScreen`
*   **Endpoint:** `POST users/notifications/read`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Marks a single notification as read.
*   **Request Body:**
    ```json
    {
      "notification_id": 1
    }
    ```

    | Field | Type | Required | Description |
    |-------|------|----------|-------------|
    | `notification_id` | Int | Yes | ID of the notification to mark as read |

*   **Response:**
    ```json
    {
      "success": true,
      "message": "Notification marked as read"
    }
    ```
*   **Client Action:** Optimistic update â€” the notification is marked as read locally immediately; unread count is recomputed.

---

### 14.3 Mark All Notifications as Read
*   **Page Name:** `NotificationsScreen`
*   **Endpoint:** `POST users/notifications/read-all`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Marks every notification as read in a single call.
*   **Request Body:** `{}`
*   **Response:**
    ```json
    {
      "success": true,
      "message": "All notifications marked as read"
    }
    ```
*   **Client Action:** Optimistic update â€” all local notifications set to `isRead: true`, unread count reset to `0`.

---

### 14.4 Delete Notification
*   **Page Name:** `NotificationsScreen`
*   **Endpoint:** `POST users/notifications/delete`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Permanently deletes a single notification.
*   **Request Body:**
    ```json
    {
      "notification_id": 1
    }
    ```

    | Field | Type | Required | Description |
    |-------|------|----------|-------------|
    | `notification_id` | Int | Yes | ID of the notification to delete |

*   **Response:**
    ```json
    {
      "success": true,
      "message": "Notification deleted"
    }
    ```
*   **Client Action:** On success, the notification is removed from the local list and the unread count is recomputed. On failure (including `409` session conflict), the card stays in place.

---

### 14.5 Fetch Unread Count
*   **Page Name:** `HomeScreen` (nav bar badge), `NotificationsScreen`
*   **Endpoint:** `POST users/notifications/unread-count`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Returns the number of unread notifications for the badge indicator on the nav bar / home screen.
*   **Request Body:** `{}`
*   **Response:**
    ```json
    {
      "success": true,
      "data": {
        "count": 5
      }
    }
    ```

    > [!NOTE]
    > The client handles multiple response shapes for backwards compatibility:
    > `{ "data": { "count": N } }`, `{ "data": { "unread_count": N } }`, `{ "data": N }`, or top-level `{ "count": N }` / `{ "unread_count": N }`.

*   **Client Provider:** `unreadCountProvider` â€” lightweight provider derived from `notificationProvider`, used by the nav bar badge.

---

### 14.6 Register FCM Device Token
*   **Endpoint:** `POST users/notifications/register-token`
*   **Authorization:** `Bearer Token`
*   **Purpose:** Registers (or updates) the device's FCM push-notification token on the server so the backend can target this specific device for push delivery. The device metadata is also used to populate the **"New device attempting login"** security notification card.
*   **Trigger:** Called automatically after Firebase returns a new or refreshed token. The client deduplicates: if the stored token matches the new token, the call is skipped.
*   **Request Body:**
    ```json
    {
      "fcm_token": "dGhpcyBpcyBhIHNhbXBsZSBGQ00gdG9rZW4...",
      "device_id": "uuid-abc-123",
      "device_type": "android",
      "device_model": "Galaxy S24 Ultra",
      "device_name": "e3q",
      "os": "Android",
      "os_version": "14",
      "manufacturer": "Samsung Electronics",
      "brand": "samsung",
      "hardware_id": "SM-S928B"
    }
    ```

    | Field | Type | Required | Description |
    |-------|------|----------|-------------|
    | `fcm_token` | String | Yes | Firebase Cloud Messaging device token |
    | `device_id` | String | Yes | Unique device identifier (from `DeviceIdService`) |
    | `device_type` | String | Yes | `"android"` or `"ios"` |
    | `device_model` | String | Yes | Device model name (e.g. `"Galaxy S24 Ultra"`, `"iPhone"`) |
    | `device_name` | String | Yes | Internal device codename / user-facing name (e.g. `"e3q"`, `"John's iPhone"`) |
    | `os` | String | Yes | Operating system name (`"Android"` / `"iOS"`) |
    | `os_version` | String | Yes | OS version string (e.g. `"14"`, `"17.4"`) |
    | `manufacturer` | String | Yes | Device manufacturer (e.g. `"Samsung Electronics"`, `"Apple"`) |
    | `brand` | String | Yes | Device brand (e.g. `"samsung"`, `"Apple"`) |
    | `hardware_id` | String | Yes | Hardware product ID â€” Android: `product` (e.g. `"SM-S928B"`), iOS: `utsname.machine` (e.g. `"iPhone15,2"`) |

*   **Response:**
    ```json
    {
      "success": true,
      "message": "Device token registered successfully"
    }
    ```
*   **Deduplication:** The FCM token is persisted in `SecureStorage`. On each Firebase token refresh, the client compares old vs new â€” if unchanged, the API call is skipped entirely.
*   **Failure Handling:** Registration failures are logged via `debugPrint` but silently swallowed â€” push notifications are non-critical and must not block the user experience.

> [!NOTE]
> **Security card mapping:** The server uses these fields to build the "New device attempting login" notification:
>
> | Card field | API field(s) |
> |---|---|
> | Device title | `device_model` |
> | Manufacturer | `manufacturer` |
> | Model | `device_model` + `hardware_id` (e.g. "Galaxy S24 Ultra (SM-S928B)") |
> | Operating System | `os` + `os_version` |
> | IP Address | Extracted server-side from the request |
> | Location | Derived server-side from IP geolocation |

> [!IMPORTANT]
> This endpoint does **not** require field-level encryption. The FCM token and device metadata are non-sensitive public identifiers.

---

## 15. Countdown Offer (100-Day Grand Launch)

### 15.1 Fetch Countdown Offer Configuration
*   **Page Name:** `HomeScreen`
*   **Widget:** `CountdownOfferWidget` (orchestrator) â†’ `CountdownOfferNew` / `CountdownOfferExisting`
*   **Endpoint:** `POST home/countdown-offer`
*   **Authorization:** `Bearer Token`
*   **Description:** Settings-driven offer widget. Returns whether the offer is enabled and, if so, the customer-specific payload (NEW or EXISTING). Admin can toggle/modify from the backend without app release.
*   **Encryption:** âŒ Not required â€” public display data (same category as `/gold-rate`, `/schemes`).
*   **Trigger:** Called on home screen load, tab switch, and pull-to-refresh.
*   **Provider:** `countdownOfferProvider` (auto-dispose, watches `userProvider`)

*   **Response (New Customer â€” offer enabled):**
    ```json
    {
      "success": true,
      "data": {
        "enabled": true,
        "customer_type": "NEW",
        "new_offer": {
          "offer_name": "100-DAY GRAND LAUNCH",
          "offer_start_date": "MAY 15",
          "offer_end_date": "AUG 23",
          "remaining_days": 98,
          "remaining_hours": 15,
          "remaining_minutes": 32,
          "remaining_seconds": 48,
          "reward_percentage": 78,
          "daily_penalty_percentage": 1,
          "benchmark_amount": 50000,
          "benchmark_percentage": 100,
          "cta_text": "Start Investing"
        },
        "know_more_bottom_sheet": {
          "type": "container",
          "decoration": {
            "gradient": {
              "gradientType": "linear",
              "begin": "topCenter",
              "end": "bottomCenter",
              "colors": ["#FFF8EE", "#FFF3DD"]
            }
          },
          "child": {
            "type": "column",
            "mainAxisSize": "min",
            "children": [
              {
                "type": "flexible",
                "child": {
                  "type": "singleChildScrollView",
                  "padding": {"left": 20, "top": 16, "right": 20, "bottom": 16},
                  "child": {
                    "type": "column",
                    "crossAxisAlignment": "start",
                    "children": [
                      {
                        "type": "richText",
                        "spans": [
                          {"text": "Your ", "style": {"fontSize": 24, "fontWeight": "w700", "color": "#000000", "fontFamily": "PlayfairDisplay"}},
                          {"text": "Rewards", "style": {"fontSize": 24, "fontWeight": "w700", "color": "#1B882C", "fontFamily": "PlayfairDisplay"}},
                          {"text": ",", "style": {"fontSize": 24, "fontWeight": "w700", "color": "#000000", "fontFamily": "PlayfairDisplay"}}
                        ]
                      },
                      {
                        "type": "text",
                        "data": "Explained Clearly",
                        "style": {"fontSize": 24, "fontWeight": "w700", "color": "#000000", "fontFamily": "PlayfairDisplay"}
                      },
                      {"type": "sizedBox", "height": 20},
                      {
                        "type": "card",
                        "elevation": 2,
                        "color": "#FFFFFF",
                        "borderRadius": {"all": 16},
                        "child": {
                          "type": "container",
                          "padding": {"left": 16, "top": 16, "right": 16, "bottom": 16},
                          "child": {
                            "type": "row",
                            "crossAxisAlignment": "start",
                            "children": [
                              {
                                "type": "container",
                                "width": 28,
                                "height": 28,
                                "decoration": {"color": "#E8F5E9", "borderRadius": {"all": 14}},
                                "child": {"type": "center", "child": {"type": "icon", "iconType": "info", "size": 16, "color": "#1B882C"}}
                              },
                              {"type": "sizedBox", "width": 12},
                              {
                                "type": "expanded",
                                "child": {
                                  "type": "text",
                                  "data": "Your reward percentage is locked based on the day you begin your gold saving journey.",
                                  "style": {"fontSize": 13, "fontWeight": "w400", "color": "#555555", "height": 1.5}
                                }
                              },
                              {"type": "sizedBox", "width": 8},
                              {
                                "type": "assetImage",
                                "asset": "assets/offer/gold-silver-offer.png",
                                "width": 72,
                                "height": 72,
                                "fit": "contain"
                              }
                            ]
                          }
                        }
                      },
                      {"type": "sizedBox", "height": 12},
                      {
                        "type": "card",
                        "elevation": 2,
                        "color": "#FFFFFF",
                        "borderRadius": {"all": 16},
                        "child": {
                          "type": "container",
                          "padding": {"left": 16, "top": 16, "right": 16, "bottom": 16},
                          "child": {
                            "type": "column",
                            "crossAxisAlignment": "start",
                            "children": [
                              {
                                "type": "row",
                                "children": [
                                  {
                                    "type": "container",
                                    "width": 32,
                                    "height": 32,
                                    "decoration": {"color": "#064E3B", "borderRadius": {"all": 16}},
                                    "child": {"type": "center", "child": {"type": "icon", "iconType": "star", "size": 18, "color": "#FFFFFF"}}
                                  },
                                  {"type": "sizedBox", "width": 12},
                                  {
                                    "type": "expanded",
                                    "child": {
                                      "type": "text",
                                      "data": "Turn Your Gold Savings\ninto Silver Rewards",
                                      "style": {"fontSize": 15, "fontWeight": "w700", "color": "#000000", "height": 1.3}
                                    }
                                  }
                                ]
                              },
                              {"type": "sizedBox", "height": 12},
                              {
                                "type": "text",
                                "data": "Celebrate our launch with exclusive daily silver benefits for early investors.\n\nEarly participation unlocks maximum rewards.",
                                "style": {"fontSize": 13, "fontWeight": "w400", "color": "#555555", "height": 1.5}
                              }
                            ]
                          }
                        }
                      },
                      {"type": "sizedBox", "height": 20},
                      {
                        "type": "row",
                        "children": [
                          {
                            "type": "container",
                            "width": 28,
                            "height": 28,
                            "decoration": {"color": "#E8F5E9", "borderRadius": {"all": 14}},
                            "child": {"type": "center", "child": {"type": "icon", "iconType": "info", "size": 16, "color": "#064E3B"}}
                          },
                          {"type": "sizedBox", "width": 10},
                          {"type": "text", "data": "Educational Card", "style": {"fontSize": 16, "fontWeight": "w700", "color": "#000000"}}
                        ]
                      },
                      {"type": "sizedBox", "height": 12},
                      {
                        "type": "container",
                        "decoration": {
                          "border": {"color": "#40DE6A02", "width": 1},
                          "borderRadius": {"all": 12}
                        },
                        "child": {
                          "type": "column",
                          "children": [
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 12, "right": 16, "bottom": 12},
                              "decoration": {"color": "#064E3B", "borderRadius": {"topLeft": 12, "topRight": 12}},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Investment Day", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#FFFFFF"}},
                                  {"type": "text", "data": "Silver Benefit", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#FFFFFF"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 10, "right": 16, "bottom": 10},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 1", "style": {"fontSize": 13, "color": "#333333"}},
                                  {"type": "text", "data": "100%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#1B882C"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 10, "right": 16, "bottom": 10},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 10", "style": {"fontSize": 13, "color": "#333333"}},
                                  {"type": "text", "data": "91%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#1B882C"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 10, "right": 16, "bottom": 10},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 50", "style": {"fontSize": 13, "color": "#333333"}},
                                  {"type": "text", "data": "51%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#1B882C"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 10, "right": 16, "bottom": 10},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 91 ~ 100", "style": {"fontSize": 13, "color": "#333333"}},
                                  {"type": "text", "data": "Flat 10%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#1B882C"}}
                                ]
                              }
                            }
                          ]
                        }
                      },
                      {"type": "sizedBox", "height": 20},
                      {
                        "type": "card",
                        "elevation": 2,
                        "color": "#FFFFFF",
                        "borderRadius": {"all": 16},
                        "child": {
                          "type": "container",
                          "padding": {"left": 16, "top": 16, "right": 16, "bottom": 16},
                          "child": {
                            "type": "column",
                            "children": [
                              {
                                "type": "row",
                                "crossAxisAlignment": "start",
                                "children": [
                                  {
                                    "type": "container",
                                    "width": 28,
                                    "height": 28,
                                    "decoration": {"color": "#E8F5E9", "borderRadius": {"all": 14}},
                                    "child": {"type": "center", "child": {"type": "icon", "iconType": "check", "size": 16, "color": "#1B882C"}}
                                  },
                                  {"type": "sizedBox", "width": 12},
                                  {
                                    "type": "expanded",
                                    "child": {
                                      "type": "text",
                                      "data": "You can redeem your accumulated gold after 100 days, either as FIAT or in the form of a gold bar/coin.",
                                      "style": {"fontSize": 12, "fontWeight": "w400", "color": "#555555", "height": 1.5}
                                    }
                                  }
                                ]
                              },
                              {"type": "sizedBox", "height": 14},
                              {
                                "type": "row",
                                "crossAxisAlignment": "start",
                                "children": [
                                  {
                                    "type": "container",
                                    "width": 28,
                                    "height": 28,
                                    "decoration": {"color": "#FFF3E0", "borderRadius": {"all": 14}},
                                    "child": {"type": "center", "child": {"type": "icon", "iconType": "info", "size": 16, "color": "#E65100"}}
                                  },
                                  {"type": "sizedBox", "width": 12},
                                  {
                                    "type": "expanded",
                                    "child": {
                                      "type": "text",
                                      "data": "Bonus silver will be eligible for redemption from the 101st day onwards and can be redeemed as FIAT only.",
                                      "style": {"fontSize": 12, "fontWeight": "w400", "color": "#555555", "height": 1.5}
                                    }
                                  }
                                ]
                              }
                            ]
                          }
                        }
                      },
                      {"type": "sizedBox", "height": 12},
                      {
                        "type": "card",
                        "elevation": 0,
                        "color": "#F0FAF1",
                        "borderRadius": {"all": 16},
                        "child": {
                          "type": "container",
                          "padding": {"left": 16, "top": 16, "right": 16, "bottom": 16},
                          "decoration": {
                            "border": {"color": "#40388E3C", "width": 1},
                            "borderRadius": {"all": 16}
                          },
                          "child": {
                            "type": "row",
                            "crossAxisAlignment": "start",
                            "children": [
                              {
                                "type": "container",
                                "width": 32,
                                "height": 32,
                                "decoration": {"color": "#064E3B", "borderRadius": {"all": 16}},
                                "child": {"type": "center", "child": {"type": "icon", "iconType": "star", "size": 18, "color": "#FFD700"}}
                              },
                              {"type": "sizedBox", "width": 12},
                              {
                                "type": "expanded",
                                "child": {
                                  "type": "text",
                                  "data": "The earlier you start, the more you earn.\nDon't miss out on maximum rewards!",
                                  "style": {"fontSize": 13, "fontWeight": "w600", "color": "#064E3B", "height": 1.5}
                                }
                              }
                            ]
                          }
                        }
                      }
                    ]
                  }
                }
              },
              {
                "type": "padding",
                "padding": {"left": 41, "top": 8, "right": 41, "bottom": 20},
                "child": {
                  "type": "elevatedButton",
                  "style": {
                    "foregroundColor": "#064E3B",
                    "gradient": {
                      "gradientType": "linear",
                      "begin": "centerLeft",
                      "end": "centerRight",
                      "colors": ["#FFB500", "#FFCA49"]
                    },
                    "shape": {
                      "type": "roundedRectangle",
                      "borderRadius": {"all": 50}
                    }
                  },
                  "child": {
                    "type": "text",
                    "data": "Start Investing",
                    "style": {"fontSize": 16, "fontWeight": "w700"}
                  },
                  "onPressed": {
                    "actionType": "navigate",
                    "request": {
                      "routeName": "/instantSaving"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    }
    ```
*   **Response (Existing Customer â€” offer enabled):**
    ```json
    {
      "success": true,
      "data": {
        "enabled": true,
        "customer_type": "EXISTING",
        "existing_offer": {
          "offer_name": "100-DAY GRAND LAUNCH",
          "silver_earned": "0.006300",
          "invest_days": 2,
          "days_remaining": 98,
          "current_reward_percentage": 98,
          "offer_end_date": "Aug 23",
          "cta_text": "Add Investment"
        },
        "know_more_bottom_sheet": {
          "type": "container",
          "decoration": {
            "gradient": {
              "gradientType": "linear",
              "begin": "topCenter",
              "end": "bottomCenter",
              "colors": ["#FFF8E4", "#FFDF92"]
            },
            "borderRadius": {
              "topLeft": 28,
              "topRight": 28
            }
          },
          "child": {
            "type": "column",
            "mainAxisSize": "min",
            "children": [
              {
                "type": "flexible",
                "child": {
                  "type": "singleChildScrollView",
                  "padding": {"left": 24, "top": 16, "right": 24, "bottom": 16},
                  "child": {
                    "type": "column",
                    "crossAxisAlignment": "start",
                    "children": [
                      {
                        "type": "align",
                        "alignment": "topRight",
                        "child": {
                          "type": "iconButton",
                          "icon": {"type": "icon", "iconType": "close", "size": 24, "color": "#88000000"},
                          "onPressed": {"actionType": "navigateBack"}
                        }
                      },
                      {
                        "type": "text",
                        "data": "Offer Benefits:",
                        "style": {"fontSize": 18, "fontWeight": "w700", "color": "#DE000000"}
                      },
                      {"type": "sizedBox", "height": 12},
                      {
                        "type": "text",
                        "data": "Your reward percentage is locked based on the day you begin your journey.",
                        "style": {"fontSize": 13, "fontWeight": "w400", "color": "#88000000", "height": 1.5}
                      },
                      {"type": "sizedBox", "height": 20},
                      {
                        "type": "text",
                        "data": "Turn Your Gold Investments into Silver Rewards",
                        "style": {"fontSize": 16, "fontWeight": "w700", "color": "#DE000000"}
                      },
                      {"type": "sizedBox", "height": 12},
                      {
                        "type": "text",
                        "data": "Celebrate our launch with exclusive daily silver benefits for early investors.\n\nEarly participation unlocks maximum rewards.",
                        "style": {"fontSize": 13, "fontWeight": "w400", "color": "#88000000", "height": 1.5}
                      },
                      {"type": "sizedBox", "height": 24},
                      {
                        "type": "text",
                        "data": "Educational Card",
                        "style": {"fontSize": 16, "fontWeight": "w700", "color": "#DE000000"}
                      },
                      {"type": "sizedBox", "height": 12},
                      {
                        "type": "container",
                        "decoration": {
                          "border": {"color": "#40DE6A02", "width": 1},
                          "borderRadius": {"all": 12}
                        },
                        "child": {
                          "type": "column",
                          "children": [
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 12, "right": 16, "bottom": 12},
                              "color": "#80FFFFFF",
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Investment Day", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#064E3B"}},
                                  {"type": "text", "data": "Silver Benefit", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#064E3B"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 8, "right": 16, "bottom": 8},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 1", "style": {"fontSize": 13, "color": "#000000"}},
                                  {"type": "text", "data": "100%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#000000"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 8, "right": 16, "bottom": 8},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 10", "style": {"fontSize": 13, "color": "#000000"}},
                                  {"type": "text", "data": "91%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#000000"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 8, "right": 16, "bottom": 8},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 50", "style": {"fontSize": 13, "color": "#000000"}},
                                  {"type": "text", "data": "51%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#000000"}}
                                ]
                              }
                            },
                            {
                              "type": "container",
                              "padding": {"left": 16, "top": 8, "right": 16, "bottom": 8},
                              "child": {
                                "type": "row",
                                "mainAxisAlignment": "spaceBetween",
                                "children": [
                                  {"type": "text", "data": "Day 91-100", "style": {"fontSize": 13, "color": "#000000"}},
                                  {"type": "text", "data": "Flat 10%", "style": {"fontSize": 13, "fontWeight": "w700", "color": "#000000"}}
                                ]
                              }
                            }
                          ]
                        }
                      },
                      {"type": "sizedBox", "height": 20},
                      {
                        "type": "text",
                        "data": "â€¢ User can redeem their gold anytime as FIAT, gold coin/bar redemption available only after Day 100.\nâ€¢ FIAT redemption between Day 1 â€“ 50 forfeits the Bonus Silver offer.\nâ€¢ Bonus Silver redeemable from Day 51 onwards as FIAT money.\nâ€¢ Additional Bonus Silver redemption available only after Day 100.",
                        "style": {"fontSize": 12, "fontWeight": "w400", "color": "#88000000", "height": 1.5}
                      }
                    ]
                  }
                }
              },
              {
                "type": "padding",
                "padding": {"left": 24, "top": 8, "right": 24, "bottom": 16},
                "child": {
                  "type": "elevatedButton",
                  "style": {
                    "backgroundColor": "#1B882C",
                    "foregroundColor": "#FFFFFF",
                    "shape": {
                      "type": "roundedRectangle",
                      "borderRadius": {"all": 50}
                    }
                  },
                  "child": {
  "status": true,
  "message": "You will be notified when this service launches!"
}
```

> [!NOTE]
> **Current Implementation:** Tapping "Notify Me" shows a local success toast. No API call is made. When the backend endpoint is ready, wire this to a `JewelleryService.registerNotify()` call.

> [!IMPORTANT]
> This is **non-sensitive data** — NO field-level encryption is required.



---

## 13. JEWELLERY MODULE

Display-only "Coming Soon" landing page. Card images fetched from API.

---

### 13.1 POST `/jewellery/jewellery-image`

**Purpose:** Fetch category card images for the Jewellery screen.

**When Called:** User taps Jewellery tab.

**Authentication:** `Bearer <token>` (via interceptor)

**Request Body:** _(empty)_

**Response:**

```json
{
  "success": true,
  "message": "Jewellery images fetched successfully",
  "data": [
    { "image_url": "https://startgoldapi.logimaxindia.com/api/media/images/jewellery_page/ecommerce.png" },
    { "image_url": "https://startgoldapi.logimaxindia.com/api/media/images/jewellery_page/retail.png" },
    { "image_url": "https://startgoldapi.logimaxindia.com/api/media/images/jewellery_page/direct_outlets.png" }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `image_url` | string | Full URL to the category card image |

> [!IMPORTANT]
> This is **public display data** - NO field-level encryption is required.