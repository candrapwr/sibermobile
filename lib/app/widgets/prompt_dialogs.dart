import 'dart:convert';

import 'package:flutter/material.dart';

import '../chat_items.dart';

import '../../core/tools/tool.dart';
import '../chat_controller.dart';

Future<void> maybeShowPrompt(
  BuildContext context,
  ChatController controller,
) async {
  final prompt = controller.pendingPrompt;
  if (prompt == null) return;

  switch (prompt) {
    case PendingAskUser(:final request):
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AskUserDialog(
          request: request,
          onSubmit: (answer) =>
              controller.resolveAskUser(cancelled: false, answer: answer),
          onCancel: () => controller.resolveAskUser(cancelled: true),
        ),
      );
    case PendingApproval(:final toolName, :final args):
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ApprovalDialog(toolName: toolName, args: args),
      );
      controller.resolveApproval(approved ?? false);
  }
}

class _AskUserDialog extends StatefulWidget {
  const _AskUserDialog({
    required this.request,
    required this.onSubmit,
    required this.onCancel,
  });

  final AskUserRequest request;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_AskUserDialog> createState() => _AskUserDialogState();
}

class _AskUserDialogState extends State<_AskUserDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.request.defaultChoice ?? '',
  );

  bool get _hasChoices => widget.request.choices.isNotEmpty;
  bool get _canSubmitText => widget.request.allowFreeText || !_hasChoices;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? preset]) {
    final answer = (preset ?? _controller.text).trim();
    if (answer.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSubmit(answer);
  }

  void _cancel() {
    Navigator.of(context).pop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final request = widget.request;
    return Dialog(
      backgroundColor: colors.surfaceContainerLow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.question_answer_rounded,
                      size: 15,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI membutuhkan jawaban',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Batal',
                    visualDensity: VisualDensity.compact,
                    onPressed: _cancel,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 19,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    constraints: const BoxConstraints(minHeight: 36),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      request.question,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasChoices) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final choice in request.choices)
                      FilledButton.tonal(
                        onPressed: () => _submit(choice),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.surfaceContainerHigh,
                          foregroundColor: colors.onSurface,
                          textStyle: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(choice),
                      ),
                  ],
                ),
              ],
              if (_canSubmitText) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: _hasChoices
                        ? 'Atau ketik jawaban lain…'
                        : 'Ketik jawaban…',
                    isDense: true,
                    filled: true,
                    fillColor: colors.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _cancel,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: () => _submit(),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('Kirim'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalDialog extends StatelessWidget {
  const _ApprovalDialog({required this.toolName, required this.args});

  final String toolName;
  final Map<String, dynamic> args;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.shield_outlined,
          color: theme.colorScheme.onErrorContainer,
          size: 23,
        ),
      ),
      title: const Text('Izinkan aksi ini?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'AI ingin menjalankan tool yang dapat mengubah perangkat atau data.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            toolNarration(toolName),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            toolName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (args.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'PARAMETER',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(args),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Tolak'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Izinkan'),
        ),
      ],
    );
  }
}
