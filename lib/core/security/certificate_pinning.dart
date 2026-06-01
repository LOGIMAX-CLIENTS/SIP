import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/io.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Dynamic SSL Certificate & Public Key Pinning.
///
/// Supports TWO pin formats:
///   1. **Certificate fingerprint** (colon-separated hex):
///      `"F3:AB:FB:70:B3:D0:..."` — changes on every cert renewal
///   2. **Public key pin** (Base64 SPKI SHA-256):
///      `"hEdBgpqZW1U6x1XwUf+0UfNg4zu2oy/OwkIOGCppqXs="` — stable across renewals
///
/// Public key pins are **recommended** for production because they
/// don't change when the certificate is renewed (as long as the server
/// reuses the same key pair).
///
/// How it works:
///   1. Hardcoded pins in [AppConfig] = fallback (first install / offline)
///   2. Server sends updated pins via `app/control` API → [updatePins]
///   3. Pins are cached in SecureStorage → survive app restarts
///   4. No app republish needed for cert renewals.
class CertificatePinning {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kPinsKey = 'ssl_cert_pins';

  /// Cached pins loaded at startup — avoids async calls during SSL handshake.
  static List<String> _activePins = [];

  // ── Initialization ──────────────────────────────────────────────────────

  /// Call once at app startup (e.g., in main.dart).
  /// Loads cached server-managed pins, falls back to hardcoded.
  static Future<void> init() async {
    try {
      final cached = await _storage.read(key: _kPinsKey);
      if (cached != null && cached.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cached);
        _activePins = decoded.cast<String>();
        if (kDebugMode) {
          debugPrint('CERT PIN: Loaded ${_activePins.length} cached pins');
        }
      }
    } catch (_) {
      // Cache corrupted or empty — will use hardcoded fallback
    }

