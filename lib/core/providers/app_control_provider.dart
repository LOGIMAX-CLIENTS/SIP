import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import '../models/app_control_model.dart';
import '../services/app_control_service.dart';
import '../security/certificate_pinning.dart';
import '../security/screenshot_security_service.dart';

// ─── Intervals ────────────────────────────────────────────────────────────────
const _kAlertPollInterval = Duration(minutes: 1); // check every 1 min globally
const _kMaintenancePollInterval =
    Duration(seconds: 30); // faster while in maintenance

class AppControlState {
  final AppControlData? data;
  final bool isLoading;
  final bool updateRequired;
  final bool forceUpdate;
  final bool showAlert;
  final bool isMaintenance;
  final String currentVersion;

  const AppControlState({
    this.data,
    this.isLoading = false,
    this.updateRequired = false,
    this.forceUpdate = false,
    this.showAlert = false,
    this.isMaintenance = false,
    this.currentVersion = '',
  });

  AppAlert? get alert => data?.alert;
  AppVersionInfo? get versionInfo => data?.versionInfo;
  MaintenanceInfo? get maintenanceInfo => data?.maintenance;

  AppControlState copyWith({
    AppControlData? data,
    bool? isLoading,
    bool? updateRequired,
    bool? forceUpdate,
    bool? showAlert,
    bool? isMaintenance,
    String? currentVersion,
  }) =>
      AppControlState(
        data: data ?? this.data,
        isLoading: isLoading ?? this.isLoading,
        updateRequired: updateRequired ?? this.updateRequired,
        forceUpdate: forceUpdate ?? this.forceUpdate,
        showAlert: showAlert ?? this.showAlert,
        isMaintenance: isMaintenance ?? this.isMaintenance,
        currentVersion: currentVersion ?? this.currentVersion,
      );
}

class AppControlNotifier extends StateNotifier<AppControlState> {
  final AppControlService _service;
  Timer? _pollTimer;
  Timer? _maintenancePollTimer;
  bool _initialized = false;

  AppControlNotifier(this._service) : super(const AppControlState());

