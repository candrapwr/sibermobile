/// The agent loop: drives one user turn through repeated provider calls and
/// tool executions until the model produces a final answer.
///
/// Ported from siberflow's `packages/core/src/agent/agent.ts`, keeping the parts
/// that matter on mobile: streaming deltas, tool-call rounds, auto-continue on
/// `length`, empty-final retry, cancellation between steps, and rolling
/// AI-generated context compaction.
library;

import 'dart:async';

import '../ai/provider.dart';
import '../ai/types.dart';
import 'context_compaction.dart';
import '../tools/registry.dart';
import '../tools/tool.dart';

/// Nudge appended when a text response was cut off by the output token limit.
const String continueNudge =
    'Your previous message was cut off by the output length limit. Continue '
    'from exactly where you stopped — do not repeat anything you already wrote, '
    'and do not add a preamble.';

/// Nudge used for the single retry when the model returned no visible content.
const String emptyFinalRetryNudge =
    'The previous assistant response contained no user-visible content. Produce '
    'the answer again now, in normal assistant content. If a tool call is still '
    'required, call the tool; otherwise answer the user directly.';

/// How many times a `length`-truncated text reply is auto-continued.
const int maxAutoContinues = 4;

/// Fallback text when recovery also yields nothing visible.
const String emptyFinalFallback =
    'Maaf, model selesai tanpa mengirim jawaban yang bisa ditampilkan. '
    'Coba ulangi permintaannya.';

/// Streamed callbacks the UI subscribes to during one turn.
class AgentEvents {
  const AgentEvents({
    this.onAssistantStart,
    this.onContent,
    this.onAssistantEnd,
    this.onToolCallStart,
    this.onToolCallArgs,
    this.onToolResult,
    this.onHistoryChanged,
    this.onUsage,
    this.onContextCompacting,
    this.onContextCompacted,
    this.onContextCompactionFinished,
    this.onMaxIterations,
    this.cancel,
  });

  /// Fires before each provider call in the loop.
  final void Function()? onAssistantStart;

  /// A chunk of assistant text (already accumulated in history).
  final void Function(String delta)? onContent;

  /// One provider call finished; [message] is the complete assistant message.
  final void Function(Message message, FinishReason reason, UsageStats? usage)?
  onAssistantEnd;

  /// The model opened tool call #[index].
  final void Function(int index, String id, String name)? onToolCallStart;

  /// A fragment of a tool call's streamed JSON arguments.
  final void Function(int index, String delta)? onToolCallArgs;

  /// One tool finished; [result] is what the model will see.
  final void Function(int index, String name, String result)? onToolResult;

  /// History changed (persist so a crash cannot lose the turn).
  final void Function()? onHistoryChanged;

  /// Token accounting after each provider call.
  final void Function(UsageStats? last, UsageStats total)? onUsage;

  /// The compact mode started an extra AI call to summarize old turns.
  final void Function()? onContextCompacting;

  /// Compact mode stored an updated summary of older history.
  final void Function(CompactionStats stats)? onContextCompacted;

  /// The compact request ended, including when it failed harmlessly.
  final void Function()? onContextCompactionFinished;

  /// The loop hit [Agent.maxIterations] without a final answer.
  final void Function(int limit)? onMaxIterations;

  /// Cooperative cancellation; checked between every step.
  final CancellationToken? cancel;
}

/// Holds conversation state and runs turns against a provider + tool registry.
class Agent {
  Agent({
    required this.provider,
    required this.registry,
    required this.context,
    this.model = '',
    this.maxTokens,
    this.temperature,
    this.maxIterations = 25,
    this.autoContinue = true,
    this.maxHistoryMessages = 200,
    this.systemPrompt = '',
    this.compactContext = true,
    int contextWindow = 200000,
    double compactThreshold = 0.8,
    int compactKeepRecent = 2,
    UsageStats initialTotalUsage = UsageStats.zero,
    UsageStats? initialLastUsage,
    int? lastPromptTokens,
  }) : contextWindow = contextWindow < 1000 ? 1000 : contextWindow,
       compactThreshold = compactThreshold.clamp(0.1, 1.0).toDouble(),
       compactKeepRecent = compactKeepRecent < 0 ? 0 : compactKeepRecent,
       _totalUsage = initialTotalUsage,
       _lastUsage = initialLastUsage,
       _lastPromptTokens =
           lastPromptTokens ?? initialLastUsage?.promptTokens ?? 0;

