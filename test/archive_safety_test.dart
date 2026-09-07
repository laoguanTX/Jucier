import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/archive/seven_zip_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  final executable = p.join(
    Directory.current.path,
    'assets',
    'sevenzip',
    '7zz',
  );
  late Directory root;
  late SevenZipEngine engine;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('jucier-safety-');
    engine = SevenZipEngine(executablePath: executable);
  });
  tearDown(() async {
    await engine.cancel();
    await root.delete(recursive: true);
  });
  Future<String> file(String name, [String content = 'hello']) async {
    final result = File(p.join(root.path, name));
    await result.parent.create(recursive: true);
    await result.writeAsString(content);
    return result.path;
  }

  Future<String> create(
    List<String> sources, {
    String name = 'test.zip',
    ArchiveFormat format = ArchiveFormat.zip,
    String? password,
    String? volume,
  }) async {
    final path = p.join(root.path, name);
    await engine.create(
      CreateArchiveOptions(
        archivePath: path,
        sources: sources,
        format: format,
        password: password,
        volumeSize: volume,
      ),
    );
    return path;
  }

  test(
    'exact deletion and extraction preserve wildcard neighbours and @ names',
    () async {
      final sources = <String>[];
      for (final name in ['a?.txt', 'ab.txt', '@notes.txt', '-notes.txt']) {
        sources.add(await file(name, name));
      }
      final archive = await create(sources);
      final out = p.join(root.path, 'out');
      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: ['a?.txt', '@notes.txt', '-notes.txt'],
          outputDirectory: out,
        ),
      );
      expect(await File(p.join(out, 'a?.txt')).readAsString(), 'a?.txt');
      expect(await File(p.join(out, '@notes.txt')).exists(), isTrue);
      expect(await File(p.join(out, '-notes.txt')).exists(), isTrue);
      expect(await File(p.join(out, 'ab.txt')).exists(), isFalse);
      await engine.deleteEntries(
        archivePath: archive,
        entryPaths: ['a?.txt', '@notes.txt', '-notes.txt'],
      );
      expect((await engine.list(archive)).entries.map((entry) => entry.path), [
        'ab.txt',
      ]);
    },
  );

  test(
    'encrypted headers request a password without waiting on stdin',
    () async {
      final archive = await create(
        [await file('secret.txt')],
        name: 'secret.7z',
        format: ArchiveFormat.sevenZip,
        password: 'secret',
      );
      await expectLater(
        engine.list(archive).timeout(const Duration(seconds: 3)),
        throwsA(isA<ArchivePasswordRequiredException>()),
      );
      expect(
        (await engine.list(archive, password: 'secret')).entries,
        hasLength(1),
      );
    },
  );

  test(
    'new archive replaces old contents and removes obsolete volumes',
    () async {
      final archive = await create([await file('old.txt')]);
      await File('$archive.001').writeAsString('obsolete volume');
      await create([await file('new.txt')]);
      expect((await engine.list(archive)).entries.map((entry) => entry.path), [
        'new.txt',
      ]);
      expect(await File('$archive.001').exists(), isFalse);
    },
  );

  test(
    'split creation publishes complete volumes and can replace them',
    () async {
      final source = await file(
        'large.txt',
        List.generate(5000, (i) => '$i:sample\n').join(),
      );
      final archive = await create([source], volume: '1k');
      expect(await File('$archive.001').exists(), isTrue);
      await engine.test('$archive.001');
      await create([await file('small.txt')], volume: '1k');
      expect(await File('$archive.002').exists(), isFalse);
      expect(
        (await engine.list('$archive.001')).entries.single.path,
        'small.txt',
      );
    },
  );

  test('failed creation preserves an existing archive', () async {
    final archive = await create([await file('original.txt')]);
    final before = await File(archive).readAsBytes();
    await expectLater(
      engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [p.join(root.path, 'missing')],
          format: ArchiveFormat.zip,
        ),
      ),
      throwsA(isA<ArchiveException>()),
    );
    expect(await File(archive).readAsBytes(), before);
  });

  test(
    'single directory extraction preserves internal symbolic links',
    () async {
      await file('Bundle/real.txt');
      await Link(p.join(root.path, 'Bundle', 'alias.txt')).create('real.txt');
      final archive = await create(
        [p.join(root.path, 'Bundle')],
        name: 'links.7z',
        format: ArchiveFormat.sevenZip,
      );
      final entries = (await engine.list(archive)).entries
          .map((e) => e.path)
          .toList();
      final out = p.join(root.path, 'out');
      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: entries,
          outputDirectory: out,
          withoutParentDirectories: true,
          selectedEntryPath: 'Bundle',
        ),
      );
      expect(
        await Link(p.join(out, 'Bundle', 'alias.txt')).target(),
        'real.txt',
      );
    },
    skip: !Platform.isMacOS,
  );

  test(
    'selected extraction refuses existing destination directory links',
    () async {
      await file('Input/Sub/data.txt', 'new');
      final archive = await create([p.join(root.path, 'Input')]);
      await file('outside/data.txt', 'original');
      final out = p.join(root.path, 'out');
      await Directory(p.join(out, 'Input')).create(recursive: true);
      await Link(p.join(out, 'Input', 'Sub'))
          .create(p.join(root.path, 'outside'));
      await expectLater(
        engine.extractEntries(
          ExtractEntriesOptions(
            archivePath: archive,
            entryPaths: (await engine.list(archive)).entries
                .map((e) => e.path)
                .toList(),
            outputDirectory: out,
            withoutParentDirectories: true,
            selectedEntryPath: 'Input',
          ),
        ),
        throwsA(isA<ArchiveException>()),
      );
      expect(
        await File(p.join(root.path, 'outside', 'data.txt')).readAsString(),
        'original',
      );
    },
    skip: !Platform.isMacOS,
  );

  test('batch selected extraction retains both nested files', () async {
    await file('A/a.txt', 'a');
    await file('B/b.txt', 'b');
    final archive = await create([
      p.join(root.path, 'A'),
      p.join(root.path, 'B'),
    ]);
    final out = p.join(root.path, 'out');
    await engine.extractEntries(
      ExtractEntriesOptions(
        archivePath: archive,
        entryPaths: ['A/a.txt', 'B/b.txt'],
        selectedEntryPaths: ['A/a.txt', 'B/b.txt'],
        outputDirectory: out,
        withoutParentDirectories: true,
      ),
    );
    expect(await File(p.join(out, 'a.txt')).readAsString(), 'a');
    expect(await File(p.join(out, 'b.txt')).readAsString(), 'b');
  });

  test(
    'ZIP encryption is AES by default and legacy mode is explicit',
    () async {
      final source = await file('secret.txt');
      final archive = await create([source], password: 'secret');
      expect(
        (await engine.list(archive)).entries.single.method,
        contains('AES'),
      );
      await engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [source],
          format: ArchiveFormat.zip,
          password: 'secret',
          zipEncryption: ZipEncryption.compatible,
        ),
      );
      expect(
        (await engine.list(archive)).entries.single.method,
        contains('ZipCrypto'),
      );
    },
  );

  test(
    'fast 7z additions keep existing blocks without full recompaction',
    () async {
      final archive = await create(
        [await file('one.txt')],
        name: 'fast.7z',
        format: ArchiveFormat.sevenZip,
      );
      await engine.addEntries(
        AddEntriesOptions(
          archivePath: archive,
          sources: [await file('two.txt')],
          destinationDirectory: '',
        ),
      );
      final listing = await engine.list(archive);
      expect(listing.entries.where((e) => !e.isDirectory), hasLength(2));
      expect(listing.blocks, 2);
    },
  );

  test(
    'cancellation between compression and verification preserves old output',
    () async {
      final archive = await create([await file('old.txt')]);
      final original = await File(archive).readAsBytes();
      await expectLater(
        engine.create(
          CreateArchiveOptions(
            archivePath: archive,
            sources: [await file('replacement.txt')],
            format: ArchiveFormat.zip,
          ),
          onProgress: (value) {
            if (value >= 0.9) unawaited(engine.cancel());
          },
        ),
        throwsA(isA<ArchiveCancelledException>()),
      );
      expect(await File(archive).readAsBytes(), original);
    },
  );
  test('large member lists use an exact UTF-8 list file', () async {
    final names = List.generate(160, (index) => '${index}_中文_${'x' * 160}.txt');
    final source = <String>[];
    for (final name in names) {
      source.add(await file(name));
    }
    final archive = await create(source);
    await engine.deleteEntries(
      archivePath: archive,
      entryPaths: names.take(159).toList(),
    );
    expect((await engine.list(archive)).entries.single.path, names.last);
  });

  test('TAR.GZ preserves a directory as an inner tar archive', () async {
    await file('Folder/readme.txt');
    final archive = await create(
      [p.join(root.path, 'Folder')],
      name: 'bundle.tar.gz',
      format: ArchiveFormat.tarGzip,
    );
    final out = p.join(root.path, 'out');
    await engine.extract(
      ExtractArchiveOptions(archivePath: archive, outputDirectory: out),
    );
    final tar = (await Directory(out).list().toList()).whereType<File>().single;
    expect(
      (await engine.list(tar.path)).entries.map((e) => e.path),
      contains('Folder/readme.txt'),
    );
  });
  test(
    'encrypted ZIP additions require and verify the existing password',
    () async {
      final archive = await create([
        await file('old-secret.txt'),
      ], password: 'secret');
      final original = await File(archive).readAsBytes();
      final added = await file('new-secret.txt');
      for (final password in [null, 'incorrect']) {
        await expectLater(
          engine.addEntries(
            AddEntriesOptions(
              archivePath: archive,
              sources: [added],
              destinationDirectory: '',
              password: password,
            ),
          ),
          throwsA(isA<ArchivePasswordRequiredException>()),
        );
        expect(await File(archive).readAsBytes(), original);
      }
      await engine.addEntries(
        AddEntriesOptions(
          archivePath: archive,
          sources: [added],
          destinationDirectory: '',
          password: 'secret',
        ),
      );
      expect(
        (await engine.list(archive)).entries
            .every((entry) => entry.encrypted == true),
        isTrue,
      );
      await engine.test(archive, password: 'secret');
    },
  );

  test(
    'saving inside the source excludes the output and staging directory',
    () async {
      final source = await Directory(p.join(root.path, 'Folder')).create();
      await File(p.join(source.path, 'readme.txt')).writeAsString('content');
      final archive = p.join(source.path, 'inside.zip');
      for (var i = 0; i < 2; i++) {
        await engine.create(
          CreateArchiveOptions(
            archivePath: archive,
            sources: [source.path],
            format: ArchiveFormat.zip,
          ),
        );
        final entries = (await engine.list(archive)).entries;
        expect(
          entries.any(
            (e) =>
                e.path.contains('.jucier-create-') ||
                e.path.endsWith('inside.zip'),
          ),
          isFalse,
        );
        expect(entries.any((e) => e.path.endsWith('readme.txt')), isTrue);
      }
    },
  );
}
