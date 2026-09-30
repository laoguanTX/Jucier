import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Run with `flutter run -d windows -t tool/windows_platform_smoke.dart`.
// No Flutter frame is drawn, so the runner stays hidden. This checks actual
// runner channels rather than mocks, without opening any external application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('dev.jucier/platform');
  const archiveOpen = MethodChannel('dev.jucier/archive_open');
  try {
    if (!Platform.isWindows) throw StateError('Requires the Windows runner');
    final status = await platform.invokeMapMethod<String, Object?>(
      'fileAccessStatus',
    );
    if (status?['requested'] != true || status?['granted'] != true) {
      throw StateError('Windows file access channel failed');
    }
    for (final method in [
      'themeMode',
      'singleEntryExtractionMode',
      'smartExtractionEnabled',
      'archiveColumnPreferences',
    ]) {
      await platform.invokeMethod<Object?>(method);
    }
    final pending = await archiveOpen.invokeListMethod<String>(
      'takePendingOpenFiles',
    );
    if (pending == null) throw StateError('Open-file channel failed');
    final drained = await archiveOpen.invokeListMethod<String>(
      'takePendingOpenFiles',
    );
    if (drained?.isNotEmpty != false) {
      throw StateError('Pending files were not drained');
    }
    try {
      await platform.invokeMethod<void>('openFile', '');
      throw StateError('Invalid preview path was accepted');
    } on PlatformException catch (error) {
      if (error.code != 'invalid_path') rethrow;
    }
    debugPrint('WINDOWS_PLATFORM_SMOKE_PASSED');
  } catch (error, stack) {
    debugPrint('WINDOWS_PLATFORM_SMOKE_FAILED: $error\n$stack');
  } finally {
    await archiveOpen.invokeMethod<void>('quitApplication');
  }
}
