/// OpenAI-compatible chat provider with SSE streaming.
///
/// Ported from siberflow's `packages/core/src/providers/openai-compatible.ts`.
/// Only the `custom` flavour is kept: the user supplies base URL, API key and
/// model name, and we speak `/chat/completions` with `stream: true`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider.dart';
import 'sse.dart';
import 'types.dart';
import '../user_agent.dart';

/// Endpoint path appended to [OpenAiCompatibleProvider.baseUrl]. Kept separate
/// so users can paste either `https://host/v1` or `https://host/v1/`.
const String chatCompletionsPath = '/chat/completions';

/// Model metadata endpoint (`GET /models`) used by the settings screen to let
/// the user pick a model instead of typing it.
const String modelsPath = '/models';

/// After a terminal choice, some gateways send a final `choices: []` frame
/// containing usage while others keep the socket open forever. Wait briefly
/// for the former without making tool calls or the UI wait on the latter.
const Duration _trailingUsageTimeout = Duration(milliseconds: 750);

class ProviderRequestException implements Exception {
  ProviderRequestException(this.statusCode, this.body, {this.requestBody});

  final int statusCode;
  final String body;
  final String? requestBody;

  @override
  String toString() =>
      'Provider API error $statusCode: ${body.length > 800 ? '${body.substring(0, 800)}…' : body}';
}

/// Streams chat completions from any gateway that speaks the OpenAI wire format.
class OpenAiCompatibleProvider implements ChatProvider {
  OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.includeUsageInStream = true,
    this.extraHeaders = const {},
    this.extraBody = const {},
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Base URL without the endpoint path, e.g. `https://api.example.com/v1`.
  final String baseUrl;
  final String apiKey;
  @override
  final String model;

  /// Some upstreams reject `stream_options`; set false to omit it (you lose
  /// token usage stats from the stream).
  final bool includeUsageInStream;
  final Map<String, String> extraHeaders;

  /// Extra top-level request fields (e.g. `reasoning_effort`).
  final Map<String, dynamic> extraBody;

  final http.Client _client;

  Uri _endpoint(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream, application/json',
    'User-Agent': kDefaultUserAgent,
    if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
    ...extraHeaders,
  };

