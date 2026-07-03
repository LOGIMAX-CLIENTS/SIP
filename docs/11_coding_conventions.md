# Coding Conventions — startGOLD

Follow these conventions to maintain consistency across the codebase.

---

## File & Folder Naming

| Item | Convention | Example |
|------|-----------|---------|
| Dart files | `snake_case.dart` | `auth_service.dart` |
| Feature folders | `snake_case` | `instant_saving/` |
| Class names | `PascalCase` | `AuthService`, `LoginScreen` |
| Variables & functions | `camelCase` | `sendOtp()`, `isLoading` |
| Constants | `camelCase` | `keyAccessToken`, `minWithdrawalGrams` |
| Private members | `_camelCase` | `_apiClient`, `_isForceLoggedOut` |
| Route names | `kebab-case` | `/instant-saving`, `/sip-manage` |

---

## Feature Module Structure

When creating a new feature, follow this structure:

```
features/my_feature/
├── controllers/           # Business logic, validation
│   └── my_feature_controller.dart
├── models/               # Data classes
│   └── my_feature_model.dart
├── providers/            # Riverpod state management
│   └── my_feature_provider.dart
├── services/             # API calls
│   └── my_feature_service.dart
├── screens/              # UI screens
│   ├── my_feature_screen.dart
│   └── my_feature_detail_screen.dart
└── widgets/              # Feature-specific widgets
    └── my_feature_card.dart
```

> Not every feature needs all subdirectories. Simple features like `daily_savings` may have just one screen file.

---

## Dart Style Guide

### Imports

Order imports in this sequence:
```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:convert';

// 2. Flutter SDK
import 'package:flutter/material.dart';

// 3. External packages
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 4. Internal packages — core first, then features
import '../core/network/api_client.dart';
import '../core/security/secure_storage_service.dart';
import '../features/auth/login/login_screen.dart';
```

### Const Constructors

Always use `const` where possible:
```dart
// ✅ Good
const SizedBox(height: 16);
const Text('Hello');
const EdgeInsets.all(16);

// ❌ Bad
SizedBox(height: 16);
Text('Hello');
```

### String Interpolation

```dart
// ✅ Good
'Hello $name'
'Total: ${amount.toStringAsFixed(2)}'

// ❌ Bad
'Hello ' + name
'Total: ' + amount.toString()
```

### Null Safety

```dart
// ✅ Good — use null-aware operators
final name = user?.name ?? 'Unknown';
final photo = data?['user']?['photo_url'];

// ✅ Good — use pattern matching for Map access
if (response.data != null && response.data['data'] != null) {
  final data = response.data['data'];
}

// ❌ Bad — null check without handling
final name = user.name; // May crash
```

---

## Screen Widget Convention

### Use `ConsumerWidget` for screens that need providers:

```dart
class MyScreen extends ConsumerWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,  // Global gradient shows through
      body: SafeArea(
        child: // ... content
      ),
    );
  }
}
```

### Use `ConsumerStatefulWidget` for screens with local state + providers:

```dart
class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  final _formKey = GlobalKey<FormState>();
  
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myProvider);
    // ...
  }
}
```

---

## Service Layer Convention

```dart
class MyFeatureService {
  final ApiClient _apiClient = ApiClient();
  
  /// Fetches data from the API.
  /// Returns the raw response data map.
  /// Throws [Failure] subclass on error.
  Future<Map<String, dynamic>> fetchData({required String id}) async {
    final response = await _apiClient.get('my-endpoint/$id');
    return response.data;
  }
  
  /// Submits data to the API.
  /// Returns success status and response data.
  Future<Map<String, dynamic>> submitData({
    required String name,
    required double amount,
  }) async {
    final response = await _apiClient.post(
      'my-endpoint/submit',
      data: {
        'name': name,
        'amount': amount,
      },
    );
    return response.data;
  }
}
```

---

## Error Handling Convention

### In Services — Let exceptions propagate

```dart
// ✅ Services should NOT catch DioException — ApiClient does this
Future<Map<String, dynamic>> fetchData() async {
  final response = await _apiClient.get('endpoint');
  return response.data;
}
```

### In Notifiers — Catch and set error state

```dart
// ✅ Notifiers should catch and update state
Future<void> loadData() async {
  state = state.copyWith(isLoading: true, clearError: true);
  try {
    final data = await _service.fetchData();
    state = state.copyWith(isLoading: false, data: data);
  } catch (e) {
    String message = 'Something went wrong';
    if (e is DioException && e.response?.data != null) {
      message = e.response!.data['message'] ?? message;
    }
    state = state.copyWith(isLoading: false, error: message);
  }
}
```

### In UI — Show error from state

```dart
// ✅ UI reads error from state, doesn't catch
if (state.error != null) {
  AppToast.show(context, state.error!, type: ToastType.error);
}
```

---

## Comments & Documentation

### Required Comments

- **All service methods**: Document what the API does and what it returns
- **Complex business logic**: Explain WHY, not WHAT
- **Security-related code**: Always document security implications
- **Workarounds**: Document why a workaround was needed

### Comment Style

```dart
/// Fetches the user's portfolio holdings from the server.
/// Returns a map containing:
/// - `gold_weight`: Total gold in grams
/// - `silver_weight`: Total silver in grams
/// - `total_invested`: Total ₹ invested
/// - `current_value`: Current portfolio value
Future<Map<String, dynamic>> getPortfolio() async { ... }

// ── Force Logout Guard ───────────────────────────────────
// When a 409 SESSION_INVALIDATED response is received, this flag is set
// to `true` so that all subsequent API calls are immediately rejected.
static bool _isForceLoggedOut = false;
```

---

## Git Conventions

### Branch Naming

| Pattern | Example |
|---------|---------|
| `feature/<name>` | `feature/sip-transaction-history` |
| `bugfix/<name>` | `bugfix/withdrawal-amount-validation` |
| `hotfix/<name>` | `hotfix/cert-pin-update` |

### Commit Messages

```
feat: add SIP transaction history screen
fix: correct withdrawal minimum amount validation
refactor: extract payment handler from instant saving
docs: update API reference for SIP endpoints
chore: upgrade dio to 5.4.2
```

---

## Don'ts — Common Mistakes

| ❌ Don't | ✅ Do Instead |
|----------|--------------|
| Use raw `Dio()` for API calls | Use `ApiClient` |
| Use `print()` for logging | Use `SecureLogger` or `debugPrint()` |
| Store tokens in `SharedPreferences` | Use `SecureStorageService` |
| Create global singletons | Use Riverpod `Provider` for DI |
| Hardcode colors | Reference `AppTheme` constants |
| Use pixel values directly | Use `ScreenUtil` (`.w`, `.h`, `.sp`) |
| Import from other features directly | Put shared code in `core/` or `shared/` |
| Catch `SessionInvalidatedFailure` and show error | Let it pass silently (interceptor handles it) |
