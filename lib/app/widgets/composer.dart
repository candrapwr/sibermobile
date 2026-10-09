import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../file_uploads.dart';
import '../../core/ai/types.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.busy,
    this.initialText = '',
    this.enabled = true,
    this.hintText = 'Tulis pesan…',
    this.statusText,
    this.usage,
    this.contextWindow = 200000,
    this.compactThreshold = 0.8,
    this.compactContext = true,
    this.compactingContext = false,
  });

  final void Function(String text, List<PendingFileUpload> attachments) onSend;
  final VoidCallback onStop;
  final bool busy;

  /// Prefills the field once (e.g. a turn cut off before its reply, offered
  /// back for an easy resend). Only applied while the field is empty so it
  /// never clobbers what the user is typing.
  final String initialText;
  final bool enabled;
  final String hintText;
  final String? statusText;
  final UsageStats? usage;
  final int contextWindow;
  final double compactThreshold;
  final bool compactContext;
  final bool compactingContext;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;
  bool _pickingFiles = false;
  final List<PendingFileUpload> _attachments = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    if (widget.initialText.isNotEmpty) _controller.text = widget.initialText;
  }

  @override
  void didUpdateWidget(covariant Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText.isNotEmpty &&
        oldWidget.initialText != widget.initialText &&
        _controller.text.isEmpty) {
      _controller.text = widget.initialText;
    }
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) ||
        widget.busy ||
        !widget.enabled) {
      return;
    }
    widget.onSend(text, List<PendingFileUpload>.of(_attachments));
    _controller.clear();
    setState(_attachments.clear);
    _focus.requestFocus();
  }

  Future<void> _pickFiles() async {
    if (widget.busy || !widget.enabled || _pickingFiles) return;
    setState(() => _pickingFiles = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Pilih file (maks. 10 MB per file)',
      );
      if (!mounted || files.isEmpty) return;

      final accepted = <PendingFileUpload>[];
      final rejected = <String>[];
      for (final file in files) {
        final path = file.path;
        final bytes = await file.length();
        if (path == null || bytes == null) {
          rejected.add('${file.name}: file tidak dapat diakses');
        } else if (bytes > maxUploadBytes) {
          rejected.add('${file.name}: melebihi 10 MB');
        } else {
          accepted.add(
            PendingFileUpload(sourcePath: path, name: file.name, bytes: bytes),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        for (final file in accepted) {
          if (_attachments.every(
            (item) => item.sourcePath != file.sourcePath,
          )) {
            _attachments.add(file);
          }
        }
      });
      if (rejected.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(rejected.join('\n'))));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File tidak dapat dipilih. Coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _pickingFiles = false);
    }
  }

  void _removeAttachment(PendingFileUpload file) {
    setState(() => _attachments.remove(file));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend =
        (_hasText || _attachments.isNotEmpty) && widget.enabled && !widget.busy;
    final promptTokens = widget.usage?.promptTokens ?? 0;
    final contextPercent = widget.contextWindow <= 0
        ? 0.0
        : (promptTokens / widget.contextWindow).clamp(0.0, 1.0).toDouble();
    final threshold = widget.compactThreshold.clamp(0.1, 1.0).toDouble();
    final meterColor = contextPercent < 0.5
        ? theme.colorScheme.primary
        : contextPercent < threshold
        ? theme.colorScheme.tertiary
        : theme.colorScheme.error;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        widget.statusText ?? 'AI sedang bekerja…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Tekan stop untuk batal',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
              ],
              if (_attachments.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final file in _attachments)
                        InputChip(
                          avatar: const Icon(
                            Icons.attach_file_rounded,
                            size: 16,
                          ),
                          label: Text(
                            '${file.name} · ${_formatBytes(file.bytes)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          tooltip: file.name,
                          onDeleted: widget.busy
                              ? null
                              : () => _removeAttachment(file),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
              ],
              Container(
                key: const ValueKey('chat-input-shell'),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.surfaceContainerHigh
                      : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _focus.hasFocus
                        ? theme.colorScheme.primary.withValues(alpha: 0.7)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Lampirkan file (maks. 10 MB)',
                      onPressed: widget.enabled && !widget.busy
                          ? _pickFiles
                          : null,
                      icon: _pickingFiles
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('chat-input-field'),
                        controller: _controller,
                        focusNode: _focus,
                        textAlignVertical: TextAlignVertical.center,
                        enabled: widget.enabled && !widget.busy,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        minLines: 1,
                        maxLines: 6,
                        onSubmitted: (_) {
                          if (!_controller.text.contains('\n')) _send();
                        },
                        decoration: InputDecoration(
                          hintText: widget.enabled
                              ? (widget.busy
                                    ? 'Menunggu jawaban…'
                                    : widget.hintText)
                              : 'Hubungkan provider untuk mulai chat',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.fromLTRB(
                            12,
                            6,
                            8,
                            6,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: widget.busy
                            ? IconButton.filled(
                                key: const ValueKey('stop'),
                                onPressed: widget.onStop,
                                tooltip: 'Stop',
                                icon: const Icon(Icons.stop_rounded, size: 21),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(38, 38),
                                  backgroundColor:
                                      theme.colorScheme.errorContainer,
                                  foregroundColor:
                                      theme.colorScheme.onErrorContainer,
                                ),
                              )
                            : IconButton.filled(
                                key: const ValueKey('send'),
                                onPressed: canSend ? _send : null,
                                tooltip: 'Kirim',
                                icon: const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 21,
                                ),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(38, 38),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.compactContext) ...[
                const SizedBox(height: 5),
                Semantics(
                  label: widget.compactingContext
                      ? 'AI sedang merangkum konteks percakapan'
                      : 'Konteks ${_formatTokens(promptTokens)} dari ${_formatTokens(widget.contextWindow)} token',
                  child: Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  value: widget.compactingContext
                                      ? null
                                      : contextPercent,
                                  color: meterColor,
                                  backgroundColor: theme
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              if (threshold < 1)
                                Positioned(
                                  left:
                                      (constraints.maxWidth * threshold) - 0.5,
                                  top: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 1,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        widget.compactingContext
                            ? 'Merangkum…'
                            : '${_formatTokens(promptTokens)} / '
                                  '${_formatTokens(widget.contextWindow)}'
                                  ' · ${(contextPercent * 100).round()}%'
                                  ' · @${(threshold * 100).round()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatTokens(int tokens) {
  if (tokens >= 1000000) {
    final millions = tokens / 1000000;
    return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}jt';
  }
  if (tokens >= 1000) {
    final thousands = tokens / 1000;
    return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}k';
  }
  return '$tokens';
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
