package com.startgold.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.startgold.app/security"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Prevent screenshots, screen recording, and proxy screen capture
        // on all screens — required for fintech/PCI-DSS compliance.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "clearClipboard" -> {
                        clearClipboard()
                        result.success(true)
                    }
                    "setScreenshotProtection" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        setScreenshotProtection(enabled)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setScreenshotProtection(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
    }

    /**
     * Clears the system clipboard using the native ClipboardManager.
     * This also clears the keyboard's (Gboard) clipboard suggestion strip
     * on most Android versions.
     *
     * - API 28+ (Android P): Uses clearPrimaryClip() for a clean wipe.
     * - Older: Sets an empty clip to overwrite the current content.
     */
    private fun clearClipboard() {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            clipboard.clearPrimaryClip()
        } else {
            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        }
    }
}
