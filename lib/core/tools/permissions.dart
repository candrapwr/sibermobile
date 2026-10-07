/// Runtime permission helpers shared by optional device tools.
///
/// Android splits permissions into "normal" (granted at install) and
/// "dangerous" (runtime prompt). Every tool that touches a dangerous permission
/// routes through [ensurePermission] so it can request once and report a clear
/// reason when denied — including pointing the user at app settings for a
/// permanently denied permission.
library;

import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Maps a permission name used in tool arguments to a [Permission] instance.
/// Keeping the mapping in one place means the tool descriptions can advertise
/// a small, stable vocabulary.
Permission? permissionByName(String name) {
  switch (name) {
    case 'location':
      return Permission.locationWhenInUse;
    case 'locationAlways':
      return Permission.locationAlways;
    case 'camera':
      return Permission.camera;
    case 'microphone':
      return Permission.microphone;
    case 'contacts':
      return Permission.contacts;
    case 'notification':
    case 'notifications':
      return Permission.notification;
    case 'storage':
      return Permission.storage;
    case 'photos':
      return Permission.photos;
    case 'videos':
      return Permission.videos;
    case 'bluetooth':
      return Permission.bluetooth;
    case 'bluetoothScan':
      return Permission.bluetoothScan;
    case 'bluetoothConnect':
      return Permission.bluetoothConnect;
    case 'calendar':
      return Permission.calendarWriteOnly;
    case 'nearbyWifiDevices':
      return Permission.nearbyWifiDevices;
    default:
      return null;
  }
}

/// Human-readable permission status for tool output.
String describeStatus(PermissionStatus status) {
  if (status.isGranted) return 'granted';
  if (status.isDenied) return 'denied';
  if (status.isPermanentlyDenied) return 'permanentlyDenied';
  if (status.isRestricted) return 'restricted';
  if (status.isLimited) return 'limited';
  if (status.isProvisional) return 'provisional';
  return status.toString();
}

/// Result of a permission request.
class PermissionOutcome {
  const PermissionOutcome({
    required this.granted,
    required this.status,
    this.permanentlyDenied = false,
  });

  final bool granted;
  final PermissionStatus status;
  final bool permanentlyDenied;

  /// Tool-facing message when not granted.
  String denialMessage(String name) {
    if (permanentlyDenied) {
      return 'Permission "$name" is permanently denied. The user must enable '
          'it in Android system settings (open_app_settings can do that).';
    }
    return 'Permission "$name" was denied (status: ${describeStatus(status)}). '
        'The action cannot proceed without it.';
  }
}

/// Checks (and requests when needed) a single permission.
///
/// On non-Android platforms the request is skipped and reported as granted so
/// the tools still work where the plugin does not apply.
Future<PermissionOutcome> ensurePermission(Permission permission) async {
  if (!Platform.isAndroid) {
    return PermissionOutcome(granted: true, status: PermissionStatus.granted);
  }

  var status = await permission.status;
  if (_isUsable(status)) {
    return PermissionOutcome(granted: true, status: status);
  }
  if (status.isPermanentlyDenied) {
    return PermissionOutcome(
      granted: false,
      status: status,
      permanentlyDenied: true,
    );
  }

  status = await permission.request();
  if (_isUsable(status)) {
    return PermissionOutcome(granted: true, status: status);
  }
  return PermissionOutcome(
    granted: false,
    status: status,
    permanentlyDenied: status.isPermanentlyDenied,
  );
}

/// Requests several permissions in one system dialog (Android batches them).
Future<Map<Permission, PermissionStatus>> ensurePermissions(
  Iterable<Permission> permissions,
) async {
  if (!Platform.isAndroid) {
    return {for (final p in permissions) p: PermissionStatus.granted};
  }
  final already = <Permission, PermissionStatus>{};
  final toRequest = <Permission>[];
  for (final p in permissions) {
    final s = await p.status;
    if (_isUsable(s)) {
      already[p] = s;
    } else {
      toRequest.add(p);
    }
  }
  if (toRequest.isEmpty) return already;
  final result = await toRequest.request();
  return {...already, ...result};
}

/// Convenience wrapper for tools: ensures [permission] is granted and returns
/// `null` on success, or a model-readable denial message otherwise.
///
/// [name] is used in the message so the model can tell the user which
/// permission to enable.
Future<String?> ensurePermissionOrMessage(
  Permission permission, {
  required String name,
}) async {
  final outcome = await ensurePermission(permission);
  return outcome.granted ? null : outcome.denialMessage(name);
}

/// Resolves a permission name from tool arguments to a [Permission], returning
/// a denial message when the name is unknown.
Future<String?> ensureNamedPermission(String name) async {
  final permission = permissionByName(name);
  if (permission == null) {
    return 'Unknown permission "$name". Supported: location, locationAlways, '
        'camera, microphone, contacts, notification, '
        'storage, photos, videos, bluetooth, bluetoothScan, bluetoothConnect, '
        'calendar, nearbyWifiDevices.';
  }
  return ensurePermissionOrMessage(permission, name: name);
}

/// A limited media grant is still usable: Android 14+ can allow only selected
/// photos/videos, which is sufficient for a user-driven picker.
bool _isUsable(PermissionStatus status) =>
    status.isGranted || status.isLimited || status.isProvisional;
