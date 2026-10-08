package com.idsiber.sibermobile

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
}
