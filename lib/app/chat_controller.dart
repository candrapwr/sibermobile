/// Chat controller: owns settings, the active session, the agent, and the list
/// of [ChatItem]s the UI renders. This is the bridge between the core agent
/// loop and Flutter widgets (provider + ChangeNotifier).
///
/// Responsibilities:
///  - load/save settings and the API key (SettingsStore)
///  - build provider + registry + agent for the active session
///  - run a turn, folding streaming events into chat items
///  - bridge ask_user and tool approval to modal UI via Completers
///  - persist history after every change
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/agent/agent.dart';
import '../core/agent/prompts.dart';
import '../core/ai/openai_compatible_provider.dart';
import '../core/ai/types.dart';
import '../core/native/device_bridge.dart';
import '../core/session/session_store.dart';
import '../core/settings/settings.dart';
import '../core/tools/registry.dart';
import '../core/tools/registry_builder.dart';
import '../core/tools/hardware/file_tools.dart';
import '../core/tools/tool.dart';
import 'chat_items.dart';
import 'file_uploads.dart';

/// A pending modal prompt (ask_user or tool approval). The UI watches
/// [ChatController.pendingPrompt] and resolves it by calling answer/cancel.
sealed class PendingPrompt {
  PendingPrompt({required this.id});
  final String id;
}

/// The ask_user tool is waiting for the user's answer.
class PendingAskUser extends PendingPrompt {
  PendingAskUser({required super.id, required this.request});
  final AskUserRequest request;
}

/// A destructive tool is waiting for the user to allow/deny it.
class PendingApproval extends PendingPrompt {
  PendingApproval({
    required super.id,
    required this.toolName,
    required this.args,
  });
  final String toolName;
  final Map<String, dynamic> args;
}

/// Everything needed to build the agent, kept so the controller can rebuild it
/// when settings change without reloading the session.
class _AgentBundle {
  _AgentBundle(this.provider, this.registry, this.agent);
  final OpenAiCompatibleProvider provider;
  final ToolRegistry registry;
  final Agent agent;
}

class ChatController extends ChangeNotifier {
  ChatController({SettingsStore? settingsStore, SessionStore? sessionStore})
    : _settingsStore = settingsStore ?? SettingsStore(),
      _sessionStore = sessionStore ?? SessionStore();

  final SettingsStore _settingsStore;
  final SessionStore _sessionStore;

  AppSettings _settings = AppSettings();
  String? _apiKey;
  String? _webApiKey;
  bool _loading = true;
  String? _loadError;

  AppSettings get settings => _settings;
  bool get isLoading => _loading;
  String? get loadError => _loadError;
  bool get isConfigured => _settings.isConfigured && (_apiKey ?? '').isNotEmpty;
  bool get hasApiKey => (_apiKey ?? '').isNotEmpty;
  bool get hasWebApiKey => (_webApiKey ?? '').isNotEmpty;

  /// Web search needs either the manual endpoint+key pair, or — when the
  /// provider is the Siber gateway — just the provider key: the static
  /// Exa-compatible endpoint on the gateway is used with the same token.
  bool get hasWebSearchConfig => _settings.usesSiberGateway
      ? (_apiKey ?? '').isNotEmpty
      : _settings.webBaseUrl.trim().isNotEmpty && (_webApiKey ?? '').isNotEmpty;

  // ── chat state ──────────────────────────────────────────────────────────
  final List<ChatItem> _items = [];
  List<ChatItem> get items => List.unmodifiable(_items);

  Session? _session;
  Session? get session => _session;

  _AgentBundle? _bundle;
  CancellationToken? _cancelToken;

  /// Resolved sandbox dir for the active session (created on first message).
  String _workDir = '';
  bool _busy = false;
  bool get isBusy => _busy;
  String? _activityText;
  String? get activityText => _activityText;
  bool _compactingContext = false;
  bool get isCompactingContext => _compactingContext;

  /// Most recent provider-reported prompt size for the context meter. A saved
  /// session restores this value before its next request.
  UsageStats get lastUsage =>
      _bundle?.agent.lastUsage ?? _session?.usage.last ?? UsageStats.zero;
  UsageStats get totalUsage =>
      _bundle?.agent.totalUsage ?? _session?.usage.total ?? UsageStats.zero;

