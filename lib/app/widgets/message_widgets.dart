import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat_items.dart';
import '../theme/app_theme.dart';
import 'markdown_table.dart';

class UserBubbleView extends StatelessWidget {
  const UserBubbleView({super.key, required this.item});

  final UserBubble item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bubbleColor = colors.primaryContainer.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.88 : 0.9,
    );
    final bubbleText = colors.onPrimaryContainer;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(42, 4, 4, 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          border: Border.all(color: bubbleText.withValues(alpha: 0.12)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.text.isNotEmpty)
              SelectableText(
                item.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: bubbleText,
                  height: 1.45,
                ),
              ),
            if (item.text.isNotEmpty && item.attachmentNames.isNotEmpty)
              const SizedBox(height: 7),
            for (final name in item.attachmentNames)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: bubbleText.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      color: bubbleText,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: bubbleText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AssistantBubbleView extends StatelessWidget {
  const AssistantBubbleView({super.key, required this.item});

  final AssistantBubble item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: SizedBox(
        width: double.infinity,
        child: _AssistantMarkdown(data: item.text),
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = splitMarkdownSegments(data);

    Widget markdown(String text) => MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      onTapLink: (_, href, _) => _openMarkdownLink(href),
      styleSheet: _sheetFor(theme),
    );

    // Without tables, keep the single MarkdownBody (cheaper than a Column).
    if (!segments.any((s) => s.isTable)) {
      return markdown(data);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final segment in segments)
          if (segment.isTable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: MarkdownTableView(table: segment.table!),
            )
          else if (segment.text!.trim().isNotEmpty)
            markdown(segment.text!),
      ],
    );
  }

  MarkdownStyleSheet _sheetFor(ThemeData theme) {
    final colors = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.48);
    final codeBackground = colors.surfaceContainerHighest.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.75 : 0.6,
    );

    return MarkdownStyleSheet(
      p: body,
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.25,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
      h4: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      strong: body?.copyWith(fontWeight: FontWeight.w800),
      em: body?.copyWith(fontStyle: FontStyle.italic),
      a: body?.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary.withValues(alpha: 0.55),
      ),
      blockquote: body?.copyWith(color: colors.onSurfaceVariant),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 7, 9, 7),
      blockquoteDecoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
        borderRadius: BorderRadius.circular(8),
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        fontSize: 12.5,
        height: 1.5,
        color: colors.onSurface,
        backgroundColor: codeBackground,
      ),
      codeblockPadding: const EdgeInsets.all(10),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      listBullet: body?.copyWith(
        color: colors.primary,
        fontWeight: FontWeight.w800,
      ),
      tableHead: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      tableBody: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      tableBorder: TableBorder.all(
        color: colors.outlineVariant.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      pPadding: const EdgeInsets.only(bottom: 4),
      h1Padding: const EdgeInsets.only(top: 6, bottom: 5),
      h2Padding: const EdgeInsets.only(top: 6, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 4, bottom: 3),
      blockSpacing: 6,
    );
  }

  Future<void> _openMarkdownLink(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class AiThinkingIndicator extends StatefulWidget {
  const AiThinkingIndicator({super.key, required this.label});

  final String label;

  @override
  State<AiThinkingIndicator> createState() => _AiThinkingIndicatorState();
}

class _AiThinkingIndicatorState extends State<AiThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _animation,
            builder: (context, _) => Row(
              children: List.generate(3, (index) {
                final wave =
                    (math.sin((_animation.value * math.pi * 2) - index * 0.8) +
                        1) /
                    2;
                return Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(
                      alpha: 0.3 + wave * 0.7,
                    ),
                  ),
                  transform: Matrix4.translationValues(0, -2 * wave, 0),
                );
              }),
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                widget.label,
                key: ValueKey(widget.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SystemNoticeView extends StatelessWidget {
  const SystemNoticeView({super.key, required this.item});

  final SystemNotice item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.isError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            item.isError
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class ToolCallBlockView extends StatelessWidget {
  const ToolCallBlockView({
    super.key,
    required this.item,
    this.onSaveFile,
    this.resolveFile,
    this.resolveImageFile,
  });

  final ToolCallBlock item;
  final Future<Uri?> Function(SharedFileInfo file)? onSaveFile;

  /// Resolves a shared file to its absolute sandbox path for image previews.
  final File? Function(SharedFileInfo file)? resolveFile;

  /// Resolves a raw tool-argument path (e.g. analyze_image's `image`) to its
  /// sandbox file, for the live scanning preview.
  final File? Function(String path)? resolveImageFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _toolVisual(item.status, theme);
    final sharedFile = item.sharedFile;
    final running =
        item.status == ToolCallStatus.running ||
        item.status == ToolCallStatus.pending;
    final failed = item.status == ToolCallStatus.error;
    final blockMargin = const EdgeInsets.fromLTRB(10, 3, 10, 3);

    // File delivery shows the card alone — no tool-call chrome. Failures
    // still render as a normal block so the error stays visible.
    if (item.name == 'send_file_to_user' && !failed) {
      if (sharedFile == null || running) return const SizedBox.shrink();
      return Padding(
        padding: blockMargin,
        child: _SharedFileCard(
          file: sharedFile,
          onSave: onSaveFile == null
              ? null
              : () => _saveSharedFile(context, sharedFile),
          resolveFile: resolveFile,
        ),
      );
    }

    // Live image-tool animations replace the whole block while running;
    // the finished block (name + status) returns once the tool completes.
    if (running && item.name == 'analyze_image') {
      return Padding(
        padding: blockMargin,
        child: _ScanningImagePreview(
          source: _toolArgs(item)['image']?.toString(),
          resolveImageFile: resolveImageFile,
        ),
      );
    }
    if (running && item.name == 'generate_image') {
      return Padding(
        padding: blockMargin,
        child: const _GeneratingImagePlaceholder(),
      );
    }

    return Container(
      margin: blockMargin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: visual.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (running)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: visual.color,
                  ),
                )
              else
                Icon(visual.icon, color: visual.color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                visual.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: visual.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (sharedFile != null && !running) ...[
            const SizedBox(height: 8),
            _SharedFileCard(
              file: sharedFile,
              onSave: onSaveFile == null
                  ? null
                  : () => _saveSharedFile(context, sharedFile),
              resolveFile: resolveFile,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _saveSharedFile(
    BuildContext context,
    SharedFileInfo file,
  ) async {
    try {
      final saved = await onSaveFile!(file);
      if (!context.mounted || saved == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('File berhasil disimpan ke perangkat.'),
          ),
        );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            content: Text(
              'File gagal disimpan: $error',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        );
    }
  }
}

/// Parses a tool block's JSON arguments (best effort, empty on failure).
Map<String, dynamic> _toolArgs(ToolCallBlock item) {
  try {
    final decoded = jsonDecode(item.arguments);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {}
  return const {};
}

/// Live preview while `analyze_image` runs: the target image with a
/// sweeping scan line and corner brackets. Falls back to a dark scanning
/// panel when the source cannot be displayed (missing file, exotic format).
class _ScanningImagePreview extends StatefulWidget {
  const _ScanningImagePreview({required this.source, this.resolveImageFile});

  final String? source;
  final File? Function(String path)? resolveImageFile;

  @override
  State<_ScanningImagePreview> createState() => _ScanningImagePreviewState();
}

class _ScanningImagePreviewState extends State<_ScanningImagePreview>
    with SingleTickerProviderStateMixin {
  // Created in initState (not a late field read during build): starting a
  // ticker mid-build is fragile under rebuild storms (keyboard resizes).
  late final AnimationController _scan;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Widget? _buildImage() {
    final src = widget.source?.trim();
    if (src == null || src.isEmpty) return null;
    Widget fallback(BuildContext _, Object _, StackTrace? _) =>
        const SizedBox.shrink();
    // Contain with a height cap: the whole image stays visible and sizes
    // the scanning box by its natural aspect ratio.
    Widget full(ImageProvider provider) => ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 380),
      child: Image(
        image: provider,
        width: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: fallback,
      ),
    );
    if (src.startsWith('data:image/')) {
      final comma = src.indexOf(',');
      if (comma < 0) return null;
      try {
        final bytes = base64Decode(src.substring(comma + 1));
        return full(MemoryImage(bytes));
      } catch (_) {
        return null;
      }
    }
    final lower = src.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return full(NetworkImage(src));
    }
    final file = widget.resolveImageFile?.call(src);
    if (file == null) return null;
    return full(FileImage(file));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = _buildImage();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: colors.surfaceContainerHighest,
        child: Stack(
          // The image is the sizing (non-positioned) child; overlays fill
          // whatever height its aspect ratio produces. The no-image
          // fallback keeps the fixed panel.
          children: [
            if (image != null)
              image
            else
              SizedBox(
                height: 210,
                width: double.infinity,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_search_rounded,
                        size: 30,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Memindai gambar…',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            // Slight dark veil so the sweep reads on bright images.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.black.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.22),
                    ],
                  ),
                ),
              ),
            ),
            // The sweeping scan band + bright center line.
            AnimatedBuilder(
              animation: _scan,
              builder: (context, _) {
                final dy = -1.0 + 2.0 * _scan.value;
                return Align(
                  alignment: Alignment(0, dy.clamp(-1.0, 1.0)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.primary.withValues(alpha: 0.0),
                              colors.primary.withValues(alpha: 0.32),
                              colors.primary.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        height: 2,
                        color: colors.primary.withValues(alpha: 0.95),
                      ),
                    ],
                  ),
                );
              },
            ),
            // Corner brackets for the "scanner" look.
            _bracket(colors, alignment: Alignment.topLeft),
            _bracket(colors, alignment: Alignment.topRight),
            _bracket(colors, alignment: Alignment.bottomLeft),
            _bracket(colors, alignment: Alignment.bottomRight),
          ],
        ),
      ),
    );
  }

  Widget _bracket(ColorScheme colors, {required Alignment alignment}) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 18,
        height: 18,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: alignment.y < 0
                  ? BorderSide(color: colors.primary, width: 2)
                  : BorderSide.none,
              bottom: alignment.y > 0
                  ? BorderSide(color: colors.primary, width: 2)
                  : BorderSide.none,
              left: alignment.x < 0
                  ? BorderSide(color: colors.primary, width: 2)
                  : BorderSide.none,
              right: alignment.x > 0
                  ? BorderSide(color: colors.primary, width: 2)
                  : BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// Live placeholder while `generate_image` runs: a shimmering image frame