  final ChatProvider provider;
  final ToolRegistry registry;
  final ToolContext context;

  /// Model override per agent; falls back to the provider's configured model.
  final String model;
  final int? maxTokens;
  final double? temperature;
  final int maxIterations;
  final bool autoContinue;

  /// When true, fold older completed turns into an AI-written summary once
  /// [compactThreshold] of [contextWindow] has been used.
  final bool compactContext;
  final int contextWindow;
  final double compactThreshold;
  final int compactKeepRecent;

  /// Legacy trim window used only when compact context is disabled.
  final int maxHistoryMessages;

  String systemPrompt;

  final List<Message> _messages = [];
  UsageStats _totalUsage;
  UsageStats? _lastUsage;
  int _lastPromptTokens;
  ContextSummary? _compactSummary;

  /// Full history including the system prompt (index 0 when set).
  List<Message> get messages => List.unmodifiable(_messages);

  /// History without the system prompt — what the session store persists.
  List<Message> get history =>
      List.unmodifiable(_messages.where((m) => m.role != Role.system));

  UsageStats get totalUsage => _totalUsage;
  UsageStats? get lastUsage => _lastUsage;
  int get lastPromptTokens => _lastPromptTokens;
  ContextSummary? get compactSummary => _compactSummary;

  /// Replaces history (session load). The system prompt is re-applied first.
  void loadHistory(
    List<Message> messages, {
    String? prompt,
    ContextSummary? compactSummary,
  }) {
    if (prompt != null) systemPrompt = prompt;
    _messages
      ..clear()
      ..addAll(_withSystemPrompt(messages));
    _compactSummary = compactContext ? compactSummary : null;
  }

  /// Drops history but keeps the system prompt.
  void reset() {
    final system = _messages.isNotEmpty && _messages.first.role == Role.system
        ? _messages.first
        : null;
    _messages.clear();
    if (system != null) _messages.add(system);
    _totalUsage = UsageStats.zero;
    _lastUsage = null;
    _lastPromptTokens = 0;
    _compactSummary = null;
  }

