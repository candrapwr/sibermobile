/// Network analysis tools: Wi-Fi AP scan, cellular/provider survey and
/// active probes (ping/DNS/TCP) — free-form intelligence primitives.
///
/// wifi_scan and cell_scan return raw observables through the DeviceBridge
/// channel; the AI does the analysis (evil-twin APs, rogue access points,
/// fake base stations / IMSI-catcher indicators). net_probe is pure Dart.
library;

import 'dart:io';

import '../../native/device_bridge.dart';
import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

/// Scans all visible Wi-Fi APs for free-form security analysis.
class WifiScanTool extends Tool {
  @override
  String get name => 'wifi_scan';

  @override
  String get description =>
      'Scan all visible Wi-Fi access points and return raw observables for '
      'security analysis: SSID, BSSID, channel/frequency, RSSI, security '
      'capabilities (WPA2/WPA3/open), channel width, and a '
      'bssidLocallyAdministered flag (randomized MAC — a classic rogue-AP '
      'sign). Also returns the current connection with IP/gateway/DNS. Needs '
      'location permission AND location services enabled. Analysis ideas: '
      'evil twins (same SSID, multiple BSSIDs/vendors), open networks '
      'mimicking trusted names, suspicious signal levels, unknown APs near '
      'the user. Android throttles scans (~4 per 2 minutes); when throttled, '
      'cached results are returned and scanTriggered=false.';

  @override
  String get category => 'Network';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final denied = await ensureNamedPermission('location');
    if (denied != null) return errorResult(denied);
    final scan = await DeviceBridge.wifiScan();
    final error = scan['error'];
    if (error is String && error.isNotEmpty) return errorResult(error);
    return jsonResult(scan);
  }
}

/// Surveys the cellular environment: SIM vs network operator, all cells with
/// identity and signal detail — the observables for fake-BTS detection.
class CellScanTool extends Tool {
  @override
  String get name => 'cell_scan';

  @override
  String get description =>
      'Survey the cellular network for free-form analysis (e.g. fake base '
      'station / IMSI-catcher detection). Returns: SIM identity (operator '
      'MCC+MNC, carrier), the REGISTERED network operator and type (LTE/NR/'
      'GSM/...), service state (roaming, channel number, cell bandwidths) and '
      'every known cell — serving plus neighbors — with identity (MCC, MNC, '
      'CI/NCI, TAC/LAC, PCI, EARFCN/NRARFCN) and signal detail (RSRP, RSRQ, '
      'SINR, timing advance). Fake-BTS indicators to analyze: registered '
      'network operator differing from SIM operator, sudden downgrade to 2G/'
      'GPRS, unexpected TAC/LAC or cell IDs, abnormally strong neighbor '
      'signals, or all cells reporting identical identifiers. Needs location '
      'and phone permissions plus a SIM card.';

  @override
  String get category => 'Network';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final locationDenied = await ensureNamedPermission('location');
    if (locationDenied != null) return errorResult(locationDenied);
    final phoneDenied = await ensureNamedPermission('phone');
    if (phoneDenied != null) return errorResult(phoneDenied);
    final scan = await DeviceBridge.cellScan();
    final error = scan['error'];
    if (error is String && error.isNotEmpty) return errorResult(error);
    return jsonResult(scan);
  }
}

/// Active network probes: ping, DNS lookup and TCP port check (pure Dart).
class NetProbeTool extends Tool {
  @override
  String get name => 'net_probe';

  @override
  String get description =>
      'Active network probes against a host: ping (ICMP via the system ping '
      'binary, Android only), DNS lookup (forward + reverse) and TCP port '
      'connectivity with timeout. op=all runs everything (default: ping). '
      'Use for diagnostics the passive tools cannot do: is a gateway/host '
      'alive, does DNS resolve correctly (also useful for hijack checks — '
      'compare against a known-good resolver), is a port filtered. Only probe '
      'hosts the user asks about.';

  @override
  String get category => 'Network';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'host': <String, dynamic>{
        'type': 'string',
        'description': 'Hostname or IP address to probe.',
      },
      'op': <String, dynamic>{
        'type': 'string',
        'enum': <String>['ping', 'dns', 'tcp', 'all'],
        'description': 'Which probe to run (default ping; all = ping+dns+tcp).',
      },
      'count': <String, dynamic>{
        'type': 'integer',
        'description': 'Ping count 1-10 (default 4).',
      },
      'port': <String, dynamic>{
        'type': 'integer',
        'description': 'TCP port for op=tcp/all (default 443).',
      },
      'timeoutSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'Per-probe timeout in seconds (default 3, max 10).',
      },
    },
    'required': <String>['host'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final host = requireString(args, 'host').trim();
    final op = optionalString(args, 'op') ?? 'ping';
    final count = optionalInt(args, 'count', 4).clamp(1, 10);
    final port = optionalInt(args, 'port', 443).clamp(1, 65535);
    final timeout = optionalInt(args, 'timeoutSeconds', 3).clamp(1, 10);

    final out = <String, dynamic>{'host': host, 'op': op};
    if (op == 'ping' || op == 'all') out['ping'] = await _ping(host, count, timeout);
    if (op == 'dns' || op == 'all') out['dns'] = await _dns(host);
    if (op == 'tcp' || op == 'all') out['tcp'] = await _tcp(host, port, timeout);
    return jsonResult(out);
  }

  Future<Map<String, dynamic>> _ping(
    String host,
    int count,
    int timeout,
  ) async {
    if (!Platform.isAndroid) {
      return {'error': 'ping is only available on Android.'};
    }
    try {
      final proc = await Process.run(
        'ping',
        ['-c', '$count', '-W', '$timeout', host],
      ).timeout(Duration(seconds: count * timeout + 5));
      final stdout = proc.stdout.toString();
      return {
        'exitCode': proc.exitCode,
        'reachable': proc.exitCode == 0,
        // rtt min/avg/max/mdev + per-packet lines; keep the tail (summary).
        'summary': stdout.trim().isEmpty ? null : stdout.trim().split('\n').last,
        'raw': stdout.trim().isEmpty ? null : stdout.trim(),
      };
    } catch (e) {
      return {'error': 'ping failed: $e'};
    }
  }

  Future<Map<String, dynamic>> _dns(String host) async {
    try {
      final addrs = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      final reverses = <String>[];
      for (final a in addrs.take(3)) {
        try {
          reverses.add((await a.reverse()).host);
        } catch (_) {}
      }
      return {
        'resolved': addrs.map((a) => a.address).toList(),
        'reverse': reverses,
      };
    } catch (e) {
      return {'error': 'DNS lookup failed: $e'};
    }
  }

  Future<Map<String, dynamic>> _tcp(
    String host,
    int port,
    int timeout,
  ) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(seconds: timeout),
      );
      socket.destroy();
      return {'open': true, 'port': port};
    } catch (e) {
      return {
        'open': false,
        'port': port,
        'error': e.toString(),
        // "refused" = host reachable but closed; timeout = filtered/no route.
      };
    }
  }
}

final List<Tool> networkAnalysisTools = <Tool>[
  WifiScanTool(),
  CellScanTool(),
  NetProbeTool(),
];
