// Core tests: the agent loop, tool registry and SSE parsing are pure Dart
// (no platform channels), so they can be tested without a device.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:sibermobile/app/file_uploads.dart';
import 'package:sibermobile/core/agent/agent.dart';
import 'package:sibermobile/core/agent/prompts.dart';
import 'package:sibermobile/core/ai/openai_compatible_provider.dart';
import 'package:sibermobile/core/ai/sse.dart';
import 'package:sibermobile/core/ai/provider.dart';
import 'package:sibermobile/core/ai/types.dart';
import 'package:sibermobile/core/settings/settings.dart';
import 'package:sibermobile/core/tools/registry.dart';
import 'package:sibermobile/core/tools/registry_builder.dart';
import 'package:sibermobile/core/tools/tool.dart';
import 'package:sibermobile/core/tools/web_tools.dart';

/// A scripted provider: each call replays the next list of stream events.
/// Implements the [ChatProvider] contract so the Agent accepts it, but never
/// touches the network.
class _FakeProvider implements ChatProvider {
  _FakeProvider(this.turns);

  final List<List<StreamEvent>> turns;
  int calls = 0;
  final List<ChatRequest> requests = [];

  @override
  String get model => 'fake-model';

  @override
  Stream<StreamEvent> chatStream(ChatRequest request) async* {
    requests.add(request);
    final events = turns[calls++ % turns.length];
    for (final e in events) {
      yield e;
    }
  }

  @override
  void close() {}
}

class _EchoTool extends Tool {
  _EchoTool(this.log);

  final List<String> log;

  @override
  String get name => 'echo';

  @override
  String get description => 'Echo the text back.';

  @override
  String get category => 'Test';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'text': {'type': 'string'},
    },
    'required': <String>['text'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final text = requireString(args, 'text');
    log.add(text);
    return 'echo: $text';
  }
}

class _DangerTool extends Tool {
  _DangerTool(this.log);

  final List<String> log;

  @override
  String get name => 'danger';

  @override
  String get description => 'A destructive tool requiring approval.';

  @override
  String get category => 'Test';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    log.add('ran');
    return 'ok';
  }
}

class _SingleSubscriptionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = [
      'data: {"choices":[{"delta":{"content":"Halo"},"finish_reason":null}]}\n\n',
      'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
      'data: [DONE]\n\n',
    ].join();
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(payload)]),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

class _PayloadClient extends http.BaseClient {
  _PayloadClient(this.payload);

  final String payload;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(payload)]),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

class _OpenEndedToolCallClient extends http.BaseClient {
  final StreamController<List<int>> _body = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    scheduleMicrotask(() {
      _body.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_device","function":{"name":"get_device_info","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}\n\n',
        ),
      );
    });
    return http.StreamedResponse(
      _body.stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }

  @override
  void close() {
    _body.close();
  }
}

