/// Markdown table rendering for assistant messages.
///
/// flutter_markdown_plus has no hook to customize how tables are laid out,
/// so messages are first split into segments ([splitMarkdownSegments]) and
/// each table block is rendered by [MarkdownTableView] instead: natural
/// column widths inside a horizontally scrollable container, with vertical
/// size left uncapped so long tables simply follow the chat's scrolling.
library;

import 'package:flutter/material.dart';

/// One parsed GFM-style table block.
class MarkdownTableData {
  const MarkdownTableData({
    required this.headers,
    required this.alignments,
    required this.rows,
  });

  final List<String> headers;
  final List<TextAlign> alignments;
  final List<List<String>> rows;

  int get columnCount => headers.length;
}

/// Either a plain markdown text block or a table block.
class MarkdownSegment {
  const MarkdownSegment.text(String this.text) : table = null;
  const MarkdownSegment.table(MarkdownTableData this.table) : text = null;

  final String? text;
  final MarkdownTableData? table;

  bool get isTable => table != null;
}

/// Splits [source] into text and table segments. A table starts at a line
/// containing `|` that is followed by a `|---|` delimiter row, and ends at
/// the first line without a pipe. Lines inside fenced code blocks are never
/// treated as tables.
List<MarkdownSegment> splitMarkdownSegments(String source) {
  final lines = source.split('\n');
  final segments = <MarkdownSegment>[];
  final text = <String>[];
  var inFence = false;

  void flushText() {
    if (text.isNotEmpty) {
      segments.add(MarkdownSegment.text(text.join('\n')));
      text.clear();
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    final isFence = trimmed.startsWith('```') || trimmed.startsWith('~~~');
    if (isFence) {
      inFence = !inFence;
      text.add(lines[i]);
      continue;
    }
    if (!inFence &&
        _isTableLine(trimmed) &&
        i + 1 < lines.length &&
        _isDelimiterRow(lines[i + 1].trim())) {
      flushText();
      final tableLines = <String>[lines[i]];
      var j = i + 1;
      while (j < lines.length && _isTableLine(lines[j].trim())) {
        // A table line followed by a delimiter row starts a new table
        // (adjacent tables without a blank line between them).
        if (j > i + 1 &&
            j + 1 < lines.length &&
            _isDelimiterRow(lines[j + 1].trim())) {
          break;
        }
        tableLines.add(lines[j]);
        j++;
      }
      final table = _parseTable(tableLines);
      if (table != null) {
        segments.add(MarkdownSegment.table(table));
      } else {
        text.addAll(tableLines);
      }
      i = j - 1;
      continue;
    }
    text.add(lines[i]);
  }
  flushText();
  return segments;
}

bool _isTableLine(String trimmed) =>
    trimmed.contains('|') && trimmed.replaceAll('|', '').trim().isNotEmpty;

bool _isDelimiterRow(String trimmed) {
  if (!trimmed.contains('-') || !trimmed.contains('|')) return false;
  final allowed = trimmed.replaceAll(RegExp(r'[\|\-\:\s]'), '');
  return allowed.isEmpty;
}

MarkdownTableData? _parseTable(List<String> lines) {
  final headers = _splitCells(lines[0]);
  if (headers.isEmpty) return null;
  final alignmentCells = _splitCells(lines[1]);
  final alignments = List<TextAlign>.generate(
    headers.length,
    (i) => _alignmentFor(i < alignmentCells.length ? alignmentCells[i] : ''),
    growable: false,
  );
  final rows = <List<String>>[];
  for (final line in lines.skip(2)) {
    final cells = _splitCells(line);
    if (cells.isEmpty) continue;
    // Normalize width so a ragged row cannot break the Table layout.
    final padded = List<String>.generate(
      headers.length,
      (i) => i < cells.length ? cells[i] : '',
      growable: false,
    );
    rows.add(padded);
  }
  return MarkdownTableData(
    headers: headers,
    alignments: alignments,
    rows: rows,
  );
}

TextAlign _alignmentFor(String cell) {
  final left = cell.startsWith(':');
  final right = cell.endsWith(':');
  if (left && right) return TextAlign.center;
  if (right) return TextAlign.right;
  return TextAlign.left;
}

List<String> _splitCells(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  const escapedPipe = '\u0001';
  s = s.replaceAll('\\|', escapedPipe);
  final cells = s
      .split('|')
      .map((c) => _cleanCell(c.replaceAll(escapedPipe, '|')))
      .toList();
  // Drop the trailing empty cell produced by a line ending in '|'.
  while (cells.isNotEmpty && cells.last.isEmpty) {
    cells.removeLast();
  }
  return cells;
}

/// Strips the common inline markdown so cells stay plain text.
String _cleanCell(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
  s = s.replaceAll('**', '').replaceAll('__', '');
  s = s.replaceAll('`', '');
  s = s.replaceAll('<br>', ' ').replaceAll('<br/>', ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Renders one [MarkdownTableData]: the table keeps its natural column
/// widths (no squeezing) inside a horizontally scrollable container, and
/// grows vertically without a cap so long tables simply follow the chat's
/// own scrolling. Narrow tables still fill the available width.
class MarkdownTableView extends StatelessWidget {
  const MarkdownTableView({super.key, required this.table});

  final MarkdownTableData table;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hairline = colors.outlineVariant.withValues(alpha: 0.6);

    final headStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(height: 1.4);

    // A wide cell would make its column enormous; cap the column so long
    // text wraps instead of stretching the scroll far off screen.
    Widget cell(String text, TextAlign align, TextStyle? style) =>
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(text, style: style, textAlign: align),
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hairline),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              // Fill the bubble width when the table is narrower than it.
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Table(
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder.all(color: hairline),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                    ),
                    children: [
                      for (var i = 0; i < table.columnCount; i++)
                        cell(table.headers[i], table.alignments[i], headStyle),
                    ],
                  ),
                  for (final row in table.rows)
                    TableRow(
                      children: [
                        for (var i = 0; i < table.columnCount; i++)
                          cell(row[i], table.alignments[i], bodyStyle),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
