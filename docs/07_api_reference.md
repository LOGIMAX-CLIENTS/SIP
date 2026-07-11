# API Reference — startGOLD

This document covers the API layer architecture, endpoint catalog, request/response patterns, and error handling.

---

## API Architecture

### Base URL

Controlled via `--dart-define=BASE_URL=<url>`:

| Environment | URL |
|-------------|-----|
| Production | `https://api.startgold.com/api/api/v1/` |
| Staging | `https://startgoldapi.logimaxindia.com/api/api/v1/` |
| VAPT | `https://vaptapi.startgold.com/api/api/v1/` |

### HTTP Client

All API calls go through `ApiClient` → `Dio` with:
- **Connect timeout**: 60 seconds
- **Receive timeout**: 60 seconds
- **Content-Type**: `application/json`
- **Interceptor**: `ApiSecurityInterceptor` (auth, encryption, error handling)
- **SSL Pinning**: `CertificatePinning` (on HTTPS connections)

---

## Request Headers

Every request includes:

| Header | Value | Source |
|--------|-------|--------|
| `Content-Type` | `application/json` | Default |
| `Accept` | `application/json` | Default |
| `Authorization` | `Bearer <access_token>` | Added by interceptor |

---

## Standard Response Format

All API responses follow this structure:

### Success Response
```json
{
  "success": true,
  "message": "Operation successful",
  "data": {
    // Response payload
  }
}
```

### Error Response
```json
{
  "success": false,
  "message": "Error description",
  "error": {
    "message": "Detailed error" | { "field": ["validation error"] }
  }
}
```

---

## Endpoint Catalog

### Authentication

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `users/auth/generate-otp` | Send OTP to mobile | ✅ |
| POST | `users/auth/verify-otp` | Verify OTP code | ✅ |
| POST | `users/auth/register` | Register new user | ✅ |
| POST | `users/auth/register-check` | Pre-validate registration | ✅ |

#### Generate OTP — Request
```json
{
  "mobile": "9876543210",
  "country_code": "+91",
  "id_country": "101",
  "type": "LOGIN",
  "device_id": "unique-device-id",
  "device_type": "android",
  "appVersion": "1.0.0"
}
```

#### Verify OTP — Response
```json
{
  "success": true,
  "data": {
    "access_token": "jwt-token",
    "refresh_token": "jwt-refresh-token",
    "is_new_user": false,
    "mpin_enabled": true,
    "user": {
      "id_customer": "12345",
      "name": "John Doe",
      "photo_url": "https://..."
    }
  }
}
```

---

### MPIN

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `mpin/create` | Create MPIN | ✅ |
| POST | `mpin/validate` | Validate MPIN | ✅ |
| POST | `mpin/change` | Change MPIN | ✅ |
| POST | `mpin/reset` | Reset MPIN | ✅ |

---

### Crypto / Key Exchange

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| GET | `crypto/public-key` | Fetch RSA public key | ❌ |

---

### Savings / Buy

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `savings/initiate` | Initiate purchase | ✅ |
| POST | `savings/check-eligibility` | Check if user can buy | ✅ |

---

### SIP (Systematic Investment Plan)

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `sip/create` | Create SIP subscription | ✅ |
| POST | `sip/cancel` | Cancel SIP | ✅ |
| POST | `sip/pause` | Pause SIP | ✅ |

---

### KYC

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `submit-kyc` | Submit KYC data | ✅ |
| POST | `update-kyc` | Update KYC data | ✅ |
| POST | `kyc/upload` | Upload KYC documents | ✅ |

---

### Withdrawal

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `withdraw` | Initiate withdrawal | ✅ |
| POST | `verify-upi` | Verify UPI ID | ✅ |
| POST | `verify-bank` | Verify bank account | ✅ |

---

### Payment

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `payment` | Process payment | ✅ |
| POST | `investment` | Investment transaction | ✅ |

---

### Nominee

| Method | Endpoint | Description | Encrypted |
|--------|----------|-------------|-----------|
| POST | `users/nominee/update` | Add/update nominee | ✅ |

---

### Content (CMS)

These endpoints serve dynamic content:

| Provider | Content Type |
|----------|-------------|
| `termsProvider` | Terms & Conditions |
| `privacyPolicyProvider` | Privacy Policy |
| `aboutUsProvider` | About Us |
| `refundPolicyProvider` | Refund Policy |

---

## Error Handling

### HTTP Status Code Mapping

| Status | Failure Type | Action |
|--------|-------------|--------|
| `401` | `AuthenticationFailure` | Token expired → attempt refresh |
| `403` | `AuthenticationFailure` | Forbidden → show error |
| `409` | `SessionInvalidatedFailure` | Force logout → redirect to login |
| `5xx` | `ServerFailure` | Show "Server unavailable" message |
| Timeout | `NetworkFailure` | Show "Connection error" message |

### Error Extraction Logic

The interceptor tries to extract the most specific error message:

```
response.data['message']
  → response.data['error']['message']
    → response.data['validation_errors']['detail']
      → response.data['data']['message']
        → fallback: "Server error code: {status}"
```

### Nested Error Format

Some endpoints return nested validation errors:

```json
{
  "error": {
    "message": {
      "email": ["The email has already been taken."],
      "mobile": ["The mobile has already been taken."]
    }
  }
}
```

The app extracts the first error value and displays it.

---

## WebSocket — Live Rates

**Service**: [native_socket_service.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/network/native_socket_service.dart)

**Purpose**: Real-time gold/silver price streaming.

**Connection**:
- Establishes WebSocket connection to server
- Receives rate updates as JSON messages
- Updates `marketProvider` on each message
- Auto-reconnects on disconnect
- Pauses when app goes to background, resumes on foreground

---

## Making API Calls — Developer Guide

### ✅ Correct Way

```dart
class MyService {
  final ApiClient _apiClient = ApiClient();
  
  Future<Map<String, dynamic>> fetchData() async {
    final response = await _apiClient.get('endpoint/path');
    return response.data;
  }
  
  Future<Map<String, dynamic>> submitData(Map<String, dynamic> data) async {
    final response = await _apiClient.post('endpoint/path', data: data);
    return response.data;
  }
}
```

### ❌ Wrong Way

```dart
// DON'T do this — bypasses security interceptor
final dio = Dio();
dio.get('https://api.startgold.com/...');

// DON'T do this — bypasses encryption
import 'package:http/http.dart' as http;
http.post(Uri.parse('...'));
```

### File Upload

```dart
final formData = FormData.fromMap({
  'file': await MultipartFile.fromFile(filePath, filename: 'photo.jpg'),
  'type': 'profile_photo',
});
final response = await _apiClient.post('upload', data: formData);
// ApiClient automatically sets Content-Type to multipart/form-data
```
