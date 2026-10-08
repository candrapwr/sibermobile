package com.idsiber.sibermobile

import io.flutter.embedding.android.FlutterActivity

/**
 * Attaches to the process-level engine owned by [SiberApplication]. A
 * destroyed activity no longer kills the engine, so closing the window
 * (back-exit, swipe, clear-all) leaves an in-flight turn running — kept
 * alive by BusyService — and reopening the app resumes the same UI state.
 *
 * DeviceBridge is registered on the engine in SiberApplication; nothing to
 * do here beyond binding the cached engine.
 */
class MainActivity : FlutterActivity() {
    override fun getCachedEngineId(): String? = SiberApplication.ENGINE_ID
}
