/// System control tool: vibration.
library;

import 'dart:io';

import 'package:vibration/vibration.dart';

import '../tool.dart';
import '../results.dart';

/// Vibrates the device.
class VibrateTool extends Tool {
  @override
  String get name => 'vibrate';

  @override
  String get category => 'System';

  @override
  String get description =>
      'Vibrate the device for a duration (milliseconds) or with a custom '
      'pattern (wait/vibrate/wait/... in ms).';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'durationMs': {
        'type': 'integer',
        'description': 'Vibration length in milliseconds (default 500).',
      },
      'pattern': {
        'type': 'array',
        'items': {'type': 'integer'},
        'description': 'Custom pattern of wait/vibrate durations in ms.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return errorResult('Vibration is only supported on Android/iOS.');
    }
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator != true) {
      return errorResult('This device has no vibrator.');
    }

    final rawPattern = args['pattern'];
    if (rawPattern is List && rawPattern.isNotEmpty) {
      final pattern = rawPattern.map((e) => (e as num).toInt()).toList();
      await Vibration.vibrate(pattern: pattern);
      return jsonResult({'ok': true, 'pattern': pattern});
    }

    final duration = optionalInt(args, 'durationMs', 500).clamp(0, 10000);
    await Vibration.vibrate(duration: duration);
    return jsonResult({'ok': true, 'durationMs': duration});
  }
}

final List<Tool> systemTools = [VibrateTool()];
