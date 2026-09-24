# Security Architecture — startGOLD

startGOLD implements enterprise-grade security following **OWASP MASVS** (Mobile Application Security Verification Standard) guidelines.

---

## Security Layer Overview

```
┌───────────────────────────────────────────────────────┐
│                    RUNTIME PROTECTION                  │
│  Root/Jailbreak Detection │ Screen Protection          │
│  App Lifecycle Observer   │ Orientation Lock            │
├───────────────────────────────────────────────────────┤
│                    NETWORK SECURITY                    │
│  SSL Certificate Pinning  │ RSA Payload Encryption     │
│  API Interceptor          │ Token Management            │
├───────────────────────────────────────────────────────┤
│                    DATA PROTECTION                     │
│  Secure Storage (Keychain/Keystore)                    │
│  Secure Logger (PII Redaction)                         │
│  Session Manager (Force Logout)                        │
├───────────────────────────────────────────────────────┤
│                    AUTH PROTECTION                      │
│  OTP-based Authentication │ MPIN Verification          │
│  Biometric Auth           │ Session Invalidation        │
└───────────────────────────────────────────────────────┘
```

---

## 1. Root / Jailbreak Detection

**File**: [root_detection_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/root_detection_service.dart)

- Runs at app startup (before `runApp`)
- Uses `root_checker_plus` package
- If device is rooted/jailbroken:
  - Shows `CompromisedDeviceScreen`
  - App exits — no further access allowed
- Only runs on mobile (skipped on web)

```dart
if (!kIsWeb) {
  bool isCompromised = await RootDetectionService.isDeviceCompromised();
  if (isCompromised) {
    runApp(MaterialApp(home: CompromisedDeviceScreen()));
    return; // EXIT
  }
}
```

---

## 2. SSL Certificate Pinning

**File**: [certificate_pinning.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/certificate_pinning.dart)

**Purpose**: Prevents man-in-the-middle (MITM) attacks by validating the server's SSL certificate fingerprint.

**Pinning Methods**:
1. **Certificate fingerprint** — SHA-256 hash of the full certificate
2. **Public key pin** — Hash of the public key (stable across certificate renewals)

**Pinned Fingerprints** (from `AppConfig`):
```
F3:AB:FB:70:B3:D0:A7:F2:CB:EF:02:8A:2C:C4:95:62:...  (cert fingerprint)
hEdBgpqZW1U6x1XwUf+0UfNg4zu2oy/OwkIOGCppqXs=       (public key pin)
```

**Initialization**:
```dart
// At startup
await CertificatePinning.init(); // Load cached pins

// During ApiClient setup
CertificatePinning.setup(_dio);  // Attach to Dio instance
```

---

## 3. RSA Payload Encryption

**File**: [encryption_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/encryption_service.dart)

**Algorithm**: **RSA-OAEP with SHA-256**

**How It Works**:
1. App fetches the server's RSA public key from `crypto/public-key` endpoint
2. Public key is cached in secure storage
3. Before sending sensitive API requests, the interceptor encrypts specific fields
4. Server decrypts with its private key

**Encrypted Endpoints** (all POST requests to these paths have payload encryption):
```
auth/generate-otp, auth/verify-otp, auth/register,
savings/initiate, savings/check-eligibility,
submit-kyc, update-kyc, kyc/upload,
withdraw, verify-upi, verify-bank, payment, investment,
mpin/create, mpin/validate, mpin/change, mpin/reset,
sip/create, sip/cancel, sip/pause,
users/nominee/update
```

**Sensitive Fields** (encrypted individually within payloads):
```
password, otp, login_pin, transaction_pin,
aadhaar_number, pan_number, pan,
bank_account_number, account_no, ifsc_code, upi_id,
kyc_details, withdrawal_amount, payment_details,
amount, amount_inr, payment_pin, bank_details,
mpin, old_mpin, new_mpin, mobile,
weight, buy_rate
```

**Flow**:
```
API Request
    │
    ▼
ApiSecurityInterceptor.onRequest()
    │
    ├── Is this an encrypted endpoint?
    │       │
    │       ├── YES → encryptJson(body)
    │       │         ├── For each sensitive field:
    │       │         │   └── RSA-OAEP-SHA256 encrypt → Base64 string
    │       │         └── Send encrypted payload
    │       │
    │       └── NO → Send as-is
    │
    └── Attach Authorization header
```

> **Important**: The app never has the RSA private key. Only the server can decrypt.

---

## 4. API Security Interceptor

**File**: [api_interceptor.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/api_interceptor.dart)

