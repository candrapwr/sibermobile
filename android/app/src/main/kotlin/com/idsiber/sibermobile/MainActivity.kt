package com.idsiber.sibermobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The bridge needs the Activity context: NFC reader mode and opening
        // settings screens are activity-scoped.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sibermobile/device",
        ).setMethodCallHandler(DeviceBridge(this))
    }

    override fun onDestroy() {
        // The engine dies with the activity, so an in-flight turn cannot
        // continue — never leave the keep-alive notification behind.
        stopService(Intent(this, BusyService::class.java))
        super.onDestroy()
    }
}
