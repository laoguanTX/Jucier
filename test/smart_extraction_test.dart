import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/archive/smart_extraction.dart';
import 'package:jucier/platform/smart_extraction_preference_store.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ArchiveListing listing(
    List<String> paths, {
    String name = '/tmp/photos.zip',
  }) => ArchiveListing(
    archivePath: name,
    entries: [
      for (final path in paths) ArchiveEntry(path: path, isDirectory: false),
    ],
  );

  test('single file and implicit top-level folder need no wrapper', () {
    expect(smartExtractionDirectory(listing(['note.txt']), '/out'), '/out');
    expect(
      smartExtractionDirectory(
        listing(['photos/a.jpg', 'photos/b.jpg']),
        '/out',
      ),
      '/out',
    );
    expect(smartExtractionDirectory(listing([]), '/out'), '/out');
  });

  test(
    'multiple roots use archive name including compound and split suffixes',
    () {
      for (final name in ['photos.zip', 'photos.tar.gz', 'photos.7z.001']) {
        expect(
          smartExtractionDirectory(
            listing(['a.jpg', 'b.jpg'], name: name),
            '/out',
          ),
          p.join('/out', 'photos'),
        );
      }
      expect(
        smartExtractionDirectory(listing(['folder/a', 'b']), '/out'),
        p.join('/out', 'photos'),
      );
    },
  );

  test('unsafe archive paths are rejected', () {
    expect(
      () => smartExtractionDirectory(listing(['../escape', 'safe']), '/out'),
      throwsException,
    );
  });

  test(
    'smart extraction defaults on and persists a disabled preference',
    () async {
      const channel = MethodChannel('dev.jucier/platform');
      bool? saved;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'smartExtractionEnabled') return saved;
            if (call.method == 'setSmartExtractionEnabled') {
              saved = call.arguments as bool;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = MacOSSmartExtractionPreferenceStore();
      expect(await store.load(), isTrue);
      await store.save(false);
      expect(await MacOSSmartExtractionPreferenceStore().load(), isFalse);
    },
  );
}
