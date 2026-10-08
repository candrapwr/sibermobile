package com.idsiber.sibermobile

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.MifareClassic
import android.nfc.tech.MifareUltralight
import android.nfc.tech.Ndef
import android.nfc.tech.NfcA
import android.nfc.tech.NfcB
import android.nfc.tech.NfcF
import android.nfc.tech.NfcV
import android.nfc.tech.TagTechnology
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.telephony.CellIdentityCdma
import android.telephony.CellIdentityGsm
import android.telephony.CellIdentityLte
import android.telephony.CellIdentityNr
import android.telephony.CellIdentityWcdma
import android.telephony.CellInfo
import android.telephony.CellInfoCdma
import android.telephony.CellInfoGsm
import android.telephony.CellInfoLte
import android.telephony.CellInfoNr
import android.telephony.CellInfoWcdma
import android.telephony.CellSignalStrengthGsm
import android.telephony.CellSignalStrengthLte
import android.telephony.CellSignalStrengthNr
import android.telephony.CellSignalStrengthWcdma
import android.telephony.ServiceState
import android.telephony.TelephonyManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Backing for the `sibermobile/device` MethodChannel. Covers the four tools
 * that used to come from plugins which had not migrated to Flutter's built-in
 * Kotlin: disk_space_update, app_settings, installed_apps and flutter_tts.
 * Behavior (settings screen mapping, speech-rate scaling, storage volume) is
 * kept identical to those plugins.
 */
class DeviceBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingSpeak: (() -> Unit)? = null
    private var speakResult: MethodChannel.Result? = null
    private var utteranceCounter = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDiskSpace" -> result.success(getDiskSpace())

            "getInstalledApps" -> {
                val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
                executor.execute {
                    val apps = try {
                        getInstalledApps(includeSystemApps)
                    } catch (e: Exception) {
                        null
                    }
                    mainHandler.post {
                        if (apps == null) {
                            result.error("ERROR", "Failed to list installed apps", null)
                        } else {
                            result.success(apps)
                        }
                    }
                }
            }

            "isAppInstalled" -> result.success(
                isAppInstalled(call.argument<String>("packageName") ?: ""),
            )

            "startApp" -> result.success(
                startApp(call.argument<String>("packageName") ?: ""),
            )

            "ttsSpeak" -> ttsSpeak(
                call.argument<String>("text") ?: "",
                call.argument<String>("language") ?: "id-ID",
                (call.argument<Double>("rate") ?: 0.5).toFloat(),
                (call.argument<Double>("pitch") ?: 1.0).toFloat(),
                result,
            )

            "ttsStop" -> ttsStop(result)

            "nfcStatus" -> nfcStatus(result)

            "nfcAnalyze" -> nfcAnalyze(
                timeoutSeconds = ((call.argument<Number>("timeoutSeconds") ?: 20).toInt()),
                readNdef = call.argument<Boolean>("readNdef") ?: true,
                result = result,
            )

            "nfcTransceive" -> nfcTransceive(
                dataHex = call.argument<String>("dataHex") ?: "",
                tech = call.argument<String>("tech") ?: "auto",
                result = result,
            )

            "nfcWriteNdef" -> nfcWriteNdef(
                records = call.argument<List<Map<String, Any?>>>("records") ?: emptyList(),
                result = result,
            )

            "wifiScan" -> wifiScan(result)

            "cellScan" -> cellScan(result)

            "setBusy" -> {
                setBusyService(
                    call.argument<Boolean>("busy") ?: false,
                    call.argument<String>("text"),
                )
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /** Total and free bytes on the primary external storage volume. */
    private fun getDiskSpace(): Map<String, Long> {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return mapOf(
            "totalBytes" to stat.blockCountLong * stat.blockSizeLong,
            "freeBytes" to stat.availableBlocksLong * stat.blockSizeLong,
        )
    }

    private fun getInstalledApps(includeSystemApps: Boolean): List<Map<String, Any?>> {
        val pm = context.packageManager
        return pm.getInstalledPackages(0)
            .asSequence()
            .filter { it.applicationInfo != null }
            .filter {
                includeSystemApps ||
                    (it.applicationInfo!!.flags and ApplicationInfo.FLAG_SYSTEM) == 0
            }
            .map {
                mapOf(
                    "name" to pm.getApplicationLabel(it.applicationInfo!!).toString(),
                    "packageName" to it.packageName,
                    "versionName" to it.versionName,
                    "isSystemApp" to
                        ((it.applicationInfo!!.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            }
            .toList()
    }

    private fun isAppInstalled(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return try {
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun startApp(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            if (context !is Activity) launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun ensureTts() {
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            val pending = pendingSpeak
            pendingSpeak = null
            pending?.invoke()
        }.also { engine ->
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(utteranceId: String?) {
                    resolveSpeak(true)
                }

                override fun onError(utteranceId: String?) {
                    resolveSpeak(false)
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    resolveSpeak(false)
                }

                private fun resolveSpeak(ok: Boolean) {
                    mainHandler.post {
                        speakResult?.success(ok)
                        speakResult = null
                    }
                }
            })
        }
    }

    /**
     * Speaks [text] and resolves the call only once the utterance finishes
     * (or fails / is stopped). Rate/pitch semantics follow flutter_tts: the
     * Flutter scale runs 0.0-1.0 with 0.5 == Android normal speed, and pitch
     * passes through unchanged.
     */
    private fun ttsSpeak(
        text: String,
        language: String,
        rate: Float,
        pitch: Float,
        result: MethodChannel.Result,
    ) {
        ensureTts()
        val doSpeak: () -> Unit = doSpeak@{
            val engine = tts
            if (engine == null || !ttsReady) {
                mainHandler.post { result.success(false) }
                return@doSpeak
            }
            // Engines ignore unsupported languages; keep defaults like the
            // previous Dart-side try/catch did.
            try {
                engine.language = Locale.forLanguageTag(language)
            } catch (_: Exception) {}
            engine.setSpeechRate(rate * 2f)
            engine.setPitch(pitch)
            speakResult = result
            val id = "siber_tts_${++utteranceCounter}"
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        }
        if (ttsReady) {
            doSpeak()
        } else {
            pendingSpeak = doSpeak
        }
    }

    private fun ttsStop(result: MethodChannel.Result) {
        try {
            tts?.stop()
        } catch (_: Exception) {}
        mainHandler.post {
            speakResult?.success(false)
            speakResult = null
            result.success(true)
        }
    }

    // ── NFC ───────────────────────────────────────────────────────────────
    //
    // Reader-mode based: nfcAnalyze starts reader mode and keeps the discovered
    // tag in a short-lived session so follow-up nfcTransceive/nfcWriteNdef
    // calls can talk to the same tag while it stays on the reader.

    // java.lang.Object (not kotlin.Any) so wait/notifyAll are callable.
    private val nfcLock = java.lang.Object()
    private var nfcSessionTag: Tag? = null
    private var nfcSessionExpiresAt = 0L
    private var nfcReaderEnabled = false

    private val readerCallback = NfcAdapter.ReaderCallback { tag ->
        synchronized(nfcLock) {
            nfcSessionTag = tag
            nfcSessionExpiresAt = System.currentTimeMillis() + NFC_SESSION_MS
            nfcLock.notifyAll()
        }
    }

    private fun nfcAdapterOrNull(): NfcAdapter? = try {
        NfcAdapter.getDefaultAdapter(context)
    } catch (_: Exception) {
        null
    }

    /** The tag of a still-fresh session, or null once it expired. */
    private fun currentNfcTag(): Tag? = synchronized(nfcLock) {
        if (System.currentTimeMillis() < nfcSessionExpiresAt) nfcSessionTag else null
    }

    /** Extends the hold on reader mode and the tag; ends it when idle. */
    private fun touchNfcSession() {
        synchronized(nfcLock) {
            nfcSessionExpiresAt = System.currentTimeMillis() + NFC_SESSION_MS
        }
        mainHandler.postDelayed({ endNfcSessionIfExpired() }, NFC_SESSION_MS + 1_000)
    }

    private fun endNfcSessionIfExpired() {
        synchronized(nfcLock) {
            if (System.currentTimeMillis() < nfcSessionExpiresAt) return
            nfcSessionTag = null
            nfcSessionExpiresAt = 0
            if (nfcReaderEnabled) {
                nfcReaderEnabled = false
                val adapter = nfcAdapterOrNull()
                val activity = context as? Activity
                if (adapter != null && activity != null) {
                    try {
                        adapter.disableReaderMode(activity)
                    } catch (_: Exception) {}
                }
            }
        }
    }

    private fun nfcStatus(result: MethodChannel.Result) {
        val adapter = nfcAdapterOrNull()
        mainHandler.post {
            result.success(
                mapOf(
                    "available" to (adapter != null),
                    "enabled" to (adapter?.isEnabled == true),
                ),
            )
        }
    }

    private fun nfcAnalyze(
        timeoutSeconds: Int,
        readNdef: Boolean,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            val adapter = nfcAdapterOrNull()
            if (adapter == null) {
                mainHandler.post {
                    result.success(mapOf("found" to false, "error" to "NFC is not available on this device."))
                }
                return@execute
            }
            if (!adapter.isEnabled) {
                mainHandler.post {
                    result.success(
                        mapOf(
                            "found" to false,
                            "error" to "NFC is disabled. Ask the user to enable NFC in Android settings.",
                        ),
                    )
                }
                return@execute
            }

            var tag = currentNfcTag()
            if (tag == null) {
                val activity = context as? Activity
                if (activity == null) {
                    mainHandler.post {
                        result.success(mapOf("found" to false, "error" to "No foreground activity for reader mode."))
                    }
                    return@execute
                }
                try {
                    adapter.enableReaderMode(
                        activity,
                        readerCallback,
                        NfcAdapter.FLAG_READER_NFC_A or
                            NfcAdapter.FLAG_READER_NFC_B or
                            NfcAdapter.FLAG_READER_NFC_F or
                            NfcAdapter.FLAG_READER_NFC_V,
                        null,
                    )
                    nfcReaderEnabled = true
                } catch (e: Exception) {
                    mainHandler.post {
                        result.success(mapOf("found" to false, "error" to (e.message ?: "Failed to start NFC reader mode.")))
                    }
                    return@execute
                }

                val deadline = System.currentTimeMillis() + timeoutSeconds * 1000L
                synchronized(nfcLock) {
                    nfcSessionTag = null
                    while (nfcSessionTag == null) {
                        val remaining = deadline - System.currentTimeMillis()
                        if (remaining <= 0) break
                        nfcLock.wait(remaining)
                    }
                    tag = nfcSessionTag
                }
                if (tag == null) {
                    synchronized(nfcLock) {
                        nfcSessionExpiresAt = 0
                    }
                    endNfcSessionIfExpired()
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "found" to false,
                                "error" to "No NFC tag detected within ${timeoutSeconds}s. Ask the user to place a tag on the back of the phone.",
                            ),
                        )
                    }
                    return@execute
                }
            }

            touchNfcSession()
            val info = try {
                analyzeTag(tag!!, readNdef)
            } catch (e: Exception) {
                mapOf("found" to true, "error" to (e.message ?: "Failed to read the tag."))
            }
            mainHandler.post { result.success(info) }
        }
    }

    /** Harvests identity, per-technology parameters and NDEF content. */
    private fun analyzeTag(tag: Tag, readNdef: Boolean): Map<String, Any?> {
        val info = linkedMapOf<String, Any?>()
        info["found"] = true
        info["idHex"] = bytesToHex(tag.id)
        info["techList"] = tag.techList.map { it.substringAfterLast('.') }
        try {
            NfcA.get(tag)?.let {
                info["nfcA"] = mapOf(
                    "atqaHex" to bytesToHex(it.atqa),
                    "sak" to it.sak,
                    "maxTransceiveLength" to it.maxTransceiveLength,
                )
            }
        } catch (_: Exception) {}
        try {
            IsoDep.get(tag)?.let {
                info["isoDep"] = mapOf(
                    "maxTransceiveLength" to it.maxTransceiveLength,
                    "isExtendedLengthApduSupported" to it.isExtendedLengthApduSupported,
                )
            }
        } catch (_: Exception) {}
        try {
            MifareClassic.get(tag)?.let {
                // Raw type code: its meaning shifted across platform versions
                // (TYPE_CLASSIC_1K/4K became TYPE_CLASSIC), so the size fields
                // below are the reliable way to tell 1K/2K/4K apart.
                info["mifareClassic"] = mapOf(
                    "typeCode" to it.type,
                    "sizeBytes" to it.size,
                    "sectorCount" to it.sectorCount,
                    "blockCount" to it.blockCount,
                )
            }
        } catch (_: Exception) {}
        try {
            MifareUltralight.get(tag)?.let {
                info["mifareUltralight"] = mapOf(
                    "type" to when (it.type) {
                        MifareUltralight.TYPE_ULTRALIGHT -> "ULTRALIGHT"
                        MifareUltralight.TYPE_ULTRALIGHT_C -> "ULTRALIGHT_C"
                        else -> "UNKNOWN"
                    },
                    "maxTransceiveLength" to it.maxTransceiveLength,
                )
            }
        } catch (_: Exception) {}

        if (readNdef) {
            try {
                val ndef = Ndef.get(tag)
                if (ndef == null) {
                    info["ndef"] = mapOf("supported" to false)
                } else {
                    val records = try {
                        ndef.cachedNdefMessage?.records?.map { ndefRecordToMap(it) }
                            ?: emptyList()
                    } catch (_: Exception) {
                        emptyList()
                    }
                    info["ndef"] = mapOf(
                        "supported" to true,
                        "type" to ndef.type,
                        "maxSizeBytes" to ndef.maxSize,
                        "writable" to ndef.isWritable,
                        "records" to records,
                    )
                }
            } catch (_: Exception) {
                info["ndef"] = mapOf("supported" to false, "error" to "NDEF read failed")
            }
        }
        return info
    }

    private fun ndefRecordToMap(r: NdefRecord): Map<String, Any?> {
        val tnfName = when (r.tnf) {
            NdefRecord.TNF_EMPTY -> "EMPTY"
            NdefRecord.TNF_WELL_KNOWN -> "WELL_KNOWN"
            NdefRecord.TNF_MIME_MEDIA -> "MIME_MEDIA"
            NdefRecord.TNF_ABSOLUTE_URI -> "ABSOLUTE_URI"
            NdefRecord.TNF_EXTERNAL_TYPE -> "EXTERNAL_TYPE"
            NdefRecord.TNF_UNKNOWN -> "UNKNOWN"
            NdefRecord.TNF_UNCHANGED -> "UNCHANGED"
            else -> "RESERVED"
        }
        val type = String(r.type, Charsets.US_ASCII)
        var parsed: String? = null
        if (r.tnf == NdefRecord.TNF_WELL_KNOWN) {
            parsed = when (type) {
                "T" -> parseRtdText(r.payload)
                "U" -> parseRtdUri(r.payload)
                else -> null
            }
        }
        val hex = bytesToHex(r.payload)
        return mapOf(
            "tnf" to tnfName,
            "type" to type,
            "sizeBytes" to r.payload.size,
            "parsed" to parsed,
            "payloadHex" to if (hex.length > 1024) {
                "${hex.take(1024)}... (truncated, ${r.payload.size} bytes total)"
            } else {
                hex
            },
        )
    }

    private fun parseRtdText(payload: ByteArray): String? = try {
        if (payload.isEmpty()) return null
        val status = payload[0].toInt()
        val languageLength = status and 0x3F
        val isUtf16 = (status and 0x80) != 0
        val textStart = 1 + languageLength
        if (payload.size <= textStart) return null
        val textBytes = payload.copyOfRange(textStart, payload.size)
        String(textBytes, if (isUtf16) Charsets.UTF_16 else Charsets.UTF_8)
    } catch (_: Exception) {
        null
    }

    private val uriPrefixes = arrayOf(
        "", "http://www.", "https://www.", "http://", "https://",
        "tel:", "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.",
        "ftps://", "sftp://", "smb://", "nfs://", "ftp://", "dav://",
        "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:",
        "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://",
        "file://", "urn:epc:id:", "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:",
        "urn:epc:", "urn:nfc:",
    )

    private fun parseRtdUri(payload: ByteArray): String? = try {
        if (payload.isEmpty()) return null
        val code = payload[0].toInt() and 0xFF
        val prefix = if (code < uriPrefixes.size) uriPrefixes[code] else ""
        prefix + String(payload.copyOfRange(1, payload.size), Charsets.UTF_8)
    } catch (_: Exception) {
        null
    }

    /**
     * Sends raw frames to the tag of the active session. With tech=auto an
     * IsoDep tag is preferred (APDU exchange: response ends in the 2-byte
     * status word), otherwise NfcA/B/F/V in that order.
     */
    private fun nfcTransceive(
        dataHex: String,
        tech: String,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            val finish: (Map<String, Any?>) -> Unit = { map ->
                mainHandler.post { result.success(map) }
            }
            val tag = currentNfcTag()
            if (tag == null) {
                finish(
                    mapOf(
                        "error" to "No active NFC session. Call nfc_analyze first and keep the tag on the reader.",
                    ),
                )
                return@execute
            }
            val cleanHex = dataHex.replace(" ", "").lowercase()
            val bytes = hexToBytesOrNull(cleanHex)
            if (bytes == null || bytes.isEmpty()) {
                finish(mapOf("error" to "dataHex must be a non-empty even-length hex string."))
                return@execute
            }

            val techs = tag.techList
            val selected: TagTechnology? = when {
                (tech == "isoDep" || tech == "auto") &&
                    techs.contains("android.nfc.tech.IsoDep") -> IsoDep.get(tag)
                (tech == "nfcA" || tech == "auto") &&
                    techs.contains("android.nfc.tech.NfcA") -> NfcA.get(tag)
                (tech == "nfcB" || tech == "auto") &&
                    techs.contains("android.nfc.tech.NfcB") -> NfcB.get(tag)
                (tech == "nfcF" || tech == "auto") &&
                    techs.contains("android.nfc.tech.NfcF") -> NfcF.get(tag)
                (tech == "nfcV" || tech == "auto") &&
                    techs.contains("android.nfc.tech.NfcV") -> NfcV.get(tag)
                else -> null
            }
            if (selected == null) {
                finish(mapOf("error" to "The tag does not expose tech '$tech'. Available: ${techs.joinToString { it.substringAfterLast('.') }}"))
                return@execute
            }

            val maxLen = when (selected) {
                is IsoDep -> selected.maxTransceiveLength
                is NfcA -> selected.maxTransceiveLength
                is NfcB -> selected.maxTransceiveLength
                is NfcF -> selected.maxTransceiveLength
                is NfcV -> selected.maxTransceiveLength
                else -> 0
            }
            if (maxLen in 1 until bytes.size) {
                finish(mapOf("error" to "Frame is ${bytes.size} bytes but the tech accepts at most $maxLen."))
                return@execute
            }

            try {
                selected.connect()
                val response = when (selected) {
                    is IsoDep -> selected.transceive(bytes)
                    is NfcA -> selected.transceive(bytes)
                    is NfcB -> selected.transceive(bytes)
                    is NfcF -> selected.transceive(bytes)
                    is NfcV -> selected.transceive(bytes)
                    else -> throw IllegalStateException("unsupported tech")
                }
                touchNfcSession()
                finish(
                    mapOf(
                        "responseHex" to bytesToHex(response),
                        "tech" to selected.javaClass.simpleName,
                    ),
                )
            } catch (e: Exception) {
                finish(
                    mapOf(
                        "error" to (e.message ?: "transceive failed"),
                        "hint" to "The tag may have been removed from the reader; run nfc_analyze again.",
                    ),
                )
            }
        }
    }

    /** Writes NDEF text/URI records to the tag of the active session. */
    private fun nfcWriteNdef(
        records: List<Map<String, Any?>>,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            val finish: (Map<String, Any?>) -> Unit = { map ->
                mainHandler.post { result.success(map) }
            }
            val tag = currentNfcTag()
            if (tag == null) {
                finish(mapOf("error" to "No active NFC session. Call nfc_analyze first and keep the tag on the reader."))
                return@execute
            }
            val ndef = try {
                Ndef.get(tag)
            } catch (_: Exception) {
                null
            }
            if (ndef == null) {
                finish(mapOf("error" to "The tag is not NDEF-formatted; this app cannot format blank tags."))
                return@execute
            }
            val out = try {
                val messages = records.map { r ->
                    val kind = r["kind"] as? String ?: "text"
                    val value = r["value"] as? String ?: ""
                    if (kind == "uri") {
                        NdefRecord.createUri(value)
                    } else {
                        NdefRecord.createTextRecord(
                            r["language"] as? String ?: "en",
                            value,
                        )
                    }
                }
                if (messages.isEmpty()) {
                    finish(mapOf("error" to "records must contain at least one entry."))
                    return@execute
                }
                ndef.connect()
                if (!ndef.isWritable) {
                    finish(mapOf("error" to "The tag is read-only."))
                    return@execute
                }
                ndef.writeNdefMessage(NdefMessage(messages.toTypedArray()))
                true
            } catch (e: Exception) {
                finish(mapOf("error" to (e.message ?: "write failed")))
                return@execute
            }
            touchNfcSession()
            finish(mapOf("ok" to out))
        }
    }

    private fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    /** Starts/stops the keep-alive foreground service while a turn runs. */
    private fun setBusyService(busy: Boolean, text: String?) {
        try {
            val intent = Intent(context, BusyService::class.java)
            if (busy) {
                // A turn always starts from the foreground UI, so launching
                // the foreground service from the application context is
                // allowed even on Android 12+.
                intent.action = BusyService.ACTION_START
                intent.putExtra(BusyService.EXTRA_TEXT, text ?: "Sedang memproses…")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } else {
                // The turn may end while the app is in the background, where
                // startService() is forbidden — stopService() always works.
                context.stopService(intent)
            }
        } catch (_: Exception) {
            // Best effort: a failed start must never break the chat turn.
        }
    }

    // ── Network analysis ───────────────────────────────────────────────────
    //
    // Wi-Fi AP scan and cellular/provider survey for free-form analysis
    // (rogue AP / fake base station indicators are inferred by the AI from
    // the raw observables returned here).

    private fun wifiScan(result: MethodChannel.Result) {
        executor.execute {
            val finish: (Map<String, Any?>) -> Unit = { map ->
                mainHandler.post { result.success(map) }
            }
            val wifi = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (wifi == null || !wifi.isWifiEnabled) {
                finish(mapOf("error" to "Wi-Fi is off or unavailable on this device."))
                return@execute
            }

            val out = linkedMapOf<String, Any?>()

            // Fresh scan + wait for the system broadcast. startScan() is
            // throttled (about 4 scans / 2 minutes), so results below may be
            // the cached ones either way; scanTriggered reports the difference.
            val latch = CountDownLatch(1)
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context?, i: Intent?) {
                    latch.countDown()
                }
            }
            var scanTriggered = false
            try {
                val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    @Suppress("UnspecifiedRegisterReceiverFlag")
                    context.registerReceiver(receiver, filter)
                }
                @Suppress("DEPRECATION")
                scanTriggered = try {
                    wifi.startScan()
                } catch (_: Exception) {
                    false
                }
                latch.await(8, TimeUnit.SECONDS)
            } catch (_: Exception) {
            } finally {
                try {
                    context.unregisterReceiver(receiver)
                } catch (_: Exception) {}
            }

            val results = try {
                wifi.scanResults ?: emptyList<ScanResult>()
            } catch (_: Exception) {
                emptyList<ScanResult>()
            }
            out["scanTriggered"] = scanTriggered
            out["resultCount"] = results.size
            out["aps"] = results.map { apMap(it) }

            // Location toggle matters: scan results come back empty without it.
            try {
                val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                out["locationEnabled"] =
                    lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true ||
                        lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
            } catch (_: Exception) {}

            // Current connection: modern transport info first, then the
            // deprecated getter, then link properties for IPs/DNS/gateway.
            val conn = linkedMapOf<String, Any?>()
            try {
                val cm =
                    context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
                val info = caps?.transportInfo as? WifiInfo
                if (info != null) {
                    conn["ssid"] = stripQuotes(info.ssid)
                    conn["bssid"] = info.bssid
                    conn["rssiDbm"] = info.rssi
                    conn["linkSpeedMbps"] = info.linkSpeed
                    conn["frequencyMHz"] = info.frequency
                }
                val lp = cm?.getLinkProperties(cm.activeNetwork)
                if (lp != null) {
                    conn["interfaceName"] = lp.interfaceName
                    conn["ips"] = lp.linkAddresses.mapNotNull { it.address.hostAddress }
                    conn["dnsServers"] = lp.dnsServers.mapNotNull { it.hostAddress }
                    conn["gateway"] = lp.routes
                        .filter { it.isDefaultRoute }
                        .mapNotNull { it.gateway?.hostAddress }
                        .firstOrNull()
                }
            } catch (_: Exception) {}
            if (conn.isEmpty()) {
                try {
                    @Suppress("DEPRECATION")
                    val info = wifi.connectionInfo
                    if (info != null && info.bssid != null &&
                        info.bssid != "02:00:00:00:00:00"
                    ) {
                        conn["ssid"] = stripQuotes(info.ssid)
                        conn["bssid"] = info.bssid
                        conn["rssiDbm"] = info.rssi
                        conn["linkSpeedMbps"] = info.linkSpeed
                        conn["frequencyMHz"] = info.frequency
                    }
                } catch (_: Exception) {}
            }
            out["connection"] = if (conn.isEmpty()) null else conn

            finish(out)
        }
    }

    private fun apMap(r: ScanResult): Map<String, Any?> {
        val m = linkedMapOf<String, Any?>()
        m["ssid"] = r.SSID
        m["bssid"] = r.BSSID
        m["frequencyMHz"] = r.frequency
        m["channel"] = freqToChannel(r.frequency)
        m["rssiDbm"] = r.level
        m["security"] = r.capabilities
        val caps = r.capabilities?.uppercase() ?: ""
        m["open"] = listOf("WPA", "WEP", "PSK", "EAP", "SAE", "OWE")
            .none { caps.contains(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            m["channelWidth"] = channelWidthName(r.channelWidth)
            if (r.centerFreq0 > 0) m["centerFreq0MHz"] = r.centerFreq0
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            m["is80211mcResponder"] = r.is80211mcResponder
        }
        m["timestampUs"] = r.timestamp
        // Locally-administered BSSID (randomized MAC): a classic rogue-AP sign
        // for a network pretending to be infrastructure.
        m["bssidLocallyAdministered"] = isLocallyAdministeredMac(r.BSSID)
        return m
    }

    private fun stripQuotes(s: String?): String? =
        if (s == null || s == "<unknown ssid>") null else s.removeSurrounding("\"")

    private fun isLocallyAdministeredMac(mac: String?): Boolean = try {
        val firstOctet = mac?.take(2)?.toInt(16) ?: return false
        (firstOctet and 0x02) != 0
    } catch (_: Exception) {
        false
    }

    private fun freqToChannel(freqMHz: Int): Int = when {
        freqMHz == 2484 -> 14
        freqMHz in 2412..2472 -> (freqMHz - 2407) / 5
        freqMHz >= 5000 -> (freqMHz - 5000) / 5
        else -> 0
    }

    private fun channelWidthName(w: Int): String = when (w) {
        ScanResult.CHANNEL_WIDTH_20MHZ -> "20MHZ"
        ScanResult.CHANNEL_WIDTH_40MHZ -> "40MHZ"
        ScanResult.CHANNEL_WIDTH_80MHZ -> "80MHZ"
        ScanResult.CHANNEL_WIDTH_160MHZ -> "160MHZ"
        ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> "80MHZ_PLUS_MHZ"
        else -> "UNKNOWN"
    }

    private fun cellScan(result: MethodChannel.Result) {
        executor.execute {
            val finish: (Map<String, Any?>) -> Unit = { map ->
                mainHandler.post { result.success(map) }
            }
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (tm == null) {
                finish(mapOf("error" to "No telephony service on this device."))
                return@execute
            }

            val out = linkedMapOf<String, Any?>()
            try {
                out["simState"] = simStateName(tm.simState)
                if (tm.simState == TelephonyManager.SIM_STATE_READY) {
                    out["simOperator"] = tm.simOperator
                    out["simOperatorName"] = tm.simOperatorName
                    out["simCountryIso"] = tm.simCountryIso
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        out["simCarrierId"] = tm.simCarrierId
                        out["simCarrierIdName"] = tm.simCarrierIdName?.toString()
                    }
                }
            } catch (e: SecurityException) {
                out["phonePermissionMissing"] = true
            } catch (_: Exception) {}

            try {
                out["networkOperator"] = tm.networkOperator
                out["networkOperatorName"] = tm.networkOperatorName
                out["networkCountryIso"] = tm.networkCountryIso
                out["dataNetworkType"] = networkTypeName(tm.dataNetworkType)
            } catch (e: SecurityException) {
                out["phonePermissionMissing"] = true
            } catch (_: Exception) {}

            try {
                val ss = tm.serviceState
                if (ss != null) {
                    val s = linkedMapOf<String, Any?>()
                    s["state"] = serviceStateName(ss.state)
                    s["roaming"] = ss.roaming
                    s["operatorNumeric"] = try {
                        ss.operatorNumeric
                    } catch (_: Exception) {
                        null
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        s["channelNumber"] = ss.channelNumber
                        s["cellBandwidthsKHz"] = ss.cellBandwidths?.toList() ?: emptyList<Int>()
                        s["duplexMode"] = ss.duplexMode
                    }
                    out["serviceState"] = s
                }
            } catch (e: SecurityException) {
                out["phonePermissionMissing"] = true
            } catch (_: Exception) {}

            val cells = try {
                tm.allCellInfo
            } catch (e: SecurityException) {
                out["locationPermissionMissing"] = true
                null
            } catch (_: Exception) {
                null
            }
            out["cellCount"] = cells?.size ?: 0
            out["cells"] = (cells ?: emptyList<CellInfo>()).map { cellInfoMap(it) }
            if (cells == null || cells.isEmpty()) {
                out["cellsHint"] =
                    "No cell info — check location permission, a SIM being present, " +
                        "and that the device is registered on a network."
            }
            finish(out)
        }
    }

    private fun cellInfoMap(info: CellInfo): Map<String, Any?> {
        val m = linkedMapOf<String, Any?>()
        m["registered"] = info.isRegistered
        m["type"] = when (info) {
            is CellInfoLte -> "LTE"
            is CellInfoNr -> "NR"
            is CellInfoGsm -> "GSM"
            is CellInfoWcdma -> "WCDMA"
            is CellInfoCdma -> "CDMA"
            else -> "OTHER"
        }
        try {
            // Explicit types: getCellIdentity()/getCellSignalStrength() have
            // covariant overloads, and Kotlin's implicit property otherwise
            // resolves to the base return type.
            when (info) {
                is CellInfoGsm -> {
                    val i: CellIdentityGsm = info.cellIdentity
                    m["identity"] = mapOf(
                        "mcc" to i.mccString, "mnc" to i.mncString,
                        "cid" to i.cid, "lac" to i.lac,
                        "arfcn" to i.arfcn, "bsic" to i.bsic,
                    )
                    val s: CellSignalStrengthGsm = info.cellSignalStrength
                    m["signal"] = mapOf(
                        "dbm" to s.dbm, "asu" to s.asuLevel,
                        "rssi" to s.rssi, "timingAdvance" to s.timingAdvance,
                        "level" to s.level,
                    )
                }
                is CellInfoWcdma -> {
                    val i: CellIdentityWcdma = info.cellIdentity
                    m["identity"] = mapOf(
                        "mcc" to i.mccString, "mnc" to i.mncString,
                        "cid" to i.cid, "lac" to i.lac,
                        "psc" to i.psc, "uarfcn" to i.uarfcn,
                    )
                    val s: CellSignalStrengthWcdma = info.cellSignalStrength
                    m["signal"] = mapOf("dbm" to s.dbm, "asu" to s.asuLevel, "level" to s.level)
                }
                is CellInfoLte -> {
                    val i: CellIdentityLte = info.cellIdentity
                    m["identity"] = mapOf(
                        "mcc" to i.mccString, "mnc" to i.mncString,
                        "ci" to i.ci, "tac" to i.tac,
                        "pci" to i.pci, "earfcn" to i.earfcn,
                        "bands" to i.bands.toList(), "bandwidthKHz" to i.bandwidth,
                    )
                    val s: CellSignalStrengthLte = info.cellSignalStrength
                    m["signal"] = mapOf(
                        "dbm" to s.dbm, "rsrp" to s.rsrp, "rsrq" to s.rsrq,
                        "rssnr" to s.rssnr, "rssi" to s.rssi,
                        "timingAdvance" to s.timingAdvance, "level" to s.level,
                    )
                }
                is CellInfoNr -> {
                    @Suppress("RemoveExplicitTypeArguments")
                    val i = info.cellIdentity as CellIdentityNr
                    m["identity"] = mapOf(
                        "mcc" to i.mccString, "mnc" to i.mncString,
                        "nci" to i.nci, "tac" to i.tac,
                        "pci" to i.pci, "nrarfcn" to i.nrarfcn,
                    )
                    val s = info.cellSignalStrength as CellSignalStrengthNr
                    m["signal"] = mapOf(
                        "dbm" to s.dbm, "level" to s.level,
                        "timingAdvanceMicros" to s.timingAdvanceMicros,
                    )
                }
                is CellInfoCdma -> {
                    val i: CellIdentityCdma = info.cellIdentity
                    m["identity"] = mapOf(
                        "basestationId" to i.basestationId,
                        "networkId" to i.networkId,
                        "systemId" to i.systemId,
                    )
                    val s = info.cellSignalStrength
                    m["signal"] = mapOf("dbm" to s.dbm, "level" to s.level)
                }
            }
        } catch (_: Exception) {
            m["fieldError"] = true
        }
        return m
    }

    private fun simStateName(state: Int): String = when (state) {
        TelephonyManager.SIM_STATE_READY -> "READY"
        TelephonyManager.SIM_STATE_ABSENT -> "ABSENT"
        TelephonyManager.SIM_STATE_PIN_REQUIRED -> "PIN_REQUIRED"
        TelephonyManager.SIM_STATE_PUK_REQUIRED -> "PUK_REQUIRED"
        TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "NETWORK_LOCKED"
        TelephonyManager.SIM_STATE_NOT_READY -> "NOT_READY"
        TelephonyManager.SIM_STATE_PERM_DISABLED -> "PERM_DISABLED"
        TelephonyManager.SIM_STATE_CARD_IO_ERROR -> "CARD_IO_ERROR"
        TelephonyManager.SIM_STATE_CARD_RESTRICTED -> "CARD_RESTRICTED"
        else -> "UNKNOWN"
    }

    private fun serviceStateName(state: Int): String = when (state) {
        ServiceState.STATE_IN_SERVICE -> "IN_SERVICE"
        ServiceState.STATE_OUT_OF_SERVICE -> "OUT_OF_SERVICE"
        ServiceState.STATE_EMERGENCY_ONLY -> "EMERGENCY_ONLY"
        ServiceState.STATE_POWER_OFF -> "POWER_OFF"
        else -> "UNKNOWN"
    }

    private fun networkTypeName(type: Int): String = when (type) {
        TelephonyManager.NETWORK_TYPE_GPRS -> "GPRS"
        TelephonyManager.NETWORK_TYPE_EDGE -> "EDGE"
        TelephonyManager.NETWORK_TYPE_UMTS -> "UMTS"
        TelephonyManager.NETWORK_TYPE_CDMA -> "CDMA"
        TelephonyManager.NETWORK_TYPE_EVDO_0 -> "EVDO_0"
        TelephonyManager.NETWORK_TYPE_EVDO_A -> "EVDO_A"
        TelephonyManager.NETWORK_TYPE_1xRTT -> "1xRTT"
        TelephonyManager.NETWORK_TYPE_HSDPA -> "HSDPA"
        TelephonyManager.NETWORK_TYPE_HSUPA -> "HSUPA"
        TelephonyManager.NETWORK_TYPE_HSPA -> "HSPA"
        TelephonyManager.NETWORK_TYPE_IDEN -> "IDEN"
        TelephonyManager.NETWORK_TYPE_EVDO_B -> "EVDO_B"
        TelephonyManager.NETWORK_TYPE_LTE -> "LTE"
        TelephonyManager.NETWORK_TYPE_EHRPD -> "EHRPD"
        TelephonyManager.NETWORK_TYPE_HSPAP -> "HSPAP"
        TelephonyManager.NETWORK_TYPE_GSM -> "GSM"
        TelephonyManager.NETWORK_TYPE_TD_SCDMA -> "TD_SCDMA"
        TelephonyManager.NETWORK_TYPE_IWLAN -> "IWLAN"
        TelephonyManager.NETWORK_TYPE_NR -> "NR"
        else -> "UNKNOWN"
    }

    private fun hexToBytesOrNull(hex: String): ByteArray? {
        if (hex.isEmpty() || hex.length % 2 != 0) return null
        return try {
            ByteArray(hex.length / 2) { i ->
                hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        } catch (_: NumberFormatException) {
            null
        }
    }

    private companion object {
        const val NFC_SESSION_MS = 30_000L
    }
}
