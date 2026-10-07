/// Wire-format types shared by the provider and the agent loop.
///
/// Ported from siberflow's `packages/core/src/agent/types.ts`, reduced to the
/// single OpenAI-compatible provider that sibermobile supports.
library;

/// Chat message roles understood by an OpenAI-compatible `/chat/completions`
/// endpoint.
enum Role { system, user, assistant, tool }

/// One function/tool call requested by the model. [arguments] is kept as the
/// raw JSON string exactly as streamed by the provider.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    final fn = (json['function'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ToolCall(
      id: json['id']?.toString() ?? '',
      name: fn['name']?.toString() ?? '',
      arguments: fn['arguments']?.toString() ?? '',
    );
  }
}

/// A user-uploaded file copied into the current session's working directory.
///
/// [relativePath] is intentionally relative to that sandbox, so it can be
/// passed straight to the file tools without exposing or trusting an external
/// storage path.
class AttachedFile {
  const AttachedFile({
    required this.name,
    required this.relativePath,
    required this.bytes,
  });

  final String name;
  final String relativePath;
  final int bytes;

  Map<String, dynamic> toStorageJson() => {
    'name': name,
    'relativePath': relativePath,
    'bytes': bytes,
  };

  factory AttachedFile.fromStorageJson(Map<String, dynamic> json) =>
      AttachedFile(
        name: json['name']?.toString() ?? 'file',
        relativePath: json['relativePath']?.toString() ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );
}

/// A single conversation message. `assistant` messages may carry tool calls
/// with empty [content]; `tool` messages carry the result for one call.
class Message {
  const Message({
    required this.role,
    this.content = '',
    this.displayContent,
    this.attachments = const [],
    this.toolCalls,
    this.toolCallId,
    this.name,
  });

  factory Message.system(String content) =>
      Message(role: Role.system, content: content);
  factory Message.user(
    String content, {
    String? displayContent,
    List<AttachedFile> attachments = const [],
  }) => Message(
    role: Role.user,
    content: content,
    displayContent: displayContent,
    attachments: attachments,
  );
  factory Message.assistant(String content, {List<ToolCall>? toolCalls}) =>
      Message(role: Role.assistant, content: content, toolCalls: toolCalls);
  factory Message.toolResult({
    required String toolCallId,
    required String name,
    required String content,
  }) => Message(
    role: Role.tool,
    content: content,
    toolCallId: toolCallId,
    name: name,
  );

  final Role role;
  final String content;

  /// The concise text shown in the chat UI. For uploaded files the model sees
  /// [content] with its sandbox location, while users only see their message.
  final String? displayContent;

  /// File metadata persisted with a user message. It is never sent directly
  /// to the provider; the model-facing [content] carries the safe path.
  final List<AttachedFile> attachments;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final String? name;

  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;

  /// Serializes to the OpenAI chat-completions message shape.
  ///
  /// Assistant content is never emitted as null/empty when there are no tool
  /// calls: strict OpenAI-compatible servers reject that with a 400, so an
  /// empty reply falls back to a single space.
  Map<String, dynamic> toApiJson() {
    switch (role) {
      case Role.system:
      case Role.user:
        return {'role': role.name, 'content': content};
      case Role.assistant:
        final json = <String, dynamic>{
          'role': 'assistant',
          'content': hasToolCalls ? content : (content.isEmpty ? ' ' : content),
        };
        if (hasToolCalls) {
          json['tool_calls'] = toolCalls!.map((t) => t.toJson()).toList();
        }
        return json;
      case Role.tool:
        return {
          'role': 'tool',
          'content': content,
          'tool_call_id': toolCallId ?? '',
          if (name != null) 'name': name,
        };
    }
  }

  /// Session-file serialization (keeps toolCalls as JSON so history can be
  /// replayed into a fresh agent after an app restart).
  Map<String, dynamic> toStorageJson() => {
    'role': role.name,
    'content': content,
    if (displayContent != null) 'displayContent': displayContent,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((file) => file.toStorageJson()).toList(),
    if (hasToolCalls) 'toolCalls': toolCalls!.map((t) => t.toJson()).toList(),
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (name != null) 'name': name,
  };