**Responsibilities**:
1. **Request Phase**:
   - Attach `Authorization: Bearer <token>` header
   - Encrypt sensitive payload fields (RSA)
   - Add device metadata headers
   - Block requests if force-logged-out

2. **Response Phase**:
   - Handle `401 Unauthorized` → attempt token refresh
   - Handle `409 Conflict` (SESSION_INVALIDATED):
     - Set force-logout flag
     - Show session invalidated dialog
     - Clear all stored data
     - Redirect to login

3. **Error Phase**:
   - Map DioExceptions to typed Failure classes
   - Log errors securely (redact sensitive data)

---

## 5. Secure Storage

**File**: [secure_storage_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/secure_storage_service.dart)

**Backend**:
- **iOS**: Keychain Services
- **Android**: Android Keystore + EncryptedSharedPreferences

**Stored Data**:

| Key | Data | Purpose |
|-----|------|---------|
| `access_token` | JWT access token | API authentication |
| `refresh_token` | JWT refresh token | Token renewal |
| `mobile_number` | User's phone | Session identification |
| `is_mpin_enabled` | Boolean | MPIN gate flag |
| `is_biometric_enabled` | Boolean | Biometric toggle |
| `customer_id` | User ID | API requests |
| `customer_name` | Display name | UI display |
| `customer_photo` | Photo URL | Profile picture |
| `server_public_key` | RSA PEM key | Encryption cache |
| `fcm_token` | FCM device token | Push notifications |

**Logout Behavior**: On logout, ALL stored data is wiped (tokens, user data, cached keys).

---

## 6. Session Manager

**File**: [session_manager.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/session_manager.dart)

**Session States**:

| State | Meaning |
|-------|---------|
| Authenticated | Valid token exists, not force-logged-out |
| Unauthenticated | No token or expired token |
| Force-logged-out | Server sent 409, all API calls blocked |

**Force Logout (409) Flow**:
```
Server returns 409 SESSION_INVALIDATED
    │
    ▼
ApiSecurityInterceptor detects 409
    │
    ├── SessionManager.forceLogout()
    │       ├── Set _isForceLoggedOut = true
    │       └── Clear all secure storage
    │
    ├── Show SessionInvalidatedDialog
    │       └── "You've been logged out because your account was accessed from another device"
    │
    └── Redirect to Login screen
```

**Deduplication**: If multiple concurrent API calls all return 409, only the first one triggers the dialog. Subsequent calls are silently blocked.

---

## 7. App Lifecycle Observer

**File**: [app_lifecycle_observer.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/app_lifecycle_observer.dart)

**Purpose**: Monitors app foreground/background transitions for security.

**Behaviors**:
- When app goes to background → start session timeout countdown
- When app returns to foreground → check if session timed out
- If timed out → require MPIN re-entry
- Manages WebSocket reconnection on resume

---

## 8. Secure Logger

**File**: [secure_logger.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/security/secure_logger.dart)

**Purpose**: Logging that automatically redacts sensitive data.

**Redacted Fields**: Any field in `AppConfig.sensitiveFields` is replaced with `[REDACTED]` in log output.

> **Rule**: Never use `print()` or `debugPrint()` for data that might contain PII. Always use `SecureLogger`.

---

## 9. Screen Protection

**Package**: `screen_protector`

**Features**:
- Prevents screenshots on sensitive screens
- Blocks screen recording
- Applied at the app level

---

## 10. Biometric Authentication

**File**: [biometric_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/services/biometric_service.dart)

**Package**: `local_auth`

**Flow**:
1. User enables biometric in Settings
2. Requires MPIN verification first (to confirm identity)
3. On next login, biometric prompt appears before MPIN
4. Fingerprint / Face ID matches → skip MPIN
5. Biometric fails → fall back to MPIN entry

---

## Security Checklist for Developers

> [!IMPORTANT]
> Follow these rules when writing code:

- [ ] **Never log sensitive data** — Use `SecureLogger`, never `print()` for API data
- [ ] **Never hardcode keys** — All keys come from server or secure storage
- [ ] **Never store tokens in SharedPreferences** — Use `SecureStorageService` only
- [ ] **Always use ApiClient for API calls** — Don't create raw Dio instances
- [ ] **Check if endpoint needs encryption** — If handling PII/financial data, add to `encryptedEndpoints`
- [ ] **Handle 409 responses gracefully** — Catch `SessionInvalidatedFailure` silently
- [ ] **Test on non-rooted devices** — Rooted device detection blocks app access
- [ ] **Verify SSL pins after cert renewal** — Update `allowedCertFingerprints` in `AppConfig`
