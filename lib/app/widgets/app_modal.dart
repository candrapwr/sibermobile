/// The one modal/dialog frame used across the app.
///
/// Flat styling (8px corners, tight paddings, hairline separators) with a
/// fixed three-part layout: header (icon + title + subtitle + close),
/// scrollable content, and a footer that is ALWAYS visible — long content
/// scrolls inside instead of pushing the buttons off-screen.
library;

import 'package:flutter/material.dart';

class AppModal extends StatelessWidget {
  const AppModal({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.destructive = false,
    this.onClose,
    this.footer,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
    this.maxWidth = 420,
  });

  /// Short header title (rendered small-caps style, not a big title).
  final String title;

  /// Optional one-line subtitle under the title.
  final String? subtitle;

  /// Small leading icon; tinted [Colors.error] when [destructive].
  final IconData? icon;

  /// Called when the X button is pressed. When null, no X is shown.
  final VoidCallback? onClose;

  /// Modal body; scrollable, safely capped at 62% of the screen height.
  final Widget child;

  /// Bottom action row — pinned, never scrolled away.
  final Widget? footer;

  final bool destructive;
  final EdgeInsetsGeometry contentPadding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = destructive ? colors.error : colors.primary;
    final hairline = colors.outlineVariant.withValues(alpha: 0.6);

    return Dialog(
      backgroundColor: colors.surfaceContainerLow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(icon, size: 15, color: tint),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: 'Tutup',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: hairline),

            // ── Content (scrollable, capped) ──────────────────────────────
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: SingleChildScrollView(
                  padding: contentPadding,
                  child: child,
                ),
              ),
            ),

            // ── Footer (always visible) ───────────────────────────────────
            if (footer != null) ...[
              Divider(height: 1, thickness: 1, color: hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Standard footer row: [left] spacer + actions aligned right.
  static Widget actions(BuildContext context, List<Widget> actions) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        actions[i],
      ],
    ],
  );
}
