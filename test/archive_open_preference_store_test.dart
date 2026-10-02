import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/platform/archive_open_preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.jucier/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('desktop channel saves and reloads both double-click modes', () async {
    String? saved;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setArchiveOpenMode') saved = call.arguments as String;
      if (call.method == 'archiveOpenMode') return saved;
      return null;
    });
    final store = DesktopArchiveOpenPreferenceStore(channel: channel);
    expect(await store.load(), ArchiveOpenMode.open);
    for (final mode in ArchiveOpenMode.values) {
      await store.save(mode);
      expect(
        await DesktopArchiveOpenPreferenceStore(channel: channel).load(),
        mode,
      );
    }
  });

  test('unknown or unavailable preferences keep double-click open', () async {
    final store = DesktopArchiveOpenPreferenceStore(channel: channel);
    messenger.setMockMethodCallHandler(channel, (_) async => 'unknown');
    expect(await store.load(), ArchiveOpenMode.open);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await store.load(), ArchiveOpenMode.open);
    await store.save(ArchiveOpenMode.extract);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await store.load(), ArchiveOpenMode.open);
  });
}
