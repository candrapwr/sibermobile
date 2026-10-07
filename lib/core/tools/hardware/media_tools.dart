/// Camera and media tools: capture a photo, pick from gallery, play audio.
library;

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';

import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

final ImagePicker _picker = ImagePicker();

/// Captures a photo with the camera. Requires the camera permission; the
/// resulting image is saved into the session working directory and its path is
/// returned so the user can open or share it.
class TakePhotoTool extends Tool {
  @override
  String get name => 'take_photo';

  @override
  String get description =>
      'Capture a photo with the device camera. Returns the saved file path, '
      'its size in bytes, and the mime type. Requires camera permission. '
      'Use `front: true` for the selfie camera. Optionally limit `maxWidth`/'
      '`maxHeight` (pixels) and `quality` (1-100) to reduce file size.';

  @override
  String get category => 'Camera';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'front': {
        'type': 'boolean',
        'description': 'Use the front camera. Default false (rear).',
      },
      'maxWidth': {
        'type': 'number',
        'description': 'Optional maximum width in pixels.',
      },
      'maxHeight': {
        'type': 'number',
        'description': 'Optional maximum height in pixels.',
      },
      'quality': {
        'type': 'integer',
        'description': 'Optional JPEG quality 1-100 (lower = smaller file).',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final denied = await ensureNamedPermission('camera');
    if (denied != null) return errorResult(denied);

    final front = optionalBool(args, 'front', false);
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: front ? CameraDevice.front : CameraDevice.rear,
      maxWidth: _nullableDouble(args['maxWidth']),
      maxHeight: _nullableDouble(args['maxHeight']),
      imageQuality: _nullableInt(args['quality']),
    );
    if (file == null) {
      return errorResult(
        'No photo was captured (the user may have cancelled).',
      );
    }

    final dest =
        '${ctx.workDir}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(dest).writeAsBytes(await file.readAsBytes());
    final size = await File(dest).length();

    return jsonResult({
      'path': dest,
      'sizeBytes': size,
      'mimeType': file.mimeType ?? 'image/jpeg',
    });
  }

  double? _nullableDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  int? _nullableInt(Object? v) {
    if (v is num) return v.toInt().clamp(1, 100);
    if (v is String) return int.tryParse(v)?.clamp(1, 100);
    return null;
  }
}

/// Picks an existing image from the gallery and copies it into the working
/// directory.
class PickGalleryImageTool extends Tool {
  @override
  String get name => 'pick_gallery_image';

  @override
  String get description =>
      'Let the user choose an existing image or video from the gallery. The '
      'file is copied into the session working directory and its path is '
      'returned. Requires photo/storage permission.';

  @override
  String get category => 'Camera';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'video': {
        'type': 'boolean',
        'description': 'Pick a video instead of an image. Default false.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final wantVideo = optionalBool(args, 'video', false);
    final denied = await ensureNamedPermission(wantVideo ? 'videos' : 'photos');
    if (denied != null) return errorResult(denied);

    final picked = wantVideo
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return errorResult('No file was selected (the user may have cancelled).');
    }

    final ext = wantVideo ? 'mp4' : 'jpg';
    final dest =
        '${ctx.workDir}/gallery_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(dest).writeAsBytes(await picked.readAsBytes());
    final size = await File(dest).length();

    return jsonResult({
      'path': dest,
      'sizeBytes': size,
      'mimeType': picked.mimeType ?? (wantVideo ? 'video/mp4' : 'image/jpeg'),
    });
  }
}

/// Plays an audio file from the working directory or a URL.
class PlayAudioTool extends Tool {
  @override
  String get name => 'play_audio';

  @override
  String get description =>
      'Play an audio file on the device speaker. Pass `path` for a local file '
      '(typically one saved earlier by another tool) or `url` for a remote '
      'stream. Optionally set `volume` (0.0-1.0). Returns once playback starts; '
      'call stop_audio to end it.';

  @override
  String get category => 'Media';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': {
        'type': 'string',
        'description': 'Absolute path to a local audio file.',
      },
      'url': {
        'type': 'string',
        'description': 'Remote audio URL (http/https).',
      },
      'volume': {
        'type': 'number',
        'description': 'Playback volume 0.0-1.0. Default 1.0.',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final path = optionalString(args, 'path');
    final url = optionalString(args, 'url');
    if (path == null && url == null) {
      return errorResult('Either `path` or `url` is required.');
    }

    final volume = optionalDouble(args, 'volume', 1.0).clamp(0.0, 1.0);

    if (path != null && !File(path).existsSync()) {
      return errorResult('File not found: $path');
    }

    // A single shared player so stop_audio can reach whatever is playing.
    final player = sharedAudioPlayer();
    await player.stop();
    await player.setVolume(volume);
    await player.play(path != null ? DeviceFileSource(path) : UrlSource(url!));

    return jsonResult({
      'playing': true,
      'source': path ?? url,
      'volume': volume,
    });
  }
}

/// Stops any audio started by play_audio.
class StopAudioTool extends Tool {
  @override
  String get name => 'stop_audio';

  @override
  String get description => 'Stop audio playback started by play_audio.';

  @override
  String get category => 'Media';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final player = sharedAudioPlayer();
    await player.stop();
    return jsonResult({'stopped': true});
  }
}

/// Lazily created single audio player, reused so stop can reach the playback.
AudioPlayer? _sharedPlayer;
AudioPlayer sharedAudioPlayer() => _sharedPlayer ??= AudioPlayer();

final List<Tool> mediaTools = [
  TakePhotoTool(),
  PickGalleryImageTool(),
  PlayAudioTool(),
  StopAudioTool(),
];
