import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/platform/file_access_service.dart';
import 'package:jucier/platform/single_entry_extraction_preference_store.dart';
import 'package:jucier/platform/theme_preference_store.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('requests file access on first launch and opens settings', (
    tester,
  ) async {
    final permissions = _FakeFileAccessService();

    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: permissions,
        themePreferenceStore: _FakeThemePreferenceStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(permissions.requestCount, 1);
    expect(find.text('macOS archive utility'), findsNothing);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('文件与文件夹访问'), findsOneWidget);
    expect(find.textContaining('/Users/example'), findsOneWidget);
    expect(find.text('授权由 macOS 系统选择器完成，Jucier 只会访问你明确选择的文件夹。'), findsNothing);

    final viewCenter = tester.getCenter(find.byType(MaterialApp));
    final appearanceCard = tester.getRect(
      find.byKey(const ValueKey('settings-appearance-card')),
    );
    final permissionCard = tester.getRect(
      find.byKey(const ValueKey('settings-permission-card')),
    );
    final actionCenter = tester.getCenter(
      find.byKey(const ValueKey('settings-permission-action')),
    );
    expect((appearanceCard.center.dx - viewCenter.dx).abs(), lessThan(1));
    expect((permissionCard.center.dx - viewCenter.dx).abs(), lessThan(1));
    expect(appearanceCard.bottom, lessThan(permissionCard.top));
    final cardsCenterY = (appearanceCard.top + permissionCard.bottom) / 2;
    expect((cardsCenterY - viewCenter.dy).abs(), lessThan(1));
    expect((actionCenter.dy - permissionCard.center.dy).abs(), lessThan(1));

    final icon = tester.widget<Icon>(
      find.byKey(const ValueKey('settings-permission-icon')),
    );
    expect(icon.size, 22);

    final backButton = find.byKey(const ValueKey('settings-back-button'));
    expect(tester.getTopLeft(backButton), const Offset(24, 24));
    expect(tester.getSize(backButton).width, lessThan(120));
  });

  testWidgets('Command-comma opens the secondary settings page', (
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('settings-circular-reveal')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('文件与文件夹访问'), findsOneWidget);
    expect(permissions.requestCount, 0);
  });

  testWidgets('native settings command opens the same page', (tester) async {
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(requested: true, granted: false),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: permissions,
        themePreferenceStore: _FakeThemePreferenceStore(),
      ),
    );
    await tester.pumpAndSettle();

    permissions.openSettingsHandler?.call();
    await tester.pumpAndSettle();

    expect(find.text('文件与文件夹访问'), findsOneWidget);
  });

  testWidgets('loads, switches, and persists the selected appearance', (
    tester,
  ) async {
    final preferences = _FakeThemePreferenceStore(ThemeMode.dark);
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(requested: true, granted: true),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: permissions,
        themePreferenceStore: preferences,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(preferences.savedModes, [ThemeMode.light]);
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('theme-mode-light')))
          .variant,
      FButtonVariant.primary,
    );
  });

  testWidgets('loads, switches, and persists the single-entry mode', (
    tester,
  ) async {
    final extractionPreferences = _FakeSingleEntryExtractionPreferenceStore(
      SingleEntryExtractionMode.selectedOnly,
    );
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(requested: true, granted: true),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: _UnusedArchiveEngine(),
        fileAccessService: permissions,
        themePreferenceStore: _FakeThemePreferenceStore(),
        singleEntryExtractionPreferenceStore: extractionPreferences,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('单文件解压/预览模式'), findsOneWidget);
    expect(find.text('仅解压所选文件或文件夹，不包含其父目录。'), findsOneWidget);
    expect(
      tester
          .widget<FButton>(
            find.byKey(const ValueKey('single-entry-mode-selectedOnly')),
          )
          .variant,
      FButtonVariant.primary,
    );

    await tester.tap(
      find.byKey(const ValueKey('single-entry-mode-preserveArchiveStructure')),
    );
    await tester.pumpAndSettle();

    expect(extractionPreferences.savedModes, [
      SingleEntryExtractionMode.preserveArchiveStructure,
    ]);
    expect(find.text('单独解压时保留压缩包中的完整父目录。'), findsOneWidget);
  });
}

class _FakeFileAccessService implements FileAccessService {
  _FakeFileAccessService({
    FileAccessStatus initialStatus = const FileAccessStatus(
      requested: false,
      granted: false,
    ),
  }) : _status = initialStatus;

  FileAccessStatus _status;
  int requestCount = 0;
  VoidCallback? openSettingsHandler;

  @override
  Future<FileAccessStatus> status() async => _status;

  @override
  Future<FileAccessStatus> requestAccess() async {
    requestCount++;
    return _status = const FileAccessStatus(
      requested: true,
      granted: true,
      directory: '/Users/example',
    );
  }

  @override
  void setOpenSettingsHandler(VoidCallback? handler) {
    openSettingsHandler = handler;
  }
}

class _UnusedArchiveEngine implements ArchiveEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeThemePreferenceStore implements ThemePreferenceStore {
  _FakeThemePreferenceStore([this.mode = ThemeMode.system]);

  ThemeMode mode;
  final List<ThemeMode> savedModes = [];

  @override
  Future<ThemeMode> load() async => mode;

  @override
  Future<void> save(ThemeMode mode) async {
    this.mode = mode;
    savedModes.add(mode);
  }
}

class _FakeSingleEntryExtractionPreferenceStore
    implements SingleEntryExtractionPreferenceStore {
  _FakeSingleEntryExtractionPreferenceStore(this.mode);

  SingleEntryExtractionMode mode;
  final List<SingleEntryExtractionMode> savedModes = [];

  @override
  Future<SingleEntryExtractionMode> load() async => mode;

  @override
  Future<void> save(SingleEntryExtractionMode mode) async {
    this.mode = mode;
    savedModes.add(mode);
  }
}
