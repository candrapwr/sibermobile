/// Network tools: connectivity type and Wi-Fi details.
library;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

final Connectivity _connectivity = Connectivity();
final NetworkInfo _networkInfo = NetworkInfo();

/// Reports the active network type(s) plus, when on Wi-Fi, the SSID/IP/gateway.
/// Wi-Fi details need location permission on Android 8+.
class NetworkInfoTool extends Tool {
  @override
  String get name => 'network_info';

  @override
  String get description =>
      'Get the current network connectivity (wifi/mobile/ethernet/bluetooth/none) '
      'and, when connected to Wi-Fi, the SSID, BSSID, local IP and gateway. '
      'Wi-Fi details require location permission on Android 8+; if denied, only '
      'the connectivity type is returned.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': const {},
    'required': const [],
    'additionalProperties': false,
  };

  @override
  String get category => 'Network';

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final results = await _connectivity.checkConnectivity();
    final types = results.map((r) => r.name).toList();
    final onWifi = results.contains(ConnectivityResult.wifi);

    final out = <String, dynamic>{'connectivity': types, 'onWifi': onWifi};
    if (onWifi) {
      final denied = await ensureNamedPermission('location');
      if (denied != null) {
        out['wifiDetailsError'] = denied;
      } else {
        out['wifiName'] = await _safe(() => _networkInfo.getWifiName());
        out['wifiBSSID'] = await _safe(() => _networkInfo.getWifiBSSID());
        out['wifiIp'] = await _safe(() => _networkInfo.getWifiIP());
        out['wifiGateway'] = await _safe(() => _networkInfo.getWifiGatewayIP());
      }
    }
    return jsonResult(out);
  }

  Future<String?> _safe(Future<String?> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }
}

final List<Tool> networkTools = [NetworkInfoTool()];
