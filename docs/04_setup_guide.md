# Setup Guide — startGOLD

This guide walks you through setting up the development environment from scratch, building, and running the app.

---

## Prerequisites

Ensure the following tools are installed:

| Tool | Minimum Version | Install Link |
|------|----------------|--------------|
| **Flutter SDK** | ≥ 3.4.1 | [flutter.dev/get-started](https://flutter.dev/docs/get-started/install) |
| **Dart SDK** | < 4.0.0 (bundled with Flutter) | Included with Flutter |
| **Android Studio** | Latest | [developer.android.com](https://developer.android.com/studio) |
| **Xcode** (macOS only) | Latest | Mac App Store |
| **VS Code** | Latest | [code.visualstudio.com](https://code.visualstudio.com/) |
| **Git** | Latest | [git-scm.com](https://git-scm.com/) |
| **Java JDK** | 17 | Required for Android builds |

### VS Code Extensions (Recommended)

- **Dart** — Dart language support
- **Flutter** — Flutter development tools
- **Pubspec Assist** — Dependency management
- **Error Lens** — Inline error display

---

## Step 1: Clone the Repository

```bash
git clone <your-repo-url>
cd SIP
```

---

## Step 2: Verify Flutter Installation

```bash
flutter doctor -v
```

Ensure all checks pass (especially Android toolchain and Xcode if on macOS). Fix any issues the doctor reports.

---

## Step 3: Install Dependencies

```bash
flutter pub get
```

This downloads all packages defined in `pubspec.yaml`.

---

## Step 4: Firebase Setup

The project uses Firebase for push notifications. Configuration files should already be in the repo:

| Platform | File | Location |
|----------|------|----------|
| Android | `google-services.json` | `android/app/` |
| iOS | `GoogleService-Info.plist` | `ios/Runner/` |

> **Note**: If these files are missing, contact the team lead. They are sometimes `.gitignore`'d for security.

---

## Step 5: Run the App

### Android

```bash
# Debug mode (default — connects to VAPT server)
flutter run

# With specific base URL
flutter run --dart-define=BASE_URL=https://startgoldapi.logimaxindia.com/api/api/v1/

# With specific environment
flutter run --dart-define=ENV=staging --dart-define=BASE_URL=https://startgoldapi.logimaxindia.com/api/api/v1/
```

### iOS (macOS only)

```bash
cd ios && pod install && cd ..
flutter run -d <ios-device-id>
```

### Web (limited support)

```bash
flutter run -d chrome
```

> **Warning**: Web does not support Firebase Messaging, root detection, biometric auth, or Cashfree SDK.

---

## Step 6: Build for Release

### Android APK

```bash
flutter build apk --release
```

### Android App Bundle (for Play Store)

```bash
flutter build appbundle --release
```

### iOS (macOS only)

```bash
flutter build ios --release
```

---

## Environment Configuration

The app uses `--dart-define` for build-time configuration:

| Flag | Purpose | Default |
|------|---------|---------|
| `BASE_URL` | API server URL | VAPT server (see `app_config.dart`) |
| `ENV` | Environment name | `production` |

### Example: Run Against Staging

```bash
flutter run --dart-define=ENV=staging --dart-define=BASE_URL=https://startgoldapi.logimaxindia.com/api/api/v1/
```

### Example: Run Against Production

```bash
flutter run --dart-define=ENV=production --dart-define=BASE_URL=https://api.startgold.com/api/api/v1/
```

---

## Common Build Commands

| Command | Purpose |
|---------|---------|
| `flutter pub get` | Install/update dependencies |
| `flutter pub upgrade` | Upgrade dependencies to latest compatible versions |
| `flutter analyze` | Run static analysis (linter checks) |
| `flutter test` | Run unit/widget tests |
| `flutter clean` | Clear build cache (fixes many build issues) |
| `flutter run --release` | Run in release mode |
| `flutter devices` | List connected devices |
| `flutter gen-l10n` | Generate localization files |

---

## Generating App Icons

The project uses `flutter_launcher_icons`:

```bash
flutter pub run flutter_launcher_icons
```

Icon source: `assets/resources/icon.png`

---

## Generating Splash Screen

The project uses `flutter_native_splash`:

```bash
flutter pub run flutter_native_splash:create
```

Splash config is defined in `pubspec.yaml` under `flutter_native_splash`.

---

## Keystore / Signing (Android)

For release builds, you need the signing keystore:

1. Get `upload-keystore.jks` from the team lead
2. Create/update `android/key.properties`:

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<path-to-keystore>/upload-keystore.jks
```

3. Ensure `android/app/build.gradle.kts` references `key.properties`

> **Important**: Never commit keystores or passwords to Git.

---

## IDE Setup Tips

### VS Code — `launch.json`

Create `.vscode/launch.json` for quick debug configurations:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "startGOLD (Staging)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=ENV=staging",
        "--dart-define=BASE_URL=https://startgoldapi.logimaxindia.com/api/api/v1/"
      ]
    },
    {
      "name": "startGOLD (Production)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=ENV=production",
        "--dart-define=BASE_URL=https://api.startgold.com/api/api/v1/"
      ]
    }
  ]
}
```

### Android Studio

Use **Run/Debug Configurations** → **Additional run args** to add `--dart-define` flags.

---

## Post-Setup Verification Checklist

- [ ] `flutter doctor` shows all green
- [ ] `flutter pub get` completes without errors
- [ ] App launches on emulator/device
- [ ] Splash screen appears with brand colors (warm gold `#FEF7E6`)
- [ ] Login screen loads (you should see the phone number input)
- [ ] No red error screens on launch
