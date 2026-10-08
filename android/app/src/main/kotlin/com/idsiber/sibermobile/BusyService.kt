package com.idsiber.sibermobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service shown while the agent is working: with it, Android
 * keeps the process alive across screen-off, doze and swipe-from-recents,
 * so an in-flight turn survives the user leaving the app. Started/stopped
 * from DeviceBridge via the `setBusy` channel method.
 */
class BusyService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            else -> {
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Sedang memproses…"
                startAsForeground(text)
            }
        }
        return START_NOT_STICKY
    }

    private fun startAsForeground(text: String) {
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Proses berjalan",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        val notification = builder
            .setSmallIcon(R.drawable.ic_busy)
            .setContentTitle("SiberMobile")
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(openApp)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_START = "com.idsiber.sibermobile.busy.START"
        const val ACTION_STOP = "com.idsiber.sibermobile.busy.STOP"
        const val EXTRA_TEXT = "text"
        const val CHANNEL_ID = "siber_busy"
        const val NOTIFICATION_ID = 4711
    }
}
