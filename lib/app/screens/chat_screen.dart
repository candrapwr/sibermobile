/// Main conversation experience.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat_controller.dart';
import '../chat_items.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/composer.dart';
import '../widgets/message_widgets.dart';
import '../widgets/prompt_dialogs.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';
import 'ssh_accounts_screen.dart';
import 'tools_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  bool _promptShowing = false;
  bool _promptScheduled = false;
  bool _followOutput = true;
  bool _scrollScheduled = false;
  bool _wasBusy = false;
  bool _backArmed = false;
  Timer? _backArmTimer;
  bool _jumpingToBottom = false;

  static const double _followThreshold = 96;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_handleScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_jumpingToBottom || !_scroll.hasClients) return;
    final distanceFromBottom =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    // Once the user scrolls away from the tail, streaming output must not
    // steal the gesture. Scrolling back near the tail re-enables follow mode.
    _followOutput = distanceFromBottom <= _followThreshold;
  }

  void _scheduleFollowScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients || !_followOutput) return;
      _jumpingToBottom = true;
      try {
        // A direct jump avoids stacking animations for every streamed token.
        // The follow flag is checked again above, so a manual drag wins.
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } finally {
        _jumpingToBottom = false;
      }
    });
  }

  void _maybeShowPrompt(ChatController controller) {
    if (_promptShowing || _promptScheduled) return;
    final prompt = controller.pendingPrompt;
    if (prompt == null) return;

    // A dialog mutates Navigator's Overlay, so it must be pushed after the
    // current ChatScreen build has completed. Keep the prompt id so a stopped
    // or superseded request cannot open a stale dialog next frame.
    final promptId = prompt.id;
    _promptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptScheduled = false;
      if (!mounted || _promptShowing) return;
      final current = controller.pendingPrompt;
      if (current == null || current.id != promptId) return;

      _promptShowing = true;
      maybeShowPrompt(context, controller).whenComplete(() {
        _promptShowing = false;
        if (mounted) _maybeShowPrompt(controller);
      });
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _handleMenu(_ChatMenu value) async {
    // Let PopupMenuRoute finish dismissing before pushing the next page. This
    // avoids the popup remaining visually above the newly opened screen.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    switch (value) {
      case _ChatMenu.tools:
        await _open(const ToolsScreen());
      case _ChatMenu.sshAccounts:
        _open(const SshAccountsScreen());
        break;
      case _ChatMenu.history:
        await _open(const SessionsScreen());
      case _ChatMenu.settings:
        await _open(const SettingsScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    _maybeShowPrompt(controller);
    if (controller.isBusy && !_wasBusy) {
      // Starting a new turn should reveal the new user message even when the
      // previous conversation was scrolled somewhere in the middle.
      _followOutput = true;
    }
    _wasBusy = controller.isBusy;
    if (controller.isBusy && _followOutput) _scheduleFollowScroll();

    final configured = controller.isConfigured;
    final items = controller.items;
    final theme = Theme.of(context);

    return PopScope(
      // While a turn is running, an accidental back press must not kill the
      // engine: require a second press within the window to really exit.
      canPop: !controller.isBusy || _backArmed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _backArmed) return;
        setState(() => _backArmed = true);
        _backArmTimer?.cancel();
        _backArmTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _backArmed = false);
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 4),
              content: Text(
                'Masih memproses. Tekan kembali sekali lagi untuk keluar, '
                'atau minimalkan aplikasi — proses lanjut di latar belakang.',
              ),
            ),
          );
      },
      child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 64,
        leadingWidth: 56,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12, top: 12, bottom: 12),
          child: SiberLogo(size: 36),
        ),
        titleSpacing: 6,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('sibermobile'),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: configured
                        ? AppTheme.accent
                        : theme.colorScheme.error,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    configured
                        ? controller.settings.model
                        : 'Belum dikonfigurasi',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chat baru',
            icon: const Icon(Icons.add_comment_rounded),
            onPressed: controller.isBusy ? null : controller.newSession,
          ),
          PopupMenuButton<_ChatMenu>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_horiz_rounded),
            position: PopupMenuPosition.under,
            onSelected: _handleMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ChatMenu.tools,
                child: _MenuRow(
                  icon: Icons.grid_view_rounded,
                  label: 'Tool perangkat',
                ),
              ),
              PopupMenuItem(
                value: _ChatMenu.history,
                child: _MenuRow(
                  icon: Icons.history_rounded,
                  label: 'Riwayat chat',
                ),
              ),
              PopupMenuItem(
                value: _ChatMenu.sshAccounts,
                child: _MenuRow(
                  icon: Icons.dns_outlined,
                  label: 'Akun SSH',
                ),
              ),
              PopupMenuItem(
                value: _ChatMenu.settings,
                child: _MenuRow(icon: Icons.tune_rounded, label: 'Pengaturan'),
              ),
            ],
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: items.isEmpty && !controller.isBusy
                    ? _EmptyState(
                        configured: configured,
                        onOpenSettings: () => _open(const SettingsScreen()),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                        itemCount:
                            items.length +
                            (controller.activityText != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == items.length) {
                            return AiThinkingIndicator(
                              label: controller.activityText!,
                            );
                          }
                          final item = items[index];
                          return KeyedSubtree(
                            key: ValueKey(item.id),
                            child: switch (item) {
                              UserBubble() => UserBubbleView(item: item),
                              AssistantBubble() => AssistantBubbleView(
                                item: item,
                              ),
                              SystemNotice() => SystemNoticeView(item: item),
                              ToolCallBlock() => ToolCallBlockView(
                                item: item,
                                onSaveFile: controller.saveSharedFile,
                                resolveFile: controller.sharedFileSource,
                                resolveImageFile: controller.toolImageSource,
                              ),
                            },
                          );
                        },
                      ),
              ),
              Composer(
                onSend: (text, attachments) =>
                    controller.send(text, attachments: attachments),
                onStop: controller.stop,
                initialText: controller.pendingRetryText ?? '',
                busy: controller.isBusy,
                enabled: configured,
                statusText: controller.activityText,
                usage: controller.lastUsage,
                contextWindow: controller.settings.contextWindow,
                compactThreshold: controller.settings.compactThreshold,
                compactContext:
                    configured && controller.settings.compactContext,
                compactingContext: controller.isCompactingContext,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

enum _ChatMenu { tools, history, sshAccounts, settings }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.configured, required this.onOpenSettings});

  final bool configured;
  final VoidCallback onOpenSettings;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Selamat pagi';
    if (hour < 15) return 'Selamat siang';
    if (hour < 19) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo with a soft glow so the welcome feels alive without
              // being noisy.
              Container(
                width: 150,
                height: 150,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    radius: 0.75,
                    colors: [
                      colors.primary.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.30 : 0.20,
                      ),
                      colors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: const SiberLogo(size: 120),
              ),
              const SizedBox(height: 18),
              Text(
                configured
                    ? '$_greeting 👋'
                    : 'Konfigurasi provider dulu',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(
                  configured
                      ? 'SiberMobile siap membantu.'
                      : 'Hubungkan provider OpenAI-compatible untuk mulai '
                            'mengobrol dengan asisten AI Anda.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: configured
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (!configured) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Buka Pengaturan'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
