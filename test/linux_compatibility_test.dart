import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/app.dart';
import 'package:jucier/platform/seven_zip_runtime.dart';

void main() {
  test('Linux searches beside the app and accepts both 7zz and system 7z', () {
    final candidates = sevenZipExecutableCandidates(
      windows: false,
      macOS: false,
      appExecutable: '/opt/Jucier/jucier',
      currentDirectory: '/tmp/unrelated',
      environment: {
        'PATH': '/usr/local/bin:/usr/bin',
        'JUCIER_7ZZ_PATH': '/custom/7zz',
      },
      configuredPath: '/override/7zz',
    );
    expect(candidates, [
      '/override/7zz',
      '/custom/7zz',
      '/opt/Jucier/bin/7zz',
      '/opt/Jucier/bin/7z',
      '/usr/local/bin/7zz',
      '/usr/local/bin/7z',
      '/usr/bin/7zz',
      '/usr/bin/7z',
    ]);
  });

  test(
    'Unix ignores a configured runtime without execute permission',
    () async {
      final root = await Directory.systemTemp.createTemp('jucier-runtime-');
      addTearDown(() => root.delete(recursive: true));
      final file = await File('${root.path}/7zz')
          .writeAsString('not executable');
      await Process.run('chmod', ['644', file.path]);
      expect(
        await findSevenZipExecutable(configuredPath: file.path),
        isNot(file.path),
      );
      await Process.run('chmod', ['755', file.path]);
      expect(
        await findSevenZipExecutable(configuredPath: file.path),
        file.path,
      );
    },
    skip: Platform.isWindows,
  );

  testWidgets(
    'Linux keeps useful settings and hides unsupported native controls',
    (tester) async {
      final calls = <String>[];
      const channel = MethodChannel('dev.jucier/platform');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'fileAccessStatus') {
          return {'requested': true, 'granted': true};
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await tester.pumpWidget(const JucierApp());
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      for (final key in [
        'settings-appearance-card',
        'settings-smart-extraction-card',
        'settings-single-entry-card',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      for (final key in [
        'settings-permission-card',
        'settings-file-association-card',
        'settings-finder-menu-card',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      expect(calls, isNot(contains('requestFileAccess')));
      expect(calls, isNot(contains('archiveFileAssociationStatus')));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );
}
