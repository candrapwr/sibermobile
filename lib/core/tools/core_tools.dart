/// Built-in tools that are always available to the assistant.
library;

import 'results.dart';
import 'tool.dart';
import 'file_delivery.dart';

/// Reads the actual clock from the device.
///
/// This is intentionally a core tool rather than an optional device feature:
/// a model must not guess a date or time when the user asks for current,
/// time-sensitive information.
class GetCurrentTimeTool extends Tool {
  @override
  String get name => 'get_current_time';

  @override
  String get category => 'Core';

  @override
  bool get isCoreTool => true;

  @override
  String get description =>
      'Get the actual current date and time from this device, including its '
      'local UTC offset and UTC time. Always use this tool when the user asks '
      'for the current time, date, day, or other time-sensitive information; '
      'do not guess from your training data.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final offsetText = _formatUtcOffset(offset);

    return jsonResult({
      'localDateTime': '${now.toIso8601String()}$offsetText',
      'utcDateTime': now.toUtc().toIso8601String(),
      'timeZoneName': now.timeZoneName,
      'utcOffset': offsetText,
      'unixTimestampMs': now.millisecondsSinceEpoch,
      'weekdayIso': now.weekday,
    });
  }
}

String _formatUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final totalMinutes = offset.inMinutes.abs();
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return '$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

/// Tools that must stay registered regardless of the user's toggle choices.
final List<Tool> coreTools = <Tool>[GetCurrentTimeTool(), SendFileToUserTool()];
