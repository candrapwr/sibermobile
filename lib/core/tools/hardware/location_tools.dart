/// Location tools: current GPS position and accuracy.
library;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

/// Gets the device's current GPS position. Requests location permission at
/// runtime; returns a clear reason when the service is off or denied.
class GetCurrentLocationTool extends Tool {
  @override
  String get name => 'get_current_location';

  @override
  String get description =>
      'Get the device current GPS location (latitude, longitude, accuracy, '
      'altitude, speed). Requests location permission at runtime. Returns an '
      'error string when location services are off or the user denies access.';

  @override
  String get category => 'Location';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': {
      'accuracy': {
        'type': 'string',
        'enum': ['lowest', 'low', 'medium', 'high', 'best'],
        'description':
            'Desired accuracy. Higher accuracy uses more battery. Default: high.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final permissionError = await ensurePermissionOrMessage(
      Permission.locationWhenInUse,
      name: 'location',
    );
    if (permissionError != null) return errorResult(permissionError);

    if (!await Geolocator.isLocationServiceEnabled()) {
      return errorResult(
        'Location services are disabled. Ask the user to turn on GPS/location.',
      );
    }

    final accuracy = _parseAccuracy(args['accuracy']);
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: accuracy),
    );

    return jsonResult({
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'accuracyMeters': round2(pos.accuracy),
      'altitude': pos.altitude,
      'speed': pos.speed,
      'timestamp': pos.timestamp.toIso8601String(),
    });
  }

  LocationAccuracy _parseAccuracy(Object? raw) {
    switch (raw?.toString().toLowerCase()) {
      case 'lowest':
        return LocationAccuracy.lowest;
      case 'low':
        return LocationAccuracy.low;
      case 'medium':
        return LocationAccuracy.medium;
      case 'best':
        return LocationAccuracy.best;
      case 'high':
      default:
        return LocationAccuracy.high;
    }
  }
}

/// All tools in this file.
final List<Tool> locationTools = [GetCurrentLocationTool()];
