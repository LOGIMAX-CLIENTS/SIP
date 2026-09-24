package com.startgold.app

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import java.io.ByteArrayOutputStream
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
                    "getUpiApps" -> {
                        val url = call.argument<String>("url")
                        result.success(getUpiApps(url))
                    }
                    "launchUpiApp" -> {
                        val url = call.argument<String>("url")
                        val pkg = call.argument<String>("packageName")
                        val activity = call.argument<String>("activityName")
                        result.success(launchUpiApp(url, pkg, activity))
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
     * Lists installed apps that can pay a upi:// link, so Flutter can show its
     * own picker instead of the system "Open with" sheet.
     *
     * Why not the system sheet: on MIUI (seen on POCO F1 / MIUI 12, GetApps
     * 39.x) both ResolverActivity and ChooserActivity are redirected to
     * GetApps' AppChooserActivity, which finishes itself instantly — the
     * customer only sees a dim flicker and can never pick an app.
     *
     * Each entry carries the exact activity so the launch is explicit and
     * never goes through a system resolver again.
     */
    private fun getUpiApps(url: String?): List<Map<String, Any>> {
        if (url.isNullOrBlank()) return emptyList()
        val pm = packageManager
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        val seen = mutableSetOf<String>()
        val apps = mutableListOf<Map<String, Any>>()
        for (info in pm.queryIntentActivities(intent, 0)) {
            val activity = info.activityInfo ?: continue
            if (!seen.add(activity.packageName)) continue
            val app = mutableMapOf<String, Any>(
                "packageName" to activity.packageName,
                "activityName" to activity.name,
                "label" to pm.getApplicationLabel(activity.applicationInfo).toString(),
            )
            iconPng(activity.loadIcon(pm))?.let { app["icon"] = it }
            apps.add(app)
        }
        return apps
    }

    private fun iconPng(drawable: Drawable): ByteArray? = try {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    /** Opens [url] in exactly the app the customer picked (no system chooser). */
    private fun launchUpiApp(url: String?, pkg: String?, activity: String?): Boolean {
        if (url.isNullOrBlank() || pkg.isNullOrBlank()) return false
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        if (!activity.isNullOrBlank()) {
            intent.setClassName(pkg, activity)
        } else {
            intent.setPackage(pkg)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
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
