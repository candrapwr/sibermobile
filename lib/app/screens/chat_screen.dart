/// Main conversation experience.
library;

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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
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
    if (controller.isBusy) _scrollToBottom();

    final configured = controller.isConfigured;
    final items = controller.items;
    final theme = Theme.of(context);

    return Scaffold(
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
                        onPrompt: controller.send,
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
    );
  }
}

enum _ChatMenu { tools, history, settings }

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
  const _EmptyState({
    required this.configured,
    required this.onOpenSettings,
    required this.onPrompt,
  });

  final bool configured;
  final VoidCallback onOpenSettings;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SiberLogo(size: 62),
              const SizedBox(height: 16),
              Text(
                configured
                    ? 'Asisten AI untuk apa saja'
                    : 'Konfigurasi provider dulu',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(
                  configured
                      ? 'Tanya, diskusikan ide, minta bantuan menulis, atau gunakan tool perangkat saat memang diperlukan.'
                      : 'Hubungkan provider OpenAI-compatible untuk mulai mengobrol dengan asisten AI Anda.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
              ] else ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'COBA TANYAKAN',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SuggestionGrid(onPrompt: onPrompt),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionGrid extends StatelessWidget {
  const _SuggestionGrid({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  static const suggestions = [
    (
      Icons.lightbulb_outline_rounded,
      'Jelaskan konsep',
      'Jelaskan konsep ini dengan sederhana: ',
    ),
    (
      Icons.edit_note_rounded,
      'Bantu menulis',
      'Bantu saya menulis pesan yang sopan untuk ',
    ),
    (
      Icons.account_tree_outlined,
      'Buat rencana',
      'Bantu buatkan rencana langkah demi langkah untuk ',
    ),
    (
      Icons.auto_awesome_outlined,
      'Cari ide',
      'Berikan beberapa ide kreatif untuk ',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in suggestions)
              SizedBox(
                width: width,
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  onTap: () => onPrompt(suggestion.$3),
                  child: Row(
                    children: [
                      Icon(
                        suggestion.$1,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          suggestion.$2,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
