import 'package:flutter/foundation.dart';
import 'package:root_checker_plus/root_checker_plus.dart';
import 'dart:io';

/// Multi-layered root/jailbreak detection service.
///
/// Uses 5 independent detection layers to make bypass significantly
/// harder than a single-check approach. Each layer checks a different
/// indicator — an attacker would need to hook ALL of them simultaneously.
///
/// VAPT Finding 5: Hardened to resist Frida, Magisk Hide, and Xposed bypass.
class RootDetectionService {
  static Future<bool> isDeviceCompromised() async {
    if (kIsWeb) return false; // Root detection not applicable to web

    if (Platform.isAndroid) {
      return await _checkAndroid();
    } else if (Platform.isIOS) {
      return await _checkIOS();
    }
    return false;
  }

  /// Multi-layered Android root detection.
  static Future<bool> _checkAndroid() async {
    // ── Layer 1: Package-based detection (root_checker_plus) ────────────
    try {
      if (await RootCheckerPlus.isRootChecker() == true) return true;
    } catch (_) {
      // Plugin failure — continue to other layers
    }

    // ── Layer 2: Check for su binary in known paths ─────────────────────
    final suPaths = [
      '/system/bin/su',
      '/system/xbin/su',
      '/sbin/su',
      '/system/app/Superuser.apk',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/data/local/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/vendor/bin/su',
    ];
    for (final path in suPaths) {
      try {
        if (await File(path).exists()) return true;
      } catch (_) {}
    }

    // ── Layer 3: Check for Magisk / root management artifacts ───────────
    final magiskPaths = [
      '/sbin/.magisk',
      '/data/adb/magisk',
      '/cache/.disable_magisk',
      '/dev/.magisk.unblock',
    ];
    for (final path in magiskPaths) {
      try {
        if (await File(path).exists()) return true;
      } catch (_) {}
    }

    // ── Layer 4: Check for Frida (dynamic instrumentation tool) ─────────
    try {
      final maps = await File('/proc/self/maps').readAsString();
      if (maps.contains('frida') || maps.contains('gadget')) {
        return true;
      }
    } catch (_) {}

    // ── Layer 5: Check for Xposed / LSPosed / EdXposed hooks ────────────
    try {
      final maps = await File('/proc/self/maps').readAsString();
      if (maps.contains('xposed') ||
          maps.contains('edxposed') ||
          maps.contains('lsposed')) {
        return true;
      }
    } catch (_) {}

    // ── Layer 6: Check for common root management packages ──────────────
    // These are checked via /data/data/ directory existence
    final rootPackages = [
      '/data/data/com.topjohnwu.magisk',
      '/data/data/eu.chainfire.supersu',
      '/data/data/com.koushikdutta.superuser',
      '/data/data/com.noshufou.android.su',
      '/data/data/com.thirdparty.superuser',
      '/data/data/com.yellowes.su',
      '/data/data/com.zachspong.temprootremovejb',
      '/data/data/com.ramdroid.appquarantine',
    ];
    for (final path in rootPackages) {
      try {
        if (await Directory(path).exists()) return true;
      } catch (_) {}
    }

    // ── Layer 7: Test command execution (try running 'which su') ────────
    try {
      final result = await Process.run('which', ['su']);
      if (result.stdout.toString().trim().isNotEmpty) return true;
    } catch (_) {
      // Expected to fail on non-rooted devices
    }

    return false;
  }

  /// Multi-layered iOS jailbreak detection.
  ///
  /// VAPT Finding 5: Hardened with 7 independent layers to resist
  /// bypass by Frida, Cycript, Liberty Lite, and similar tools.
  static Future<bool> _checkIOS() async {
    // ── Layer 1: Package-based detection (root_checker_plus) ────────────
    try {
      if (await RootCheckerPlus.isJailbreak() == true) return true;
    } catch (_) {}

    // ── Layer 2: Check for common jailbreak file paths ─────────────────
    final jailbreakPaths = [
      // Classic jailbreak apps
      '/Applications/Cydia.app',
      '/Applications/Sileo.app',
      '/Applications/Zebra.app',
      '/Applications/Installer.app',
      '/Applications/Filza.app',
      '/Applications/iFile.app',
      '/Applications/blackra1n.app',
      // Substrate & hooks
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/Library/MobileSubstrate/DynamicLibraries',
      '/usr/lib/libsubstitute.dylib',
      '/usr/lib/substitute-loader.dylib',
      '/usr/lib/libhooker.dylib',
      '/usr/lib/TweakInject.dylib',
      // Shell & tools
      '/bin/bash',
      '/bin/sh',
      '/usr/sbin/sshd',
      '/usr/bin/ssh',
      '/usr/bin/sshd',
      '/usr/libexec/sftp-server',
      // Package managers
      '/etc/apt',
      '/etc/apt/sources.list.d',
      '/private/var/lib/apt/',
      '/private/var/lib/cydia',
      '/private/var/tmp/cydia.log',
      '/var/cache/apt',
      '/var/lib/dpkg',
      // Jailbreak artifacts
      '/private/var/stash',
      '/private/var/db/stash',
      '/private/var/jailbreak',
      '/private/var/mobile/Library/SBSettings',
      // Modern jailbreak tools
      '/private/var/checkra1n.dmg',
      '/private/var/binpack',
      '/var/LIB/undecimus',
      '/var/jb',                            // rootless jailbreaks (Dopamine, etc.)
      '/var/jb/usr/bin/su',
    ];
    for (final path in jailbreakPaths) {
      try {
        if (await File(path).exists()) return true;
        if (await Directory(path).exists()) return true;
      } catch (_) {}
    }

    // ── Layer 3: Check for writable system paths (sandbox escape) ──────
    // On non-jailbroken iOS, writing outside the sandbox fails.
    try {
      final testFile = File('/private/jailbreak_test_${DateTime.now().millisecondsSinceEpoch}');
      await testFile.writeAsString('jb_test');
      // If we get here, sandbox is broken — device is jailbroken
      await testFile.delete();
      return true;
    } catch (_) {
      // Expected to fail on non-jailbroken devices
    }

    // ── Layer 4: Check for Frida (dynamic instrumentation) ─────────────
    // Frida's default listening port is 27042
    try {
      final socket = await Socket.connect('127.0.0.1', 27042,
          timeout: const Duration(milliseconds: 200));
      socket.destroy();
      return true; // Frida server is running
    } catch (_) {
      // Expected to fail when Frida is not present
    }

    // ── Layer 5: Check for Cycript / instrumentation dylibs ────────────
    // Cycript listens on port 8556 by default
    try {
      final socket = await Socket.connect('127.0.0.1', 8556,
          timeout: const Duration(milliseconds: 200));
      socket.destroy();
      return true; // Cycript is running
    } catch (_) {}

    // ── Layer 6: Check for suspicious environment variables ────────────
    try {
      final env = Platform.environment;
      if (env.containsKey('DYLD_INSERT_LIBRARIES')) return true;
      if (env.containsKey('_MSSafeMode')) return true;
    } catch (_) {}

    // ── Layer 7: Check for symbolic links to jailbreak paths ───────────
    // Jailbroken devices often symlink /var/lib/undecimus, /var/jb, etc.
    final symlinkPaths = [
      '/var/lib/undecimus/apt',
      '/Applications',
      '/Library/Ringtones',
      '/Library/Wallpaper',
    ];
    for (final path in symlinkPaths) {
      try {
        final link = Link(path);
        if (await link.exists()) {
          final target = await link.target();
          if (target != path) return true; // Symlink detected — suspicious
        }
      } catch (_) {}
    }

    return false;
  }
}
