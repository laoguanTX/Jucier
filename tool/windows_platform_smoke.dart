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
  const finderAction = MethodChannel('dev.jucier/finder_action');
  const window = MethodChannel('dev.jucier/window');
  try {
    if (!Platform.isWindows) throw StateError('Requires the Windows runner');
    if (await window.invokeMethod<bool>('windowState') != false) {
      throw StateError('Initial window state is not restored');
    }
    if (await window.invokeMethod<bool>('prepareOperationWindow') != true) {
      throw StateError('Cold quick action did not select the compact window');
    }
    await window.invokeMethod<void>('configureOperationWindow', true);
    await window.invokeMethod<void>('configureOperationWindow', false);
    if (await window.invokeMethod<bool>('finishOperationWindow') != true) {
      throw StateError(
        'Cold quick action did not request temporary-session exit',
      );
    }
    if (await finderAction.invokeMethod<bool>('finderContextMenuAvailable') ==
        null) {
      throw StateError('Explorer integration status channel failed');
    }
    final actions = await finderAction.invokeListMethod<Object?>(
      'takePendingFinderActions',
    );
    if (actions == null || actions.isNotEmpty) {
      throw StateError('Unexpected initial Explorer requests');
    }
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
      'compressionPerformance',
      'archiveOpenMode',
    ]) {
      await platform.invokeMethod<Object?>(method);
    }
    for (final preference in [
      (
        getter: 'compressionPerformance',
        setter: 'setCompressionPerformance',
        modes: ['balanced', 'speed', 'resourceSaving'],
      ),
      (
        getter: 'archiveOpenMode',
        setter: 'setArchiveOpenMode',
        modes: ['open', 'extract'],
      ),
    ]) {
      final previous = await platform.invokeMethod<String>(preference.getter);
      try {
        for (final mode in preference.modes) {
          await platform.invokeMethod<void>(preference.setter, mode);
          if (await platform.invokeMethod<String>(preference.getter) != mode) {
            throw StateError('${preference.getter} did not round trip: $mode');
          }
        }
        try {
          await platform.invokeMethod<void>(preference.setter, 'invalid');
          throw StateError('Invalid ${preference.getter} was accepted');
        } on PlatformException catch (error) {
          if (error.code != 'invalid_preference') rethrow;
        }
      } finally {
        await platform.invokeMethod<void>(
          preference.setter,
          previous ?? preference.modes.first,
        );
      }
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
