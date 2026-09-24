import 'package:flutter/material.dart';

/// VAPT Finding #4 — Unintended Data Leakage (Clipboard)
///
/// Provides a reusable [contextMenuBuilder] that completely disables
/// the clipboard context menu (Copy / Cut / Paste / Select All).
///
/// This prevents sensitive data from being accessible via the
/// system clipboard where other apps can read it.
///
/// Usage:
/// ```dart
/// TextField(
///   enableInteractiveSelection: false,
///   contextMenuBuilder: SecureClipboard.none,
///   enableSuggestions: false,
///   autocorrect: false,
/// )
/// ```
class SecureClipboard {
  SecureClipboard._();

  /// Completely disables the context menu — no Copy, Cut, Paste, Select All.
  ///
  /// Use this on ALL sensitive input fields (phone, OTP, PIN, PAN,
  /// UPI, bank account, withdrawal amount, etc.).
  ///
  /// For maximum protection, also set on the TextField / TextFormField:
  /// - `enableInteractiveSelection: false`
  /// - `enableSuggestions: false`
  /// - `autocorrect: false`
  static Widget none(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return const SizedBox.shrink();
  }
}