/// with a pulsing sparkle. Replaced by the normal finished tool card (with
/// its inline image preview) once the tool completes.
class _GeneratingImagePlaceholder extends StatefulWidget {
  const _GeneratingImagePlaceholder();

  @override
  State<_GeneratingImagePlaceholder> createState() =>
      _GeneratingImagePlaceholderState();
}

class _GeneratingImagePlaceholderState
    extends State<_GeneratingImagePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = colors.surfaceContainerHighest;
    final highlight = colors.primary.withValues(alpha: 0.22);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            final t = _shimmer.value;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.0 + 2.0 * t, -0.6),
                  end: Alignment(0.0 + 2.0 * t, 0.6),
                  colors: [base, highlight, base],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 1.0 + 0.12 * math.sin(t * 2 * math.pi).abs(),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 30,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Menghasilkan gambar…',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SharedFileCard extends StatelessWidget {
  const _SharedFileCard({
    required this.file,
    required this.onSave,
    this.resolveFile,
  });

  final SharedFileInfo file;
  final VoidCallback? onSave;

  /// Optional resolver for inline image previews (absolute sandbox path).
  final File? Function(SharedFileInfo file)? resolveFile;

  static const _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
  };

  bool get _isImage =>
      file.mimeType.startsWith('image/') ||
      _imageExtensions.any(file.name.toLowerCase().endsWith);

  File? get _imageSource => _isImage ? resolveFile?.call(file) : null;

  void _openFullScreen(BuildContext context, File source) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: _FullScreenImage(name: file.name, source: source),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final source = _imageSource;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          if (source != null) ...[
            GestureDetector(
              onTap: () => _openFullScreen(context, source),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.file(
                  source,
                  width: double.infinity,
                  height: 230,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Icon(
                _isImage
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                color: colors.primary,
                size: 21,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatFileSize(file.bytes)} · siap disimpan',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onSave,
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text('Simpan'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Zoomable fullscreen viewer for shared images.
class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.name, required this.source});

  final String name;
  final File source;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap anywhere (outside the pinch area) closes; the pop button gives
      // an explicit target too.
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.file(
                  source,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 56,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

({IconData icon, Color color, String label}) _toolVisual(
  ToolCallStatus status,
  ThemeData theme,
) {
  return switch (status) {
    ToolCallStatus.pending => (
      icon: Icons.schedule_rounded,
      color: theme.colorScheme.primary,
      label: 'Menunggu',
    ),
    ToolCallStatus.running => (
      icon: Icons.sync_rounded,
      color: theme.colorScheme.primary,
      label: 'Menjalankan',
    ),
    ToolCallStatus.done => (
      icon: Icons.check_circle_outline_rounded,
      color: AppTheme.accent,
      label: 'Berhasil',
    ),
    ToolCallStatus.denied => (
      icon: Icons.block_rounded,
      color: theme.colorScheme.error,
      label: 'Ditolak',
    ),
    ToolCallStatus.error => (
      icon: Icons.error_outline_rounded,
      color: theme.colorScheme.error,
      label: 'Gagal',
    ),
  };
}
