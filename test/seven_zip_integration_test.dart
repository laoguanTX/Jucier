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
  final skip = !File(executable).existsSync();

  test(
    'creates, previews, updates, deletes, tests, and extracts entries',
    () async {
      final temporary = await Directory.systemTemp.createTemp('jucier-e2e-');
      addTearDown(() => temporary.delete(recursive: true));

      final source = File(p.join(temporary.path, 'hello.txt'));
      await source.writeAsString('hello from jucier');
      final archive = p.join(temporary.path, 'sample.7z');
      final output = p.join(temporary.path, 'output');
      final selectedOutput = p.join(temporary.path, 'selected-output');
      final engine = SevenZipEngine(executablePath: executable);

      await engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [source.path],
          format: ArchiveFormat.sevenZip,
        ),
      );
      final listing = await engine.list(archive);
      expect(listing.entries.map((entry) => entry.name), contains('hello.txt'));
      expect(listing.type, '7Z');
      expect(listing.physicalSize, await File(archive).length());

      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: const ['hello.txt'],
          outputDirectory: selectedOutput,
        ),
      );
      final preview = File(p.join(selectedOutput, 'hello.txt'));
      expect(await preview.readAsString(), 'hello from jucier');

      await preview.writeAsString('edited in preview');
      await engine.updateEntry(
        archivePath: archive,
        entryPath: 'hello.txt',
        sourcePath: preview.path,
      );

      await engine.test(archive);
      await engine.extract(
        ExtractArchiveOptions(archivePath: archive, outputDirectory: output),
      );
      expect(
        await File(p.join(output, 'hello.txt')).readAsString(),
        'edited in preview',
      );

      await engine.deleteEntries(
        archivePath: archive,
        entryPaths: const ['hello.txt'],
      );
      final afterDelete = await engine.list(archive);
      expect(
        afterDelete.entries.map((entry) => entry.path),
        isNot(contains('hello.txt')),
      );
    },
    skip: skip ? 'Build assets/sevenzip/7zz first.' : false,
  );

  test(
    'single-entry extraction can preserve or remove parent directories',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'jucier-single-entry-e2e-',
      );
      addTearDown(() => temporary.delete(recursive: true));

      final sourceRoot = Directory(p.join(temporary.path, 'source'));
      final selectedFolder = Directory(
        p.join(sourceRoot.path, 'Parent', 'Folder'),
      );
      await Directory(p.join(selectedFolder.path, 'Sub'))
          .create(recursive: true);
      await File(p.join(selectedFolder.path, 'a.txt')).writeAsString('a');
      await File(p.join(selectedFolder.path, 'Sub', 'b.txt'))
          .writeAsString('b');

      final archive = p.join(temporary.path, 'nested.7z');
      final created = await Process.run(executable, [
        'a',
        archive,
        'Parent',
      ], workingDirectory: sourceRoot.path);
      expect(created.exitCode, 0, reason: '${created.stdout}${created.stderr}');

      final engine = SevenZipEngine(executablePath: executable);
      final listing = await engine.list(archive);
      final folderEntries = listing.entries
          .map((entry) => entry.path)
          .where(
            (path) =>
                path == 'Parent/Folder' || path.startsWith('Parent/Folder/'),
          )
          .toList();

      final flatFileOutput = p.join(temporary.path, 'flat-file');
      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: const ['Parent/Folder/a.txt'],
          selectedEntryPath: 'Parent/Folder/a.txt',
          outputDirectory: flatFileOutput,
          withoutParentDirectories: true,
        ),
      );
      expect(await File(p.join(flatFileOutput, 'a.txt')).readAsString(), 'a');
      expect(
        await Directory(p.join(flatFileOutput, 'Parent')).exists(),
        isFalse,
      );

      final promisedOutput = p.join(
        temporary.path,
        'promised-file',
        'renamed-by-finder.txt',
      );
      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: const ['Parent/Folder/a.txt'],
          selectedEntryPath: 'Parent/Folder/a.txt',
          outputDirectory: p.dirname(promisedOutput),
          outputPath: promisedOutput,
          withoutParentDirectories: true,
        ),
      );
      expect(await File(promisedOutput).readAsString(), 'a');
      expect(
        await Directory(promisedOutput).exists(),
        isFalse,
        reason: 'The promised file path must not become a directory.',
      );

      final flatFolderOutput = p.join(temporary.path, 'flat-folder');
      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: folderEntries,
          selectedEntryPath: 'Parent/Folder',
          outputDirectory: flatFolderOutput,
          withoutParentDirectories: true,
        ),
      );
      expect(
        await File(p.join(flatFolderOutput, 'Folder', 'a.txt')).readAsString(),
        'a',
      );
      expect(
        await File(p.join(flatFolderOutput, 'Folder', 'Sub', 'b.txt'))
            .readAsString(),
        'b',
      );
      expect(
        await Directory(p.join(flatFolderOutput, 'Parent')).exists(),
        isFalse,
      );

      final preservedOutput = p.join(temporary.path, 'preserved');
      await engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: const ['Parent/Folder/a.txt'],
          outputDirectory: preservedOutput,
        ),
      );
      expect(
        await File(p.join(preservedOutput, 'Parent', 'Folder', 'a.txt'))
            .readAsString(),
        'a',
      );

      await expectLater(
        engine.extractEntries(
          ExtractEntriesOptions(
            archivePath: archive,
            entryPaths: const ['missing.txt'],
            outputDirectory: preservedOutput,
          ),
        ),
        throwsA(isA<ArchiveException>()),
      );
    },
    skip: skip ? 'Build assets/sevenzip/7zz first.' : false,
  );

  test('creates every format exposed by the create menu', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'jucier-create-formats-e2e-',
    );
    addTearDown(() => temporary.delete(recursive: true));

    final source = File(p.join(temporary.path, 'source.txt'));
    await source.writeAsString('format coverage');
    final engine = SevenZipEngine(executablePath: executable);

    for (final format in ArchiveFormat.values) {
      final archive = p.join(temporary.path, 'sample.${format.extension}');
      await engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [source.path],
          format: format,
        ),
      );
      expect(File(archive).lengthSync(), greaterThan(0), reason: format.label);
      await engine.test(archive);
    }
  }, skip: skip ? 'Build assets/sevenzip/7zz first.' : false);

  test(
    'keeps ZIP Deflate and preserves macOS symbolic links',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'jucier-macos-links-e2e-',
      );
      addTearDown(() => temporary.delete(recursive: true));

      final source = Directory(p.join(temporary.path, 'source'));
      await source.create();
      final payload = File(p.join(source.path, 'payload.txt'));
      await payload.writeAsString('compressible payload\n' * 8192);
      await Link(p.join(source.path, 'payload-link.txt')).create('payload.txt');

      final archive = p.join(temporary.path, 'links.zip');
      final output = p.join(temporary.path, 'output');
      final engine = SevenZipEngine(executablePath: executable);
      await engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [source.path],
          format: ArchiveFormat.zip,
        ),
      );

      final listing = await engine.list(archive);
      final payloadEntry = listing.entries.singleWhere(
        (entry) => entry.path == 'source/payload.txt',
      );
      final linkEntry = listing.entries.singleWhere(
        (entry) => entry.path == 'source/payload-link.txt',
      );
      expect(payloadEntry.method, 'Deflate');
      expect(linkEntry.attributes, contains('l'));

      await engine.extract(
        ExtractArchiveOptions(archivePath: archive, outputDirectory: output),
      );
      final extractedLink = p.join(output, 'source', 'payload-link.txt');
      expect(
        await FileSystemEntity.type(extractedLink, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(await Link(extractedLink).target(), 'payload.txt');
      expect(
        await File(extractedLink).readAsString(),
        await payload.readAsString(),
      );
    },
    skip: skip || !Platform.isMacOS
        ? 'Requires the bundled macOS 7-Zip engine.'
        : false,
  );

  test('adds dropped files and folders to an archive subdirectory', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'jucier-add-entries-e2e-',
    );
    addTearDown(() => temporary.delete(recursive: true));

    final original = File(p.join(temporary.path, 'original.txt'));
    await original.writeAsString('original');
    final archive = p.join(temporary.path, 'drop-target.7z');
    final engine = SevenZipEngine(executablePath: executable);
    await engine.create(
      CreateArchiveOptions(
        archivePath: archive,
        sources: [original.path],
        format: ArchiveFormat.sevenZip,
      ),
    );

    final addedFile = File(p.join(temporary.path, 'added.txt'));
    await addedFile.writeAsString('added');
    final addedFolder = Directory(p.join(temporary.path, 'DroppedFolder'));
    await addedFolder.create();
    await File(p.join(addedFolder.path, 'child.txt')).writeAsString('child');

    await engine.addEntries(
      AddEntriesOptions(
        archivePath: archive,
        sources: [addedFile.path, addedFolder.path],
        destinationDirectory: 'Current/Inner',
      ),
    );
    final listing = await engine.list(archive);
    expect(
      listing.entries.map((entry) => entry.path),
      containsAll([
        'Current/Inner/added.txt',
        'Current/Inner/DroppedFolder/child.txt',
      ]),
    );

    final output = p.join(temporary.path, 'output');
    await engine.extract(
      ExtractArchiveOptions(archivePath: archive, outputDirectory: output),
    );
    expect(
      await File(p.join(output, 'Current', 'Inner', 'added.txt'))
          .readAsString(),
      'added',
    );
    expect(
      await File(
        p.join(output, 'Current', 'Inner', 'DroppedFolder', 'child.txt'),
      ).readAsString(),
      'child',
    );
  }, skip: skip ? 'Build assets/sevenzip/7zz first.' : false);
}
