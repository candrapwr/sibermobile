package com.idsiber.sibermobile

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import kotlin.random.Random

/**
 * Auto clicker engine: an AccessibilityService that injects taps at the
 * target position. The timing loop runs on a dedicated background thread —
 * the main thread only receives the individual dispatchGesture calls, so
 * the overlay's stop button stays responsive even at 1-50ms intervals.
 *
 * Each tap gets a wide random jitter in position (±15px), duration
 * (50-150ms) and timing (±80ms) so anti-bot filters in TikTok/games
 * that flag perfectly repetitive synthetic input pass it through.
 */
class AutoClickerService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var clickThread: HandlerThread? = null
    private var clickHandler: Handler? = null
    private var running = false
    private var intervalMs = DEFAULT_INTERVAL_MS
    private var targetX = 0f
    private var targetY = 0f

    private val clickRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            // Build the gesture here (background thread), dispatch on main.
            val gesture = buildTapGesture()
            mainHandler.post {
                if (running) {
                    try { dispatchGesture(gesture, null, null) } catch (_: Exception) {}
                }
            }
            // Randomize the delay ±80ms so the interval is never uniform.
            val jitter = Random.nextLong(-80, 81)
            val delay = (intervalMs.toLong() + jitter).coerceIn(1L, MAX_INTERVAL_MS.toLong())
            clickHandler?.postDelayed(this, delay)
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
        this.intervalMs = intervalMs.coerceIn(1, MAX_INTERVAL_MS)
    }

    fun start() {
        if (running) return
        running = true
        android.util.Log.d(
            TAG,
            "engine start interval=${intervalMs}ms target=($targetX,$targetY)",
        )
        // Dedicated thread: the timing loop never blocks the main thread,
        // so overlay buttons remain easy to tap at any interval.
        if (clickThread == null) {
            clickThread = HandlerThread("AutoClickerLoop").also { it.start() }
            clickHandler = Handler(clickThread!!.looper)
        }
        clickHandler?.post(clickRunnable)
    }

    fun stop() {
        android.util.Log.d(TAG, "engine stop (was running=$running)")
        running = false
        clickHandler?.removeCallbacks(clickRunnable)
        mainHandler.removeCallbacksAndMessages(null)
    }

    val isRunning: Boolean get() = running

    /** Builds a tap gesture with ±15px jitter and 50-150ms duration. */
    private fun buildTapGesture(): GestureDescription {
        val jitterX = -15f + Random.nextFloat() * 30f
        val jitterY = -15f + Random.nextFloat() * 30f
        val x = (targetX + jitterX).coerceAtLeast(1f)
        val y = (targetY + jitterY).coerceAtLeast(1f)
        val duration = 50L + Random.nextLong(0, 101) // 50-150ms

        val path = Path().apply {
            moveTo(x, y)
            lineTo(x + 0.5f, y + 0.5f)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, duration)
        return GestureDescription.Builder().addStroke(stroke).build()
    }

    companion object {
        private const val TAG = "AutoClicker"
        var instance: AutoClickerService? = null
            private set

        const val DEFAULT_INTERVAL_MS = 200
        const val MAX_INTERVAL_MS = 60000
    }
}
