import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/platform/file_access_service.dart';
import 'package:jucier/platform/theme_preference_store.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

void main() {
  testWidgets('create archive opens the reusable compose file tree', (
    tester,
  ) async {
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(
        requested: true,
        granted: true,
        directory: '/Users/example',
      ),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: permissions,
        themePreferenceStore: _FakeThemePreferenceStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FButton, '创建压缩包'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('archive-compose-page')), findsOneWidget);
    expect(find.text('尚未导入文件'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });

  testWidgets('home header keeps the title centered without overlapping the '
      'right-aligned settings button', (tester) async {
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(
        requested: true,
        granted: true,
        directory: '/Users/example',
      ),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: permissions,
        themePreferenceStore: _FakeThemePreferenceStore(),
      ),
    );
    await tester.pumpAndSettle();

    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    final title = tester.getRect(find.text('Jucier'));
    final settingsButton = tester.getRect(find.widgetWithText(FButton, '设置'));

    // The brand title is horizontally centered in the window.
    expect((title.center.dx - window.width / 2).abs(), lessThan(1));

    // The settings button hugs the right edge of the content area.
    expect((window.width - settingsButton.right).abs(), lessThan(25));

    // Title and button share the same vertical band.
    expect((title.center.dy - settingsButton.center.dy).abs(), lessThan(1));

    // No horizontal overlap between the title and the settings button.
    expect(settingsButton.left, greaterThan(title.right));
  });

  testWidgets(
    'macOS reserves 50px at the top for the floating traffic lights',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final permissions = _FakeFileAccessService(
          initialStatus: const FileAccessStatus(
            requested: true,
            granted: true,
            directory: '/Users/example',
          ),
        );

        await tester.pumpWidget(
          JucierApp(
            engine: _UnusedArchiveEngine(),
            fileAccessService: permissions,
            themePreferenceStore: _FakeThemePreferenceStore(),
          ),
        );
        await tester.pumpAndSettle();

        final contentPadding = tester.widget<Padding>(
          find.byKey(const ValueKey('window-content-padding')),
        );
        expect(contentPadding.padding, const EdgeInsets.only(top: 26));

        // The home page (including its own 24px padding) must start below the
        // 50px traffic-light band.
        final title = tester.getRect(find.text('Jucier'));
        expect(title.top, greaterThanOrEqualTo(50));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
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

class _FakeThemePreferenceStore implements ThemePreferenceStore {
  @override
  Future<ThemeMode> load() async => ThemeMode.system;

  @override
  Future<void> save(ThemeMode mode) async {}
}
