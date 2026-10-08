import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sibermobile/app/widgets/markdown_table.dart';

void main() {
  group('splitMarkdownSegments', () {
    test('splits text before, table, and text after', () {
      const source = 'Sebelum tabel.\n\n'
          '| Nama | Nilai |\n'
          '| --- | :---: |\n'
          '| a | 1 |\n'
          '| b | 2 |\n'
          '\nSetelah tabel.';

      final segments = splitMarkdownSegments(source);

      expect(segments, hasLength(3));
      expect(segments[0].isTable, isFalse);
      expect(segments[0].text, contains('Sebelum tabel.'));
      expect(segments[1].isTable, isTrue);
      final table = segments[1].table!;
      expect(table.headers, ['Nama', 'Nilai']);
      expect(table.alignments[1], TextAlign.center);
      expect(table.rows, hasLength(2));
      expect(table.rows[0], ['a', '1']);
      expect(segments[2].text, contains('Setelah tabel.'));
    });

    test('multiple consecutive tables become separate segments', () {
      const source = '| A | B |\n| --- | --- |\n| 1 | 2 |\n'
          '| C | D |\n| --- | --- |\n| 3 | 4 |';

      final segments = splitMarkdownSegments(source);

      expect(segments.where((s) => s.isTable), hasLength(2));
    });

    test('pipes inside code fences are not tables', () {
      const source = 'Contoh:\n'
          '```dart\n'
          'final x = a | b;\n'
          'final y = c | d;\n'
          '```\n'
          'Selesai.';

      final segments = splitMarkdownSegments(source);

      expect(segments.any((s) => s.isTable), isFalse);
    });

    test('single pipe line without delimiter row stays text', () {
      const source = 'halo | dunia\nlanjut';

      final segments = splitMarkdownSegments(source);

      expect(segments.any((s) => s.isTable), isFalse);
    });

    test('inline markdown is stripped from cells', () {
      const source = '| Kolom |\n| --- |\n| **tebal** dan `kode` |';

      final table = splitMarkdownSegments(source).first.table!;

      expect(table.rows[0][0], 'tebal dan kode');
    });

    test('ragged rows are padded to the header width', () {
      const source = '| A | B | C |\n| --- | --- | --- |\n| satu |';

      final table = splitMarkdownSegments(source).first.table!;

      expect(table.rows[0], ['satu', '', '']);
    });

    test('message without tables returns a single text segment', () {
      final segments = splitMarkdownSegments('hanya teks biasa');

      expect(segments, hasLength(1));
      expect(segments[0].isTable, isFalse);
    });
  });

  group('MarkdownTableView', () {
    Widget wrap(Widget child) =>
        MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

    testWidgets('renders one table inside a horizontal scroll view',
        (tester) async {
      const table = MarkdownTableData(
        headers: ['Tool', 'Izin'],
        alignments: [TextAlign.left, TextAlign.left],
        rows: [
          ['wifi_scan', 'Location'],
          ['cell_scan', 'Location + Phone'],
        ],
      );

      await tester.pumpWidget(wrap(const MarkdownTableView(table: table)));

      // Header and body live in ONE table, so columns always line up.
      expect(find.byType(Table), findsOneWidget);
      final scroll = find.byType(SingleChildScrollView);
      expect(scroll, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
      expect(find.text('wifi_scan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long table grows vertically with no internal cap',
        (tester) async {
      final table = MarkdownTableData(
        headers: const ['Kolom A', 'Kolom B'],
        alignments: const [TextAlign.left, TextAlign.left],
        rows: List.generate(40, (i) => ['baris-$i', 'nilai-$i']),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MarkdownTableView(table: table),
              ),
            ),
          ),
        ),
      );

      // The view is taller than the 600px test surface: no internal vertical
      // scrolling is applied, the chat (outer view) handles it.
      final view = tester.renderObject<RenderBox>(
        find.byType(MarkdownTableView),
      );
      expect(view.size.height, greaterThan(600));
      // Every row is laid out at once, including the tail.
      expect(find.text('baris-39'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide table scrolls horizontally to reveal off-screen cells',
        (tester) async {
      final wide = List.generate(
        8,
        (i) => List.generate(6, (j) => 'kolom-$i-$j'),
      );
      final table = MarkdownTableData(
        headers: List.generate(6, (j) => 'Header-$j'),
        alignments: List.filled(6, TextAlign.left),
        rows: wide,
      );

      await tester.pumpWidget(wrap(MarkdownTableView(table: table)));

      // Content is wider than the 800px test surface, so the horizontal
      // scroll range is positive and dragging right reveals the last column.
      final scrollable = find.descendant(
        of: find.byType(MarkdownTableView),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(scrollable, const Offset(-500, 0));
      await tester.pump();
      expect(find.text('Header-5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
