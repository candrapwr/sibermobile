/// Battery tools: level, charging state, and battery-saver mode.
library;

import 'package:battery_plus/battery_plus.dart';

import '../tool.dart';
import '../results.dart';

final Battery _battery = Battery();

/// Reports the current battery level, charging state and whether battery saver
/// is on. Read-only; needs no permission.
class BatteryStatusTool extends Tool {
  @override
  String get name => 'battery_status';

  @override
  String get description =>
      'Get the device battery level (0-100), charging state '
      '(charging/full/discharging) and whether battery-saver mode is on. '
      'Read-only, no permission required.';

  @override
  Map<String, dynamic> get parameters => {
    'type': 'object',
    'properties': const {},
    'required': const [],
    'additionalProperties': false,
  };

  @override
  String get category => 'Battery';

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final level = await _battery.batteryLevel;
    final state = await _battery.batteryState;
    final saveMode = await _battery.isInBatterySaveMode;
    return jsonResult({
      'levelPercent': level,
      'state': state.name,
      'isBatterySaverOn': saveMode,
    });
  }
}

final List<Tool> batteryTools = [BatteryStatusTool()];
