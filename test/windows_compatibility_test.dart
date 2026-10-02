import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_path.dart';
import 'package:jucier/archive/seven_zip_engine.dart';
import 'package:jucier/platform/seven_zip_runtime.dart';

void main() {
  test('Windows runtime search uses app location, then development and installed engines', () {
    final paths = sevenZipExecutableCandidates(
      windows: true,
      macOS: false,
      appExecutable: r'C:\Apps\Jucier\jucier.exe',
      currentDirectory: r'D:\Unrelated',
      environment: {
        'ProgramFiles': r'C:\Program Files',
        'Path': r'"C:\Tools\7-Zip";D:\Tools',
      },
    );
    expect(paths.first, r'C:\Apps\Jucier\bin\7z.exe');
    expect(
      paths,
      contains(
        r'C:\Apps\Jucier\data\flutter_assets\assets\sevenzip\windows\7z.exe',
      ),
    );
    expect(paths, contains(r'C:\Program Files\7-Zip\7z.exe'));
    expect(paths, contains(r'C:\Tools\7-Zip\7z.exe'));
    expect(
      paths.any((path) => path.endsWith('7zz') || path.contains('/bin/')),
      isFalse,
    );
  });

  test('macOS keeps bundle locations and override precedence', () {
    final paths = sevenZipExecutableCandidates(
      windows: false,
      macOS: true,
      appExecutable: '/Applications/Jucier.app/Contents/MacOS/Jucier',
      currentDirectory: '/project',
      configuredPath: '/custom/7zz',
      environment: {
        'JUCIER_7ZZ_PATH': '/env/7zz',
        'PATH': '/opt/homebrew/bin:/usr/local/bin',
      },
    );
    expect(paths.take(3), [
      '/custom/7zz',
      '/env/7zz',
      '/Applications/Jucier.app/Contents/Resources/bin/7zz',
    ]);
    expect(paths, contains('/opt/homebrew/bin/7zz'));
    expect(
      paths,
      contains(
        '/Applications/Jucier.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/sevenzip/7zz',
      ),
    );
  });

  test('Windows listing separators match the shared archive tree and selection paths', () {
    final listing = SevenZipEngine.parseTechnicalListing(r'C:\sample.7z', r'''
Path = C:\sample.7z
Type = 7z

Path = Folder\中文.txt
Size = 12
Attributes = A
''');
    expect(listing.entries.single.path, 'Folder/中文.txt');
  });

  test('Windows paths reject devices, ADS, aliases and invalid filename characters', () {
    for (final path in [
      'NUL.txt',
      'folder/CON',
      'COM1.txt',
      'a:stream',
      'a?.txt',
      'a.',
      'a ',
      'a\u0001.txt',
    ]) {
      expect(
        () => normalizeArchiveEntryPath(path, windows: true),
        throwsA(isA<ArchiveException>()),
        reason: path,
      );
    }
    expect(normalizeArchiveEntryPath(r'目录\文档.txt', windows: true), '目录/文档.txt');
    expect(normalizeArchiveEntryPath('a?.txt', windows: false), 'a?.txt');
  });

  testWidgets(
    'Windows shows Explorer integration and uses system file permissions',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        const channel = MethodChannel('dev.jucier/platform');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            if (call.method == 'fileAccessStatus') {
              return {'requested': true, 'granted': true};
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        const openChannel = MethodChannel('dev.jucier/archive_open');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          openChannel,
          (_) async => <String>[],
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            openChannel,
            null,
          ),
        );
        const finderChannel = MethodChannel('dev.jucier/finder_action');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          finderChannel,
          (call) async =>
              call.method == 'takePendingFinderActions' ? <Object>[] : false,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            finderChannel,
            null,
          ),
        );
        await tester.pumpWidget(
          const JucierApp(waitForInitialArchiveOpen: true),
        );
        await tester.pumpAndSettle();
        expect(find.text('设置'), findsOneWidget);
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.text('Finder 右键菜单支持'), findsNothing);
        expect(find.text('资源管理器右键菜单支持'), findsOneWidget);
        expect(find.text('由系统管理'), findsOneWidget);
        expect(find.text('使用当前 Windows 用户的文件访问权限。'), findsOneWidget);
        expect(find.text('授权…'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('settings-back-button')));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.comma);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.text('由系统管理'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );
}
