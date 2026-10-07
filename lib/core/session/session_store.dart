/// Session persistence: each conversation is a JSON file in the app documents
/// directory, holding metadata plus the message history.
///
/// Adapted from siberflow's `packages/core/src/session/store.ts` — same idea
/// (one JSON file per session, versioned format), but rooted in the Android app
/// documents dir instead of `~/.siberflow`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../agent/context_compaction.dart';
import '../ai/types.dart';

/// Version 3 adds user-upload metadata, alongside the compact-context summary.
const int sessionFormatVersion = 3;

/// Token accounting carried with a session.
class SessionUsage {
  const SessionUsage({
    this.last = UsageStats.zero,
    this.total = UsageStats.zero,
  });

  /// The last provider call in the most recent turn.
  final UsageStats last;

  /// Sum of every call — reflects actual API usage.
  final UsageStats total;

  Map<String, dynamic> toJson() => {
    'last': last.toJson(),
    'total': total.toJson(),
  };

  factory SessionUsage.fromJson(Map<String, dynamic> json) => SessionUsage(
    last: _usageFrom(json['last']),
    total: _usageFrom(json['total']),
  );

  static UsageStats _usageFrom(Object? raw) =>
      raw is Map<String, dynamic> ? UsageStats.fromJson(raw) : UsageStats.zero;
}

/// A persisted conversation.
class Session {
  Session({
    required this.id,
    this.name,
    this.model = '',
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
    this.usage = const SessionUsage(),
    this.compactSummary,
    this.version = sessionFormatVersion,
  });

  int version;
  String id;
  String? name;
  String model;
  DateTime createdAt;
  DateTime updatedAt;
  List<Message> messages;
  SessionUsage usage;
  ContextSummary? compactSummary;

  Map<String, dynamic> toJson() => {
    'version': version,
    'id': id,
    'name': name,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toStorageJson()).toList(),
    'usage': usage.toJson(),
    if (compactSummary != null) 'compactSummary': compactSummary!.toJson(),
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    version: (json['version'] as num?)?.toInt() ?? sessionFormatVersion,
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString(),
    model: json['model']?.toString() ?? '',
    createdAt: _dateFrom(json['createdAt']),
    updatedAt: _dateFrom(json['updatedAt']),
    messages:
        (json['messages'] as List?)
            ?.whereType<Map>()
            .map((m) => Message.fromStorageJson(m.cast<String, dynamic>()))
            .toList() ??
        const [],
    usage: json['usage'] is Map<String, dynamic>
        ? SessionUsage.fromJson(json['usage'] as Map<String, dynamic>)
        : const SessionUsage(),
    compactSummary: json['compactSummary'] is Map<String, dynamic>
        ? ContextSummary.fromJson(
            json['compactSummary'] as Map<String, dynamic>,
          )
        : null,
  );

  static DateTime _dateFrom(Object? raw) => raw is String
      ? (DateTime.tryParse(raw) ?? DateTime.now())
      : DateTime.now();

  /// A compact view for the session list.
  SessionSummary toSummary() => SessionSummary(
    id: id,
    name: name,
    model: model,
    updatedAt: updatedAt,
    messageCount: messages
        .where((m) => m.role == Role.user || m.role == Role.assistant)
        .length,
  );
}

/// Lightweight session info for list rendering.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.name,
    required this.model,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String? name;
  final String model;
  final DateTime updatedAt;
  final int messageCount;
}

/// Generates a new session id: a sortable timestamp plus a random suffix.
String newSessionId() {
  final ts = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-')
      .replaceAll('Z', '');
  final rand = (DateTime.now().microsecondsSinceEpoch % 0xffffff).toRadixString(
    36,
  );
  return '$ts-$rand';
}

/// Reads/writes session JSON files under `<appDocuments>/sessions`.
class SessionStore {
  SessionStore({Directory? root}) : _root = root;

  final Directory? _root;
  Directory? _sessionsDir;

  Future<Directory> get sessionsDir async {
    if (_sessionsDir != null) return _sessionsDir!;
    final base = _root ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}sessions');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _sessionsDir = dir;
    return dir;
  }

  File _fileFor(String id) =>
      File('${_sessionsDir!.path}${Platform.pathSeparator}$id.json');

  Future<void> save(Session session) async {
    await sessionsDir;
    session.updatedAt = DateTime.now();
    final file = _fileFor(session.id);
    // Write atomically so a crash mid-write cannot corrupt the session.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<Session?> load(String id) async {
    await sessionsDir;
    final file = _fileFor(id);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return Session.fromJson(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Lists sessions (metadata only) sorted by most recently updated.
  Future<List<SessionSummary>> list() async {
    await sessionsDir;
    final entries = _sessionsDir!.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    );
    final out = <SessionSummary>[];
    for (final file in entries) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          out.add(Session.fromJson(decoded).toSummary());
        }
      } catch (_) {
        // Skip unreadable/corrupt files rather than failing the whole list.
      }
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> delete(String id) async {
    await sessionsDir;
    final file = _fileFor(id);
    if (await file.exists()) await file.delete();
  }

  /// Creates a fresh (unsaved) session with a generated id. It is written to
  /// disk lazily — on the first message — so an empty "New chat" leaves no file.
  Session createSession({String model = '', String? name}) {
    final now = DateTime.now();
    return Session(
      id: newSessionId(),
      name: name,
      model: model,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Per-session sandbox root for the file tools: `<appDocuments>/work/<id>`.
  /// Created on demand so tools always have a directory to write into.
  Future<String> workDirFor(String id) async {
    final base = _root ?? await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}work${Platform.pathSeparator}$id',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }
}
