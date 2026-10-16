package com.idsiber.sibermobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.TagLostException
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
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.Locale
import java.util.concurrent.ExecutorService

/**
 * NFC module for the DeviceBridge channel: reader-mode based tag discovery
 * with short-lived sessions, raw-frame transceive and NDEF writing.
 *
 * Session model: [analyze] starts reader mode and keeps the discovered tag
 * alive for ~30s; [transceive]/[writeNdef] operate on that tag while it
 * stays on the reader (each command extends the session).
 */
internal class NfcModule(
    private val context: Context,
    private val executor: ExecutorService,
    private val mainHandler: Handler,
    /** NFC reader mode is activity-scoped; the bridge supplies the current one. */
    private val activityProvider: () -> Activity?,
) {
    private val nfcLock = Any()
    private var nfcSessionTag: Tag? = null
    private var nfcSessionExpiresAt = 0L
    private var nfcReaderEnabled = false

    private val readerCallback = NfcAdapter.ReaderCallback { tag ->
        synchronized(nfcLock) {
            nfcSessionTag = tag
            nfcSessionExpiresAt = System.currentTimeMillis() + NFC_SESSION_MS
            (nfcLock as Object).notifyAll()
        }
    }

    private fun nfcAdapterOrNull(): NfcAdapter? = try {
        NfcAdapter.getDefaultAdapter(context)
    } catch (_: Exception) {
        null
    }

    private fun currentNfcTag(): Tag? = synchronized(nfcLock) {
        if (System.currentTimeMillis() < nfcSessionExpiresAt) nfcSessionTag else null
    }

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
                val activity = activityProvider()
                if (adapter != null && activity != null) {
                    try {
                        adapter.disableReaderMode(activity)
                    } catch (_: Exception) {}
                }
            }
        }
    }

    fun status(result: MethodChannel.Result) {
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

    fun analyze(
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
                val activity = activityProvider()
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
                        (nfcLock as Object).wait(remaining)
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
        info["techList"] = tag.techList.map { it.substringAfterLast('.') }.distinct()
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
    fun transceive(
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
            val available = techs.map { it.substringAfterLast('.') }.distinct()
            val requested = tech.trim().lowercase()

            if (requested == "mifareclassic") {
                finish(
                    mapOf(
                        "error" to "MIFARE Classic does not accept raw transceive frames: " +
                            "its sectors need authenticateSectorWithKey + readBlock calls. " +
                            "The tag's metadata (type, size, sectors, blocks) is already in " +
                            "the nfc_analyze result.",
                    ),
                )
                return@execute
            }

            val selected: TagTechnology? = when {
                (requested == "isodep" || requested == "auto") &&
                    techs.contains("android.nfc.tech.IsoDep") -> IsoDep.get(tag)
                (requested == "nfca" || requested == "auto") &&
                    techs.contains("android.nfc.tech.NfcA") -> NfcA.get(tag)
                (requested == "nfcb" || requested == "auto") &&
                    techs.contains("android.nfc.tech.NfcB") -> NfcB.get(tag)
                (requested == "nfcf" || requested == "auto") &&
                    techs.contains("android.nfc.tech.NfcF") -> NfcF.get(tag)
                (requested == "nfcv" || requested == "auto") &&
                    techs.contains("android.nfc.tech.NfcV") -> NfcV.get(tag)
                requested == "mifareultralight" &&
                    techs.contains("android.nfc.tech.MifareUltralight") ->
                    MifareUltralight.get(tag)
                else -> null
            }
            if (selected == null) {
                finish(
                    mapOf(
                        "error" to "Tech '${tech.trim()}' is not available on this tag. " +
                            "Available: ${available.joinToString()}. Supported values: auto, " +
                            "isoDep, nfcA, nfcB, nfcF, nfcV, mifareUltralight " +
                            "(mifareClassic has no raw-frame support).",
                    ),
                )
                return@execute
            }

            val maxLen = when (selected) {
                is IsoDep -> selected.maxTransceiveLength
                is NfcA -> selected.maxTransceiveLength
                is NfcB -> selected.maxTransceiveLength
                is NfcF -> selected.maxTransceiveLength
                is NfcV -> selected.maxTransceiveLength
                is MifareUltralight -> selected.maxTransceiveLength
                else -> 0
            }
            if (maxLen in 1 until bytes.size) {
                finish(mapOf("error" to "Frame is ${bytes.size} bytes but ${selected.javaClass.simpleName} accepts at most $maxLen."))
                return@execute
            }

            // One connection per command: connect → transceive → close.
            try {
                selected.connect()
                val response = when (selected) {
                    is IsoDep -> selected.transceive(bytes)
                    is NfcA -> selected.transceive(bytes)
                    is NfcB -> selected.transceive(bytes)
                    is NfcF -> selected.transceive(bytes)
                    is NfcV -> selected.transceive(bytes)
                    is MifareUltralight -> selected.transceive(bytes)
                    else -> throw IllegalStateException("unsupported tech")
                }
                touchNfcSession()
                finish(
                    mapOf(
                        "responseHex" to bytesToHex(response),
                        "tech" to selected.javaClass.simpleName,
                    ),
                )
            } catch (e: TagLostException) {
                finish(
                    mapOf(
                        "error" to "The tag left the reader field while ${selected.javaClass.simpleName} was busy. Hold the card steady and retry; if it keeps happening, rerun nfc_analyze.",
                    ),
                )
            } catch (e: IOException) {
                finish(
                    mapOf(
                        "error" to "${selected.javaClass.simpleName} transceive failed: ${e.message ?: "I/O error"}",
                        "hint" to "Either the card does not support this command (check CLA/INS and parameters — e.g. 6E00 means 'instruction not supported') or the RF link dropped. Keep the card on the reader and retry.",
                    ),
                )
            } catch (e: Exception) {
                finish(
                    mapOf(
                        "error" to "${selected.javaClass.simpleName} error: ${e.message ?: "transceive failed"}",
                    ),
                )
            } finally {
                try {
                    selected.close()
                } catch (_: Exception) {}
            }
        }
    }

    /** Writes NDEF text/URI records to the tag of the active session. */
    fun writeNdef(
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
            var connected = false
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
                connected = true
                if (!ndef.isWritable) {
                    finish(mapOf("error" to "The tag is read-only."))
                    return@execute
                }
                ndef.writeNdefMessage(NdefMessage(messages.toTypedArray()))
                true
            } catch (e: Exception) {
                finish(mapOf("error" to (e.message ?: "write failed")))
                return@execute
            } finally {
                // Same leak as transceive: an open Ndef connection blocks
                // every later TagTechnology on this tag.
                if (connected) {
                    try {
                        ndef.close()
                    } catch (_: Exception) {}
                }
            }
            touchNfcSession()
            finish(mapOf("ok" to out))
        }
    }

    internal fun bytesToHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

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
