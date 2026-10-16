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
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 40)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, null, null)
    }

    companion object {
        var instance: AutoClickerService? = null
            private set

        const val DEFAULT_INTERVAL_MS = 1000
        const val MIN_INTERVAL_MS = 200
        const val MAX_INTERVAL_MS = 60000
    }
}