class _ExaClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final List<String> requestBodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    requestBodies.add(await request.finalize().bytesToString());
    final content = request.url.path.endsWith('/contents');
    final payload = content
        ? {
            'results': [
              {
                'title': 'Example page',
                'url': 'https://example.com',
                'text': 'Readable page text.',
              },
            ],
          }
        : {
            'results': [
              {
                'title': 'Example result',
                'url': 'https://example.com',
                'highlights': ['A useful highlight'],
              },
            ],
          };
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(jsonEncode(payload))]),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('parseSse', () {
    test('decodes data frames and stops at [DONE]', () async {
      final payload = [
        'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":" there"}}]}\n\n',
        'data: [DONE]\n\n',
      ].join();
      final out = await parseSse(
        Stream<List<int>>.fromIterable([payload.codeUnits]),
      ).toList();
      expect(out, hasLength(2));
      expect(out.first['choices'], isNotNull);
    });

    test('ignores comment/keep-alive lines', () async {
      final payload = ': keepalive\n\ndata: {"a":1}\n\n';
      final out = await parseSse(
        Stream<List<int>>.fromIterable([payload.codeUnits]),
      ).toList();
      expect(out, hasLength(1));
      expect(out.single['a'], 1);
    });
  });

  group('OpenAiCompatibleProvider', () {
    test('consumes the HTTP response body exactly once', () async {
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://example.test/v1',
        apiKey: 'test-key',
        model: 'test-model',
        includeUsageInStream: false,
      );
      final events = await provider
          .chatStream(
            ChatRequest(model: 'test-model', messages: [Message.user('hai')]),
            httpClient: _SingleSubscriptionClient(),
          )
          .toList();

      expect(events.whereType<ContentDelta>().single.delta, 'Halo');
      expect(events.whereType<StreamDone>().single.message.content, 'Halo');
      provider.close();
    });

    test(
      'reads trailing input/output usage from Responses-style gateways',
      () async {
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://example.test/v1',
          apiKey: 'test-key',
          model: 'test-model',
        );
        final events = await provider
            .chatStream(
              ChatRequest(model: 'test-model', messages: [Message.user('hai')]),
              httpClient: _PayloadClient(
                [
                  'data: {"choices":[{"delta":{"content":"Halo"},"finish_reason":"stop"}]}\n\n',
                  'data: {"choices":[],"usage":{"input_tokens":21,"output_tokens":8}}\n\n',
                  'data: [DONE]\n\n',
                ].join(),
              ),
            )
            .toList();

        final usage = events.whereType<StreamDone>().single.usage;
        expect(usage?.promptTokens, 21);
        expect(usage?.completionTokens, 8);
        provider.close();
      },
    );

    test('starts a tool when gateway leaves the SSE connection open', () async {
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://example.test/v1',
        apiKey: 'test-key',
        model: 'test-model',
      );
      final client = _OpenEndedToolCallClient();
      final events = await provider
          .chatStream(
            ChatRequest(
              model: 'test-model',
              messages: [Message.user('device')],
            ),
            httpClient: client,
          )
          .toList()
          .timeout(const Duration(seconds: 2));

      final start = events.whereType<ToolCallStart>().single;
      final done = events.whereType<StreamDone>().single;
      expect(start.name, 'get_device_info');
      expect(done.finishReason, FinishReason.toolCalls);
      expect(done.message.toolCalls!.single.arguments, '{}');
      client.close();
      provider.close();
    });
  });

  group('ToolRegistry', () {
    test('exposes the supported core and optional tools', () {
      final names = allTools.map((tool) => tool.name).toSet();

      expect(names, hasLength(41));
      expect(
        names,
        containsAll([
          'get_current_time',
          'send_file_to_user',
          'web_search',
          'http_request',
          'analyze_image',
          'generate_image',
          'shell_exec',
          'get_device_info',
          'take_photo',
          'nfc_status',
          'nfc_analyze',
          'nfc_transceive',
          'nfc_write_ndef',
          'wifi_scan',
          'cell_scan',
          'net_probe',
        ]),
      );
      for (final retiredName in const [
        'read_accelerometer',
        'read_gyroscope',
        'read_magnetometer',
        'read_compass',
        'set_torch',
        'get_clipboard',
        'set_clipboard',
        'set_screen_brightness',
        'set_volume',
        'set_wakelock',
        'call_phone',
        'send_sms',
        'network_info',
        'vibrate',
        'open_app_settings',
      ]) {
        expect(names, isNot(contains(retiredName)));
      }
    });

    test('keeps core tools enabled when all optional tools are off', () async {
      final registry = buildRegistry(
        AppSettings(
          disabledTools: optionalTools.map((tool) => tool.name).toSet(),
        ),
      );

      expect(registry.names, [
        'get_current_time',
        'send_file_to_user',
        'ask_user',
      ]);
      expect(registry['get_current_time']!.isCoreTool, isTrue);
      expect(registry['send_file_to_user']!.isCoreTool, isTrue);
      expect(registry['ask_user']!.isCoreTool, isTrue);

      final output = await registry.execute(
        'get_current_time',
        '{}',
        ToolContext(workDir: '/tmp'),
      );
      final result = jsonDecode(output) as Map<String, dynamic>;
      expect(result['utcDateTime'], isNotEmpty);
      expect(result['utcOffset'], matches(RegExp(r'^[+-]\d{2}:\d{2}$')));
      expect(result['unixTimestampMs'], isA<int>());
    });

    test('keeps web search out of the registry until configured', () {
      expect(buildRegistry(AppSettings()).contains('web_search'), isFalse);
      expect(
        buildRegistry(
          AppSettings(disabledTools: const {}),
          webSearchAvailable: true,
        ).contains('web_search'),
        isTrue,
      );
    });

    test('siber gateway base URL switches web search to built-in mode', () {
      expect(
        AppSettings(baseUrl: 'https://api.idsiber.com/v1').usesSiberGateway,
        isTrue,
      );
      expect(
        AppSettings(baseUrl: 'https://API.Idsiber.Com/v1').usesSiberGateway,
        isTrue,
      );
      expect(
        AppSettings(baseUrl: 'https://api.openai.com/v1').usesSiberGateway,
        isFalse,
      );
      expect(AppSettings(baseUrl: '').usesSiberGateway, isFalse);
      // web_search must not sit in the default-disabled set: through the
      // Siber gateway it is meant to work out of the box.
      expect(AppSettings().disabledTools.contains('web_search'), isFalse);
    });

    test('image tools exist only through the Siber gateway', () {
      // Not on the registry without the gateway, regardless of toggles.
      expect(
        buildRegistry(
          AppSettings(disabledTools: const {}),
        ).contains('analyze_image'),
        isFalse,
      );
      // With the gateway flag they register and follow the toggle.
      expect(
        buildRegistry(
          AppSettings(disabledTools: const {}),
          imageToolsAvailable: true,
        ).contains('analyze_image'),
        isTrue,
      );
      expect(
        buildRegistry(
          AppSettings(disabledTools: const {}),
          imageToolsAvailable: true,
        ).contains('generate_image'),
        isTrue,
      );
      expect(
        buildRegistry(
          AppSettings(disabledTools: const {'generate_image'}),
          imageToolsAvailable: true,
        ).contains('generate_image'),
        isFalse,
      );
    });

    test('heavy device tools start disabled by default', () {
      final registry = buildRegistry(AppSettings());
      // Off out of the box to keep the tool schema light...
      for (final off in const [
        'web_search',
        'get_device_info',
        'get_storage_info',
        'get_app_info',
        'battery_status',
        'take_photo',
        'pick_gallery_image',
        'speak_text',
        'stop_speaking',
        'speech_to_text',
        'list_installed_apps',
        'launch_app',
        'wifi_scan',
        'cell_scan',
        'net_probe',
        'nfc_status',
        'nfc_analyze',
        'nfc_transceive',
        'nfc_write_ndef',
        'shell_exec',
        'ssh_list_accounts',
        'ssh_select_account',
        'ssh_exec',
        'sftp_list',
        'sftp_get',
        'sftp_put',
      ]) {
        expect(registry.contains(off), isFalse, reason: '$off should default off');
      }
      // ...while lightweight and text-oriented tools stay available.
      for (final on in const [
        'get_current_time',
        'ask_user',
        'send_file_to_user',
        'http_request',
        'get_current_location',
        'read_file',
        'write_file',
      ]) {
        expect(registry.contains(on), isTrue, reason: '$on should default on');
      }
      // Every default-off tool can be turned back on.
      expect(
        buildRegistry(AppSettings(disabledTools: const {})).contains('nfc_analyze'),
        isTrue,
      );
    });

    test(
      'uses the configured Exa-compatible search and contents endpoints',
      () async {
        final client = _ExaClient();
        final tool = WebSearchTool(client: client);
        final ctx = ToolContext(
          workDir: '/tmp',
          webBaseUrl: 'https://proxy.example.test/exa/',
          webApiKey: 'secret',
        );

        final search = await tool.execute({
          'mode': 'search',
          'query': 'Flutter news',
        }, ctx);
        final content = await tool.execute({
          'mode': 'content',
          'url': 'https://example.com',
          'maxCharacters': 1000,
        }, ctx);

        expect(search, contains('Example result'));
        expect(content, contains('Readable page text.'));
        expect(client.requests.map((request) => request.url.path), [
          '/exa/search',
          '/exa/contents',
        ]);
        expect(client.requests.first.headers['authorization'], 'Bearer secret');
        final searchBody =
            jsonDecode(client.requestBodies.first) as Map<String, dynamic>;
        expect(searchBody['query'], 'Flutter news');
        expect(searchBody['numResults'], 5);
      },
    );

    test('returns safe metadata for a file in the session sandbox', () async {
      final root = await Directory.systemTemp.createTemp('sibermobile-share-');
      try {
        final file = File(
          '${root.path}${Platform.pathSeparator}exports${Platform.pathSeparator}report.pdf',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes([1, 2, 3, 4]);

        final registry = buildRegistry(AppSettings());
        final result = await registry.execute(
          'send_file_to_user',
          jsonEncode({'path': 'exports/report.pdf'}),
          ToolContext(workDir: root.path),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['type'], 'file');
        expect(decoded['path'], 'exports/report.pdf');
        expect(decoded['name'], 'report.pdf');
        expect(decoded['bytes'], 4);
        expect(result, isNot(contains(root.path)));
      } finally {
        await root.delete(recursive: true);
      }
    });

    test('reports unknown tool as a string result', () async {
      final registry = ToolRegistry();
      final ctx = ToolContext(workDir: '/tmp');
      expect(await registry.execute('nope', '{}', ctx), contains('not found'));
    });

    test('reports invalid JSON arguments', () async {
      final registry = ToolRegistry()..register(_EchoTool([]));
      final ctx = ToolContext(workDir: '/tmp');
      final result = await registry.execute('echo', '{not json', ctx);
      expect(result, contains('invalid JSON'));
    });

    test('returns thrown errors as tool results', () async {
      final registry = ToolRegistry()..register(_EchoTool([]));
      final ctx = ToolContext(workDir: '/tmp');
      final result = await registry.execute('echo', '{}', ctx);
      expect(result, startsWith('Error:'));
      expect(result, contains('text'));
    });

    test('gates destructive tools behind approval', () async {
      final log = <String>[];
      final registry = ToolRegistry()..register(_DangerTool(log));

      final denied = ToolContext(
        workDir: '/tmp',
        requestApproval: (_, _) async => false,
      );
      final result = await registry.execute('danger', '{}', denied);
      expect(result, contains('declined'));
      expect(log, isEmpty);

      final allowed = ToolContext(
        workDir: '/tmp',
        requestApproval: (_, _) async => true,
      );
      expect(await registry.execute('danger', '{}', allowed), 'ok');
      expect(log, ['ran']);
    });

    test('skips approval when no callback is set', () async {
      final log = <String>[];
      final registry = ToolRegistry()..register(_DangerTool(log));
      final ctx = ToolContext(workDir: '/tmp');
      expect(await registry.execute('danger', '{}', ctx), 'ok');
      expect(log, ['ran']);
    });
  });

  test('persists the manual theme preference', () {
    final settings = AppSettings(themeMode: AppThemeMode.dark);
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.themeMode, AppThemeMode.dark);
  });

  test('uses 50k output tokens when max tokens is not configured', () {
    expect(AppSettings().maxTokens, 50000);
    expect(AppSettings.fromJson(const {}).maxTokens, 50000);
    expect(AppSettings.fromJson(const {'maxTokens': 4096}).maxTokens, 50000);
    expect(
      AppSettings.fromJson(const {
        'maxTokens': 4096,
        'maxTokensCustomized': true,
      }).maxTokens,
      4096,
    );
  });

  test('system prompt carries the session workspace path when known', () {
    const workDir = '/data/user/0/com.idsiber.sibermobile/files/work/s1';
    final withPath = buildSystemPrompt(
      enabledToolNames: const ['get_current_time'],
      workDir: workDir,
    );
    expect(withPath, contains(workDir));
    expect(withPath, contains('Session workspace'));

    // Without a workdir (e.g. before the first message) the section is
    // omitted entirely instead of mentioning an empty path.
    final withoutPath = buildSystemPrompt(
      enabledToolNames: const ['get_current_time'],
    );
    expect(withoutPath, isNot(contains('Session workspace')));
  });

  group('File uploads', () {
    test(
      'copies into the work directory and keeps only safe display metadata',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'sibermobile-upload-',
        );
        try {
          final source = File(
            '${root.path}${Platform.pathSeparator}agenda.txt',
          );
          await source.writeAsString('Agenda rahasia');
          final workDir = Directory(
            '${root.path}${Platform.pathSeparator}work',
          );
          await workDir.create();

          final files = await copyUploadsToWorkDir(
            uploads: [
              PendingFileUpload(
                sourcePath: source.path,
                name: 'agenda.txt',
                bytes: await source.length(),
              ),
            ],
            workDir: workDir.path,
          );

          expect(files.single.name, 'agenda.txt');
          expect(files.single.relativePath, 'uploads/agenda.txt');
          expect(
            await File(
              '${workDir.path}${Platform.pathSeparator}uploads${Platform.pathSeparator}agenda.txt',
            ).readAsString(),
            'Agenda rahasia',
          );

          final content = contentWithAttachments('Baca agenda ini', files);
          expect(content, contains('uploads/agenda.txt'));
          final restored = Message.fromStorageJson(
            Message.user(
              content,
              displayContent: 'Baca agenda ini',
              attachments: files,
            ).toStorageJson(),
          );
          expect(restored.displayContent, 'Baca agenda ini');
          expect(restored.attachments.single.name, 'agenda.txt');
        } finally {
          await root.delete(recursive: true);
        }
      },
    );

    test('rejects a file larger than 10 MB', () async {
      final root = await Directory.systemTemp.createTemp('sibermobile-upload-');
      try {
        final source = File('${root.path}${Platform.pathSeparator}large.bin');
        await source.create();
        final handle = await source.open(mode: FileMode.write);
        await handle.truncate(maxUploadBytes + 1);
        await handle.close();

        await expectLater(
          copyUploadsToWorkDir(
            uploads: [
              PendingFileUpload(
                sourcePath: source.path,
                name: 'large.bin',
                bytes: maxUploadBytes + 1,
              ),
            ],
            workDir: root.path,
          ),
          throwsA(isA<FileUploadException>()),
        );
      } finally {
        await root.delete(recursive: true);
      }
    });
  });

  group('Agent', () {
    test('streams a plain text answer with no tools', () async {
      final provider = _FakeProvider([
        [
          ContentDelta('Halo'),
          ContentDelta(' dunia'),
          StreamDone(
            message: Message.assistant('Halo dunia'),
            finishReason: FinishReason.stop,
            usage: const UsageStats(promptTokens: 10, completionTokens: 4),
          ),
        ],
      ]);
      final deltas = <String>[];
      final agent = Agent(
        provider: provider,
        registry: ToolRegistry(),
        context: ToolContext(workDir: '/tmp'),
        systemPrompt: 'You are a test.',
      );

      final answer = await agent.send('hi', AgentEvents(onContent: deltas.add));

      expect(answer, 'Halo dunia');
      expect(deltas, ['Halo', ' dunia']);
      expect(agent.history.last.role, Role.assistant);
      // System prompt is not part of the persisted history.
      expect(agent.history.any((m) => m.role == Role.system), isFalse);
    });

    test('executes a tool call then returns the final answer', () async {
      final log = <String>[];
      final registry = ToolRegistry()..register(_EchoTool(log));

      final provider = _FakeProvider([
        // First turn: the model asks for the echo tool.
        [
          ToolCallStart(index: 0, id: 'call_1', name: 'echo'),
          ToolCallArgs(index: 0, delta: '{"text":"halo"}'),
          StreamDone(
            message: Message.assistant(
              '',
              toolCalls: const [
                ToolCall(
                  id: 'call_1',
                  name: 'echo',
                  arguments: '{"text":"halo"}',
                ),
              ],
            ),
            finishReason: FinishReason.toolCalls,
          ),
        ],
        // Second turn: the model answers using the tool result.
        [
          ContentDelta('Sudah: halo'),
          StreamDone(
            message: Message.assistant('Sudah: halo'),
            finishReason: FinishReason.stop,
          ),
        ],
      ]);

      final toolResults = <String>[];
      final agent = Agent(
        provider: provider,
        registry: registry,
        context: ToolContext(workDir: '/tmp'),
      );

      final answer = await agent.send(
        'echo halo',
        AgentEvents(
          onToolResult: (index, name, result) =>
              toolResults.add('$name=$result'),
        ),
      );

      expect(log, ['halo']);
      expect(toolResults, ['echo=echo: halo']);
      expect(answer, 'Sudah: halo');
      // History keeps the tool result so it can be replayed.
      expect(agent.history.any((m) => m.role == Role.tool), isTrue);
      expect(provider.calls, 2);
    });

    test(
      'substitutes a fallback when the model returns empty content',
      () async {
        final provider = _FakeProvider([
          [
            StreamDone(
              message: Message.assistant(''),
              finishReason: FinishReason.stop,
            ),
          ],
          // The retry also comes back empty, so the fallback text is used.
          [
            StreamDone(
              message: Message.assistant('   '),
              finishReason: FinishReason.stop,
            ),
          ],
        ]);

        final agent = Agent(
          provider: provider,
          registry: ToolRegistry(),
          context: ToolContext(workDir: '/tmp'),
        );
        final answer = await agent.send('hi');

        expect(answer.trim(), isNotEmpty);
        expect(answer, emptyFinalFallback);
      },
    );

    test('stop() cancels the turn between iterations', () async {
      final token = CancellationToken();
      final provider = _FakeProvider([
        [
          ContentDelta('partial'),
          StreamDone(
            message: Message.assistant('partial'),
            finishReason: FinishReason.stop,
          ),
        ],
      ]);
      final agent = Agent(
        provider: provider,
        registry: ToolRegistry(),
        context: ToolContext(workDir: '/tmp'),
      );

      token.cancel();
      expect(
        () => agent.send('hi', AgentEvents(cancel: token)),
        throwsA(isA<AgentCancelledException>()),
      );
    });

    test(
      'compacts old turns with an AI summary after the token threshold',
      () async {
        StreamDone reply(String text) => StreamDone(
          message: Message.assistant(text),
          finishReason: FinishReason.stop,
          usage: const UsageStats(promptTokens: 800, completionTokens: 10),
        );

        final provider = _FakeProvider([
          [reply('jawaban satu')],
          [reply('jawaban dua')],
          [reply('jawaban tiga')],
          [
            StreamDone(
              message: Message.assistant('Ringkasan turn pertama.'),
              finishReason: FinishReason.stop,
              usage: const UsageStats(promptTokens: 400, completionTokens: 12),
            ),
          ],
          [reply('jawaban empat')],
        ]);
        final agent = Agent(
          provider: provider,
          registry: ToolRegistry(),
          context: ToolContext(workDir: '/tmp'),
          contextWindow: 1000,
          compactThreshold: 0.5,
          compactKeepRecent: 2,
        );

        await agent.send('turn satu');
        await agent.send('turn dua');
        await agent.send('turn tiga');
        await agent.send('turn empat');

        expect(agent.compactSummary?.text, 'Ringkasan turn pertama.');
        expect(agent.compactSummary?.upToHistoryIndex, 1);
        expect(provider.requests, hasLength(5));
        expect(provider.requests[3].tools, isEmpty);
        expect(
          provider.requests[4].messages
              .map((message) => message.content)
              .join('\n'),
          contains('[Conversation summary so far]'),
        );
        expect(agent.history, hasLength(8));
      },
    );
  });
}
