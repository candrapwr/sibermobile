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
    private var crosshairParams: WindowManager.LayoutParams? = null
    private var bubble: View? = null
    private var intervalMs = AutoClickerService.DEFAULT_INTERVAL_MS
    private var intervalLabel: android.widget.EditText? = null
    private var playButton: ImageView? = null

    /**
     * Makes the crosshair transparent to touches while clicking, so the
     * injected taps reach the app UNDER it instead of hitting the crosshair
     * overlay itself (which sits on the topmost window layer).
     */
    private fun setCrosshairPassThrough(passThrough: Boolean) {
        val ch = crosshair ?: return
        val params = crosshairParams ?: return
        if (passThrough) {
            params.flags = params.flags or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        } else {
            params.flags = params.flags and
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        }
        try {
            windowManager.updateViewLayout(ch, params)
        } catch (_: Exception) {}
    }

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
        setCrosshairPassThrough(false)
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
        // Stop action in the notification: always reachable from the shade,
        // immune to the input flood at fast intervals (1-100ms) that makes
        // the overlay buttons hard to hit.
        val stopIntent = Intent(this, AutoClickerOverlay::class.java)
            .setAction(ACTION_STOP)
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        startForeground(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.drawable.ic_busy)
                .setContentTitle("Auto clicker aktif")
                .setContentText("Tarik ke bawah → Stop, atau pakai tombol ⏸ di bubble.")
                .setOngoing(true)
                .setContentIntent(open)
                .addAction(R.drawable.ic_busy, "STOP", stopPending)
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
        crosshairParams = params
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

        val label = android.widget.EditText(this).apply {
            setText(intervalMs.toString())
            setTextColor(Color.WHITE)
            textSize = 12f
            gravity = Gravity.CENTER
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
            hint = "ms"
            setHintTextColor(Color.parseColor("#88FFFFFF"))
            setBackgroundColor(Color.parseColor("#22FFFFFF"))
            setPadding(pad(4), pad(2), pad(4), pad(2))
        }
        intervalLabel = label

        // When tapped, make the overlay focusable so the keyboard appears;
        // on Enter/done, apply the value and unfocus.
        label.setOnFocusChangeListener { v, hasFocus ->
            val bubbleView = bubble
            if (bubbleView != null) {
                val lp = bubbleView.layoutParams as? WindowManager.LayoutParams
                if (lp != null) {
                    if (hasFocus) {
                        lp.flags = lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                    } else {
                        lp.flags = lp.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    }
                    try { windowManager.updateViewLayout(bubbleView, lp) } catch (_: Exception) {}
                }
            }
        }
        label.setOnEditorActionListener { v, actionId, _ ->
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_DONE) {
                val ms = v.text.toString().toIntOrNull() ?: intervalMs
                intervalMs = ms.coerceIn(1, AutoClickerService.MAX_INTERVAL_MS)
                v.setText(intervalMs.toString())
                v.clearFocus()
                syncEngine()
                true
            } else false
        }

        fun miniButton(icon: Int, onTap: () -> Unit): ImageView =
            ImageView(this).apply {
                setImageResource(icon)
                setColorFilter(Color.WHITE)
                setOnClickListener { onTap() }
            }

        val close = miniButton(android.R.drawable.ic_delete) {
            AutoClickerService.instance?.stop()
            stopSelf()
        }

        playPause.setOnClickListener {
            val engine = AutoClickerService.instance ?: return@setOnClickListener
            if (engine.isRunning) {
                engine.stop()
                // Restore draggability on the crosshair.
                setCrosshairPassThrough(false)
                playPause.setImageResource(android.R.drawable.ic_media_play)
            } else {
                syncEngine()
                // Make the crosshair transparent to touches so the injected
                // taps reach the app underneath, not the crosshair overlay.
                setCrosshairPassThrough(true)
                // Small delay so the play-button tap itself doesn't get
                // counted as the first auto-tap.
                playPause.postDelayed({ engine.start() }, 350)
                playPause.setImageResource(android.R.drawable.ic_media_pause)
            }
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC071120"))
            setPadding(pad(6), pad(6), pad(6), pad(6))
            addView(
                playPause,
                LinearLayout.LayoutParams(pad(48), pad(48)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                label,
                LinearLayout.LayoutParams(pad(56), pad(32)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                close,
                LinearLayout.LayoutParams(pad(40), pad(40)).apply { gravity = Gravity.CENTER_HORIZONTAL },
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
     *  Posted to run after layout so getLocationOnScreen is accurate. */
    private fun syncEngine() {
        val ch = crosshair ?: return
        val engine = AutoClickerService.instance
        ch.post {
            val e = AutoClickerService.instance ?: return@post
            val loc = IntArray(2)
            ch.getLocationOnScreen(loc)
            val x = loc[0] + ch.width / 2f
            val y = loc[1] + ch.height / 2f
            e.configure(x, y, intervalMs)
        }
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
