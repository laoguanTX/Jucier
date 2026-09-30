import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/platform/compression_preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.jucier/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'saves and reloads each mode through the shared desktop channel',
    () async {
      String? saved;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setCompressionPerformance') {
          saved = call.arguments as String;
        }
        if (call.method == 'compressionPerformance') return saved;
        return null;
      });
      final store = DesktopCompressionPreferenceStore(channel: channel);
      expect(await store.load(), CompressionPerformance.balanced);
      for (final mode in CompressionPerformance.values) {
        await store.save(mode);
        expect(
          await DesktopCompressionPreferenceStore(channel: channel).load(),
          mode,
        );
      }
    },
  );
  test('unknown or unavailable settings fall back to balanced', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'unknown');
    final store = DesktopCompressionPreferenceStore(channel: channel);
    expect(await store.load(), CompressionPerformance.balanced);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await store.load(), CompressionPerformance.balanced);
    await store.save(CompressionPerformance.speed);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await store.load(), CompressionPerformance.balanced);
  });
}
