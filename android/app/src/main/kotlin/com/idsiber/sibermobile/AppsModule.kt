package com.idsiber.sibermobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Environment
import android.os.StatFs
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService

/**
 * Apps + storage module for the DeviceBridge channel: disk space on the
 * primary volume, installed-app listing (background thread), install check
 * and app launching.
 */
internal class AppsModule(
    private val context: Context,
    private val executor: ExecutorService,
    private val mainHandler: android.os.Handler,
) {
    /** Total and free bytes on the primary external storage volume. */
    internal fun getDiskSpace(): Map<String, Long> {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return mapOf(
            "totalBytes" to stat.blockCountLong * stat.blockSizeLong,
            "freeBytes" to stat.availableBlocksLong * stat.blockSizeLong,
        )
    }

    internal fun getInstalledApps(includeSystemApps: Boolean): List<Map<String, Any?>> {
        val pm = context.packageManager
        return pm.getInstalledPackages(0)
            .asSequence()
            .filter { it.applicationInfo != null }
            .filter {
                includeSystemApps ||
                    (it.applicationInfo!!.flags and ApplicationInfo.FLAG_SYSTEM) == 0
            }
            .map {
                mapOf(
                    "name" to pm.getApplicationLabel(it.applicationInfo!!).toString(),
                    "packageName" to it.packageName,
                    "versionName" to it.versionName,
                    "isSystemApp" to
                        ((it.applicationInfo!!.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            }
            .toList()
    }


    /** Channel entry: runs the listing off the main thread. */
    internal fun getInstalledAppsChannel(
        includeSystemApps: Boolean,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            val apps = try {
                getInstalledApps(includeSystemApps)
            } catch (e: Exception) {
                null
            }
            mainHandler.post {
                if (apps == null) {
                    result.error("ERROR", "Failed to list installed apps", null)
                } else {
                    result.success(apps)
                }
            }
        }
    }

    internal fun isAppInstalled(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    internal fun startApp(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            if (context !is Activity) launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