  factory Message.fromStorageJson(Map<String, dynamic> json) {
    final role = Role.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => Role.user,
    );
    final rawCalls = json['toolCalls'];
    return Message(
      role: role,
      content: json['content']?.toString() ?? '',
      displayContent: json['displayContent']?.toString(),
      attachments:
          (json['attachments'] as List?)
              ?.whereType<Map>()
              .map(
                (file) =>
                    AttachedFile.fromStorageJson(file.cast<String, dynamic>()),
              )
              .toList() ??
          const [],
      toolCallId: json['toolCallId']?.toString(),
      name: json['name']?.toString(),
      toolCalls: rawCalls is List
          ? rawCalls
                .whereType<Map>()
                .map((m) => ToolCall.fromJson(m.cast<String, dynamic>()))
                .toList()
          : null,
    );
  }
}

/// JSON-schema description of one tool, sent in the request's `tools` field.
class ToolSchema {
  const ToolSchema({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toApiJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

class ChatRequest {
  const ChatRequest({
    required this.model,
    required this.messages,
    this.tools = const [],
    this.temperature,
    this.maxTokens,
    this.cancel,
  });

  final String model;
  final List<Message> messages;
  final List<ToolSchema> tools;
  final double? temperature;
  final int? maxTokens;
  final CancellationToken? cancel;
}

enum FinishReason { stop, toolCalls, length, other }

class UsageStats {
  const UsageStats({
    required this.promptTokens,
    required this.completionTokens,
    this.reasoningTokens,
    this.textTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int? reasoningTokens;
  final int? textTokens;

  UsageStats operator +(UsageStats? other) {
    if (other == null) return this;
    return UsageStats(
      promptTokens: promptTokens + other.promptTokens,
      completionTokens: completionTokens + other.completionTokens,
    );
  }

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    if (reasoningTokens != null) 'reasoningTokens': reasoningTokens,
    if (textTokens != null) 'textTokens': textTokens,
  };

  factory UsageStats.fromJson(Map<String, dynamic> json) => UsageStats(
    promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
    completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
    reasoningTokens: (json['reasoningTokens'] as num?)?.toInt(),
    textTokens: (json['textTokens'] as num?)?.toInt(),
  );

  static const UsageStats zero = UsageStats(
    promptTokens: 0,
    completionTokens: 0,
  );
}

/// Incremental output of one streaming provider call.
sealed class StreamEvent {}

/// A chunk of assistant text.
class ContentDelta extends StreamEvent {
  ContentDelta(this.delta);
  final String delta;
}

/// The model opened tool call #[index]; arguments stream afterwards.
class ToolCallStart extends StreamEvent {
  ToolCallStart({required this.index, required this.id, required this.name});
  final int index;
  final String id;
  final String name;
}

/// A fragment of a tool call's JSON arguments.
class ToolCallArgs extends StreamEvent {
  ToolCallArgs({required this.index, required this.delta});
  final int index;
  final String delta;
}

/// The stream finished; [message] is the complete assistant message.
class StreamDone extends StreamEvent {
  StreamDone({required this.message, required this.finishReason, this.usage});
  final Message message;
  final FinishReason finishReason;
  final UsageStats? usage;
}

/// Cooperative cancellation for a provider stream / agent turn.
///
/// `http` requests have no AbortSignal equivalent, so the provider closes its
/// response stream when [cancel] fires, and the agent checks [isCancelled]
/// between iterations and tool calls.
class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {
        // A listener throwing must not prevent the others from running.
      }
    }
    _listeners.clear();
  }

  /// Register a callback invoked on cancellation. Fires immediately when the
  /// token is already cancelled.
  void onCancel(void Function() cb) {
    if (_cancelled) {
      cb();
      return;
    }
    _listeners.add(cb);
  }
}

class AgentCancelledException implements Exception {
  const AgentCancelledException();
  @override
  String toString() => 'AgentCancelledException: the turn was cancelled';
}

FinishReason finishReasonFromString(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'stop':
    case 'end_turn':
    case 'complete':
      return FinishReason.stop;
    case 'tool_calls':
    case 'function_call':
    case 'tool_use':
      return FinishReason.toolCalls;
    case 'length':
    case 'max_tokens':
    case 'model_length':
      return FinishReason.length;
    default:
      return FinishReason.other;
  }
}
