import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:forui/forui.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/screens/archive_screen.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test(
    'archive browser creates implicit directories and sorts folders first',
    () {
      const entries = [
        ArchiveEntry(path: 'z.txt', isDirectory: false, size: 2),
        ArchiveEntry(path: 'Pictures/photo.jpg', isDirectory: false, size: 10),
        ArchiveEntry(path: 'a.txt', isDirectory: false, size: 1),
      ];

      final root = visibleArchiveEntries(entries, '');
      expect(root.map((entry) => entry.name), ['Pictures', 'a.txt', 'z.txt']);
      expect(root.first.isDirectory, isTrue);

      final pictures = visibleArchiveEntries(entries, 'Pictures');
      expect(pictures.single.name, 'photo.jpg');
      expect(pictures.single.size, 10);
    },
  );

  test('name sorting uses Chinese pinyin and supports all sort columns', () {
    final entries = [
      ArchiveEntry(
        path: '中目录',
        isDirectory: true,
        modified: DateTime(2026, 1, 2),
      ),
      ArchiveEntry(
        path: '阿.txt',
        isDirectory: false,
        size: 20,
        packedSize: 5,
        modified: DateTime(2026, 1, 3),
      ),
      ArchiveEntry(
        path: '波.txt',
        isDirectory: false,
        size: 10,
        packedSize: 8,
        modified: DateTime(2026, 1, 1),
      ),
    ];

    expect(visibleArchiveEntries(entries, '').map((entry) => entry.name), [
      '中目录',
      '阿.txt',
      '波.txt',
    ]);
    expect(
      visibleArchiveEntries(
        entries,
        '',
        sort: const ArchiveSort(
          column: ArchiveSortColumn.name,
          direction: ArchiveSortDirection.ascending,
        ),
      ).map((entry) => entry.name),
      ['阿.txt', '波.txt', '中目录'],
    );
    expect(
      visibleArchiveEntries(
        entries,
        '',
        sort: const ArchiveSort(
          column: ArchiveSortColumn.size,
          direction: ArchiveSortDirection.descending,
        ),
      ).map((entry) => entry.name),
      ['阿.txt', '波.txt', '中目录'],
    );
    expect(
      visibleArchiveEntries(
        entries,
        '',
        sort: const ArchiveSort(
          column: ArchiveSortColumn.packedSize,
          direction: ArchiveSortDirection.ascending,
        ),
      ).map((entry) => entry.name),
      ['中目录', '阿.txt', '波.txt'],
    );
    expect(
      visibleArchiveEntries(
        entries,
        '',
        sort: const ArchiveSort(
          column: ArchiveSortColumn.modified,
          direction: ArchiveSortDirection.ascending,
        ),
      ).map((entry) => entry.name),
      ['波.txt', '中目录', '阿.txt'],
    );
  });

  test('byte formatting stays compact', () {
    expect(formatBytes(null), '—');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1.00 KB');
    expect(formatBytes(12 * 1024), '12.0 KB');
  });

  testWidgets('breadcrumb shows home and navigates to any parent level', (
    tester,
  ) async {
    const listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [
        ArchiveEntry(
          path: 'Projects/Docs/readme.txt',
          isDirectory: false,
          size: 42,
        ),
      ],
    );
    await _pumpArchiveScreen(tester, listing);

    expect(
      find.byKey(const ValueKey('archive-breadcrumb-root')),
      findsOneWidget,
    );
    expect(find.byIcon(FLucideIcons.house), findsOneWidget);

    await _doubleTap(tester, find.text('Projects'));
    expect(
      find.byKey(const ValueKey('archive-breadcrumb-Projects')),
      findsOneWidget,
    );
    expect(find.text('/'), findsOneWidget);

    await _doubleTap(tester, find.text('Docs'));
    expect(
      find.byKey(const ValueKey('archive-breadcrumb-Projects/Docs')),
      findsOneWidget,
    );
    expect(find.text('/'), findsNWidgets(2));
    expect(find.text('readme.txt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('archive-breadcrumb-Projects')));
    await tester.pump();
    expect(find.text('Docs'), findsNWidgets(1));
    expect(
      find.byKey(const ValueKey('archive-breadcrumb-Projects/Docs')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('archive-breadcrumb-root')));
    await tester.pump();
    expect(find.text('Projects'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('archive-breadcrumb-Projects')),
      findsNothing,
    );
  });

  testWidgets('dragging a header divider resizes aligned content columns', (
    tester,
  ) async {
    final listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [
        ArchiveEntry(
          path: 'report.txt',
          isDirectory: false,
          size: 42,
          packedSize: 21,
          modified: DateTime(2026, 8, 27, 12, 30),
        ),
      ],
    );
    await _pumpArchiveScreen(tester, listing);

    final sizeHeaderBefore = tester.getTopLeft(find.text('大小')).dx;
    final sizeValueBefore = tester.getTopLeft(find.text('42 B')).dx;
    expect(sizeValueBefore, moreOrLessEquals(sizeHeaderBefore));
    expect(
      tester.getTopLeft(find.text('21 B')).dx,
      moreOrLessEquals(tester.getTopLeft(find.text('压缩后')).dx),
    );
    expect(
      tester.getTopLeft(find.text('2026-08-27 12:30')).dx,
      moreOrLessEquals(tester.getTopLeft(find.text('修改时间')).dx),
    );

    await tester.drag(
      find.byKey(const ValueKey('archive-column-resizer-0')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();

    final sizeHeaderAfter = tester.getTopLeft(find.text('大小')).dx;
    final sizeValueAfter = tester.getTopLeft(find.text('42 B')).dx;
    expect(
      sizeHeaderAfter - sizeHeaderBefore,
      moreOrLessEquals(40, epsilon: 0.1),
    );
    expect(sizeValueAfter, moreOrLessEquals(sizeHeaderAfter));
  });

  testWidgets('dark header uses a visible light-gray border', (tester) async {
    const listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [],
    );
    await _pumpArchiveScreen(tester, listing, dark: true);

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('archive-table-header-surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    final colors = FTheme.neutral.dark.desktop.colors;
    expect(border.top.color, colors.foreground.withValues(alpha: 0.28));
  });

  testWidgets('clicking a header cycles ascending, descending, and default', (
    tester,
  ) async {
    const listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [
        ArchiveEntry(path: '中目录', isDirectory: true),
        ArchiveEntry(path: '阿.txt', isDirectory: false),
        ArchiveEntry(path: '波.txt', isDirectory: false),
      ],
    );
    await _pumpArchiveScreen(tester, listing);

    _expectVerticalOrder(tester, ['中目录', '阿.txt', '波.txt']);
    expect(
      find.byKey(const ValueKey('archive-sort-indicator-name')),
      findsNothing,
    );

    await tester.tap(find.text('名称'));
    await tester.pump();
    _expectVerticalOrder(tester, ['阿.txt', '波.txt', '中目录']);
    expect(find.byIcon(FLucideIcons.chevronUp), findsOneWidget);

    await tester.tap(find.text('名称'));
    await tester.pump();
    _expectVerticalOrder(tester, ['中目录', '波.txt', '阿.txt']);
    expect(find.byIcon(FLucideIcons.chevronDown), findsOneWidget);

    await tester.tap(find.text('名称'));
    await tester.pump();
    _expectVerticalOrder(tester, ['中目录', '阿.txt', '波.txt']);
    expect(
      find.byKey(const ValueKey('archive-sort-indicator-name')),
      findsNothing,
    );
  });

  testWidgets('double-click previews a file with its complete archive path', (
    tester,
  ) async {
    const listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [
        ArchiveEntry(path: 'Docs/readme.txt', isDirectory: false, size: 12),
      ],
    );
    ArchiveEntry? previewed;
    await _pumpArchiveScreen(
      tester,
      listing,
      onPreviewEntry: (entry) => previewed = entry,
    );

    await _doubleTap(tester, find.text('Docs'));
    await _doubleTap(tester, find.text('readme.txt'));
    expect(previewed?.path, 'Docs/readme.txt');
  });

  testWidgets('right-click menu extracts and deletes an archive entry', (
    tester,
  ) async {
    const listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [ArchiveEntry(path: 'report.txt', isDirectory: false, size: 12)],
    );
    ArchiveEntry? extracted;
    ArchiveEntry? deleted;
    await _pumpArchiveScreen(
      tester,
      listing,
      onExtractEntry: (entry) => extracted = entry,
      onDeleteEntry: (entry) => deleted = entry,
    );

    await tester.tap(
      find.byKey(const ValueKey('archive-row-report.txt')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('解压该文件'), findsOneWidget);
    expect(find.text('删除压缩包内文件'), findsOneWidget);

    await tester.tap(find.text('解压该文件'));
    await tester.pumpAndSettle();
    expect(extracted?.path, 'report.txt');

    await tester.tap(
      find.byKey(const ValueKey('archive-row-report.txt')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除压缩包内文件'));
    await tester.pumpAndSettle();
    expect(deleted?.path, 'report.txt');
  });

  testWidgets('multi-select mode exposes checkboxes and batch actions', (
    tester,
  ) async {
    const listing = ArchiveListing(
      archivePath: '/tmp/example.zip',
      entries: [
        ArchiveEntry(path: 'one.txt', isDirectory: false),
        ArchiveEntry(path: 'two.txt', isDirectory: false),
      ],
    );
    var extracted = <ArchiveEntry>[];
    var deleted = <ArchiveEntry>[];
    await _pumpArchiveScreen(
      tester,
      listing,
      onExtractEntries: (entries) async {
        extracted = entries;
        return true;
      },
      onDeleteEntries: (entries) async {
        deleted = entries;
        return true;
      },
    );

    expect(find.byType(FCheckbox), findsNothing);
    await tester.tap(find.byKey(const ValueKey('archive-selection-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(FCheckbox), findsNWidgets(2));
    expect(find.text('已选择 0 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('archive-select-one.txt')));
    await tester.pump();
    expect(find.text('已选择 1 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('archive-batch-extract')));
    await tester.pumpAndSettle();
    expect(extracted.map((entry) => entry.path), ['one.txt']);
    expect(find.text('已选择 0 项'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选择 2 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('archive-batch-delete')));
    await tester.pumpAndSettle();
    expect(deleted.map((entry) => entry.path), ['one.txt', 'two.txt']);

    await tester.tap(find.byKey(const ValueKey('archive-selection-done')));
    await tester.pumpAndSettle();
    expect(find.byType(FCheckbox), findsNothing);
    expect(find.text('多选'), findsOneWidget);
  });
}

void _expectVerticalOrder(WidgetTester tester, List<String> labels) {
  final positions = labels
      .map((label) => tester.getTopLeft(find.text(label)).dy)
      .toList();
  expect(positions, orderedEquals(positions.toList()..sort()));
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _pumpArchiveScreen(
  WidgetTester tester,
  ArchiveListing listing, {
  bool dark = false,
  ValueChanged<ArchiveEntry>? onPreviewEntry,
  ValueChanged<ArchiveEntry>? onExtractEntry,
  ValueChanged<ArchiveEntry>? onDeleteEntry,
  ArchiveEntriesCallback? onExtractEntries,
  ArchiveEntriesCallback? onDeleteEntries,
}) async {
  final theme = dark
      ? FTheme.neutral.dark.desktop
      : FTheme.neutral.light.desktop;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.toApproximateMaterialTheme(),
      home: FTheme(
        data: theme,
        child: Material(
          child: ArchiveScreen(
            listing: listing,
            enabled: true,
            onClose: () {},
            onExtract: () {},
            onTest: () {},
            onPreviewEntry: onPreviewEntry ?? (_) {},
            onExtractEntry: onExtractEntry ?? (_) {},
            onDeleteEntry: onDeleteEntry ?? (_) {},
            onExtractEntries: onExtractEntries ?? (_) async => true,
            onDeleteEntries: onDeleteEntries ?? (_) async => true,
          ),
        ),
      ),
    ),
  );
}
