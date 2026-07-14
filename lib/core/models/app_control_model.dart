import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform-specific version + popup configuration.
/// Each platform (Android / iOS) now carries its own version numbers,
/// store URL, and user-facing popup text.
class PlatformVersionInfo {
  final String latestVersion;
  final String minVersion;
  final String storeUrl;
  final String title;
  final String message;
  final String buttonText;

  const PlatformVersionInfo({
    required this.latestVersion,
    required this.minVersion,
    required this.storeUrl,
    required this.title,
    required this.message,
    required this.buttonText,
  });

  factory PlatformVersionInfo.fromJson(
    Map<String, dynamic> json, {
    // Fallbacks from the parent level (backward compatibility)
    String? fallbackLatest,
    String? fallbackMin,
    String? fallbackStoreUrl,
  }) =>
      PlatformVersionInfo(
        latestVersion: json['latest_version'] ?? fallbackLatest ?? '',
        minVersion: json['min_version'] ?? fallbackMin ?? '',
        storeUrl: json['store_url'] ?? fallbackStoreUrl ?? '',
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        buttonText: json['button_text'] ?? 'Update',
      );

  static const PlatformVersionInfo empty = PlatformVersionInfo(
    latestVersion: '',
    minVersion: '',
    storeUrl: '',
    title: '',
    message: '',
    buttonText: 'Update',
  );
}

/// Version info returned by backend.
///
/// Supports two API shapes:
/// 1. **Per-platform** (recommended):
///    `android.latest_version`, `android.min_version`, `android.store_url`, etc.
/// 2. **Legacy / shared** (backward compat):
///    Top-level `latest_version`, `min_version`, `store_url` used as fallback
///    when the platform block doesn't contain its own version fields.
class AppVersionInfo {
  final bool forceUpdate;
  final PlatformVersionInfo android;
  final PlatformVersionInfo ios;

  const AppVersionInfo({
    required this.forceUpdate,
    required this.android,
    required this.ios,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    // Legacy top-level fallbacks
    final fallbackLatest = json['latest_version'] as String?;
    final fallbackMin = json['min_version'] as String?;
    final fallbackStoreUrl = json['store_url'] as String?;

    return AppVersionInfo(
      forceUpdate: json['force_update'] == true,
      android: PlatformVersionInfo.fromJson(
        (json['android'] as Map<String, dynamic>?) ?? {},
        fallbackLatest: fallbackLatest,
        fallbackMin: fallbackMin,
        fallbackStoreUrl: fallbackStoreUrl,
      ),
      ios: PlatformVersionInfo.fromJson(
        (json['ios'] as Map<String, dynamic>?) ?? {},
        fallbackLatest: fallbackLatest,
        fallbackMin: fallbackMin,
        fallbackStoreUrl: fallbackStoreUrl,
      ),
    );
  }

  /// Returns the correct platform block for the running OS.
  /// On web, defaults to android since web has no platform-specific store.
  PlatformVersionInfo get current {
    if (kIsWeb) return android;
    return Platform.isAndroid ? android : ios;
  }
}

/// Live global alert banner
class AppAlert {
  final bool isActive;
  final String title;
  final String message;
  final String type; // "info" | "warning" | "maintenance"
  final String? actionUrl;
  final String? actionLabel;

  const AppAlert({
    required this.isActive,
    required this.title,
    required this.message,
    required this.type,
    this.actionUrl,
    this.actionLabel,
  });

  factory AppAlert.fromJson(Map<String, dynamic> json) => AppAlert(
        isActive: json['is_active'] == true,
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        type: json['type'] ?? 'info',
        actionUrl: json['action_url'],
        actionLabel: json['action_label'],
      );

  bool get isMaintenance => type == 'maintenance';
}

/// Maintenance mode — when enabled the entire app is blocked.
class MaintenanceInfo {
  final bool isEnabled;
  final String title;
  final String subtitle;
  final String? expectedResume;

  const MaintenanceInfo({
    required this.isEnabled,
    required this.title,
    required this.subtitle,
    this.expectedResume,
  });

  factory MaintenanceInfo.fromJson(Map<String, dynamic> json) =>
      MaintenanceInfo(
        isEnabled: json['is_enabled'] == true,
        title: json['title'] ?? 'Under Maintenance',
        subtitle: json['subtitle'] ??
            "We're upgrading our systems for a better experience.",
        expectedResume: json['expected_resume'],
      );

  static const MaintenanceInfo off = MaintenanceInfo(
    isEnabled: false,
    title: '',
    subtitle: '',
  );
}

/// Combined response from GET /app/control
class AppControlData {
  final AppVersionInfo? versionInfo;
  final AppAlert? alert;
  final MaintenanceInfo maintenance;
  final String responsePlatform; // platform field from API response
  final bool dynamicSwitching;
  final int? dynamicSwitchingPassword;

  const AppControlData({
    this.versionInfo,
    this.alert,
    this.maintenance = MaintenanceInfo.off,
    this.responsePlatform = '',
    this.dynamicSwitching = false,
    this.dynamicSwitchingPassword,
  });

  /// Whether the response platform matches the running device platform.
  /// Returns false when server returns e.g. "web" but app runs on android/ios.
  bool get isPlatformMatch {
    if (responsePlatform.isEmpty)
      return true; // no platform field → assume match
    if (kIsWeb) return responsePlatform == 'web';
    try {
      if (Platform.isAndroid) return responsePlatform == 'android';
      if (Platform.isIOS) return responsePlatform == 'ios';
    } catch (_) {}
    return true; // fallback — don't block
  }

  factory AppControlData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return AppControlData(
      versionInfo: data.containsKey('version')
          ? AppVersionInfo.fromJson(data['version'])
          : null,
      alert: data.containsKey('alert') && data['alert'] != null
          ? AppAlert.fromJson(data['alert'])
          : null,
      maintenance:
          data.containsKey('maintenance') && data['maintenance'] != null
              ? MaintenanceInfo.fromJson(data['maintenance'])
              : MaintenanceInfo.off,
      responsePlatform: (data['platform'] as String?) ?? '',
      dynamicSwitching: data['dynamic_switching'] == true,
      dynamicSwitchingPassword: data['dynamic_switching_password'] != null 
          ? int.tryParse(data['dynamic_switching_password'].toString()) 
          : null,
    );
  }
}
