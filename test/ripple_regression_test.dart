import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/app.dart';
import 'package:jucier/application/settings_page_transition.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/platform/archive_file_association_service.dart';
import 'package:jucier/platform/file_access_service.dart';
import 'package:jucier/screens/settings_screen.dart';

void main() {
  testWidgets('settings keeps loaded rows throughout opening and closing', (
    tester,
  ) async {
    final associations = _DelayedAssociationService();
    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: _FakeFileAccessService(
          initialStatus: const FileAccessStatus(requested: true, granted: true),
        ),
        archiveFileAssociationService: associations,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pump();
    final settingsState = tester.state(find.byType(SettingsScreen));
    await tester.pump(const Duration(milliseconds: 48));
    await tester.pump();
    final associationCard = find.byKey(
      const ValueKey('settings-file-association-card'),
    );
    final finderCard = find.byKey(const ValueKey('settings-finder-menu-card'));
    expect(associationCard, findsOneWidget);
    final finderRect = tester.getRect(finderCard);

    void expectStableRows() {
      expect(tester.state(find.byType(SettingsScreen)), same(settingsState));
      expect(associations.statusCalls, 1);
      expect(associationCard, findsOneWidget);
      expect(tester.getRect(finderCard), finderRect);
    }

    // Include the frame where the outgoing home page is removed from Stack.
    for (var frame = 0; frame < 34; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expectStableRows();
    }
    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pump();
    expectStableRows();
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expectStableRows();
    }
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(associations.statusCalls, 1);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'settings covers returning workspace (${dark ? 'dark' : 'light'})',
      (tester) async {
        final theme = dark
            ? FTheme.neutral.dark.desktop
            : FTheme.neutral.light.desktop;
        final open = ValueNotifier(true);
        addTearDown(open.dispose);
        final boundaryKey = GlobalKey();
        const workspaceColor = Color(0xFFFF0000);

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: FTheme(
              data: theme,
              child: RepaintBoundary(
                key: boundaryKey,
                child: ColoredBox(
                  color: theme.colors.background,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: open,
                    builder: (context, settingsOpen, _) =>
                        SettingsPageTransition(
                          child: settingsOpen
                              ? const SizedBox.expand(
                                  key: ValueKey('settings-page'),
                                )
                              : const ColoredBox(
                                  key: ValueKey('home-page'),
                                  color: workspaceColor,
                                ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final coveredPixel = await _centerPixel(tester, boundaryKey);

        open.value = false;
        await tester.pump();
        // The center is still inside the shrinking settings surface while the
        // workspace fades in. Its pixels must not bleed through that surface.
        for (var frame = 0; frame < 2; frame++) {
          await tester.pump(const Duration(milliseconds: 80));
          expect(await _centerPixel(tester, boundaryKey), coveredPixel);
        }
        await tester.pumpAndSettle();
        expect(await _centerPixel(tester, boundaryKey), [255, 0, 0, 255]);
      },
    );
  }

  testWidgets('ripple ring fully hides after settings closes', (tester) async {
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(
        requested: true,
        granted: true,
        directory: '/Users/example',
      ),
    );

    await tester.pumpWidget(
      JucierApp(engine: _UnusedArchiveEngine(), fileAccessService: permissions),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(_rippleProgress(tester), 1);

    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    // The AnimatedSwitcher detaches the outgoing settings entry before its
    // final animation tick is built, so the ripple progress must be driven to
    // zero by the transition status rather than left a fraction above it.
    expect(_rippleProgress(tester), 0);
  });
}

Future<List<int>> _centerPixel(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
      return List<int>.generate(
        4,
        (channel) => bytes.getUint8(offset + channel),
      );
    } finally {
      image.dispose();
    }
  }))!;
}

double? _rippleProgress(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    if (paint.painter.runtimeType.toString().contains('Ripple')) {
      return (paint.painter as dynamic).progress as double;
    }
  }
  return null;
}

class _FakeFileAccessService implements FileAccessService {
  _FakeFileAccessService({required this.initialStatus});

  final FileAccessStatus initialStatus;

  @override
  Future<FileAccessStatus> status() async => initialStatus;

  @override
  Future<FileAccessStatus> requestAccess() async => initialStatus;

  @override
  void setOpenSettingsHandler(VoidCallback? handler) {}
}

class _UnusedArchiveEngine implements ArchiveEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedAssociationService implements ArchiveFileAssociationService {
  int statusCalls = 0;

  @override
  Future<ArchiveFileAssociationStatus> status(List<String> extensions) async {
    statusCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 32));
    return const ArchiveFileAssociationStatus(available: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
