package com.idsiber.sibermobile

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

/**
 * Auto clicker engine: an AccessibilityService that injects taps at the
 * target position on a Handler loop. The overlay UI (AutoClickerOverlay)
 * drives it through the static [instance]; the service itself keeps no UI.
 */
class AutoClickerService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var intervalMs = DEFAULT_INTERVAL_MS
    private var targetX = 0f
    private var targetY = 0f

    private val clickRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            tap(targetX, targetY)
            handler.postDelayed(this, intervalMs.toLong())
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        stop()
        instance = null
        super.onDestroy()
    }

    fun configure(x: Float, y: Float, intervalMs: Int) {
        targetX = x
        targetY = y
        this.intervalMs = intervalMs.coerceIn(MIN_INTERVAL_MS, MAX_INTERVAL_MS)
    }

    fun start() {
        if (running) return
        running = true
        handler.post(clickRunnable)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(clickRunnable)
    }

    val isRunning: Boolean get() = running

    private fun tap(x: Float, y: Float) {
        // Mimic a real finger tap: a short press with a tiny drift so apps
        // that filter single-point synthetic touches still register it.
        val path = Path().apply {
            moveTo(x, y)
            // Small linear drift (~1px) makes the stroke register as a real
            // touch on apps that ignore zero-movement gestures.
            lineTo(x + 0.8f, y + 0.8f)
        }
        val stroke = GestureDescription.StrokeDescription(
            path,
            0,
            TAP_DURATION_MS,
        )
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    companion object {
        var instance: AutoClickerService? = null
            private set

        const val DEFAULT_INTERVAL_MS = 1000
        const val MIN_INTERVAL_MS = 200
        const val MAX_INTERVAL_MS = 60000
        const val TAP_DURATION_MS = 90L
    }
}
