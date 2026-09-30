import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/archive/seven_zip_engine.dart';
import 'package:path/path.dart' as p;

void main() {
  final executable = p.absolute(
    p.joinAll([
      'assets',
      'sevenzip',
      if (Platform.isWindows) 'windows',
      Platform.isWindows ? '7z.exe' : '7zz',
    ]),
  );
  final skip = !File(executable).existsSync();
  for (final mode in CompressionPerformance.values) {
    for (final format in [ArchiveFormat.sevenZip, ArchiveFormat.zip]) {
      test(
        '${mode.name} ${format.name} replaces, checks phases, and round trips',
        () async {
          final root = await Directory.systemTemp.createTemp('jucier-policy-');
          addTearDown(() => root.delete(recursive: true));
          final old = await File(p.join(root.path, 'old.txt'))
              .writeAsString('old');
          final source = await File(p.join(root.path, 'new.txt'))
              .writeAsString('new content' * 1000);
          final archive = p.join(root.path, 'archive.${format.extension}');
          final engine = SevenZipEngine(executablePath: executable);
          await engine.create(
            CreateArchiveOptions(
              archivePath: archive,
              sources: [old.path],
              format: format,
            ),
          );
          final phases = <String>[];
          final progress = <double>[];
          engine.onPhaseChanged = phases.add;
          await engine.create(
            CreateArchiveOptions(
              archivePath: archive,
              sources: [source.path],
              format: format,
              performance: mode,
              password: 'secret',
            ),
            onProgress: progress.add,
          );
          expect(phases.contains('正在校验'), mode != CompressionPerformance.speed);
          expect(progress.last, 1);
          for (var i = 1; i < progress.length; i++) {
            expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
          }
          final listing = await engine.list(archive, password: 'secret');
          expect(listing.entries.map((e) => e.name), ['new.txt']);
          await engine.test(archive, password: 'secret');
          final output = p.join(root.path, 'output');
          await engine.extract(
            ExtractArchiveOptions(
              archivePath: archive,
              outputDirectory: output,
              password: 'secret',
            ),
          );
          expect(
            await File(p.join(output, 'new.txt')).readAsString(),
            await source.readAsString(),
          );
        },
        skip: skip,
      );
    }
  }
  test('cancelled speed create preserves the original archive', () async {
    final root = await Directory.systemTemp.createTemp('jucier-speed-cancel-');
    addTearDown(() => root.delete(recursive: true));
    final source = await File(p.join(root.path, 'source.txt'))
        .writeAsString('content');
    final archive = p.join(root.path, 'archive.7z');
    final engine = SevenZipEngine(executablePath: executable);
    await engine.create(
      CreateArchiveOptions(
        archivePath: archive,
        sources: [source.path],
        format: ArchiveFormat.sevenZip,
      ),
    );
    final original = await File(archive).readAsBytes();
    engine.onPhaseChanged = (_) {
      engine.cancel();
    };
    await expectLater(
      engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [source.path],
          format: ArchiveFormat.sevenZip,
          performance: CompressionPerformance.speed,
        ),
      ),
      throwsA(isA<ArchiveCancelledException>()),
    );
    expect(await File(archive).readAsBytes(), original);
    expect(
      await root.list().any(
        (e) => p.basename(e.path).startsWith('.jucier-create-'),
      ),
      isFalse,
    );
  }, skip: skip);
}
