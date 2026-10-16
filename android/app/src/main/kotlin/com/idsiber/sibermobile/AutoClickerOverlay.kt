package com.idsiber.sibermobile

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Floating auto-clicker UI: a draggable crosshair marking the tap position
 * plus a compact control bubble (interval stepper, start/stop, close).
 * Runs as a foreground service so the overlay survives; every change is
 * applied live to [AutoClickerService].
 */
class AutoClickerOverlay : android.app.Service() {

    private lateinit var windowManager: WindowManager
    private var crosshair: View? = null
    private var bubble: View? = null
    private var intervalMs = AutoClickerService.DEFAULT_INTERVAL_MS
    private var intervalLabel: TextView? = null
    private var playButton: ImageView? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startAsForeground()
        addCrosshair()
        addBubble()
        syncEngine()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            AutoClickerService.instance?.stop()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        AutoClickerService.instance?.stop()
        crosshair?.let { try { windowManager.removeView(it) } catch (_: Exception) {} }
        bubble?.let { try { windowManager.removeView(it) } catch (_: Exception) {} }
        super.onDestroy()
    }

    private fun startAsForeground() {
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Auto clicker",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val open = PendingIntent.getActivity(
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
        startForeground(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.drawable.ic_busy)
                .setContentTitle("Auto clicker aktif")
                .setContentText("Geser crosshair, atur interval dari bubble.")
                .setOngoing(true)
                .setContentIntent(open)
                .build(),
        )
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun addCrosshair() {
        val dp = resources.displayMetrics.density
        val size = (44 * dp).toInt()

        val view = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_mylocation)
            setColorFilter(Color.parseColor("#075DFF"))
            alpha = 0.9f
        }
        val params = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = windowManager.defaultDisplay.width / 2 - size / 2
            y = windowManager.defaultDisplay.height / 2 - size / 2
        }

        attachDrag(view, params) { _, _ ->
            syncEngine()
        }
        windowManager.addView(view, params)
        crosshair = view
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun addBubble() {
        val dp = resources.displayMetrics.density
        fun pad(v: Int) = (v * dp).toInt()

        val playPause = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_media_play)
            setColorFilter(Color.WHITE)
        }
        playButton = playPause

        val label = TextView(this).apply {
            text = formatInterval(intervalMs)
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            minWidth = pad(44)
        }
        intervalLabel = label

        fun miniButton(icon: Int, onTap: () -> Unit): ImageView =
            ImageView(this).apply {
                setImageResource(icon)
                setColorFilter(Color.WHITE)
                setOnClickListener { onTap() }
            }

        val faster = miniButton(android.R.drawable.arrow_up_float) {
            intervalMs = (intervalMs / 2).coerceAtLeast(AutoClickerService.MIN_INTERVAL_MS)
            label.text = formatInterval(intervalMs)
            syncEngine()
        }
        val slower = miniButton(android.R.drawable.arrow_down_float) {
            val next = intervalMs * 2
            intervalMs = next.coerceAtMost(AutoClickerService.MAX_INTERVAL_MS)
            label.text = formatInterval(intervalMs)
            syncEngine()
        }
        val close = miniButton(android.R.drawable.ic_delete) {
            AutoClickerService.instance?.stop()
            stopSelf()
        }

        playPause.setOnClickListener {
            val engine = AutoClickerService.instance ?: return@setOnClickListener
            if (engine.isRunning) {
                engine.stop()
                playPause.setImageResource(android.R.drawable.ic_media_play)
            } else {
                // Always re-sync before starting: onCreate may have run before
                // the accessibility service connected.
                syncEngine()
                engine.start()
                playPause.setImageResource(android.R.drawable.ic_media_pause)
            }
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC071120"))
            setPadding(pad(4), pad(4), pad(4), pad(4))
            addView(
                playPause,
                LinearLayout.LayoutParams(pad(36), pad(36)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                label,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                faster,
                LinearLayout.LayoutParams(pad(32), pad(32)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                slower,
                LinearLayout.LayoutParams(pad(32), pad(32)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                close,
                LinearLayout.LayoutParams(pad(32), pad(32)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = pad(8)
            y = windowManager.defaultDisplay.height / 3
        }

        attachDrag(column, params) { _, _ -> }
        windowManager.addView(column, params)
        bubble = column
    }

    /** Generic drag handling that updates the window position live. */
    @SuppressLint("ClickableViewAccessibility")
    private fun attachDrag(
        view: View,
        params: WindowManager.LayoutParams,
        onRelease: (Int, Int) -> Unit,
    ) {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (dx * dx + dy * dy > 25) moved = true
                    params.x = startX + dx
                    params.y = startY + dy
                    windowManager.updateViewLayout(v, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) onRelease(params.x, params.y)
                    v.performClick()
                    true
                }
                else -> false
            }
        }
    }

    /** Push current overlay state (crosshair center + interval) to the engine.
     *  Uses the window LayoutParams directly — getLocationOnScreen returns
     *  [0,0] for TYPE_APPLICATION_OVERLAY windows. */
    private fun syncEngine() {
        val engine = AutoClickerService.instance ?: return
        val ch = crosshair ?: return
        val chParams = ch.layoutParams as? WindowManager.LayoutParams ?: return
        // params.x/y are the top-left corner with Gravity.TOP|START; the tap
        // point is the center of the crosshair view.
        val x = chParams.x + ch.width / 2f
        val y = chParams.y + ch.height / 2f
        engine.configure(x, y, intervalMs)
    }

    private fun formatInterval(ms: Int): String =
        if (ms >= 1000) {
            if (ms % 1000 == 0) "${ms / 1000}s" else String.format("%.1fs", ms / 1000f)
        } else {
            "${ms}ms"
        }

    companion object {
        const val CHANNEL_ID = "auto_clicker"
        const val NOTIFICATION_ID = 4712
        const val ACTION_STOP = "com.idsiber.sibermobile.autoclicker.STOP"
    }
}
