package com.idsiber.sibermobile

import io.flutter.embedding.android.FlutterActivity

/**
 * Attaches to the process-level engine owned by [SiberApplication]. A
 * destroyed activity no longer kills the engine, so closing the window
 * (back-exit, swipe, clear-all) leaves an in-flight turn running — kept
 * alive by BusyService — and reopening the app resumes the same UI state.
 *
 * While started, this activity publishes itself to the shared DeviceBridge:
 * NFC reader mode is activity-scoped and the bridge otherwise only holds
 * the application context.
 */
class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String? = SiberApplication.ENGINE_ID

    override fun onStart() {
        super.onStart()
        (application as SiberApplication).deviceBridge.activity = this
    }

    override fun onStop() {
        val app = application as? SiberApplication
        if (app?.deviceBridge?.activity === this) {
            app.deviceBridge.activity = null
        }
        super.onStop()
    }
}