  // ── modal prompt state ──────────────────────────────────────────────────
  PendingPrompt? _pendingPrompt;
  PendingPrompt? get pendingPrompt => _pendingPrompt;
  Completer<AskUserResponse>? _askUserCompleter;
  Completer<bool>? _approvalCompleter;

  String _nextId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Loads settings + API key. Called once from main() before the first frame.
  Future<void> bootstrap() async {
    _loading = true;
    notifyListeners();
    try {
      _settings = await _settingsStore.load();
      _apiKey = await _settingsStore.readApiKey();
      _webApiKey = await _settingsStore.readWebApiKey();
    } catch (e) {
      _loadError = 'Gagal memuat pengaturan: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Applies new settings (and optionally a new API key), then rebuilds the
  /// agent for the active session.
  Future<void> saveSettings(
    AppSettings next, {
    String? apiKey,
    String? webApiKey,
  }) async {
    _settings = next;
    await _settingsStore.save(next);
    if (apiKey != null) {
      final trimmed = apiKey.trim();
      if (trimmed.isEmpty) {
        await _settingsStore.deleteApiKey();
        _apiKey = null;
      } else {
        await _settingsStore.writeApiKey(trimmed);
        _apiKey = trimmed;
      }
    }
    if (webApiKey != null) {
      final trimmed = webApiKey.trim();
      if (trimmed.isEmpty) {
        await _settingsStore.deleteWebApiKey();
        _webApiKey = null;
      } else {
        await _settingsStore.writeWebApiKey(trimmed);
        _webApiKey = trimmed;
      }
    }
    _rebuildAgent();
    notifyListeners();
  }

  /// Sets only the API key (kept separate so the settings screen can save it
  /// without touching the rest of the config).
  Future<void> setApiKey(String key) => saveSettings(_settings, apiKey: key);

  // ── sessions ────────────────────────────────────────────────────────────

  /// Starts a brand-new empty session (persisted lazily on first message).
  Future<void> newSession() async {
    if (_busy) return;
    _closeSsh();
    _session = null;
    _workDir = '';
    _items.clear();
    _bundle?.provider.close();
    _bundle = null;
    notifyListeners();
  }

  Future<List<SessionSummary>> listSessions() => _sessionStore.list();

  Future<void> openSession(String id) async {
    if (_busy) return;
    _closeSsh();
    final loaded = await _sessionStore.load(id);
    if (loaded == null) return;
    _session = loaded;
    _workDir = await _sessionStore.workDirFor(loaded.id);
    _items
      ..clear()
      ..addAll(_historyToItems(loaded.messages));
    final draft = interruptedDraftFor(loaded.messages);
    if (draft != null) {
      _retryDraft = draft;
      _items.add(SystemNotice(
        id: _nextId(),
        text: 'Balasan terakhir terputus sebelum selesai (aplikasi tertutup '
            'saat memproses). Pesan terakhir dikembalikan ke kolom ketik — '
            'kirim ulang bila perlu.',
        isError: true,
      ));
    }
    _bundle?.provider.close();
    _bundle = null;
    _rebuildAgent();
    notifyListeners();
  }

  /// Opens the Android system save dialog and copies a shared session file to
  /// the location selected by the user. The file is read only after its path
  /// is resolved back inside the current session sandbox.
  /// Text of a turn that was cut off before any reply was persisted; offered
  /// back in the composer when the session reopens.
  String? _retryDraft;

  // ── SSH (per chat session) ────────────────────────────────────────────────
  String? _selectedSshAccountId;
  SSHClient? _sshClient;
  SftpClient? _sftpClient;
  Future<SSHClient>? _sshConnecting;
  String? get pendingRetryText => _retryDraft;

  /// A persisted history ending in a user message means the app died before
  /// the reply completed — return that message for a one-tap resend.
  @visibleForTesting
  static String? interruptedDraftFor(List<Message> messages) {
    if (messages.isEmpty) return null;
    final last = messages.last;
    if (last.role != Role.user) return null;
    final text = (last.displayContent ?? last.content).trim();
    return text.isEmpty ? null : text;
  }

  bool _busyPermissionAsked = false;

  /// Starts the keep-alive foreground service for the duration of a turn and,
  /// once, asks for notification permission so its status is visible (the
  /// service keeps the process alive either way).
  void _startBusyService() {
    unawaited(
      DeviceBridge.setBusy(busy: true, text: 'Sedang memproses permintaan…'),
    );
    if (_busyPermissionAsked || !Platform.isAndroid) return;
    _busyPermissionAsked = true;
    unawaited(
      Permission.notification.status.then<void>((status) async {
        if (status.isGranted || status.isPermanentlyDenied) return;
        await Permission.notification.request();
      }),
    );
  }

  /// Absolute, sandbox-checked file behind a shared-file card, when it still
  /// exists. Used by the chat UI to preview images inline.
  File? sharedFileSource(SharedFileInfo file) {
    if (_workDir.isEmpty) return null;
    try {
      final source = File(resolveWithin(_workDir, file.relativePath));
      return source.existsSync() ? source : null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves a raw tool-argument image path (e.g. analyze_image's `image`)
  /// to its sandbox file, for live previews while the tool runs. Data/http
  /// sources are not file-backed and return null.
  File? toolImageSource(String rawPath) {
    final path = rawPath.trim();
    if (_workDir.isEmpty ||
        path.isEmpty ||
        path.startsWith('data:') ||
        path.toLowerCase().startsWith('http://') ||
        path.toLowerCase().startsWith('https://')) {
      return null;
    }
    try {
      final source = File(resolveWithin(_workDir, path));
      return source.existsSync() ? source : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> saveSharedFile(SharedFileInfo file) async {
    final session = _session;
    if (session == null) {
      throw StateError('Sesi file sudah tidak tersedia.');
    }
    final workDir = await _sessionStore.workDirFor(session.id);
    final source = File(resolveWithin(workDir, file.relativePath));
    if (!await source.exists()) {
      throw StateError('File "${file.name}" sudah tidak ditemukan.');
    }
    await ensureResolvedWithin(workDir, source.path);
    if (await FileSystemEntity.isDirectory(source.path)) {
      throw StateError('"${file.name}" bukan file yang dapat disimpan.');
    }
    final bytes = await source.readAsBytes();
    return FilePicker.saveFile(
      fileName: file.name,
      bytes: bytes,
      mimeType: file.mimeType,
      dialogTitle: 'Simpan ${file.name}',
    );
  }

  Future<void> deleteSession(String id) async {
    await _sessionStore.delete(id);
    if (_session?.id == id) {
      await newSession();
    }
    notifyListeners();
  }

  /// Saves a new SSH account; the password goes straight to secure storage
  /// and never enters settings JSON.
  ///
  /// Returns true when this was the FIRST account and the SSH tools were
  /// auto-enabled with it — adding an account clearly signals intent to use
  /// SSH, but later additions never re-enable tools the user turned off.
  Future<bool> addSshAccount({
    required String name,
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    final wasEmpty = _settings.sshAccounts.isEmpty;
    final id = 'ssh_${DateTime.now().microsecondsSinceEpoch}';
    await _settingsStore.writeSshPassword(id, password);
    var next = _settings.copyWith(
      sshAccounts: [
        ..._settings.sshAccounts,
        SshAccount(
          id: id,
          name: name,
          host: host,
          port: port,
          username: username,
        ),
      ],
    );
    var enabledTools = false;
    if (wasEmpty) {
      final disabled = Set<String>.of(_settings.disabledTools)
        ..remove('ssh_client')
        ..remove('sftp_client');
      enabledTools = true;
      next = next.copyWith(disabledTools: disabled);
    }
    await saveSettings(next);
    return enabledTools;
  }

  /// Updates an SSH account's metadata; a non-empty [password] replaces the
  /// stored one (empty keeps it). If connection-relevant fields changed on
  /// the account in use, the cached client is dropped so the next command
  /// reconnects with the new details.
  Future<void> updateSshAccount(
    SshAccount account, {
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
  }) async {
    if (password != null && password.isNotEmpty) {
      await _settingsStore.writeSshPassword(account.id, password);
    }
    final updated = account.copyWith(
      name: name,
      host: host,
      port: port,
      username: username,
    );
    final connectionChanged = updated.host != account.host ||
        updated.port != account.port ||
        updated.username != account.username ||
        (password != null && password.isNotEmpty);
    if (connectionChanged && _selectedSshAccountId == account.id) {
      try {
        _sftpClient?.close();
      } catch (_) {}
      try {
        _sshClient?.close();
      } catch (_) {}
      _sftpClient = null;
      _sshClient = null;
      _sshConnecting = null;
    }
    await saveSettings(
      _settings.copyWith(
        sshAccounts: [
          for (final a in _settings.sshAccounts)
            if (a.id == account.id) updated else a,
        ],
      ),
    );
  }

  /// Deletes an SSH account and its stored password; drops the active
  /// connection if that account was in use.
  Future<void> deleteSshAccount(String id) async {
    await _settingsStore.deleteSshPassword(id);
    if (_selectedSshAccountId == id) {
      try {
        _sftpClient?.close();
      } catch (_) {}
      try {
        _sshClient?.close();
      } catch (_) {}
      _sftpClient = null;
      _sshClient = null;
      _sshConnecting = null;
      _selectedSshAccountId = null;
    }
    await saveSettings(
      _settings.copyWith(
        sshAccounts: _settings.sshAccounts.where((a) => a.id != id).toList(),
      ),
    );
  }

  /// Wipes every stored session (and their work directories) and starts a
  /// fresh chat.
  Future<void> deleteAllSessions() async {
    await _sessionStore.deleteAll();
    await newSession();
    notifyListeners();
  }

  // ── SSH access for tools ────────────────────────────────────────────────
  //
  // Implements SshAccess for the ssh_* tools. Credentials are read from
  // secure storage only at connect time and never leave this class: tools
  // see account metadata, command output and file listings — never secrets.

  SshAccess get sshAccess => _SshControllerAccess(this);

  void _closeSsh() {
    _selectedSshAccountId = null;
    _sshConnecting = null;
    try {
      _sftpClient?.close();
    } catch (_) {}
    try {
      _sshClient?.close();
    } catch (_) {}
    _sftpClient = null;
    _sshClient = null;
  }

  SshAccount? _findSshAccount(String nameOrId) {
    final needle = nameOrId.trim().toLowerCase();
    for (final a in _settings.sshAccounts) {
      if (a.id == nameOrId ||
          a.name.toLowerCase() == needle ||
          '${a.username}@${a.host}'.toLowerCase() == needle) {
        return a;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _sshSelectAccount(String nameOrId) async {
    final account = _findSshAccount(nameOrId);
    if (account == null) {
      final names = _settings.sshAccounts
          .map((a) => '${a.name} (${a.username}@${a.host})')
          .join(', ');
      return {
        'ok': false,
        'error': 'No SSH account matches "$nameOrId". Saved accounts: '
            '${names.isEmpty ? '(none)' : names}.',
      };
    }
    if (_selectedSshAccountId != account.id) {
      // Switching accounts drops the previous connection lazily.
      try {
        _sftpClient?.close();
      } catch (_) {}
      try {
        _sshClient?.close();
      } catch (_) {}
      _sftpClient = null;
      _sshClient = null;
      _sshConnecting = null;
      _selectedSshAccountId = account.id;
    }
    return {'ok': true, 'selected': account.name};
  }

  Future<SSHClient> _sshEnsureConnected() async {
    if (_sshClient?.isClosed == false) return _sshClient!;
    final existing = _sshConnecting;
    if (existing != null) return existing;

    final accountId = _selectedSshAccountId;
    if (accountId == null) {
      throw StateError('no-account');
    }
    final account = _settings.sshAccounts
        .where((a) => a.id == accountId)
        .firstOrNull;
    if (account == null) {
      throw StateError('account-deleted');
    }
    final password = (await _settingsStore.readSshPassword(account.id)) ?? '';
    if (password.isEmpty) {
      throw StateError('no-password');
    }

    final connecting = () async {
      final socket = await SSHSocket.connect(
        account.host,
        account.port,
        timeout: const Duration(seconds: 15),
      );
      return SSHClient(
        socket,
        username: account.username,
        onPasswordRequest: () => password,
        keepAliveInterval: const Duration(seconds: 15),
      );
    }();
    _sshConnecting = connecting;
    try {
      final client = await connecting.timeout(const Duration(seconds: 25));
      _sshClient = client;
      return client;
    } finally {
      _sshConnecting = null;
    }
  }

  Future<SftpClient> _sftpEnsure() async {
    if (_sftpClient != null) return _sftpClient!;
    final client = await _sshEnsureConnected();
    _sftpClient = await client.sftp();
    return _sftpClient!;
  }

  Future<Map<String, dynamic>> _sshExecImpl(
    String command,
    int timeoutSeconds,
  ) async {
    final client = await _sshEnsureConnected();
    final session = await client.execute(command);
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final subs = [
      session.stdout.listen(
        (d) {
          if (stdout.length < 200000) {
            stdout.write(utf8.decode(d, allowMalformed: true));
          }
        },
      ),
      session.stderr.listen(
        (d) {
          if (stderr.length < 200000) {
            stderr.write(utf8.decode(d, allowMalformed: true));
          }
        },
      ),
    ];
    try {
      await session.done.timeout(Duration(seconds: timeoutSeconds));
    } on TimeoutException {
      for (final s in subs) {
        await s.cancel();
      }
      return {
        'ok': false,
        'error': 'Command timed out after ${timeoutSeconds}s (still running '
            'on the server).',
      };
    }
    return {
      'ok': true,
      'exitCode': session.exitCode,
      'stdout': _sshClamp(stdout.toString()),
      'stderr': _sshClamp(stderr.toString()),
    };
  }

  String _sshClamp(String text) =>
      text.length <= 12000 ? text : text.substring(0, 12000);

  Map<String, dynamic> _sshErrorMap(Object e) {
    final message = e is StateError ? e.message : '';
    switch (message) {
      case 'no-account':
        return {
          'ok': false,
          'error': 'No SSH account is selected for this conversation yet. '
              'Run ssh_list_accounts, let the user pick one with ask_user, '
              'then call ssh_select_account.',
        };
      case 'no-password':
        return {
          'ok': false,
          'error': 'The saved password for this account is empty. Re-add the '
              'account from the Akun SSH menu.',
        };
      case 'account-deleted':
        return {
          'ok': false,
          'error': 'The selected SSH account was deleted. Ask the user to '
              'pick another one.',
        };
    }
    return {'ok': false, 'error': 'SSH failed: $e'};
  }

// ── agent lifecycle ─────────────────────────────────────────────────────

  void _rebuildAgent() {
    _bundle?.provider.close();
    if (!isConfigured) {
      _bundle = null;
      return;
    }
    final provider = OpenAiCompatibleProvider(
      baseUrl: _settings.baseUrl.trim(),
      apiKey: _apiKey!,
      model: _settings.model.trim(),
      includeUsageInStream: _settings.includeUsageInStream,
      extraBody: _settings.sendReasoningEffort
          ? {'reasoning_effort': _settings.reasoningEffort.name}
          : const {},
    );
    final registry = buildRegistry(
      _settings,
      webSearchAvailable: hasWebSearchConfig,
      imageToolsAvailable: _settings.usesSiberGateway && hasApiKey,
    );
    final savedUsage = _session?.usage ?? const SessionUsage();
    final agent = Agent(
      provider: provider,
      registry: registry,
      context: _buildToolContext(),
      model: _settings.model.trim(),
      maxTokens: _settings.maxTokens,
      temperature: _settings.temperature,
      maxIterations: _settings.maxIterations,
      autoContinue: _settings.autoContinue,
      compactContext: _settings.compactContext,
      contextWindow: _settings.contextWindow,
      compactThreshold: _settings.compactThreshold,
      compactKeepRecent: _settings.compactKeepRecent,
      initialTotalUsage: savedUsage.total,
      initialLastUsage: savedUsage.last,
      lastPromptTokens: savedUsage.last.promptTokens,
      systemPrompt: buildSystemPrompt(
        enabledToolNames: registry.names,
        workDir: _workDir,
      ),
    );
    // Restore history into the fresh agent.
    if (_session != null) {
      agent.loadHistory(
        _session!.messages,
        compactSummary: _session!.compactSummary,
      );
    }
    _bundle = _AgentBundle(provider, registry, agent);
  }

  ToolContext _buildToolContext() {
    final siberGateway = _settings.usesSiberGateway;
    return ToolContext(
      workDir: _workDir,
      askUser: _askUser,
      requestApproval: _settings.approveDestructiveTools
          ? _requestApproval
          : null,
      webBaseUrl: siberGateway
          ? siberWebSearchBaseUrl
          : _settings.webBaseUrl,
      webApiKey: siberGateway ? _apiKey : _webApiKey,
      visionBaseUrl: siberGateway ? _settings.baseUrl : '',
      visionApiKey: siberGateway ? _apiKey : null,
      visionModel: siberGateway ? siberVisionModel : '',
      imageGenModel: siberGateway ? siberImageGenModel : '',
      ssh: sshAccess,
    );
  }

  // ── modal bridges (Completer-based) ─────────────────────────────────────

  Future<AskUserResponse> _askUser(AskUserRequest request) {
    final id = _nextId();
    final completer = Completer<AskUserResponse>();
    _askUserCompleter = completer;
    _pendingPrompt = PendingAskUser(id: id, request: request);
    notifyListeners();
    return completer.future;
  }

  Future<bool> _requestApproval(String toolName, Map<String, dynamic> args) {
    final id = _nextId();
    final completer = Completer<bool>();
    _approvalCompleter = completer;
    _pendingPrompt = PendingApproval(id: id, toolName: toolName, args: args);
    notifyListeners();
    return completer.future;
  }

  /// Called by the UI when the user answers an ask_user prompt.
  void resolveAskUser({required bool cancelled, String answer = ''}) {
    final c = _askUserCompleter;
    _pendingPrompt = null;
    _askUserCompleter = null;
    notifyListeners();
    if (c != null && !c.isCompleted) {
      c.complete(
        cancelled
            ? const AskUserResponse.cancelled()
            : AskUserResponse.answered(answer),
      );
    }
  }

  /// Called by the UI when the user allows/denies a destructive tool.
  void resolveApproval(bool approved) {
    final c = _approvalCompleter;
    _pendingPrompt = null;
    _approvalCompleter = null;
    notifyListeners();
    if (c != null && !c.isCompleted) c.complete(approved);
  }

  // ── running a turn ──────────────────────────────────────────────────────

  Future<void> send(
    String input, {
    List<PendingFileUpload> attachments = const [],
  }) async {
    final text = input.trim();
    if ((text.isEmpty && attachments.isEmpty) || _busy) return;
    if (!isConfigured) {
      _pushNotice(
        'Atur Base URL, API key dan model di Settings dulu.',
        isError: true,
      );
      return;
    }

    _busy = true;
    _activityText = 'Menghubungi ${_settings.model}…';
    _cancelToken = CancellationToken();
    _startBusyService();
    notifyListeners();

    // A live assistant bubble that content deltas append to. Tool calls insert
    // their own blocks after it; if more text arrives we start a new bubble.
    AssistantBubble? liveBubble;
    final toolBlocks = <int, ToolCallBlock>{};

    void finishRunningTools(String result) {
      for (final block in toolBlocks.values) {
        if (block.status == ToolCallStatus.running ||
            block.status == ToolCallStatus.pending) {
          block.result = result;
          block.status = ToolCallStatus.error;
        }
      }
    }

    void ensureLiveBubble() {
      if (liveBubble == null || liveBubble!.isStreaming == false) {
        liveBubble = AssistantBubble(id: _nextId());
        _items.add(liveBubble!);
      }
    }

    final events = AgentEvents(
      cancel: _cancelToken,
      onAssistantStart: () {
        _activityText = 'AI sedang berpikir…';
        notifyListeners();
      },
      onContent: (delta) {
        _activityText = null;
        ensureLiveBubble();
        liveBubble!.text += delta;
        notifyListeners();
      },
      onToolCallStart: (index, id, name) {
        _activityText = null;
        final block = ToolCallBlock(id: _nextId(), name: name, toolCallId: id)
          ..status = ToolCallStatus.running;
        toolBlocks[index] = block;
        _items.add(block);
        // Close the current text bubble so subsequent text starts a new one.
        liveBubble?.isStreaming = false;
        liveBubble = null;
        notifyListeners();
      },
      onToolCallArgs: (index, delta) {
        final block = toolBlocks[index];
        if (block != null) {
          block.arguments += delta;
          notifyListeners();
        }
      },
      onToolResult: (index, name, result) {
        final block = toolBlocks[index];
        if (block != null) {
          block.result = result;
          final failed = _isToolErrorResult(result);
          block.status = failed
              ? (result.contains('declined to run')
                    ? ToolCallStatus.denied
                    : ToolCallStatus.error)
              : ToolCallStatus.done;
        }
        _activityText = 'Menyusun jawaban…';
        notifyListeners();
      },
      onUsage: (lastUsage, totalUsage) => notifyListeners(),
      onContextCompacting: () {
        _compactingContext = true;
        _activityText = 'Merangkum konteks percakapan…';
        notifyListeners();
      },
      onContextCompacted: (stats) {
        _activityText =
            'Konteks diringkas (${stats.messagesSummarized} pesan).';
        notifyListeners();
      },
      onContextCompactionFinished: () {
        _compactingContext = false;
        notifyListeners();
      },
      onMaxIterations: (limit) {
        _pushNotice('Batas $limit iterasi tool tercapai.', isError: true);
      },
    );

    try {
      // Lazily create the session (with its work dir) on the first message.
      _session ??= _sessionStore.createSession(model: _settings.model);
      // The work dir depends on the session id, so resolve it after creation and
      // (re)build the agent so ToolContext sees the real path.
      _workDir = await _sessionStore.workDirFor(_session!.id);
      if (attachments.isNotEmpty) {
        _activityText = 'Menyalin lampiran…';
        notifyListeners();
      }
      final copiedAttachments = await copyUploadsToWorkDir(
        uploads: attachments,
        workDir: _workDir,
      );
      final modelInput = contentWithAttachments(text, copiedAttachments);

      // Render only the text the user wrote and attachment names. The model
      // gets the sandbox-relative paths in [modelInput], never the UI bubble.
      _items.add(
        UserBubble(
          id: _nextId(),
          text: text,
          attachmentNames: copiedAttachments.map((file) => file.name).toList(),
        ),
      );
      notifyListeners();

      _rebuildAgent();
      if (_bundle == null) {
        _pushNotice(
          'Agent belum siap. Periksa konfigurasi provider.',
          isError: true,
        );
        return;
      }
      await _bundle!.agent.send(
        modelInput,
        events,
        copiedAttachments,
        copiedAttachments.isEmpty ? null : text,
      );
      liveBubble?.isStreaming = false;
    } on FileUploadException catch (e) {
      liveBubble?.isStreaming = false;
      _pushNotice(e.message, isError: true);
    } on AgentCancelledException {
      liveBubble?.isStreaming = false;
      finishRunningTools('Error: tool call dibatalkan.');
      _pushNotice('Dibatalkan.', isError: true);
    } catch (e) {
      liveBubble?.isStreaming = false;
      finishRunningTools('Error: turn berhenti sebelum tool selesai — $e');
      _pushNotice('Error: $e', isError: true);
    } finally {
      finishRunningTools(
        'Error: provider mengakhiri turn tanpa mengirim hasil tool.',
      );
      _busy = false;
      _activityText = null;
      _compactingContext = false;
      _cancelToken = null;
      unawaited(DeviceBridge.setBusy(busy: false));
      await _persist();
      notifyListeners();
    }
  }

  /// Aborts an in-flight turn. The agent checks the token between steps.
  void stop() {
    _cancelToken?.cancel();
    // Unblock any modal that is waiting.
    resolveAskUser(cancelled: true);
    resolveApproval(false);
  }

  Future<void> _persist() async {
    final agent = _bundle?.agent;
    final session = _session;
    if (agent == null || session == null) return;
    session.messages = agent.history;
    session.usage = SessionUsage(
      last: agent.lastUsage ?? UsageStats.zero,
      total: agent.totalUsage,
    );
    session.compactSummary = agent.compactSummary;
    session.name ??= _deriveName(agent.history);
    await _sessionStore.save(session);
    _session = session;
  }

  String? _deriveName(List<Message> history) {
    final firstUser = history.firstWhere(
      (m) => m.role == Role.user,
      orElse: () => Message.user(''),
    );
    final text = (firstUser.displayContent ?? firstUser.content).trim();
    final fallback = text.isNotEmpty
        ? text
        : (firstUser.attachments.isEmpty
              ? ''
              : firstUser.attachments.first.name);
    if (fallback.isEmpty) return null;
    final words = fallback.split(RegExp(r'\s+'));
    final take = words.take(5).join(' ');
    return take.length > 48 ? '${take.substring(0, 48)}…' : take;
  }

  void _pushNotice(String text, {bool isError = false}) {
    _items.add(SystemNotice(id: _nextId(), text: text, isError: isError));
    notifyListeners();
  }

  /// Rebuilds chat items from a persisted history (opening an old session).
  List<ChatItem> _historyToItems(List<Message> messages) {
    final out = <ChatItem>[];
    for (final m in messages) {
      switch (m.role) {
        case Role.user:
          out.add(
            UserBubble(
              id: _nextId(),
              text: m.displayContent ?? m.content,
              attachmentNames: m.attachments.map((file) => file.name).toList(),
            ),
          );
        case Role.assistant:
          if (m.content.trim().isNotEmpty) {
            out.add(
              AssistantBubble(id: _nextId(), text: m.content)
                ..isStreaming = false,
            );
          }
          for (final call in m.toolCalls ?? const <ToolCall>[]) {
            out.add(
              ToolCallBlock(
                id: _nextId(),
                name: call.name,
                toolCallId: call.id,
                arguments: call.arguments,
              )..status = ToolCallStatus.done,
            );
          }
        case Role.tool:
          // Attach the result to the matching tool block if present.
          final block = out
              .whereType<ToolCallBlock>()
              .where((b) => b.toolCallId == m.toolCallId)
              .toList();
          if (block.isNotEmpty) {
            block.last.result = m.content;
            final failed = _isToolErrorResult(m.content);
            block.last.status = failed
                ? (m.content.contains('declined to run')
                      ? ToolCallStatus.denied
                      : ToolCallStatus.error)
                : ToolCallStatus.done;
          }
        case Role.system:
          break;
      }
    }
    return out;
  }

  @override
  void dispose() {
    _bundle?.provider.close();
    super.dispose();
  }
}

bool _isToolErrorResult(String result) {
  if (result.startsWith('Error:') || result.contains('declined to run')) {
    return true;
  }
  try {
    final decoded = jsonDecode(result);
    return decoded is Map && decoded['ok'] == false;
  } catch (_) {
    return false;
  }
}

/// Glues the ssh_* tools to ChatController: all credential handling stays
/// inside the controller; this surface only exposes metadata and results.
class _SshControllerAccess implements SshAccess {
  _SshControllerAccess(this._controller);

  final ChatController _controller;

  @override
  Future<List<Map<String, Object?>>> listAccounts() async {
    return [
      for (final a in _controller._settings.sshAccounts)
        {
          'id': a.id,
          'name': a.name,
          'host': a.host,
          'port': a.port,
          'username': a.username,
          'selected': a.id == _controller._selectedSshAccountId,
        },
    ];
  }

  @override
  Future<Map<String, dynamic>> selectAccount(String nameOrId) =>
      _controller._sshSelectAccount(nameOrId);

  @override
  Future<Map<String, dynamic>> exec(String command, int timeoutSeconds) =>
      _controller._sshExecImpl(command, timeoutSeconds);

  @override
  Future<Map<String, dynamic>> sftpList(String path) async {
    try {
      final sftp = await _controller._sftpEnsure();
      final entries = await sftp.listdir(path);
      return {
        'ok': true,
        'path': path,
        'entries': [
          for (final e in entries.take(500))
            {
              'name': e.filename,
              'isDirectory': e.attr.isDirectory,
              if (e.attr.size != null) 'sizeBytes': e.attr.size,
            },
        ],
      };
    } catch (e) {
      return _controller._sshErrorMap(e);
    }
  }

  @override
  Future<Map<String, dynamic>> sftpDownload(String remotePath) async {
    try {
      final sftp = await _controller._sftpEnsure();
      final name = remotePath.split('/').where((p) => p.isNotEmpty).last;
      final localRel = resolveWithin(_controller._workDir, 'ssh/$name');
      final local = File(localRel);
      await local.parent.create(recursive: true);
      final sink = local.openWrite();
      final bytes = await sftp.download(remotePath, sink, closeDestination: true);
      return {
        'ok': true,
        'path': 'ssh/$name',
        'bytes': bytes,
        'hint': 'Offer the file via send_file_to_user with path "ssh/$name".',
      };
    } catch (e) {
      return _controller._sshErrorMap(e);
    }
  }

  @override
  Future<Map<String, dynamic>> sftpUpload(
    String localPath,
    String remotePath,
  ) async {
    try {
      final sftp = await _controller._sftpEnsure();
      final local = File(resolveWithin(_controller._workDir, localPath));
      if (!await local.exists()) {
        return {
          'ok': false,
          'error': 'Local file "$localPath" not found in the session workdir.',
        };
      }
      final file = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
      );
      final writer = file.write(
        local.openRead().map(Uint8List.fromList),
      );
      await writer.done;
      await file.close();
      return {
        'ok': true,
        'uploaded': await local.length(),
        'remotePath': remotePath,
      };
    } catch (e) {
      return _controller._sshErrorMap(e);
    }
  }
}
