/// Core tool for handing a file from the session sandbox back to the user.
library;

import 'dart:io';

import 'results.dart';
import 'tool.dart';
import 'hardware/file_tools.dart';

/// Lets the assistant mark a file in the current session as ready for the
/// user to save through the Android system file picker.
///
/// The tool never exposes an absolute path. The UI receives only a sandbox-
/// relative path and resolves it again before reading, so a model cannot ask
/// the app to hand out an arbitrary file from the device.
class SendFileToUserTool extends Tool {
  @override
  String get name => 'send_file_to_user';

  @override
  String get category => 'Core';

  @override
  bool get isCoreTool => true;

  @override
  String get description =>
      'Make a file from the current session working directory available for '
      'the user to save on their phone. Use this after creating or locating a '
      'file when the user asks to receive, download, export, or save it. '
      'The path must be relative to workDir and must point to an existing '
      'regular file. Do not use this for files outside the session directory.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': {
        'type': 'string',
        'description': 'Existing file path relative to the session workDir.',
      },
      'name': {
        'type': 'string',
        'description':
            'Optional filename shown in the save dialog. Defaults to the '
            'source filename.',
      },
    },
    'required': ['path'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final rawPath = requireString(args, 'path');
    final path = resolveWithin(ctx.workDir, rawPath);
    final file = File(path);
    if (!await file.exists()) {
      return errorResult('File not found: $rawPath');
    }
    await ensureResolvedWithin(ctx.workDir, path);
    if (await FileSystemEntity.isDirectory(path)) {
      return errorResult('"$rawPath" is a directory, not a file.');
    }

    final bytes = await file.length();
    final sourceName = file.uri.pathSegments.isEmpty
        ? 'download'
        : file.uri.pathSegments.last;
    final requestedName = optionalString(args, 'name')?.trim();
    final name = _safeFileName(
      requestedName?.isNotEmpty == true ? requestedName! : sourceName,
    );

    return jsonResult({
      'ok': true,
      'type': 'file',
      'path': _relativePath(ctx.workDir, path),
      'name': name,
      'bytes': bytes,
      'mimeType': _mimeTypeFor(name),
    });
  }
}

String _relativePath(String root, String absolute) {
  final prefix = Directory(root).path.endsWith(Platform.pathSeparator)
      ? Directory(root).path
      : '${Directory(root).path}${Platform.pathSeparator}';
  return absolute.startsWith(prefix)
      ? absolute
            .substring(prefix.length)
            .replaceAll(Platform.pathSeparator, '/')
      : absolute;
}

String _safeFileName(String input) {
  var name = input.split(RegExp(r'[/\\]')).last.trim();
  name = name.replaceAll(RegExp(r'[\x00-\x1F]'), '_');
  if (name.isEmpty || name == '.' || name == '..') return 'download';
  if (name.length <= 120) return name;
  final dot = name.lastIndexOf('.');
  final extension = dot > 0 ? name.substring(dot) : '';
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final stemLength = (120 - extension.length).clamp(1, 120);
  return '${stem.substring(0, stemLength)}$extension';
}

String _mimeTypeFor(String name) {
  final extension = name.contains('.')
      ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
      : '';
  const types = <String, String>{
    'txt': 'text/plain',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'application/xml',
    'html': 'text/html',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
  };
  return types[extension] ?? 'application/octet-stream';
}