    // If no cached pins, use hardcoded as fallback
    if (_activePins.isEmpty) {
      _activePins = List.from(AppConfig.allowedCertFingerprints);
    }
  }

  // ── Server-Managed Pin Update ───────────────────────────────────────────

  /// Called from AppControlNotifier after fetching `app/control`.
  /// Accepts both cert fingerprints and public key pins in the same array.
  static Future<void> updatePins(List<String> serverPins) async {
    if (serverPins.isEmpty) return;

    _activePins = List.from(serverPins);

    try {
      await _storage.write(key: _kPinsKey, value: jsonEncode(serverPins));
      if (kDebugMode) {
        debugPrint('CERT PIN: Updated ${serverPins.length} pins from server');
      }
    } catch (_) {
      // Write failed — in-memory pins still active for this session
    }
  }

  // ── Dio Setup ───────────────────────────────────────────────────────────

  /// Applies SSL pinning to a Dio instance.
  static void setup(Dio dio) {
    if (kIsWeb) return;

    try {
      if (dio.httpClientAdapter is IOHttpClientAdapter) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();

          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) {
            final pins = _activePins;

            // No valid pins configured — reject (fail-closed)
            if (pins.isEmpty ||
                pins.every((fp) => fp.startsWith('XX:'))) {
              if (kDebugMode) {
                debugPrint(
                    'CERT PIN: No valid pins configured — rejecting $host');
              }
              return false;
            }

            // Split pins by format
            final certPins = <String>[];   // Colon-hex: "AA:BB:CC:..."
            final spkiPins = <String>[];   // Base64: "hEdBgp...="

            for (final pin in pins) {
              if (pin.contains(':')) {
                certPins.add(pin);
              } else {
                spkiPins.add(pin);
              }
            }

            // 1. Check certificate fingerprint (if any cert pins exist)
            if (certPins.isNotEmpty) {
              final certFingerprint = _certFingerprint(cert.der);
              if (certPins.contains(certFingerprint)) return true;
            }

            // 2. Check public key pin / SPKI hash (if any SPKI pins exist)
            if (spkiPins.isNotEmpty) {
              final spkiHash = _spkiHash(cert.der);
              if (spkiPins.contains(spkiHash)) return true;
            }

            if (kDebugMode) {
              debugPrint('CERT PIN: Mismatch for $host');
              debugPrint('  Cert: ${_certFingerprint(cert.der)}');
              debugPrint('  SPKI: ${_spkiHash(cert.der)}');
            }

            return false;
          };

          return client;
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Certificate Pinning Error: $e');
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// SHA-256 fingerprint of the full DER certificate (colon-separated hex).
  static String _certFingerprint(Uint8List der) {
    final digest = sha256.convert(der);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  /// SHA-256 hash of the Subject Public Key Info (Base64).
  /// This is the standard SPKI pin format used by Chrome, OkHttp, etc.
  /// Stays the same across cert renewals if the key pair is reused.
  static String _spkiHash(Uint8List der) {
    // Parse SubjectPublicKeyInfo from the DER certificate.
    // The SPKI block starts after the outer SEQUENCE → TBS → ...
    // We extract it by finding the public key ASN.1 structure.
    final spki = _extractSpki(der);
    final digest = sha256.convert(spki);
    return base64Encode(digest.bytes);
  }

  /// Extracts the SubjectPublicKeyInfo bytes from a DER-encoded X.509 cert.
  /// Walks the ASN.1 structure: SEQUENCE → TBSCertificate → skip fields → SPKI.
  static Uint8List _extractSpki(Uint8List der) {
    var offset = 0;

    // Parse outer SEQUENCE
    offset = _parseTag(der, offset); // outer SEQUENCE tag
    offset = _parseLength(der, offset); // outer SEQUENCE length

    // Parse TBSCertificate SEQUENCE
    offset = _parseTag(der, offset); // TBS SEQUENCE tag
    final tbsLenEnd = _parseLength(der, offset);
    offset = tbsLenEnd;

    // Field 0: version [0] EXPLICIT (optional — skip if present)
    if (der[offset] == 0xA0) {
      offset = _parseTag(der, offset);
      final vLen = _getLengthValue(der, offset);
      offset = _parseLength(der, offset) + vLen;
    }

    // Field 1: serialNumber INTEGER — skip
    offset = _skipTlv(der, offset);

    // Field 2: signature AlgorithmIdentifier SEQUENCE — skip
    offset = _skipTlv(der, offset);

    // Field 3: issuer Name SEQUENCE — skip
    offset = _skipTlv(der, offset);

    // Field 4: validity SEQUENCE — skip
    offset = _skipTlv(der, offset);

    // Field 5: subject Name SEQUENCE — skip
    offset = _skipTlv(der, offset);

    // Field 6: subjectPublicKeyInfo SEQUENCE — THIS IS WHAT WE WANT
    final spkiStart = offset;
    final spkiEnd = _skipTlv(der, offset);

    return Uint8List.sublistView(der, spkiStart, spkiEnd);
  }

  /// Parses ASN.1 tag byte(s), returns offset after tag.
  static int _parseTag(Uint8List data, int offset) {
    if ((data[offset] & 0x1F) == 0x1F) {
      // Multi-byte tag
      offset++;
      while (data[offset] & 0x80 != 0) offset++;
      return offset + 1;
    }
    return offset + 1;
  }

  /// Parses ASN.1 length field, returns offset after length bytes.
  static int _parseLength(Uint8List data, int offset) {
    if (data[offset] & 0x80 == 0) {
      return offset + 1;
    }
    final numBytes = data[offset] & 0x7F;
    return offset + 1 + numBytes;
  }

  /// Gets the actual length value from an ASN.1 length field.
  static int _getLengthValue(Uint8List data, int offset) {
    if (data[offset] & 0x80 == 0) {
      return data[offset];
    }
    final numBytes = data[offset] & 0x7F;
    var length = 0;
    for (var i = 1; i <= numBytes; i++) {
      length = (length << 8) | data[offset + i];
    }
    return length;
  }

  /// Skips an entire TLV (tag-length-value) block, returns offset after it.
  static int _skipTlv(Uint8List data, int offset) {
    offset = _parseTag(data, offset);
    final lenValue = _getLengthValue(data, offset);
    offset = _parseLength(data, offset);
    return offset + lenValue;
  }

  /// Clears cached pins (called on logout).
  static Future<void> clearCache() async {
    _activePins = List.from(AppConfig.allowedCertFingerprints);
    try {
      await _storage.delete(key: _kPinsKey);
    } catch (_) {}
  }
}
