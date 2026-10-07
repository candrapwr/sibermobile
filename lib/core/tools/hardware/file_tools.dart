/// File tools scoped to the session working directory.
///
/// The agent can inspect and write files inside `ctx.workDir` only (app
/// documents dir + session id). All paths are resolved and verified inside that
/// sandbox before touching the disk.
library;

import 'dart:io';

import '../tool.dart';
import '../results.dart';

/// Resolves [raw] inside [root], rejecting escapes via `..` or absolute paths.
String resolveWithin(String root, String raw) {
  if (raw.trim().isEmpty) throw ArgumentError('path is required');
  final normalized = Directory(root).uri.resolve(raw).toFilePath();
  final rootPath = Directory(root).path.endsWith(Platform.pathSeparator)
      ? Directory(root).path
      : '${Directory(root).path}${Platform.pathSeparator}';
  if (!normalized.startsWith(rootPath) && normalized != Directory(root).path) {
    throw ArgumentError('path "$raw" resolves outside the session directory');
  }
  return normalized;
}

/// Verifies the resolved target stays inside the sandbox as well as the
/// lexical path. This closes the symlink escape that a string-prefix check
/// alone cannot detect.
Future<void> ensureResolvedWithin(String root, String candidate) async {
  final rootReal = await Directory(root).resolveSymbolicLinks();
  final candidateReal = await File(candidate).resolveSymbolicLinks();
  final prefix = rootReal.endsWith(Platform.pathSeparator)
      ? rootReal
      : '$rootReal${Platform.pathSeparator}';
  if (!candidateReal.startsWith(prefix) && candidateReal != rootReal) {
    throw ArgumentError('path resolves outside the session directory');
  }
}

/// Reads a text file from the session directory.
class ReadFileTool extends Tool {
  @override
  String get name => 'read_file';

  @override
  String get category => 'Files';

  @override
  String get description =>
      'Read a text file inside the session working directory. '
      'Optionally start at an `offset` line and read at most `limit` lines.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': {
        'type': 'string',
        'description': 'File path relative to the session directory.',
      },
      'offset': {
        'type': 'integer',
        'description': '1-based starting line. Optional.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum number of lines to read. Optional.',
      },
    },
    'required': ['path'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final path = resolveWithin(ctx.workDir, requireString(args, 'path'));
    final file = File(path);
    if (!await file.exists()) {
      return errorResult('File not found: ${args['path']}');
    }
    if (await FileSystemEntity.isDirectory(path)) {
      return errorResult(
        '"${args['path']}" is a directory, not a file. Use list_dir.',
      );
    }
    final lines = await file.readAsLines();
    final offset = optionalInt(
      args,
      'offset',
      1,
    ).clamp(1, lines.isEmpty ? 1 : lines.length);
    final limit = optionalInt(args, 'limit', 500).clamp(1, 5000);
    final slice = lines.skip(offset - 1).take(limit).toList();
    return truncateResult(slice.join('\n'), maxChars: 20000);
  }
}

/// Writes (creates or overwrites) a text file in the session directory.
class WriteFileTool extends Tool {
  @override
  String get name => 'write_file';

  @override
  String get category => 'Files';

  @override
  String get description =>
      'Write text content to a file inside the session working directory, '
      'creating parent folders as needed. Overwrites an existing file.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': {
        'type': 'string',
        'description': 'File path relative to the session directory.',
      },
      'content': {'type': 'string', 'description': 'Full file content.'},
    },
    'required': ['path', 'content'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final path = resolveWithin(ctx.workDir, requireString(args, 'path'));
    final content = args['content']?.toString() ?? '';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return jsonResult({
      'ok': true,
      'path': args['path'].toString(),
      'bytes': content.length,
    });
  }
}

/// Lists the entries of a directory inside the session directory.
class ListDirTool extends Tool {
  @override
  String get name => 'list_dir';

  @override
  String get category => 'Files';

  @override
  String get description =>
      'List files and sub-folders inside a directory of the session working '
      'directory. Pass an empty path (or ".") to list the root.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': {
        'type': 'string',
        'description':
            'Directory path relative to the session directory. Default ".".',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final raw = optionalString(args, 'path') ?? '.';
    final path = resolveWithin(ctx.workDir, raw);
    final dir = Directory(path);
    if (!await dir.exists()) return errorResult('Directory not found: $raw');
    final entries = await dir.list().toList();
    final out = entries.map((e) {
      final name =
          e.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? e.path;
      if (e is Directory) return {'name': name, 'type': 'dir'};
      if (e is File) {
        return {'name': name, 'type': 'file', 'bytes': e.lengthSync()};
      }
      return {'name': name, 'type': 'other'};
    }).toList();
    return jsonListResult(out);
  }
}

/// Deletes a file (or empty directory) inside the session directory.
/// Destructive: requires approval when that setting is on.
class DeleteFileTool extends Tool {
  @override
  String get name => 'delete_file';

  @override
  String get category => 'Files';

  @override
  bool get requiresApproval => true;

  @override
  String get description =>
      'Delete a file inside the session working directory. '
      'This cannot be undone.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': {
        'type': 'string',
        'description': 'File path relative to the session directory.',
      },
    },
    'required': ['path'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final path = resolveWithin(ctx.workDir, requireString(args, 'path'));
    final entity = File(path);
    if (!await entity.exists()) {
      return errorResult('File not found: ${args['path']}');
    }
    await entity.delete();
    return jsonResult({'ok': true, 'deleted': args['path'].toString()});
  }
}

final List<Tool> fileTools = [
  ReadFileTool(),
  WriteFileTool(),
  ListDirTool(),
  DeleteFileTool(),
];
