import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    'creates, lists, tests, and extracts using the bundled source build',
    () async {
      final temporary = await Directory.systemTemp.createTemp('jucier-e2e-');
      addTearDown(() => temporary.delete(recursive: true));

      final source = File(p.join(temporary.path, 'hello.txt'));
      await source.writeAsString('hello from jucier');
      final archive = p.join(temporary.path, 'sample.7z');
      final output = p.join(temporary.path, 'output');
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

      await engine.test(archive);
      await engine.extract(
        ExtractArchiveOptions(archivePath: archive, outputDirectory: output),
      );
      expect(
        await File(p.join(output, 'hello.txt')).readAsString(),
        'hello from jucier',
      );
    },
    skip: skip ? 'Build assets/sevenzip/7zz first.' : false,
  );
}
