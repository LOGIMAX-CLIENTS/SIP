# State Management — startGOLD (Riverpod)

This project uses **flutter_riverpod** (v2.4.9) for all state management. This guide explains every provider, when to use each type, and the patterns followed.

---

## Riverpod Basics

| Provider Type | When to Use | Example |
|---------------|-------------|---------|
| `Provider` | Dependency injection (services, configs) | `authServiceProvider` |
| `StateProvider` | Simple mutable state (toggles, selection) | Tab index, checkbox |
| `StateNotifierProvider` | Complex state with business logic | `authProvider`, `portfolioProvider` |
| `FutureProvider` | One-shot async data fetch | Content providers |
| `StreamProvider` | Real-time data streams | WebSocket rates |

---

## Provider Map

### Core Providers (`lib/core/providers/`)

#### `app_control_provider.dart`
- **Provider**: `appControlProvider` — `StateNotifierProvider`
- **Purpose**: Fetches and manages remote app control configuration
- **Data**: Maintenance mode, force update flags, minimum version, announcements
- **Used by**: `AppControlWrapper`, `MaintenanceGate`

#### `commodity_provider.dart`
- **Provider**: `commodityProvider`
- **Purpose**: Gold/Silver commodity data (prices, metadata)
- **Used by**: Instant Saving, SIP, Withdrawal screens

#### `connectivity_provider.dart`
- **Provider**: `connectivityProvider`
- **Purpose**: Monitors internet connectivity status
- **Used by**: `OfflineBanner` widget — shows "No Internet" banner
- **Package**: `connectivity_plus`

#### `home_dashboard_provider.dart`
- **Provider**: `homeDashboardProvider`
- **Purpose**: Aggregates home screen data
- **Used by**: Home screen

#### `market_provider.dart`
- **Provider**: `marketProvider`
- **Purpose**: Live gold/silver market rates
- **Data Source**: WebSocket via `NativeSocketService`
- **Used by**: Home, Market, Instant Saving, Withdrawal screens

#### `portfolio_provider.dart`
- **Provider**: `portfolioProvider`
- **Purpose**: User's portfolio holdings (invested, current value, returns)
- **Used by**: Home dashboard, Portfolio tab

#### `timer_provider.dart`
- **Provider**: `timerProvider`
- **Purpose**: Countdown timer for rate-locking during purchases/withdrawals
- **Behavior**: Starts countdown, triggers rate refresh on expiry
- **Used by**: Instant Saving, Withdrawal screens

#### `user_provider.dart`
- **Provider**: `userProvider`
- **Purpose**: Current user profile data
- **Used by**: Profile, Home, navigation guards

---

### Service Providers (`lib/core/services/`)

#### `auth_service.dart`
```dart
// Service DI
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// State management
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final service = ref.watch(authServiceProvider);
  return AuthNotifier(service);
});
```

**AuthState**:
```dart
class AuthState {
  final bool isLoading;        // API call in progress
  final String? error;         // Error message to display
  final Map<String, dynamic>? data;         // Transient result
  final Map<String, dynamic>? sessionData;  // Persistent session data
  final bool? isRegistered;    // Is user registered
}
```

**AuthNotifier Methods**:
| Method | Purpose |
|--------|---------|
| `sendOtp()` | Send OTP to phone number |
| `verifyOtp()` | Verify OTP code |
| `register()` | Register new user |
| `logout()` | Clear session |
| `clearError()` | Reset error state |
| `rehydrateFromStorage()` | Restore session from secure storage |

---

### Feature-Specific Providers

Each feature may define its own providers within its directory:

```
features/
├── kyc/providers/          # KYC step state
├── withdrawal/providers/   # Withdrawal flow state
└── sip/services/           # SIP-specific state
```

---

### Localization Provider

```dart
// lib/core/localization/language_provider.dart
final languageProvider = StateNotifierProvider<LanguageNotifier, LanguageState>(...);
```

- Manages current locale (`en`, `ta`, `te`)
- Persists language selection to `SharedPreferences`
- Triggers app-wide rebuild on language change

---

## Provider Usage Patterns

### Reading State in UI

```dart
class MyScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch — rebuild when state changes
    final authState = ref.watch(authProvider);
    
    if (authState.isLoading) {
      return LoadingSpinner();
    }
    
    if (authState.error != null) {
      return ErrorWidget(authState.error!);
    }
    
    return MyContent(data: authState.data);
  }
}
```

### Calling Actions

```dart
// In an event handler (onPressed, etc.)
ref.read(authProvider.notifier).sendOtp('9876543210', '+91', '101');

// DON'T use ref.watch() for calling actions
// ref.watch(authProvider.notifier).sendOtp(...); // ❌ WRONG
```

### One-Time Read

```dart
// Read current value without subscribing
final currentUser = ref.read(userProvider);
```

---

## State Flow Example: Login

```
LoginScreen
    │
    ├── ref.watch(authProvider)
    │       → shows loading spinner / error / form
    │
    └── onSubmit:
        ref.read(authProvider.notifier).sendOtp(mobile, code, country)
            │
            ├── state = AuthState(isLoading: true)
            │       → UI rebuilds with spinner
            │
            ├── await authService.sendOtp(...)
            │
            ├── SUCCESS:
            │   state = AuthState(isLoading: false, data: response)
            │       → UI rebuilds, navigates to OTP screen
            │
            └── FAILURE:
                state = AuthState(isLoading: false, error: "message")
                    → UI rebuilds with error message
```

---

## Provider Lifecycle

| Event | Behavior |
|-------|----------|
| Provider first read | Created (lazy initialization) |
| All listeners disposed | Provider disposed (unless `.autoDispose` is NOT used) |
| App restart | All providers reset — session rehydrated from storage |
| User logout | `authProvider.notifier.logout()` → resets AuthState |

---

## Rules for Developers

1. **One provider per concern** — Don't put unrelated state in the same provider
2. **Services via Provider** — Inject services using `Provider`, not global singletons
3. **StateNotifier for complex state** — Use `StateNotifier` when state has multiple fields or complex transitions
4. **copyWith pattern** — Always use immutable state with `copyWith()`
5. **ref.watch in build, ref.read in callbacks** — This is the fundamental Riverpod rule
6. **Don't access providers outside widgets** — Services should not depend on providers
7. **Feature providers stay in features** — Don't put feature-specific providers in `core/`
