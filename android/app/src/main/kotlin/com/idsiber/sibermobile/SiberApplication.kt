package com.idsiber.sibermobile

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Flutter engine at process level instead of tying it to an
 * Activity. When the activity is destroyed (back-exit, swipe from recents,
 * clear-all) the engine — and therefore the running Dart isolate — survives
 * inside the process that BusyService keeps alive, so an in-flight turn
 * continues in the background and the UI resumes exactly where it was.
 *
 * DeviceBridge is registered here with the application context; MainActivity
 * attaches itself to the bridge while started so activity-scoped features
 * (NFC reader mode, permission dialogs) keep working.
 */
class SiberApplication : Application() {

    lateinit var engine: FlutterEngine
        private set

    lateinit var deviceBridge: DeviceBridge
        private set

    override fun onCreate() {
        super.onCreate()
        deviceBridge = DeviceBridge(this)
        engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        // MainActivity looks the engine up in the static cache — publishing
        // it here is what makes the cached-engine attach work.
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(deviceBridge)
    }

    companion object {
        const val ENGINE_ID = "siber_engine"
        const val CHANNEL = "sibermobile/device"
    }
}
