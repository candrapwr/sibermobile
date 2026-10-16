package com.idsiber.sibermobile

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Router for the `sibermobile/device` MethodChannel. Thin by design: it
 * owns the shared dependencies (context, executor, main handler) and the
 * activity reference, then dispatches every call to the feature module
 * that owns it:
 *
 *  - [NfcModule]            — reader-mode tag sessions, transceive, NDEF
 *  - [NetworkModule]        — Wi-Fi AP scan + cellular survey
 *  - [TtsModule]            — text-to-speech
 *  - [AppsModule]           — installed apps + disk space
 *  - [PersonalToolsModule]  — auto clicker glue + busy service
 */
class DeviceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    /**
     * The foreground activity, attached by MainActivity. The bridge itself
     * lives on the application context (cached engine), but NFC reader mode
     * is activity-scoped — without this reference nfc_analyze can never
     * start discovery.
     */
    @Volatile
    var activity: Activity? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    private val nfc = NfcModule(context, executor, mainHandler) { activity ?: context as? Activity }
    private val network = NetworkModule(context, executor, mainHandler)
    private val tts = TtsModule(context, mainHandler)
    private val apps = AppsModule(context, executor, mainHandler)
    private val tools = PersonalToolsModule(context, mainHandler)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDiskSpace" -> result.success(apps.getDiskSpace())

            "getInstalledApps" -> apps.getInstalledAppsChannel(
                call.argument<Boolean>("includeSystemApps") ?: false,
                result,
            )

            "isAppInstalled" -> result.success(
                apps.isAppInstalled(call.argument<String>("packageName") ?: ""),
            )

            "startApp" -> result.success(
                apps.startApp(call.argument<String>("packageName") ?: ""),
            )

            "ttsSpeak" -> tts.ttsSpeak(
                call.argument<String>("text") ?: "",
                call.argument<String>("language") ?: "id-ID",
                (call.argument<Double>("rate") ?: 0.5).toFloat(),
                (call.argument<Double>("pitch") ?: 1.0).toFloat(),
                result,
            )

            "ttsStop" -> tts.ttsStop(result)

            "nfcStatus" -> nfc.status(result)

            "nfcAnalyze" -> nfc.analyze(
                timeoutSeconds = ((call.argument<Number>("timeoutSeconds") ?: 20).toInt()),
                readNdef = call.argument<Boolean>("readNdef") ?: true,
                result = result,
            )

            "nfcTransceive" -> nfc.transceive(
                dataHex = call.argument<String>("dataHex") ?: "",
                tech = call.argument<String>("tech") ?: "auto",
                result = result,
            )

            "nfcWriteNdef" -> nfc.writeNdef(
                records = call.argument<List<Map<String, Any?>>>("records") ?: emptyList(),
                result = result,
            )

            "wifiScan" -> network.wifiScan(result)

            "cellScan" -> network.cellScan(result)

            "autoClickerStatus" -> tools.autoClickerStatus(result)
            "requestOverlayPermission" -> {
                tools.requestOverlayPermission()
                result.success(true)
            }
            "openAccessibilitySettings" -> {
                tools.openAccessibilitySettings()
                result.success(true)
            }
            "autoClickerStart" -> {
                tools.startAutoClickerOverlay()
                result.success(true)
            }
            "autoClickerStop" -> {
                tools.stopAutoClickerOverlay()
                result.success(true)
            }

            "setBusy" -> {
                tools.setBusyService(
                    call.argument<Boolean>("busy") ?: false,
                    call.argument<String>("text"),
                )
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }
}
