/// Native device bridge over the `sibermobile/device` MethodChannel.
///
/// Covers storage info, system settings screens, installed apps and
/// text-to-speech — the four capabilities previously provided by the
/// disk_space_update, app_settings, installed_apps and flutter_tts plugins.
/// The native side lives in DeviceBridge.kt.
library;

import 'dart:io';

import 'package:flutter/services.dart';

class DeviceBridge {
  static const MethodChannel _channel = MethodChannel('sibermobile/device');

  DeviceBridge._();

  /// Total and free storage, in megabytes, on the device's primary external
  /// volume (the same volume the old disk_space_update plugin measured).
  static Future<({double totalMb, double freeMb})> diskSpace() async {
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getDiskSpace',
    );
    final totalBytes = (map?['totalBytes'] as num?)?.toInt() ?? 0;
    final freeBytes = (map?['freeBytes'] as num?)?.toInt() ?? 0;
    const mb = 1024 * 1024;
    return (totalMb: totalBytes / mb, freeMb: freeBytes / mb);
  }

  /// Lists installed apps. System apps are included only when
  /// [includeSystemApps] is true.
  static Future<List<InstalledAppInfo>> installedApps({
    bool includeSystemApps = false,
  }) async {
    if (!Platform.isAndroid) return const [];
    final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'getInstalledApps',
      {'includeSystemApps': includeSystemApps},
    );
    return (list ?? [])
        .map(
          (m) => InstalledAppInfo(
            name: m['name'] as String? ?? '',
            packageName: m['packageName'] as String? ?? '',
            versionName: m['versionName'] as String?,
            isSystemApp: m['isSystemApp'] as bool? ?? false,
          ),
        )
        .toList();
  }

  /// Whether [packageName] is installed on this device.
  static Future<bool> isAppInstalled(String packageName) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod('isAppInstalled', {
          'packageName': packageName,
        }) ??
        false;
  }

  /// Launches the app with [packageName]. Returns false when it is not
  /// installed or has no launch intent.
  static Future<bool> startApp(String packageName) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod('startApp', {
          'packageName': packageName,
        }) ??
        false;
  }

  /// Speaks [text] aloud and resolves only when the utterance finishes, is
  /// stopped (see [stopSpeaking]) or fails. [rate] runs 0.0-1.0 with 0.5 the
  /// normal speed; [pitch] runs 0.5-2.0 with 1.0 normal.
  static Future<bool> speak({
    required String text,
    String language = 'id-ID',
    double rate = 0.5,
    double pitch = 1.0,
  }) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod('ttsSpeak', {
          'text': text,
          'language': language,
          'rate': rate,
          'pitch': pitch,
        }) ??
        false;
  }

  /// Stops any in-progress speech; a pending [speak] resolves with false.
  static Future<void> stopSpeaking() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('ttsStop');
  }

  /// Whether the device has an NFC adapter and whether it is switched on.
  static Future<Map<String, dynamic>> nfcStatus() async {
    if (!Platform.isAndroid) {
      return const {'available': false, 'enabled': false};
    }
    return _asMap(await _channel.invokeMethod('nfcStatus'));
  }

  /// Starts NFC reader mode and waits up to [timeoutSeconds] for a tag, then
  /// returns its identity, per-technology parameters and (optionally) parsed
  /// NDEF records. The tag stays usable for about 30 seconds afterwards for
  /// [nfcTransceive] / [nfcWriteNdef] while it remains on the reader.
  static Future<Map<String, dynamic>> nfcAnalyze({
    int timeoutSeconds = 20,
    bool readNdef = true,
  }) async {
    if (!Platform.isAndroid) {
      return const {'found': false, 'error': 'NFC is only available on Android.'};
    }
    return _asMap(await _channel.invokeMethod('nfcAnalyze', {
      'timeoutSeconds': timeoutSeconds,
      'readNdef': readNdef,
    }));
  }

  /// Sends a raw frame ([dataHex]) to the tag of the active NFC session.
  /// With [tech] = auto an IsoDep tag is preferred (APDU exchange); otherwise
  /// NfcA/B/F/V. Returns the response as hex.
  static Future<Map<String, dynamic>> nfcTransceive(
    String dataHex, {
    String tech = 'auto',
  }) async {
    if (!Platform.isAndroid) {
      return const {'error': 'NFC is only available on Android.'};
    }
    return _asMap(await _channel.invokeMethod('nfcTransceive', {
      'dataHex': dataHex,
      'tech': tech,
    }));
  }

  /// Writes NDEF records (`{kind: text|uri, value, language?}`) to the tag of
  /// the active NFC session. The tag must already be NDEF-formatted.
  static Future<Map<String, dynamic>> nfcWriteNdef(
    List<Map<String, Object?>> records,
  ) async {
    if (!Platform.isAndroid) {
      return const {'error': 'NFC is only available on Android.'};
    }
    return _asMap(await _channel.invokeMethod('nfcWriteNdef', {
      'records': records,
    }));
  }

  /// Full Wi-Fi scan: all visible APs (SSID/BSSID/frequency/security/RSSI,
  /// channel width, randomized-BSSID flag) plus the current connection,
  /// IP/DNS/gateway and whether location services are on (scan results come
  /// back empty with location off).
  static Future<Map<String, dynamic>> wifiScan() async {
    if (!Platform.isAndroid) {
      return const {'error': 'Wi-Fi scan is only available on Android.'};
    }
    return _asMap(await _channel.invokeMethod('wifiScan'));
  }

  /// Cellular survey: SIM vs registered-network operator, network type,
  /// service state (roaming, channel, bandwidths) and every known cell
  /// (serving + neighbors) with full identity and signal detail — the raw
  /// observables for fake-base-station analysis.
  static Future<Map<String, dynamic>> cellScan() async {
    if (!Platform.isAndroid) {
      return const {'error': 'Cellular survey is only available on Android.'};
    }
    return _asMap(await _channel.invokeMethod('cellScan'));
  }

  static Map<String, dynamic> _asMap(Object? value) => value is Map
      ? value.map((k, v) => MapEntry(k.toString(), v))
      : <String, dynamic>{};
}

/// One installed app as returned by [DeviceBridge.installedApps].
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.name,
    required this.packageName,
    this.versionName,
    this.isSystemApp = false,
  });

  final String name;
  final String packageName;
  final String? versionName;
  final bool isSystemApp;
}