  /// Rewinds to (and excluding) the last user message so `send` can replay it.
  /// Returns the rewound prompt, or null when history has no user message.
  ///
  /// Used by "regenerate" and "edit last": dropping everything after the last
  /// user turn also removes dangling tool calls, which would otherwise make the
  /// next request invalid.
  String? rewindToLastUserMessage() {
    var lastUserIdx = -1;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == Role.user) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx == -1) return null;
    final text = _messages[lastUserIdx].content;
    final historyIndex = _messages
        .sublist(0, lastUserIdx)
        .where((message) => message.role != Role.system)
        .length;
    // Replaying a turn that is already inside the summary would otherwise
    // leave its old outcome in the provider-facing context.
    if (_compactSummary != null &&
        historyIndex <= _compactSummary!.upToHistoryIndex) {
      _compactSummary = null;
    }
    _messages.removeRange(lastUserIdx, _messages.length);
    return text;
  }

  List<Message> _withSystemPrompt(List<Message> rest) {
    final trimmed = systemPrompt.trim();
    final withoutSystem = rest.where((m) => m.role != Role.system).toList();
    if (trimmed.isEmpty) return withoutSystem;
    return [Message.system(trimmed), ...withoutSystem];
  }

  /// Enforces [maxHistoryMessages] by dropping the oldest non-system messages,
  /// never cutting between an assistant tool-call message and its tool results
  /// (an orphan tool result makes OpenAI-compatible servers reject the request).
  void _trimHistory() {
    // Compact mode preserves raw session history for recovery and replaces it
    // only in provider requests. Dropping raw messages would invalidate the
    // summary's persisted history index.
    if (compactContext) return;
    if (maxHistoryMessages <= 0) return;
    final systemCount = _messages.where((m) => m.role == Role.system).length;
    while (_messages.length - systemCount > maxHistoryMessages) {
      // Find the first removable index: skip system messages, and skip any
      // assistant message with tool calls unless all of its results follow.
      var cut = -1;
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.role == Role.system) continue;
        if (m.hasToolCalls) {
          // Keep the assistant message and its results together: cut at the
          // first following message that is not one of its tool results.
          var j = i + 1;
          final ids = m.toolCalls!.map((c) => c.id).toSet();
          while (j < _messages.length &&
              _messages[j].role == Role.tool &&
              ids.contains(_messages[j].toolCallId)) {
            j++;
          }
          cut = j - 1; // remove up to the last tool result of this call
          break;
        }
        cut = i;
        break;
      }
      if (cut == -1) break;
      // Remove the contiguous block [start..cut] where start is the first
      // non-system index at or before cut.
      var start = cut;
      while (start > 0 && _messages[start - 1].role != Role.system) {
        // Extend the block backwards over its own tool results so we never
        // leave an assistant tool-call message without its results.
        if (_messages[start - 1].hasToolCalls) break;
        start--;
      }
      _messages.removeRange(start, cut + 1);
      if (_messages.length - systemCount <= maxHistoryMessages) break;
    }
  }

  void _throwIfCancelled(CancellationToken? token) {
    if (token?.isCancelled ?? false) throw const AgentCancelledException();
  }

  /// Builds the provider-facing history. A summary replaces only the prefix it
  /// covers; raw history remains untouched for session persistence and can be
  /// rolled into the summary again later.
  List<Message> _requestMessages() {
    final summary = _compactSummary;
    if (!compactContext ||
        summary == null ||
        summary.text.trim().isEmpty ||
        summary.upToHistoryIndex < 0) {
      return List.of(_messages);
    }

    final system = _messages.where((message) => message.role == Role.system);
    final history = _messages
        .where((message) => message.role != Role.system)
        .toList();
    if (summary.upToHistoryIndex >= history.length) return List.of(_messages);

    return [
      ...system,
      Message.user('[Conversation summary so far]\n${summary.text}'),
      ...history.skip(summary.upToHistoryIndex + 1),
    ];
  }

  /// Runs a compact pass before the new user message is sent to the model.
  /// The current user message is explicitly excluded, so it is never folded
  /// into an AI-written summary before receiving an answer.
  Future<void> _maybeCompactBeforeTurn(AgentEvents events) async {
    if (!compactContext ||
        _lastPromptTokens <= 0 ||
        _lastPromptTokens / contextWindow < compactThreshold) {
      return;
    }

    final history = _messages
        .where((message) => message.role != Role.system)
        .toList();
    if (history.length < 2) return;

    var started = false;
    try {
      final result = await compactConversation(
        provider: provider,
        model: model.isEmpty ? provider.model : model,
        // The final message is the user input just added by [send].
        history: history.sublist(0, history.length - 1),
        keepRecent: compactKeepRecent,
        summary: _compactSummary,
        cancel: events.cancel,
        onStart: () {
          started = true;
          events.onContextCompacting?.call();
        },
      );
      if (result.usage != null) {
        _totalUsage += result.usage!;
        // Do not replace [_lastUsage]: the context bar needs the prompt size
        // of the real conversation request, not the small summary request.
        events.onUsage?.call(_lastUsage, _totalUsage);
      }
      if (result.compacted && result.summary != null) {
        _compactSummary = result.summary;
        events.onContextCompacted?.call(result.stats!);
        events.onHistoryChanged?.call();
      }
    } on AgentCancelledException {
      rethrow;
    } catch (_) {
      // Compaction is an optimization; an unavailable/unsupported summary
      // call must never block the user's actual chat request.
    } finally {
      if (started) events.onContextCompactionFinished?.call();
    }
  }

  /// Runs one provider call and folds its events into [events].
  Future<({Message assistant, FinishReason reason, UsageStats? usage})>
  _runStream(
    List<Message> requestMessages,
    List<ToolSchema> toolSchemas,
    AgentEvents events,
  ) async {
    events.onAssistantStart?.call();

    final request = ChatRequest(
      model: model.isEmpty ? provider.model : model,
      messages: requestMessages,
      tools: toolSchemas,
      temperature: temperature,
      maxTokens: maxTokens,
      cancel: events.cancel,
    );

    var content = '';
    Message? done;
    var reason = FinishReason.other;
    UsageStats? usage;

    await for (final event in provider.chatStream(request)) {
      _throwIfCancelled(events.cancel);
      switch (event) {
        case ContentDelta(:final delta):
          content += delta;
          events.onContent?.call(delta);
        case ToolCallStart(:final index, :final id, :final name):
          events.onToolCallStart?.call(index, id, name);
        case ToolCallArgs(:final index, :final delta):
          events.onToolCallArgs?.call(index, delta);
        case StreamDone(:final message, :final finishReason, usage: final u):
          done = message;
          reason = finishReason;
          usage = u;
      }
    }

    final assistant = done ?? Message.assistant(content);
    if (usage != null) {
      _totalUsage += usage;
      _lastUsage = usage;
      if (usage.promptTokens > 0) _lastPromptTokens = usage.promptTokens;
    }
    events.onUsage?.call(usage, _totalUsage);
    events.onAssistantEnd?.call(assistant, reason, usage);
    return (assistant: assistant, reason: reason, usage: usage);
  }

  /// Sends [userInput] as a new turn and returns the final assistant text.
  ///
  /// The full loop: append the user message, call the provider, execute any
  /// requested tools, feed the results back, repeat until the model answers
  /// without tool calls (or [maxIterations] is hit).
  Future<String> send(
    String userInput, [
    AgentEvents events = const AgentEvents(),
    List<AttachedFile> attachments = const [],
    String? displayContent,
  ]) async {
    final token = events.cancel;
    _throwIfCancelled(token);

    _messages.add(
      Message.user(
        userInput,
        displayContent: displayContent,
        attachments: attachments,
      ),
    );
    events.onHistoryChanged?.call();
    _trimHistory();

    await _maybeCompactBeforeTurn(events);

    final toolSchemas = registry.schemas();
    var finalText = '';

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      _throwIfCancelled(token);

      var streamed = await _runStream(_requestMessages(), toolSchemas, events);
      var assistant = streamed.assistant;
      var reason = streamed.reason;

      // Auto-continue a text reply cut off by the output token limit. The
      // continuation request is ephemeral — only the merged message is stored.
      var continues = 0;
      while (autoContinue &&
          reason == FinishReason.length &&
          !assistant.hasToolCalls &&
          continues < maxAutoContinues) {
        _throwIfCancelled(token);
        continues++;
        final contMessages = [
          ..._requestMessages(),
          Message.assistant(
            assistant.content.isEmpty ? ' ' : assistant.content,
          ),
          Message.user(continueNudge),
        ];
        final cont = await _runStream(contMessages, toolSchemas, events);
        assistant = Message.assistant(
          assistant.content + cont.assistant.content,
          toolCalls: cont.assistant.toolCalls,
        );
        reason = cont.reason;
      }

      // A tiny output limit can cut a tool call mid-arguments. Never persist a
      // partial call: it would have no matching tool result and orphan the
      // history. Report it as plain text instead.
      if (reason == FinishReason.length && assistant.hasToolCalls) {
        assistant = Message.assistant(
          assistant.content.trim().isEmpty
              ? 'Respons berhenti karena batas output tercapai sebelum tool call selesai.'
              : assistant.content,
        );
      }

      // The model produced nothing visible (reasoning-only output on some
      // gateways). Retry once with a short nudge before falling back.
      if (!assistant.hasToolCalls && assistant.content.trim().isEmpty) {
        final retryMessages = [
          ..._requestMessages(),
          Message.user(emptyFinalRetryNudge),
        ];
        try {
          final retry = await _runStream(retryMessages, toolSchemas, events);
          assistant = retry.assistant;
          reason = retry.reason;
        } catch (err) {
          if (err is AgentCancelledException) rethrow;
          // Recovery is best-effort; fall through to the fallback below.
        }
        if (!assistant.hasToolCalls && assistant.content.trim().isEmpty) {
          assistant = Message.assistant(emptyFinalFallback);
          events.onContent?.call(emptyFinalFallback);
          reason = FinishReason.stop;
        }
      }

      _throwIfCancelled(token);
      _messages.add(assistant);
      events.onHistoryChanged?.call();
      finalText = assistant.content;

      if (reason != FinishReason.toolCalls || !assistant.hasToolCalls) {
        _trimHistory();
        return finalText;
      }

      // Execute the tool batch sequentially: some device tools touch shared
      // state (camera or microphone), so parallel calls would race.
      for (var i = 0; i < assistant.toolCalls!.length; i++) {
        _throwIfCancelled(token);
        final call = assistant.toolCalls![i];
        final result = await registry.execute(
          call.name,
          call.arguments,
          context,
        );
        events.onToolResult?.call(i, call.name, result);
        _messages.add(
          Message.toolResult(
            toolCallId: call.id,
            name: call.name,
            content: result,
          ),
        );
        events.onHistoryChanged?.call();
      }
    }

    events.onMaxIterations?.call(maxIterations);
    return finalText.isEmpty
        ? 'Batas $maxIterations iterasi tool tercapai sebelum ada jawaban akhir.'
        : finalText;
  }
}