  /// Fetches the model list so the user can pick a valid `model` string.
  /// Returns an empty list when the gateway does not expose `/models`.
  Future<List<String>> listModels({Duration? timeout}) async {
    final res = await _client
        .get(_endpoint(modelsPath), headers: _headers)
        .timeout(timeout ?? const Duration(seconds: 30));
    if (res.statusCode != 200) return const [];
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((m) => m['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Simple round-trip used by "test connection" in settings.
  Future<String> ping({String prompt = 'ping'}) async {
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'stream': false,
      'max_tokens': 8,
      ...extraBody,
    });
    final res = await _client
        .post(_endpoint(chatCompletionsPath), headers: _headers, body: body)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ProviderRequestException(
        res.statusCode,
        utf8.decode(res.bodyBytes),
        requestBody: body,
      );
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final choices = decoded is Map ? decoded['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first as Map?;
      final message = first?['message'] as Map?;
      final content = message?['content'];
      if (content is String) return content;
    }
    return 'OK';
  }

  /// Streams one chat completion. Tool calls arrive as indexed deltas and are
  /// accumulated per index until their arguments are complete.
  ///
  /// Each call uses its own [http.Client] so cancellation can simply close it:
  /// that tears down the socket and ends the stream loop (the `http` package
  /// has no AbortSignal equivalent). Pass [httpClient] to inject a test client.
  @override
  Stream<StreamEvent> chatStream(
    ChatRequest req, {
    http.Client? httpClient,
  }) async* {
    final body = <String, dynamic>{
      'model': req.model.isEmpty ? model : req.model,
      'messages': req.messages.map((m) => m.toApiJson()).toList(),
      'stream': true,
      if (includeUsageInStream) 'stream_options': {'include_usage': true},
      if (req.tools.isNotEmpty) ...{
        'tools': req.tools.map((t) => t.toApiJson()).toList(),
        'tool_choice': 'auto',
      },
      if (req.temperature != null) 'temperature': req.temperature,
      if (req.maxTokens != null) 'max_tokens': req.maxTokens,
      ...extraBody,
    };
    final requestBody = jsonEncode(body);

    final request = http.Request('POST', _endpoint(chatCompletionsPath))
      ..headers.addAll(_headers)
      ..body = requestBody;

    // Per-call client: closing it is how cancellation aborts the in-flight
    // request, since `http` exposes no AbortSignal. An injected client (tests)
    // is left open for the caller to manage.
    final callClient = httpClient ?? http.Client();
    final ownsClient = httpClient == null;

    http.StreamedResponse streamed;
    try {
      streamed = await callClient.send(request);
    } catch (_) {
      if (ownsClient) callClient.close();
      rethrow;
    }
    if (streamed.statusCode != 200) {
      final text = await streamed.stream.bytesToString();
      if (ownsClient) callClient.close();
      throw ProviderRequestException(
        streamed.statusCode,
        text,
        requestBody: requestBody,
      );
    }

    req.cancel?.onCancel(() {
      // A StreamedResponse body is a single-subscription stream. Listening to
      // it again with drain() would throw "Stream has already been listened
      // to" while parseSse() owns the active subscription. Closing the
      // per-call client tears down the socket without adding a second listener.
      if (ownsClient) callClient.close();
    });

    var content = '';
    final toolCallsByIndex = <int, _PendingToolCall>{};
    final startedIndices = <int>{};
    var finishReason = FinishReason.other;
    UsageStats? usage;
    var terminalSeen = false;

    final events = parseSse(
      streamed.stream,
      idleTimeout: const Duration(seconds: 90),
      initialTimeout: const Duration(seconds: 120),
      idleTimeoutForNextData: () =>
          terminalSeen ? _trailingUsageTimeout : const Duration(seconds: 90),
    );

    try {
      await for (final data in events) {
        if (req.cancel?.isCancelled ?? false) break;

        final receivedUsage = _usageFrom(data['usage']);
        if (receivedUsage != null) usage = receivedUsage;

        // Qwen-style gateways place usage in the frame after a terminal
        // choice. Capture it before finishing, even when choices is empty.
        if (terminalSeen) break;

        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map) continue;
        final delta = choice['delta'] is Map
            ? choice['delta'] as Map
            : const {};

        final deltaContent = delta['content'];
        if (deltaContent is String && deltaContent.isNotEmpty) {
          content += deltaContent;
          yield ContentDelta(deltaContent);
        }

        final rawCalls = delta['tool_calls'];
        if (rawCalls is List) {
          for (final item in rawCalls) {
            if (item is! Map) continue;
            final index = (item['index'] as num?)?.toInt() ?? 0;
            final pending = toolCallsByIndex.putIfAbsent(
              index,
              _PendingToolCall.new,
            );
            if (item['id'] is String && (item['id'] as String).isNotEmpty) {
              pending.id = item['id'] as String;
            }
            final fn = item['function'] is Map ? item['function'] as Map : null;
            String? argumentsChunk;
            if (fn != null) {
              if (fn['name'] is String && (fn['name'] as String).isNotEmpty) {
                pending.name = fn['name'] as String;
              }
              if (fn['arguments'] is String) {
                argumentsChunk = fn['arguments'] as String;
                pending.arguments.write(argumentsChunk);
              }
            }
            if (!startedIndices.contains(index) &&
                pending.id.isNotEmpty &&
                pending.name.isNotEmpty) {
              startedIndices.add(index);
              yield ToolCallStart(
                index: index,
                id: pending.id,
                name: pending.name,
              );
            }
            // Start must reach the UI before its first argument fragment;
            // otherwise the UI has no tool block to attach the fragment to.
            if (argumentsChunk != null) {
              yield ToolCallArgs(index: index, delta: argumentsChunk);
            }
          }
        }

        final rawFinish = choice['finish_reason'];
        if (rawFinish is String && rawFinish.isNotEmpty) {
          finishReason = finishReasonFromString(rawFinish);
          terminalSeen = true;
          // DeepSeek-style gateways attach usage to this terminal choice.
          // If usage was disabled or is already present, finish immediately;
          // otherwise allow one short trailing-usage window for Qwen-style
          // streams before the parser times out harmlessly below.
          if (!includeUsageInStream || usage != null) break;
        }
      }
    } on TimeoutException {
      // A few OpenAI-compatible servers never send [DONE] or close their SSE
      // socket. Once a finish_reason was seen, the short trailing usage wait
      // is complete and the answer/tool call is safe to finalize.
      if (!terminalSeen) rethrow;
    } finally {
      // Cancelling the async iteration propagates to parseSse(), which cancels
      // its one subscription. Only the client remains to be released here.
      if (ownsClient) callClient.close();
    }

    if (req.cancel?.isCancelled ?? false) {
      throw const AgentCancelledException();
    }

    final indices = toolCallsByIndex.keys.toList()..sort();
    final toolCalls = indices
        .map(
          (i) => ToolCall(
            id: toolCallsByIndex[i]!.id,
            name: toolCallsByIndex[i]!.name,
            arguments: toolCallsByIndex[i]!.arguments.toString(),
          ),
        )
        .toList();

    yield StreamDone(
      message: Message(
        role: Role.assistant,
        content: content,
        toolCalls: toolCalls.isEmpty ? null : toolCalls,
      ),
      finishReason: finishReason,
      usage: usage,
    );
  }

  @override
  void close() => _client.close();
}

/// Normalizes the two usage schemas encountered in OpenAI ecosystems:
/// `/chat/completions` uses `prompt_tokens` / `completion_tokens`, whereas
/// `/responses`-style gateways use `input_tokens` / `output_tokens` even when
/// proxied through a chat-compatible endpoint.
UsageStats? _usageFrom(Object? raw) {
  if (raw is! Map) return null;

  int? readAny(List<String> names) {
    for (final name in names) {
      final value = raw[name];
      if (value is num) return value.toInt();
    }
    return null;
  }

  final prompt = readAny([
    'prompt_tokens',
    'input_tokens',
    'promptTokens',
    'inputTokens',
    'prompt_token_count',
  ]);
  final completion = readAny([
    'completion_tokens',
    'output_tokens',
    'completionTokens',
    'outputTokens',
    'candidates_token_count',
  ]);
  if (prompt == null && completion == null) return null;

  final details =
      raw['completion_tokens_details'] ??
      raw['output_tokens_details'] ??
      raw['completionTokensDetails'];
  int? detail(String snake, String camel) {
    if (details is! Map) return null;
    final value = details[snake] ?? details[camel];
    return value is num ? value.toInt() : null;
  }

  return UsageStats(
    promptTokens: prompt ?? 0,
    completionTokens: completion ?? 0,
    reasoningTokens: detail('reasoning_tokens', 'reasoningTokens'),
    textTokens: detail('text_tokens', 'textTokens'),
  );
}

/// Accumulator for one streamed tool call (mirrors the TS `Map<index, ToolCall>`).
class _PendingToolCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
