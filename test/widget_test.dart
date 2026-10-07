// Smoke test: the app boots, waits for settings, then shows the chat screen
// with the "not configured" empty state (no provider settings in the test).
//
// flutter_secure_storage talks over a platform channel that does not exist in
// the test binding, so we stub it (reads return null) to keep bootstrap from
// hanging. shared_preferences is backed by an in-memory mock.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sibermobile/app/chat_controller.dart';
import 'package:sibermobile/app/chat_items.dart';
import 'package:sibermobile/app/screens/chat_screen.dart';
import 'package:sibermobile/main.dart';
import 'package:sibermobile/app/widgets/composer.dart';
import 'package:sibermobile/app/widgets/message_widgets.dart';
import 'package:sibermobile/core/ai/types.dart';
import 'package:sibermobile/core/tools/tool.dart';

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _PromptController extends ChatController {
  _PromptController(this._prompt);

  PendingPrompt? _prompt;

  @override
  PendingPrompt? get pendingPrompt => _prompt;

  @override
  void resolveAskUser({required bool cancelled, String answer = ''}) {
    _prompt = null;
    notifyListeners();
  }

  @override
  void resolveApproval(bool approved) {
    _prompt = null;
    notifyListeners();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
          if (call.method == 'read') return null;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, null);
  });

  testWidgets('boots and prompts for provider configuration', (tester) async {
    await tester.pumpWidget(const SiberMobileApp());
    await tester.pumpAndSettle();

    // No settings configured, so the empty state offers the settings button.
    expect(find.text('Konfigurasi provider dulu'), findsOneWidget);
    expect(find.widgetWithIcon(FilledButton, Icons.settings), findsOneWidget);
    expect(find.text('sibermobile'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/sibermobile_icon.png',
      ),
      findsWidgets,
    );
  });

  testWidgets('opens the settings screen from the empty state', (tester) async {
    await tester.pumpWidget(const SiberMobileApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Base URL'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Base URL'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Tes koneksi'), findsOneWidget);
  });

  testWidgets('shows polished AI waiting feedback on a phone viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(
                child: AiThinkingIndicator(label: 'AI sedang berpikir…'),
              ),
              Composer(
                onSend: (_, _) {},
                onStop: () {},
                busy: true,
                statusText: 'AI sedang berpikir…',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('AI sedang berpikir…'), findsNWidgets(2));
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.text('Tekan stop untuk batal'), findsOneWidget);
    final shellCenter = tester.getCenter(
      find.byKey(const ValueKey('chat-input-shell')),
    );
    final fieldCenter = tester.getCenter(
      find.byKey(const ValueKey('chat-input-field')),
    );
    expect((shellCenter.dy - fieldCenter.dy).abs(), lessThan(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows the compact context meter below the chat input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Composer(
              onSend: (_, _) {},
              onStop: () {},
              busy: false,
              usage: const UsageStats(
                promptTokens: 80000,
                completionTokens: 1200,
              ),
              contextWindow: 100000,
              compactThreshold: 0.8,
            ),
          ),
        ),
      ),
    );

    expect(find.text('80k / 100k · 80% · @80%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders assistant responses as Markdown', (tester) async {
    final message = AssistantBubble(
      id: 'markdown-test',
      text: '**Tebal**\n\n- Satu\n- Dua\n\n```dart\nfinal ok = true;\n```',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AssistantBubbleView(item: message),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    expect(tester.getSize(find.byType(MarkdownBody)).width, greaterThan(700));
    expect(find.text('**Tebal**'), findsNothing);
    expect(find.text('Tebal'), findsOneWidget);
    expect(find.textContaining('final ok = true;'), findsOneWidget);
  });

  testWidgets('shows only an uploaded filename in the user history', (
    tester,
  ) async {
    final message = UserBubble(
      id: 'file-history',
      text: 'Tolong periksa file ini.',
      attachmentNames: const ['laporan-final.pdf'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UserBubbleView(item: message)),
      ),
    );

    expect(find.text('laporan-final.pdf'), findsOneWidget);
    expect(find.textContaining('uploads/'), findsNothing);
    expect(find.textContaining('work/'), findsNothing);
  });

  testWidgets('shows only a compact tool status without its result', (
    tester,
  ) async {
    final tool =
        ToolCallBlock(
            id: 'tool-test',
            name: 'get_device_info',
            toolCallId: 'call-1',
            arguments: '{"detail":true}',
          )
          ..result = '{"private":"large tool result"}'
          ..status = ToolCallStatus.done;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ToolCallBlockView(item: tool)),
      ),
    );

    expect(find.text('get_device_info'), findsOneWidget);
    expect(find.text('Berhasil'), findsOneWidget);
    expect(find.textContaining('large tool result'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
  });

  testWidgets('shows a save card for files sent by the assistant', (
    tester,
  ) async {
    final tool =
        ToolCallBlock(
            id: 'file-tool-test',
            name: 'send_file_to_user',
            toolCallId: 'call-file-1',
            arguments: '{"path":"exports/report.pdf"}',
          )
          ..result = jsonEncode({
            'ok': true,
            'type': 'file',
            'path': 'exports/report.pdf',
            'name': 'report.pdf',
            'bytes': 2048,
            'mimeType': 'application/pdf',
          })
          ..status = ToolCallStatus.done;
    SharedFileInfo? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolCallBlockView(
            item: tool,
            onSaveFile: (file) async {
              selected = file;
              return Uri.parse('content://saved/report.pdf');
            },
          ),
        ),
      ),
    );

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('2.0 KB · siap disimpan'), findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(selected?.relativePath, 'exports/report.pdf');
    expect(find.text('File berhasil disimpan ke perangkat.'), findsOneWidget);
  });

  testWidgets('opens ask_user only after ChatScreen finishes building', (
    tester,
  ) async {
    final controller = _PromptController(
      PendingAskUser(
        id: 'ask-user-test',
        request: const AskUserRequest(
          question: 'Pilih bahasa jawaban.',
          choices: ['Indonesia', 'English'],
        ),
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatController>.value(
        value: controller,
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('AI membutuhkan jawaban'), findsOneWidget);
    expect(find.text('Pilih bahasa jawaban.'), findsOneWidget);

    await tester.tap(find.text('Indonesia'));
    await tester.pumpAndSettle();
    expect(find.text('AI membutuhkan jawaban'), findsNothing);
  });

  testWidgets('opens approval only after ChatScreen finishes building', (
    tester,
  ) async {
    final controller = _PromptController(
      PendingApproval(
        id: 'approval-test',
        toolName: 'delete_file',
        args: const {'path': 'catatan.txt'},
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatController>.value(
        value: controller,
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Izinkan aksi ini?'), findsOneWidget);
    expect(find.text('delete_file'), findsOneWidget);

    await tester.tap(find.text('Tolak'));
    await tester.pumpAndSettle();
    expect(find.text('Izinkan aksi ini?'), findsNothing);
  });
}
