package com.idsiber.sibermobile

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import kotlin.random.Random

/**
 * Auto clicker engine: an AccessibilityService that injects taps at the
 * target position on a Handler loop. Each tap gets a small random jitter
 * in position (±3px) and timing (±80ms) so anti-bot filters that flag
 * perfectly repetitive synthetic input (TikTok, games) pass it through.
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
            tapWithJitter()
            // Randomize the delay ±80ms so the interval is never perfectly
            // uniform (anti-bot detection).
            val jitter = Random.nextLong(-80, 81)
            val delay = (intervalMs + jitter).toLong().coerceIn(MIN_INTERVAL_MS.toLong(), MAX_INTERVAL_MS.toLong())
            handler.postDelayed(this, delay)
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

    /**
     * Injects a tap with ±3px position jitter and slight duration variation,
     * mimicking the micro-movements of a real finger. Anti-bot systems in
     * apps like TikTok filter out touches at perfectly identical coordinates.
     */
    private fun tapWithJitter() {
        val jitterX = -3f + Random.nextFloat() * 6f
        val jitterY = -3f + Random.nextFloat() * 6f
        val x = (targetX + jitterX).coerceAtLeast(1f)
        val y = (targetY + jitterY).coerceAtLeast(1f)
        val duration = 80L + Random.nextLong(0, 41) // 80-120ms

        val path = Path().apply {
            moveTo(x, y)
            lineTo(x + 0.5f, y + 0.5f)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
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
