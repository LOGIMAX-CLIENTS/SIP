# Architecture Guide — startGOLD

## High-Level Architecture

startGOLD follows a **Feature-First Clean Architecture** pattern, with clear separation between UI, business logic, data, and infrastructure layers.

```
┌─────────────────────────────────────────────────────┐
│                    PRESENTATION                      │
│  ┌─────────────┐  ┌───────────┐  ┌───────────────┐  │
│  │   Screens   │  │  Widgets  │  │  Controllers  │  │
│  └──────┬──────┘  └─────┬─────┘  └───────┬───────┘  │
│         │               │                │           │
│  ┌──────▼───────────────▼────────────────▼───────┐  │
│  │              Riverpod Providers               │  │
│  └──────────────────────┬────────────────────────┘  │
├─────────────────────────┼───────────────────────────┤
│                    DOMAIN / SERVICES                 │
│  ┌──────────────────────▼────────────────────────┐  │
│  │              Services (API calls)             │  │
│  │   auth_service, portfolio_service, etc.       │  │
│  └──────────────────────┬────────────────────────┘  │
├─────────────────────────┼───────────────────────────┤
│                    INFRASTRUCTURE                    │
│  ┌──────────┐  ┌────────▼─────┐  ┌───────────────┐  │
│  │ Security │  │  API Client  │  │   Storage     │  │
│  │  Layer   │  │   (Dio)      │  │  (Secure/SP)  │  │
│  └──────────┘  └──────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## Design Patterns Used

### 1. Feature-First Module Structure

Each feature is a self-contained module:

```
features/kyc/
├── controllers/      # Business logic, form validation
├── models/           # Data classes (KycStep, KycField, etc.)
├── providers/        # Riverpod StateNotifiers
├── repositories/     # Data access layer
├── screens/          # UI screens
└── kyc_screen.dart   # Feature entry point
```

> **Rule**: Features should NOT import from other features directly. Shared code goes in `core/` or `shared/`.

### 2. Provider Pattern (Riverpod)

State management uses `flutter_riverpod` with this hierarchy:

```
Provider           → Simple dependency injection (services, configs)
StateProvider      → Simple mutable state (selected tab, toggles)
StateNotifierProvider → Complex state with business logic (auth, portfolio)
FutureProvider     → One-shot async data (fetch and cache)
```

### 3. Service Layer Pattern

Services encapsulate API calls and return raw data:

```dart
class AuthService {
  final ApiClient _apiClient = ApiClient();
  
  Future<Map<String, dynamic>> sendOtp({required String mobile, ...}) async {
    final response = await _apiClient.post('users/auth/generate-otp', data: {...});
    return response.data;
  }
}
```

### 4. Interceptor Chain (Dio)

Every API request passes through a security interceptor pipeline:

```
Request → ApiSecurityInterceptor → CertificatePinning → Server
                  │
                  ├── Attach Authorization header
                  ├── Encrypt sensitive fields (RSA)
                  ├── Add device metadata
                  └── Handle 401/409 responses
```

### 5. Centralized Error Handling

All Dio errors are mapped to typed `Failure` subclasses:

```
DioException
    ├── connectionTimeout → NetworkFailure
    ├── badResponse(401)  → AuthenticationFailure
    ├── badResponse(409)  → SessionInvalidatedFailure
    ├── badResponse(5xx)  → ServerFailure
    └── cancel            → SessionInvalidatedFailure (if 409-related)
```

---

## Data Flow — Example: Buy Gold

```
User taps "Buy Now"
    │
    ▼
InstantSavingScreen (UI)
    │
    ▼
PaymentHandler.initiate()
    │
    ├── 1. Check KYC status
    ├── 2. Call savings/initiate API (via ApiClient)
    │       │
    │       ▼
    │   ApiSecurityInterceptor
    │       ├── Encrypt sensitive fields (amount, rate)
    │       ├── Attach auth token
    │       └── Send HTTPS request
    │
    ├── 3. Receive payment session from server
    ├── 4. Launch Cashfree SDK with session token
    ├── 5. Handle payment callback
    └── 6. Verify payment status via API
```

---

## App Initialization Flow

When the app starts, the following sequence executes in `main()`:

```
main()
  │
  ├── 1. WidgetsFlutterBinding.ensureInitialized()
  ├── 2. Firebase.initializeApp()           [mobile only]
  ├── 3. RootDetectionService.isDeviceCompromised()
  │       ├── If rooted → Show CompromisedDeviceScreen, EXIT
  │       └── If clean  → Continue
  ├── 4. SystemChrome.setPreferredOrientations([portraitUp])
  ├── 5. CertificatePinning.init()          [load cached SSL pins]
  ├── 6. FcmService.init()                  [request notification permissions]
  └── 7. runApp(ProviderScope(child: MyApp()))
              │
              └── MyApp builds MaterialApp with:
                  ├── AppTheme.lightTheme
                  ├── AppRouter.onGenerateRoute
                  ├── initialRoute: /splash
                  ├── Locale from languageProvider
                  ├── Global gradient background
                  └── AppControlWrapper (maintenance/update gate)
```

---

## Authentication Flow

```
┌───────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────┐
│  Splash   │───▶│  Login   │───▶│  OTP Verify  │───▶│  Route   │
│  Screen   │    │  Screen  │    │   Screen     │    │ Decision │
└───────────┘    └──────────┘    └──────────────┘    └────┬─────┘
                                                          │
                                     ┌────────────────────┼────────────────┐
                                     │                    │                │
                                     ▼                    ▼                ▼
                              ┌────────────┐     ┌──────────────┐  ┌──────────┐
                              │ Registration│     │ PIN Creation │  │  MPIN    │
                              │  (new user) │     │  (new user)  │  │  Entry   │
                              └─────┬──────┘     └──────┬───────┘  │(existing)│
                                    │                    │          └────┬─────┘
                                    └────────────────────┘               │
                                                 │                       │
                                                 ▼                       ▼
                                          ┌──────────────────────────────┐
                                          │         Home / Main          │
                                          └──────────────────────────────┘
```

**Key Decision Points:**

| Condition | Destination |
|-----------|-------------|
| First launch, no token | → Onboarding → Login |
| Has token, MPIN enabled | → MPIN Screen |
| Has token, biometric enabled | → Biometric prompt → MPIN fallback |
| OTP verified, `is_new_user = true` | → Registration → PIN Creation |
| OTP verified, `is_new_user = false` | → Home (if MPIN disabled) or MPIN |

---

## Session Management

Sessions are managed via `SessionManager`:

- **Normal logout**: Clears tokens from secure storage
- **Force logout (409)**: Server invalidates session (e.g., login from another device)
  - Sets `_isForceLoggedOut = true`
  - All subsequent API calls are immediately blocked
  - Shows `SessionInvalidatedDialog`
  - Redirects to login
  - Flag resets only after successful fresh OTP verification

---

## Key Architectural Decisions

| Decision | Rationale |
|----------|-----------|
| **Riverpod over BLoC** | Less boilerplate, better testability, compile-time safety |
| **Feature-first folders** | Scales well with team size, reduces merge conflicts |
| **Dio over http** | Built-in interceptor support for security pipeline |
| **RSA over AES** | Server-managed key rotation, no symmetric key exchange needed |
| **Named routes** | Centralized route definitions, easy deep linking |
| **WebSocket for rates** | Sub-second price updates without polling overhead |
| **Secure storage for tokens** | Keychain (iOS) / Keystore (Android) backed encryption |
