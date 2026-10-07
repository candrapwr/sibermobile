/// Rolling, AI-generated conversation summaries for compact context mode.
///
/// The raw session history is never discarded. Instead, a summary records the
/// older history it covers; the agent substitutes that prefix only in requests
/// sent to the provider. This keeps recovery/history intact while bounding the
/// provider context window.
library;

import '../ai/provider.dart';
import '../ai/types.dart';

/// A persisted summary of the history through [upToHistoryIndex] (inclusive).
///
/// The index is relative to persisted history, which intentionally excludes
/// the agent's system prompt. It therefore stays stable when the prompt is
/// rebuilt after an app restart or a settings change.
class ContextSummary {
  const ContextSummary({
    required this.text,
    required this.upToHistoryIndex,
    required this.updatedAt,
  });

  final String text;
  final int upToHistoryIndex;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'text': text,
    'upToHistoryIndex': upToHistoryIndex,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ContextSummary.fromJson(Map<String, dynamic> json) => ContextSummary(
    text: json['text']?.toString() ?? '',
    upToHistoryIndex: (json['upToHistoryIndex'] as num?)?.toInt() ?? -1,
    updatedAt: json['updatedAt'] is String
        ? (DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now())
        : DateTime.now(),
  );
}

/// Information about one successful compaction pass.
class CompactionStats {
  const CompactionStats({
    required this.messagesSummarized,
    required this.summaryCharacters,
  });

  final int messagesSummarized;
  final int summaryCharacters;
}

/// Result returned from [compactConversation].
class CompactionResult {
  const CompactionResult({
    required this.summary,
    required this.compacted,
    this.stats,
    this.usage,
  });

  final ContextSummary? summary;
  final bool compacted;
  final CompactionStats? stats;

  /// Usage charged by the extra summarization request, when the gateway sends
  /// it. The agent adds it to the session total but keeps the main request's
  /// prompt size as the context-bar value.
  final UsageStats? usage;
}

/// Dense but provider-agnostic instruction for the summary call.
const String contextSummaryPrompt = '''
You are a context summarizer for an AI assistant. Create a dense,
fact-preserving summary of the conversation supplied by the user.

Keep: the user's goals and preferences, key facts and decisions, important
answers, important tool results, files or data referenced, and unresolved
questions. Do not invent facts. Drop greetings, repetition, and raw payloads
whose useful outcome is already clear. Write concise prose with no preamble,
in the language used by the conversation. Keep it under 500 words.''';

/// Creates or rolls forward an AI summary of older completed turns.
///
/// [history] has no system prompt. Its final entry is treated as eligible; the
/// caller excludes an in-progress user message when automatic compaction runs.
/// [keepRecent] counts complete user turns, not individual messages.
Future<CompactionResult> compactConversation({
  required ChatProvider provider,
  required String model,
  required List<Message> history,
  required int keepRecent,
  ContextSummary? summary,
  CancellationToken? cancel,
  void Function()? onStart,
}) async {
  final prior = summary;
  if (history.isEmpty) {
    return CompactionResult(summary: prior, compacted: false);
  }

  final previousEnd = prior?.upToHistoryIndex ?? -1;
  final candidate = _findSummaryEnd(
    history,
    keepRecent: keepRecent,
    previousEnd: previousEnd,
  );
  if (candidate <= previousEnd) {
    return CompactionResult(summary: prior, compacted: false);
  }

  final toSummarize = history.sublist(previousEnd + 1, candidate + 1);
  if (toSummarize.isEmpty) {
    return CompactionResult(summary: prior, compacted: false);
  }

  onStart?.call();
  final request = <Message>[
    Message.system(contextSummaryPrompt),
    if (prior != null && prior.text.trim().isNotEmpty)
      Message.user(
        'Previous summary. Update and extend it; preserve its key facts:\n'
        '${prior.text}',
      ),
    Message.user(
      'Conversation turns to summarize (roles: user, assistant, tool):\n\n'
      '${_serializeMessages(toSummarize)}',
    ),
  ];

  var content = '';
  UsageStats? usage;
  await for (final event in provider.chatStream(
    ChatRequest(
      model: model,
      messages: request,
      maxTokens: 1024,
      cancel: cancel,
    ),
  )) {
    if (cancel?.isCancelled ?? false) {
      throw const AgentCancelledException();
    }
    switch (event) {
      case ContentDelta(:final delta):
        content += delta;
      case StreamDone(:final message, usage: final eventUsage):
        if (content.isEmpty) content = message.content;
        usage = eventUsage;
      case ToolCallStart() || ToolCallArgs():
        // No tools are offered to the summarizer. Ignore malformed gateway
        // output rather than turning it into a persisted summary.
        break;
    }
  }

  final text = content.trim();
  if (text.isEmpty) {
    return CompactionResult(summary: prior, compacted: false, usage: usage);
  }

  final next = ContextSummary(
    text: text,
    upToHistoryIndex: candidate,
    updatedAt: DateTime.now(),
  );
  return CompactionResult(
    summary: next,
    compacted: true,
    usage: usage,
    stats: CompactionStats(
      messagesSummarized: toSummarize.length,
      summaryCharacters: text.length,
    ),
  );
}

/// Finds the last message safe to fold while keeping recent complete turns.
///
/// A turn starts at a user message. Returning the message immediately before a
/// retained turn guarantees the verbatim tail starts at a user boundary, never
/// at a tool result that would orphan an assistant tool call.
int _findSummaryEnd(
  List<Message> history, {
  required int keepRecent,
  required int previousEnd,
}) {
  if (keepRecent <= 0) return history.length - 1;

  var seenTurns = 0;
  for (var index = history.length - 1; index > previousEnd; index--) {
    if (history[index].role != Role.user) continue;
    seenTurns++;
    if (seenTurns == keepRecent) return index - 1;
  }
  return previousEnd;
}

String _serializeMessages(List<Message> messages) {
  const maxToolCharacters = 6000;
  final out = StringBuffer();
  for (final message in messages) {
    switch (message.role) {
      case Role.system:
        // Session history never contains the system prompt.
        break;
      case Role.user:
        out.writeln('[User]');
        out.writeln(message.content);
      case Role.assistant:
        out.writeln('[Assistant]');
        if (message.content.trim().isNotEmpty) out.writeln(message.content);
        for (final call in message.toolCalls ?? const <ToolCall>[]) {
          out.writeln('[Tool call: ${call.name}] ${call.arguments}');
        }
      case Role.tool:
        out.writeln('[Tool result: ${message.name ?? 'unknown'}]');
        out.writeln(_truncate(message.content, maxToolCharacters));
    }
    out.writeln();
  }
  return out.toString().trim();
}

String _truncate(String value, int cap) {
  if (value.length <= cap) return value;
  final head = (cap * 0.7).round();
  final tail = cap - head;
  return '${value.substring(0, head)}\n…[tool result truncated]…\n'
      '${value.substring(value.length - tail)}';
}