  /// Call once at app startup and begin periodic alert refresh.
  /// Safe to call multiple times — only runs once.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _fetch();
    _startPolling();
  }

  /// Safety net — call from build() to guarantee initialization.
  void ensureInitialized() {
    if (!_initialized) {
      initialize();
    }
  }

  /// Faster polling while maintenance screen is showing.
  /// Automatically stops when maintenance is lifted.
  void startMaintenancePolling() {
    _maintenancePollTimer?.cancel();
    _maintenancePollTimer =
        Timer.periodic(_kMaintenancePollInterval, (_) => _fetch());
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kAlertPollInterval, (_) => _fetch());
  }

  Future<void> _fetch() async {
    state = state.copyWith(isLoading: true);

    try {
      final raw = await _service.fetchAppControl();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (kDebugMode)
        debugPrint('[AppControl] currentVersion: $currentVersion');

      if (raw == null) {
        if (kDebugMode) debugPrint('[AppControl] raw is null — skipping');
        state =
            state.copyWith(isLoading: false, currentVersion: currentVersion);
        return;
      }

      final controlData = AppControlData.fromJson(raw);
      final versionInfo = controlData.versionInfo;
      final maintenance = controlData.maintenance;

      // ── Dynamic SSL Pin Update ──
      // Server can push new cert fingerprints via app/control.
      // This allows cert renewals without app republishing.
      final dataMap = raw['data'];
      final rawPins = dataMap is Map ? dataMap['certificate_pins'] : null;
      if (rawPins is List && rawPins.isNotEmpty) {
        final pins = rawPins.cast<String>();
        await CertificatePinning.updatePins(pins);
      }

      // ── Dynamic Screenshot Protection Update ──
      final security = dataMap is Map ? dataMap['security'] : null;
      if (security is Map) {
        final enableSec = security['enable_screenshot_protection'];
        if (enableSec is bool) {
          if (AppConfig.enableScreenshotProtection != enableSec) {
            AppConfig.enableScreenshotProtection = enableSec;
            await ScreenshotSecurityService.initialize();
          }
        }
      }

      if (kDebugMode) {
        debugPrint(
            '[AppControl] versionInfo: ${versionInfo != null ? "parsed" : "null"}');
        debugPrint(
            '[AppControl] maintenance.isEnabled: ${maintenance.isEnabled}');
      }

      // ── Maintenance takes priority over everything ──
      if (maintenance.isEnabled) {
        state = state.copyWith(
          data: controlData,
          isLoading: false,
          isMaintenance: true,
          currentVersion: currentVersion,
        );
        return;
      }

      // ── Maintenance was lifted — stop fast polling ──
      if (state.isMaintenance && !maintenance.isEnabled) {
        _maintenancePollTimer?.cancel();
        _maintenancePollTimer = null;
      }

      // ── Version check (per-platform) ──
      // Skip if the server returned a config for a different platform
      // (e.g. server returns "web" but we're running on android/ios).
      bool updateRequired = false;
      bool forceUpdate = false;

      if (versionInfo != null &&
          currentVersion.isNotEmpty &&
          controlData.isPlatformMatch) {
        final platformVersion = versionInfo.current;

        updateRequired =
            _isLower(currentVersion, platformVersion.latestVersion);
        forceUpdate = versionInfo.forceUpdate ||
            _isLower(currentVersion, platformVersion.minVersion);

        if (kDebugMode) {
          debugPrint(
              '[AppControl] updateRequired: $updateRequired, forceUpdate: $forceUpdate');
        }
      } else if (!controlData.isPlatformMatch) {
        if (kDebugMode) {
          debugPrint(
              '[AppControl] Skipping version check — response platform "${controlData.responsePlatform}" does not match device');
        }
      }

      final alert = controlData.alert;
      // Suppress maintenance-type alerts when maintenance mode is off
      final showAlert = alert != null &&
          alert.isActive &&
          !(alert.isMaintenance && !maintenance.isEnabled);

      state = state.copyWith(
        data: controlData,
        isLoading: false,
        updateRequired: updateRequired,
        forceUpdate: forceUpdate,
        showAlert: showAlert,
        isMaintenance: false,
        currentVersion: currentVersion,
      );
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('[AppControl] ERROR in _fetch: $e');
        debugPrint('[AppControl] Stack: $stack');
      }
      state = state.copyWith(isLoading: false);
    }
  }

  void dismissUpdate() {
    if (!state.forceUpdate) {
      state = state.copyWith(updateRequired: false);
    }
  }

  void dismissAlert() {
    state = state.copyWith(showAlert: false);
  }

  /// Pre-action gate — call before any critical transaction (payment,
  /// withdrawal, SIP creation). Does a **fresh** fetch from the server
  /// so the check is real-time, not stale from the 5-min poll.
  ///
  /// Returns a [MaintenanceGateResult] indicating whether the action
  /// should be blocked and the reason to show to the user.
  Future<MaintenanceGateResult> checkBeforeAction() async {
    try {
      final raw = await _service.fetchAppControl();
      if (raw == null) {
        // Network failed — allow action (don't block on connectivity issues)
        return MaintenanceGateResult.clear;
      }

      final controlData = AppControlData.fromJson(raw);
      final maintenance = controlData.maintenance;

      // ── Full maintenance → block immediately ──
      if (maintenance.isEnabled) {
        // Also update the app state so the wrapper can redirect
        state = state.copyWith(
          data: controlData,
          isMaintenance: true,
        );
        return MaintenanceGateResult(
          blocked: true,
          title: maintenance.title.isNotEmpty
              ? maintenance.title
              : 'Under Maintenance',
          message: maintenance.subtitle.isNotEmpty
              ? maintenance.subtitle
              : 'We are upgrading our systems. Please try again later.',
          isMaintenance: true,
        );
      }

      // ── Active alert (warning/info) → block with alert message ──
      final alert = controlData.alert;
      if (alert != null && alert.isActive && alert.isMaintenance) {
        return MaintenanceGateResult(
          blocked: true,
          title: alert.title,
          message: alert.message,
          isMaintenance: false,
        );
      }

      // ── All clear — update state with latest data ──
      state = state.copyWith(
        data: controlData,
        isMaintenance: false,
        showAlert: alert != null && alert.isActive,
      );
      return MaintenanceGateResult.clear;
    } catch (e) {
      // On error, allow action (don't block user on client-side failures)
      return MaintenanceGateResult.clear;
    }
  }

  Future<void> refresh() => _fetch();

  /// Compare semantic versions: returns true if [a] < [b]
  bool _isLower(String a, String b) {
    try {
      final av = a.split('.').map(int.parse).toList();
      final bv = b.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final ai = i < av.length ? av[i] : 0;
        final bi = i < bv.length ? bv[i] : 0;
        if (ai < bi) return true;
        if (ai > bi) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _maintenancePollTimer?.cancel();
    super.dispose();
  }
}

final _appControlServiceProvider =
    Provider<AppControlService>((ref) => AppControlService());

final appControlProvider =
    StateNotifierProvider<AppControlNotifier, AppControlState>(
  (ref) => AppControlNotifier(ref.read(_appControlServiceProvider)),
);

/// Result of a [checkBeforeAction] call.
class MaintenanceGateResult {
  final bool blocked;
  final String title;
  final String message;
  final bool isMaintenance; // true = full maintenance, false = warning alert

  const MaintenanceGateResult({
    this.blocked = false,
    this.title = '',
    this.message = '',
    this.isMaintenance = false,
  });

  /// Convenience constant — action is allowed.
  static const clear = MaintenanceGateResult();
}
