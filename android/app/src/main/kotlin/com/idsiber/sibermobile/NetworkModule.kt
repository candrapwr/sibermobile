package com.idsiber.sibermobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
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
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

/**
 * Network intelligence module for the DeviceBridge channel: Wi-Fi AP
 * scanning (rogue-AP observables) and the cellular survey (fake-BTS
 * indicators). Raw data only — interpretation stays on the Dart/AI side.
 */
internal class NetworkModule(
    private val context: Context,
    private val executor: ExecutorService,
    private val mainHandler: android.os.Handler,
) {
    internal fun wifiScan(result: MethodChannel.Result) {
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

    internal fun apMap(r: ScanResult): Map<String, Any?> {
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

    internal fun stripQuotes(s: String?): String? =
        if (s == null || s == "<unknown ssid>") null else s.removeSurrounding("\"")

    internal fun isLocallyAdministeredMac(mac: String?): Boolean = try {
        val firstOctet = mac?.take(2)?.toInt(16) ?: return false
        (firstOctet and 0x02) != 0
    } catch (_: Exception) {
        false
    }

    internal fun freqToChannel(freqMHz: Int): Int = when {
        freqMHz == 2484 -> 14
        freqMHz in 2412..2472 -> (freqMHz - 2407) / 5
        freqMHz >= 5000 -> (freqMHz - 5000) / 5
        else -> 0
    }

    internal fun channelWidthName(w: Int): String = when (w) {
        ScanResult.CHANNEL_WIDTH_20MHZ -> "20MHZ"
        ScanResult.CHANNEL_WIDTH_40MHZ -> "40MHZ"
        ScanResult.CHANNEL_WIDTH_80MHZ -> "80MHZ"
        ScanResult.CHANNEL_WIDTH_160MHZ -> "160MHZ"
        ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> "80MHZ_PLUS_MHZ"
        else -> "UNKNOWN"
    }

    internal fun cellScan(result: MethodChannel.Result) {
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

    internal fun cellInfoMap(info: CellInfo): Map<String, Any?> {
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

    internal fun simStateName(state: Int): String = when (state) {
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

    internal fun serviceStateName(state: Int): String = when (state) {
        ServiceState.STATE_IN_SERVICE -> "IN_SERVICE"
        ServiceState.STATE_OUT_OF_SERVICE -> "OUT_OF_SERVICE"
        ServiceState.STATE_EMERGENCY_ONLY -> "EMERGENCY_ONLY"
        ServiceState.STATE_POWER_OFF -> "POWER_OFF"
        else -> "UNKNOWN"
    }

    internal fun networkTypeName(type: Int): String = when (type) {
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

    internal fun hexToBytesOrNull(hex: String): ByteArray? {
        if (hex.isEmpty() || hex.length % 2 != 0) return null
        return try {
            ByteArray(hex.length / 2) { i ->
                hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
        } catch (_: NumberFormatException) {
            null
        }
    }
}
