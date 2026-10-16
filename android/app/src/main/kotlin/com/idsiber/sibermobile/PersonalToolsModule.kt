package com.idsiber.sibermobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/**
 * Personal-tools glue for the DeviceBridge channel: auto clicker status
 * and permission deep-links, overlay start/stop, and the busy keep-alive
 * service toggle.
 */
internal class PersonalToolsModule(
    private val context: Context,
    private val mainHandler: android.os.Handler,
) {
    internal fun autoClickerStatus(result: MethodChannel.Result) {
        val overlayGranted = Settings.canDrawOverlays(context)
        val accessibilityOn = AutoClickerService.instance != null
        mainHandler.post {
            result.success(
                mapOf(
                    "overlayGranted" to overlayGranted,
                    "accessibilityOn" to accessibilityOn,
                    "running" to (AutoClickerService.instance?.isRunning == true),
                ),
            )
        }
    }

    internal fun requestOverlayPermission() {
        if (Settings.canDrawOverlays(context)) return
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + context.packageName),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        } catch (_: Exception) {
            try {
                context.startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (_: Exception) {}
        }
    }

    internal fun openAccessibilitySettings() {
        try {
            context.startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {}
    }

    internal fun startAutoClickerOverlay() {
        val intent = Intent(context, AutoClickerOverlay::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (_: Exception) {}
    }

    internal fun stopAutoClickerOverlay() {
        val intent = Intent(context, AutoClickerOverlay::class.java)
        intent.action = AutoClickerOverlay.ACTION_STOP
        try {
            context.startService(intent)
        } catch (_: Exception) {}
    }

    /** Starts/stops the keep-alive foreground service while a turn runs. */
    internal fun setBusyService(busy: Boolean, text: String?) {
        try {
            val intent = Intent(context, BusyService::class.java)
            if (busy) {
                // A turn always starts from the foreground UI, so launching
                // the foreground service from the application context is
                // allowed even on Android 12+.
                intent.action = BusyService.ACTION_START
                intent.putExtra(BusyService.EXTRA_TEXT, text ?: "Sedang memproses…")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } else {
                // The turn may end while the app is in the background, where
                // startService() is forbidden — stopService() always works.
                context.stopService(intent)
            }
        } catch (_: Exception) {
            // Best effort: a failed start must never break the chat turn.
        }
    }
}
