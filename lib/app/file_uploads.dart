/// Copying and model-facing metadata for user-uploaded files.
library;

import 'dart:io';

import '../core/ai/types.dart';

/// Hard limit per attachment. Files are copied locally; they are never
/// uploaded by this app to a separate file server.
const int maxUploadBytes = 10 * 1024 * 1024;

/// A file selected by the composer but not yet copied into the session.
class PendingFileUpload {
  const PendingFileUpload({
    required this.sourcePath,
    required this.name,
    required this.bytes,
  });

  final String sourcePath;
  final String name;
  final int bytes;
}

class FileUploadException implements Exception {
  const FileUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Copies [uploads] into `uploads/` under [workDir] and returns only safe,
/// relative paths for the agent. A failure cleans up files copied in this call.
Future<List<AttachedFile>> copyUploadsToWorkDir({
  required List<PendingFileUpload> uploads,
  required String workDir,
}) async {
  if (uploads.isEmpty) return const [];

  final destinationDir = Directory(
    '${Directory(workDir).path}${Platform.pathSeparator}uploads',
  );
  await destinationDir.create(recursive: true);
  final created = <File>[];

  try {
    final copied = <AttachedFile>[];
    for (final upload in uploads) {
      if (upload.bytes > maxUploadBytes) {
        throw FileUploadException(
          '"${upload.name}" melebihi batas ukuran 10 MB.',
        );
      }

      final source = File(upload.sourcePath);
      if (!await source.exists()) {
        throw FileUploadException('File "${upload.name}" tidak ditemukan.');
      }
      final actualBytes = await source.length();
      if (actualBytes > maxUploadBytes) {
        throw FileUploadException(
          '"${upload.name}" melebihi batas ukuran 10 MB.',
        );
      }

      final fileName = _safeFileName(upload.name);
      final target = await _availableTarget(destinationDir, fileName);
      await source.copy(target.path);
      created.add(target);
      copied.add(
        AttachedFile(
          name: target.uri.pathSegments.last,
          relativePath: 'uploads/${target.uri.pathSegments.last}',
          bytes: actualBytes,
        ),
      );
    }
    return copied;
  } catch (_) {
    for (final file in created) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The original failure is more helpful than a best-effort cleanup one.
      }
    }
    rethrow;
  }
}

/// Builds the provider-visible user content. File paths are sandbox-relative,
/// while the UI renders [AttachedFile.name] only.
String contentWithAttachments(String text, List<AttachedFile> attachments) {
  final cleanText = text.trim();
  if (attachments.isEmpty) return cleanText;

  final lines = <String>[
    if (cleanText.isNotEmpty) cleanText,
    if (cleanText.isNotEmpty) '',
    '[Attached files]',
    'The user uploaded these files. They were copied into this session working '
        'directory; each path below is relative to workDir and can be used with '
        'the file tools.',
    for (final file in attachments)
      '- ${file.name}: ${file.relativePath} (${file.bytes} bytes)',
    'Do not claim to have read or understood a file until a suitable tool has '
        'returned its contents.',
  ];
  return lines.join('\n');
}

String _safeFileName(String input) {
  var name = input.split(RegExp(r'[/\\]')).last.trim();
  name = name.replaceAll(RegExp(r'[\x00-\x1F]'), '_');
  if (name.isEmpty || name == '.' || name == '..') name = 'upload';
  if (name.length <= 120) return name;

  final dot = name.lastIndexOf('.');
  final extension = dot > 0 ? name.substring(dot) : '';
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return '${stem.substring(0, 120 - extension.length)}$extension';
}

Future<File> _availableTarget(Directory dir, String name) async {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';

  var suffix = 1;
  var candidate = File('${dir.path}${Platform.pathSeparator}$name');
  while (await candidate.exists()) {
    suffix++;
    candidate = File(
      '${dir.path}${Platform.pathSeparator}$stem ($suffix)$extension',
    );
  }
  return candidate;
}
