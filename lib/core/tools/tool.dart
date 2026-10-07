/// Tool contract shared by every optional app tool.
///
/// Ported from siberflow's `packages/core/src/tools/base.ts`, adapted to Dart:
/// a tool is a name, a description, a JSON-schema parameter spec and an
/// `execute` that always returns a String for the model.
library;

import 'dart:convert';

import '../ai/types.dart';

/// Request payload for [ToolContext.askUser] (the `ask_user` tool).
class AskUserRequest {
  const AskUserRequest({
    required this.question,
    this.choices = const [],
    this.allowFreeText = false,
    this.defaultChoice,
  });

  final String question;
  final List<String> choices;
  final bool allowFreeText;
  final String? defaultChoice;
}

/// Response from the UI to an `ask_user` prompt.
class AskUserResponse {
  const AskUserResponse.answered(this.answer) : cancelled = false;
  const AskUserResponse.cancelled() : answer = '', cancelled = true;

  final String answer;
  final bool cancelled;
}

/// Everything a tool may need beyond its own arguments.
///
/// Mirrors siberflow's `ToolContext`, but scoped to what an Android app can
/// offer: a per-session working directory (app documents dir + session id),
/// an `askUser` bridge to the UI, and a place to report progress.
class ToolContext {
  ToolContext({
    required this.workDir,
    this.askUser,
    this.requestApproval,
    this.onProgress,
    this.webBaseUrl = '',
    this.webApiKey,
  });

  /// Sandbox root for this session — all file tools must resolve inside it.
  final String workDir;

  /// Blocks on a UI prompt. Null when no interactive UI is available; tools
  /// that depend on it must fall back gracefully.
  final Future<AskUserResponse> Function(AskUserRequest request)? askUser;

  /// Approval gate for tools flagged [Tool.requiresApproval]. The host shows a
  /// confirm dialog naming the tool and its arguments; returns true to proceed.
  /// Null means "auto-approve" (e.g. settings turned approval off), so the
  /// wrapper runs the tool directly.
  final Future<bool> Function(String toolName, Map<String, dynamic> args)?
  requestApproval;

  /// Optional progress reporting surfaced in the chat UI.
  final void Function(String message)? onProgress;

  /// Configurable Exa-compatible endpoint used by the built-in web search
  /// tool. The tool appends `/search` or `/contents` itself.
  final String webBaseUrl;

  /// API key for the Exa-compatible endpoint. Kept in secure storage by the
  /// Flutter host and passed only to the tool at execution time.
  final String? webApiKey;
}

/// A single callable tool exposed to the model.
abstract class Tool {
  /// Tool name as the model sees it (must match `^[a-z0-9_]+$`).
  String get name;

  /// One-paragraph description of what the tool does and when to use it.
  String get description;

  /// JSON-schema object describing the arguments.
  Map<String, dynamic> get parameters;

  /// Human-readable category, used by the tools screen in the UI.
  String get category => 'General';

  /// Whether invoking this tool needs explicit user approval first.
  bool get requiresApproval => false;

  /// Whether this is a built-in capability that must remain registered.
  ///
  /// Core tools are shown as locked in the tools screen and ignore entries in
  /// `AppSettings.disabledTools`. Most tools should keep the default `false`.
  bool get isCoreTool => false;

  Future<String> execute(Map<String, dynamic> args, ToolContext ctx);

  ToolSchema get schema =>
      ToolSchema(name: name, description: description, parameters: parameters);
}

/// Parses streamed tool arguments into a map, tolerating an empty payload and
/// returning a model-readable error string instead of throwing.
///
/// Returns `null` plus an error message when the JSON is unusable; otherwise
/// returns the decoded map (an empty map for empty arguments).
Map<String, dynamic>? parseToolArgs(
  String rawArgs, {
  String? Function(Object error)? onError,
}) {
  final text = rawArgs.trim();
  if (text.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    onError?.call('arguments must be a JSON object');
    return null;
  } catch (err) {
    onError?.call(err);
    return null;
  }
}

/// Reads a required String argument, throwing [ArgumentError] with a clear
/// message so the registry can hand it back to the model.
String requireString(Map<String, dynamic> args, String key) {
  final value = args[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw ArgumentError('`$key` is required and must be a non-empty string');
}

String? optionalString(Map<String, dynamic> args, String key) {
  final value = args[key];
  return value is String && value.isNotEmpty ? value : null;
}

int optionalInt(Map<String, dynamic> args, String key, int fallback) {
  final value = args[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double optionalDouble(Map<String, dynamic> args, String key, double fallback) {
  final value = args[key];
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

bool optionalBool(Map<String, dynamic> args, String key, bool fallback) {
  final value = args[key];
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

/// Truncates a tool result so a single call cannot blow up the context window.
String truncateResult(String text, {int maxChars = 20000}) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}\n…[truncated ${text.length - maxChars} chars]';
}

/// Formats a caught error into the string the model receives.
String toolError(Object error) => 'Error: $error';
