import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_store.dart';
import '../chat_controller.dart';
import '../widgets/app_modal.dart';
import '../widgets/common_widgets.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late Future<List<SessionSummary>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<ChatController>().listSessions();
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final controller = context.read<ChatController>();
    final sessions = await controller.listSessions();
    if (!context.mounted) return;
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Belum ada riwayat untuk dihapus.')),
        );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppModal(
        title: 'Hapus semua riwayat?',
        subtitle: '${sessions.length} percakapan',
        icon: Icons.delete_sweep_rounded,
        destructive: true,
        onClose: () => Navigator.pop(dialogContext, false),
        footer: AppModal.actions(
          dialogContext,
          [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hapus semua'),
            ),
          ],
        ),
        child: Text(
          'Seluruh ${sessions.length} percakapan beserta lampiran dan file '
          'hasil kerjanya akan dihapus permanen dari perangkat. Tindakan ini '
          'tidak dapat dibatalkan.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (approved != true) return;
    await controller.deleteAllSessions();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat percakapan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Hapus semua riwayat',
            icon: const Icon(Icons.delete_sweep_rounded),
            onPressed: () => _confirmDeleteAll(context),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: FutureBuilder<List<SessionSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SessionsLoading();
          }
          if (snapshot.hasError) {
            return _SessionsError(onRetry: _reload);
          }
          final sessions = snapshot.data ?? const [];
          if (sessions.isEmpty) return const _EmptySessions();
          return _SessionsList(sessions: sessions, onReload: _reload);
        },
      ),
    );
  }
}

class _SessionsList extends StatelessWidget {
  const _SessionsList({required this.sessions, required this.onReload});

  final List<SessionSummary> sessions;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.read<ChatController>();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 18),
      itemCount: sessions.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 10 : 7),
      itemBuilder: (context, index) {
        if (index == 0) {
          return SurfaceCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.forum_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sessions.length} percakapan',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tersimpan lokal dan hanya tersedia di perangkat ini.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final session = sessions[index - 1];
        final current = controller.session?.id == session.id;
        return SurfaceCard(
          padding: EdgeInsets.zero,
          borderColor: current ? theme.colorScheme.primary : null,
          onTap: () async {
            await controller.openSession(session.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 4, 9),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: current
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    current
                        ? Icons.chat_rounded
                        : Icons.chat_bubble_outline_rounded,
                    color: current
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.name?.isNotEmpty == true
                                  ? session.name!
                                  : 'Tanpa judul',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (current) ...[
                            const SizedBox(width: 5),
                            StatusPill(
                              label: 'AKTIF',
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${session.messageCount} pesan  •  ${_ago(session.updatedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (session.model.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          session.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: theme.colorScheme.error,
                  onPressed: () =>
                      _confirmDelete(context, controller, session, onReload),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChatController controller,
    SessionSummary session,
    VoidCallback reload,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppModal(
        title: 'Hapus percakapan?',
        subtitle: session.name?.isNotEmpty == true ? session.name : 'Tanpa judul',
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onClose: () => Navigator.pop(dialogContext, false),
        footer: AppModal.actions(
          dialogContext,
          [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
        child: Text(
          '“${session.name?.isNotEmpty == true ? session.name : 'Tanpa judul'}” akan dihapus permanen dari perangkat.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (approved != true) return;
    await controller.deleteSession(session.id);
    reload();
  }
}

class _SessionsLoading extends StatelessWidget {
  const _SessionsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 7),
      itemBuilder: (_, _) => const SurfaceCard(
        child: SizedBox(
          height: 48,
          child: Center(child: LinearProgressIndicator()),
        ),
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.mark_chat_unread_outlined,
                size: 30,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text('Belum ada riwayat', style: theme.textTheme.titleLarge),
            const SizedBox(height: 5),
            Text(
              'Percakapan yang kamu mulai akan tersimpan aman di perangkat ini.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Mulai percakapan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsError extends StatelessWidget {
  const _SessionsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Coba lagi'),
      ),
    );
  }
}

String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  return '${time.day}/${time.month}/${time.year}';
}
