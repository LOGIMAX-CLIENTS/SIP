# UI & Theming Guide — startGOLD

This document covers the design system, color palette, typography, gradients, shared widgets, and responsive design approach.

---

## Design System Overview

startGOLD uses a **premium fintech aesthetic** with:
- Warm gold gradient backgrounds
- Green primary accent (brand color)
- Lora / PlayfairDisplay serif fonts
- Glassmorphism-inspired cards
- Micro-animations via Lottie
- Material 3 design language

---

## Color Palette

**File**: [app_theme.dart](file:///e:/Projects/Mobileapp/SIP/lib/shared/theme/app_theme.dart)

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| `primaryGreen` | `#1B882C` | Primary buttons, accents, CTAs |
| `darkGreen` | `#003716` | Gradient end, dark accents |
| `midnightNavy` | `#020817` | Dark mode background, text |
| `glassWhite` | `#F8FAFC` | Surface color, card backgrounds |
| `auroraPurple` | `#8B5CF6` | Dark mode secondary accent |
| `buttonShadow` | `#3B8F4C05` | Elevated button shadow |

### Brand Gradients

#### Green Button Gradient
```dart
static const LinearGradient greenGradient = LinearGradient(
  colors: [Color(0xFF1B882C), Color(0xFF003716)],  // Green → Dark Green
);
```

#### Light Background Gradient (App Background)
```dart
static const LinearGradient lightGradient = LinearGradient(
  colors: [Color(0xFFFFFDF5), Color(0xFFFFE6A8)],  // Warm White → Gold
);
```

#### Dark Background Gradient
```dart
static const LinearGradient darkGradient = LinearGradient(
  colors: [Color(0xFF020617), Color(0xFF0F172A)],  // Navy → Dark Slate
);
```

> The app background is a **global gradient** applied in `MyApp.builder`, NOT on individual screens. Scaffold backgrounds are transparent.

---

## Typography

**Font Family**: `PlayfairDisplay` (with `Lora` weights)

| Font File | Weight | Usage |
|-----------|--------|-------|
| `Lora-Regular.ttf` | 400 | Body text, labels |
| `Lora-SemiBold.ttf` | 600 | Headlines, titles |
| `Lora-Bold.ttf` | 700 | Display text, CTAs |

**Text Theme Hierarchy**:

| Style | Weight | Usage |
|-------|--------|-------|
| `displayLarge/Medium/Small` | Bold (700) | Hero text, splash |
| `headlineLarge/Medium/Small` | SemiBold (600) | Section headers |
| `titleLarge/Medium/Small` | Medium (500) | Screen titles |
| `bodyLarge/Medium/Small` | Regular (400) | Content text |

**Extended Text Styles**: [app_text_styles.dart](file:///e:/Projects/Mobileapp/SIP/lib/shared/theme/app_text_styles.dart)

---

## Responsive Design

**Package**: `flutter_screenutil` (v5.8.4)

**Design Size**: `390 × 844` (iPhone 14 Pro equivalent)

### Usage

```dart
// Dimensions
Container(
  width: 200.w,     // Responsive width
  height: 100.h,    // Responsive height
  padding: EdgeInsets.all(16.w),
)

// Font sizes
Text('Hello', style: TextStyle(fontSize: 16.sp))

// Border radius
BorderRadius.circular(12.r)
```

### Initialization (in `main.dart`)

```dart
ScreenUtilInit(
  designSize: const Size(390, 844),
  minTextAdapt: true,
  splitScreenMode: true,
  builder: (context, child) => MaterialApp(...),
)
```

> **Rule**: Always use `.w`, `.h`, `.sp`, `.r` suffixes for responsive dimensions. Never use raw pixel values.

---

## Theme Configuration

### Light Theme (Primary)

```dart
ThemeData(
  useMaterial3: true,
  fontFamily: 'PlayfairDisplay',
  brightness: Brightness.light,
  primaryColor: primaryGreen,
  scaffoldBackgroundColor: Colors.transparent,  // ← Important!
  colorScheme: ColorScheme.fromSeed(
    seedColor: primaryGreen,
    primary: primaryGreen,
    secondary: electricCyan,
    surface: glassWhite,
  ),
)
```

### Dark Theme

Similar structure with navy/dark colors. Currently the app runs in **light mode only** (`themeMode: ThemeMode.light`).

---

## Shared Widgets

### `custom_button.dart`
Reusable gradient button with loading state:
```dart
CustomButton(
  text: 'Buy Now',
  onPressed: () => handleBuy(),
  isLoading: state.isLoading,
  gradient: AppTheme.greenGradient,
)
```

### `loaders.dart`
Loading indicators and shimmer effects:
```dart
// Circular loader
AppLoader()

// Shimmer placeholder
ShimmerLoader(width: 200.w, height: 100.h)
```

### `app_toast.dart`
Toast/snackbar notifications:
```dart
AppToast.show(context, 'Success message', type: ToastType.success);
AppToast.show(context, 'Error occurred', type: ToastType.error);
```

### `app_alert_banner.dart`
Top-of-screen alert banners for important messages.

### `gradient_header.dart`
Gradient page headers for consistent screen tops:
```dart
GradientHeader(title: 'My Portfolio')
```

### `offline_banner.dart`
Shows "No Internet Connection" banner when offline.

### `animations.dart`
Shared animation utilities (fade in, slide up, scale).

### `numeric_styled_text.dart`
Number formatting widget for financial data display.

### `app_control_wrapper.dart`
Runtime control layer that wraps the entire app:
- Checks for maintenance mode
- Checks for force update requirements
- Shows appropriate dialogs/screens

### `session_invalidated_dialog.dart`
Shows when server returns 409 (session expired / logged in from another device).

### `compromised_device_screen.dart`
Full-screen block shown on rooted/jailbroken devices.

---

## Input Formatters

**Path**: `lib/shared/utils/`

| Formatter | Purpose |
|-----------|---------|
| `NoLeadingZerosFormatter` | Prevents leading zeros in numeric inputs |
| `UpperCaseWordsFormatter` | Capitalizes first letter of each word |

---

## Asset Organization

```
assets/
├── images/     # General images (logos, illustrations)
├── fonts/      # Lora font family (Regular, SemiBold, Bold)
├── home/       # Home screen specific (banners, icons)
├── sip/        # SIP feature assets
├── buttons/    # Button background images
├── footer/     # Bottom nav icons
├── sidemenu/   # Side menu icons
├── withdraw/   # Withdrawal screen assets
├── resources/  # App icon, splash resources
└── lottie/     # Lottie animation JSON files
```

### Using Assets

```dart
// Images
Image.asset('assets/images/logo.png')

// SVG
SvgPicture.asset('assets/home/gold_icon.svg')

// Lottie animations
Lottie.asset('assets/lottie/success.json')
```

---

## Design Rules for Developers

1. **Never use raw colors** — Always reference `AppTheme.primaryGreen`, etc.
2. **Never use raw fonts** — Use theme text styles or `AppTextStyles`
3. **Always use ScreenUtil** — `.w`, `.h`, `.sp`, `.r` for all dimensions
4. **Scaffold background = transparent** — The gradient background is global
5. **Use shared widgets** — Don't recreate buttons, loaders, toasts
6. **Test on multiple sizes** — Design is based on 390×844 but must work on all screens
7. **SVG for icons** — Use `flutter_svg` for scalable icons, not raster PNG
8. **Lottie for animations** — Premium animations use Lottie JSON files
