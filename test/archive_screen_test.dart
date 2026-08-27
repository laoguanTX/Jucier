import 'package:flutter_test/flutter_test.dart';
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
    final theme = FTheme.neutral.light.desktop;

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
            ),
          ),
        ),
      ),
    );

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
}

Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
