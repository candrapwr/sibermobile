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
import android.util.Log

/**
 * Floating auto-clicker UI: a draggable crosshair marking the tap position
 * plus a compact control bubble (interval stepper, start/stop, close).
 * Runs as a foreground service so the overlay survives; every change is
 * applied live to [AutoClickerService].
 */
class AutoClickerOverlay : android.app.Service() {

    private lateinit var windowManager: WindowManager

    /**
     * WindowManager that owns the overlay views. Normally the service's own,
     * but TYPE_ACCESSIBILITY_OVERLAY windows must be added through the
     * accessibility service's manager (see [addViews]).
     */
    private var viewManager: WindowManager? = null
    private var windowType = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
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
            wm().updateViewLayout(ch, params)
        } catch (_: Exception) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun wm(): WindowManager = viewManager ?: windowManager

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startAsForeground()
        addViews()
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
        val wm = wm()
        crosshair?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        bubble?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        viewManager = null
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

    /**
     * TYPE_ACCESSIBILITY_OVERLAY (2032) windows must be added through the
     * accessibility service's OWN WindowManager — only it holds the window
     * token the system registered for the accessibility connection. Adding
     * that type through any other service's WindowManager throws
     * BadTokenException("token null is not valid"), even in the same
     * process/UID. The accessibility input path keeps the overlay's buttons
     * responsive while dispatchGesture floods the regular input pipeline.
     */
    private fun addViews() {
        val a11y = AutoClickerService.instance
        if (a11y != null) {
            val a11yWm =
                a11y.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            windowType = 2032
            try {
                addCrosshair(a11yWm)
                addBubble(a11yWm)
                viewManager = a11yWm
                Log.d(TAG, "overlay windows on accessibility path (type 2032)")
                return
            } catch (e: Exception) {
                // Token not usable (service still connecting); clean up any
                // partially-added view and fall back to a normal overlay.
                Log.w(TAG, "type 2032 rejected, falling back to 2038", e)
                crosshair?.let { try { a11yWm.removeView(it) } catch (_: Exception) {} }
                bubble?.let { try { a11yWm.removeView(it) } catch (_: Exception) {} }
                crosshair = null
                crosshairParams = null
                bubble = null
            }
        }
        windowType = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        addCrosshair(windowManager)
        addBubble(windowManager)
        viewManager = windowManager
        Log.d(TAG, "overlay windows on app-overlay path (type 2038)")
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun addCrosshair(wm: WindowManager) {
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
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = windowManager.defaultDisplay.width / 2 - size / 2
            y = windowManager.defaultDisplay.height / 2 - size / 2
        }

        attachDrag(view, view, params) { _, _ ->
            syncEngine()
        }
        wm.addView(view, params)
        crosshair = view
        crosshairParams = params
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun addBubble(wm: WindowManager) {
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

        // When tapped, make the overlay focusable so the keyboard appears.
        // When focus leaves, commit the typed value so it also applies
        // without the user pressing Enter/done.
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
                    try { wm().updateViewLayout(bubbleView, lp) } catch (_: Exception) {}
                }
            }
            if (!hasFocus) {
                applyIntervalFromField()
                // A mid-run edit takes effect immediately while clicking.
                if (AutoClickerService.instance?.isRunning == true) syncEngine()
            }
        }
        label.setOnEditorActionListener { v, actionId, _ ->
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_DONE) {
                applyIntervalFromField()
                v.clearFocus()
                syncEngine()
                true
            } else false
        }

        // ACTION_DOWN instead of click — same flood-resilience reason as
        // the play/pause button.
        fun miniButton(icon: Int, onTap: () -> Unit): ImageView =
            ImageView(this).apply {
                setImageResource(icon)
                setColorFilter(Color.WHITE)
                setOnTouchListener { v, event ->
                    if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                        v.performClick()
                        onTap()
                    }
                    true
                }
            }

        val close = miniButton(android.R.drawable.ic_delete) {
            AutoClickerService.instance?.stop()
            stopSelf()
        }

        // Dedicated drag handle: every other part of the panel is covered by
        // an interactive control (play, interval field, close), so this strip
        // under the close button is the panel's drag area.
        val dragHandle = TextView(this).apply {
            text = "⠿"
            setTextColor(Color.parseColor("#88FFFFFF"))
            gravity = Gravity.CENTER
            textSize = 16f
        }

        // Act on ACTION_DOWN, never on a full click. While taps are injected
        // at 1-100ms intervals the input stream is flooded and the click
        // contract (DOWN + UP on the same view with no cancel in between)
        // frequently breaks — the UP never arrives or the press is cancelled.
        // Acting on the single DOWN event makes the button respond instantly
        // and reliably at any interval.
        playPause.setOnTouchListener { v, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                v.performClick()
                // The user may have typed a new interval and pressed play
                // without hitting Enter — read the field now so the clicker
                // starts with what is on screen, not the last committed value.
                applyIntervalFromField()
                intervalLabel?.clearFocus()
                val engine = AutoClickerService.instance
                if (engine != null) {
                    if (engine.isRunning) {
                        Log.d(TAG, "pause via bubble ACTION_DOWN")
                        engine.stop()
                        // Restore draggability on the crosshair.
                        setCrosshairPassThrough(false)
                        playPause.setImageResource(android.R.drawable.ic_media_play)
                    } else {
                        Log.d(TAG, "start via bubble ACTION_DOWN intervalMs=$intervalMs")
                        syncEngine()
                        // Make the crosshair transparent to touches so the
                        // injected taps reach the app underneath.
                        setCrosshairPassThrough(true)
                        // Small delay so the play-button tap itself doesn't
                        // get counted as the first auto-tap.
                        playPause.postDelayed({ engine.start() }, 350)
                        playPause.setImageResource(android.R.drawable.ic_media_pause)
                    }
                }
            }
            true
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#CC071120"))
            setPadding(pad(3), pad(3), pad(3), pad(3))
            addView(
                playPause,
                LinearLayout.LayoutParams(pad(40), pad(40)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                label,
                LinearLayout.LayoutParams(pad(48), pad(28)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                close,
                LinearLayout.LayoutParams(pad(40), pad(40)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
            addView(
                dragHandle,
                LinearLayout.LayoutParams(pad(48), pad(20)).apply { gravity = Gravity.CENTER_HORIZONTAL },
            )
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = pad(6)
            y = windowManager.defaultDisplay.height / 3
        }

        attachDrag(dragHandle, column, params) { _, _ -> }
        wm.addView(column, params)
        bubble = column
    }

    /**
     * Generic drag handling that updates the window position live.
     * [handle] is the view that receives the touch (may be a child of the
     * window, e.g. the drag strip); [window] is the window root registered
     * with the WindowManager — only its layout may be updated.
     */
    @SuppressLint("ClickableViewAccessibility")
    private fun attachDrag(
        handle: View,
        window: View,
        params: WindowManager.LayoutParams,
        onRelease: (Int, Int) -> Unit,
    ) {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        handle.setOnTouchListener { _, event ->
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
                    try { wm().updateViewLayout(window, params) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) onRelease(params.x, params.y)
                    window.performClick()
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

    /** Reads the interval field, clamps it, and commits it to [intervalMs]. */
    private fun applyIntervalFromField() {
        val field = intervalLabel ?: return
        val parsed = field.text.toString().trim().toIntOrNull() ?: return
        intervalMs = parsed.coerceIn(1, AutoClickerService.MAX_INTERVAL_MS)
        field.setText(intervalMs.toString())
    }

    companion object {
        private const val TAG = "AutoClicker"
        const val CHANNEL_ID = "auto_clicker"
        const val NOTIFICATION_ID = 4712
        const val ACTION_STOP = "com.idsiber.sibermobile.autoclicker.STOP"
    }
}
