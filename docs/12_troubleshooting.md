# Troubleshooting Guide — startGOLD

Common issues you may encounter during development and how to fix them.

---

## Build Issues

### ❌ `flutter pub get` fails with dependency conflicts

**Solution**:
```bash
flutter clean
flutter pub cache clean
flutter pub get
```

If still failing, check `pubspec.lock` for version conflicts and try:
```bash
flutter pub upgrade --major-versions
```

---

### ❌ Android build fails with Gradle errors

**Symptoms**: `Execution failed for task ':app:compileDebugKotlin'`

**Solutions**:

1. **Clean and rebuild**:
   ```bash
   flutter clean
   cd android && ./gradlew clean && cd ..
   flutter run
   ```

2. **Check Java version** — Project requires JDK 17:
   ```bash
   java -version
   ```

3. **Invalidate caches** (Android Studio):
   - File → Invalidate Caches / Restart

---

### ❌ iOS build fails with CocoaPods errors

**Solution**:
```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
flutter run
```

---

### ❌ `Null check operator used on a null value`

**Common Cause**: Navigating to a route that expects arguments without passing them.

**Fix**: Always check for null when extracting route arguments:
```dart
final args = ModalRoute.of(context)!.settings.arguments
    as Map<String, dynamic>? ?? {};  // Provide empty map as fallback
```

---

## Runtime Issues

### ❌ App shows `CompromisedDeviceScreen` on emulator

**Cause**: Root detection triggers on some emulators.

**Workaround for development**: This is expected on rooted emulators. Use a physical device or temporarily comment out root detection in `main.dart` (never commit this change).

---

### ❌ "RSA public key not loaded" error

**Cause**: The encryption service couldn't fetch the server's public key.

**Solutions**:
1. Check internet connectivity
2. Verify the `BASE_URL` is correct
3. Check if `crypto/public-key` endpoint is accessible
4. Clear secure storage and restart:
   - Uninstall the app and reinstall

---

### ❌ `SessionInvalidatedFailure` — Force logged out

**Cause**: Server returned 409 (logged in from another device or session expired).

**Expected Behavior**: This is working as designed. The interceptor handles it automatically by:
1. Showing the session invalidated dialog
2. Clearing all stored data
3. Redirecting to login

**If this happens frequently during development**: Check if multiple developers are using the same test account.

---

### ❌ WebSocket disconnects / rates not updating

**Cause**: WebSocket connection dropped.

**Debugging**:
1. Check `NativeSocketService` logs
2. Verify WebSocket URL is accessible
3. Check if app went to background (WebSocket pauses)
4. On resume, WebSocket should auto-reconnect

---

### ❌ Payment fails with Cashfree SDK error

**Debugging Steps**:
1. Check if you're using the correct Cashfree environment (sandbox vs production)
2. Verify the payment session token is valid
3. Check Cashfree dashboard for transaction status
4. Ensure the `flutter_cashfree_pg_sdk` version matches server integration

---

### ❌ Push notifications not received

**Debugging**:
1. Check `google-services.json` (Android) / `GoogleService-Info.plist` (iOS)
2. Verify FCM token is saved: check `SecureStorageService.getFcmToken()`
3. Check notification permissions (Settings → App → Notifications)
4. Verify Firebase project matches the app's package name
5. Check FCM service logs: search for `FcmService` in debug output

---

### ❌ Certificate pinning fails

**Cause**: Server certificate was renewed but app still has old fingerprint.

**Fix**:
1. Get the new certificate fingerprint from the server admin
2. Update `allowedCertFingerprints` in [app_config.dart](file:///e:/Projects/Mobileapp/SIP/lib/core/config/app_config.dart)
3. The public key pin should remain stable across renewals

---

## UI Issues

### ❌ Screen overflows on small devices

**Cause**: Fixed pixel values instead of responsive sizing.

**Fix**: Use ScreenUtil:
```dart
// ❌ Bad
SizedBox(height: 200)

// ✅ Good  
SizedBox(height: 200.h)
```

---

### ❌ Gradient background not showing

**Cause**: Screen has non-transparent scaffold background.

**Fix**: Ensure `scaffoldBackgroundColor` is `Colors.transparent`:
```dart
Scaffold(
  backgroundColor: Colors.transparent,  // ← This is required
  body: ...
)
```

---

### ❌ Fonts look wrong / fallback to system font

**Cause**: Font family not loaded properly.

**Fix**: 
1. Verify fonts are listed in `pubspec.yaml` under `flutter > fonts`
2. Run `flutter clean && flutter pub get`
3. Check font file paths match actual file locations

---

## Environment Issues

### ❌ Wrong API environment (hitting production from dev)

**Cause**: Not passing `--dart-define` flags.

**Fix**: Always specify the environment explicitly:
```bash
flutter run --dart-define=BASE_URL=https://startgoldapi.logimaxindia.com/api/api/v1/
```

**Verification**: Add a debug log to check:
```dart
debugPrint('Current BASE_URL: ${AppConfig.baseUrl}');
```

---

### ❌ Firebase initialization fails on Web

**Cause**: Firebase Messaging is not supported on web.

**Expected Behavior**: The `main.dart` guards Firebase init with `if (!kIsWeb)`. If you see this error, ensure the guard is in place.

---

## Debugging Tips

### View API requests/responses

The `ApiSecurityInterceptor` logs requests (with sensitive fields redacted). Check the debug console for lines starting with:
- `[API REQUEST]` — Outgoing request
- `[API RESPONSE]` — Incoming response
- `[API ERROR]` — Error response

### Check stored data

Add a temporary debug screen to view secure storage contents:
```dart
final token = await SecureStorageService.getToken();
final customerId = await SecureStorageService.getCustomerId();
debugPrint('Token: ${token?.substring(0, 20)}...');
debugPrint('Customer ID: $customerId');
```

> **Warning**: Never log full tokens in production code.

### Flutter DevTools

Use Flutter DevTools for:
- **Widget inspector** — Debug layout issues
- **Network tab** — View HTTP requests
- **Performance tab** — Identify rendering issues
- **Provider observer** — Watch Riverpod state changes

---

## Getting Help

| Issue Type | Contact |
|-----------|---------|
| API endpoint issues | Backend team |
| Cashfree payment issues | Check Cashfree dashboard, contact their support |
| Firebase / FCM issues | Check Firebase Console |
| SSL / Security issues | DevOps / Security team |
| Design / UI issues | Design team (Figma) |
| Build / CI issues | DevOps |
