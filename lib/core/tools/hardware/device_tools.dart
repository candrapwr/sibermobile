/// Device information tools: hardware identity, storage, RAM, OS version, and
/// the app's own package metadata.
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:disk_space_update/disk_space_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../tool.dart';
import '../results.dart';

final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

/// Reports the device model, manufacturer, Android version, SDK level,
/// supported ABIs, RAM and disk sizes.
class DeviceInfoTool extends Tool {
  @override
  String get name => 'get_device_info';

  @override
  String get category => 'Device';

  @override
  String get description =>
      'Get detailed information about this Android device: model, manufacturer, '
      'brand, Android release and SDK level, supported ABIs, physical/available '
      'RAM, total/free disk size, and whether it is a physical device or emulator. '
      'Use this before recommending hardware-specific actions.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    if (!Platform.isAndroid) {
      return jsonResult({
        'error': 'get_device_info is only available on Android.',
      });
    }
    // A platform-channel/plugin failure must not leave the tool card spinning
    // forever. The registry converts this timeout into a model-readable error.
    final info = await _deviceInfo.androidInfo.timeout(
      const Duration(seconds: 10),
    );
    return jsonResult({
      'model': info.model,
      'manufacturer': info.manufacturer,
      'brand': info.brand,
      'device': info.device,
      'product': info.product,
      'board': info.board,
      'hardware': info.hardware,
      'androidRelease': info.version.release,
      'sdkInt': info.version.sdkInt,
      'securityPatch': info.version.securityPatch,
      'baseOs': info.version.baseOS,
      'supportedAbis': info.supportedAbis,
      'isPhysicalDevice': info.isPhysicalDevice,
      'isLowRamDevice': info.isLowRamDevice,
      'physicalRamBytes': info.physicalRamSize,
      'availableRamBytes': info.availableRamSize,
      'totalDiskBytes': info.totalDiskSize,
      'freeDiskBytes': info.freeDiskSize,
      'systemFeatures': info.systemFeatures,
    });
  }
}

/// Reports total and free storage for the app's internal storage.
class StorageInfoTool extends Tool {
  @override
  String get name => 'get_storage_info';

  @override
  String get category => 'Device';

  @override
  String get description =>
      'Get total and free disk space (in megabytes) available to this app. '
      'Useful before downloading or writing large files.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final total = await DiskSpace.getTotalDiskSpace;
    final free = await DiskSpace.getFreeDiskSpace;
    return jsonResult({
      'unit': 'MB',
      'totalMb': ?total,
      'freeMb': ?free,
      if (total != null && free != null) 'usedMb': total - free,
      'workDir': ctx.workDir,
    });
  }
}

/// Reports this app's own package metadata.
class AppInfoTool extends Tool {
  @override
  String get name => 'get_app_info';

  @override
  String get category => 'Device';

  @override
  String get description =>
      "Get this app's own metadata: application name, package name, version "
      'and build number.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final info = await PackageInfo.fromPlatform();
    return jsonResult({
      'appName': info.appName,
      'packageName': info.packageName,
      'version': info.version,
      'buildNumber': info.buildNumber,
    });
  }
}

/// All tools in this file, in the order they appear in the tools screen.
final List<Tool> deviceTools = [
  DeviceInfoTool(),
  StorageInfoTool(),
  AppInfoTool(),
];
