import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/archive/seven_zip_engine.dart';
import 'package:path/path.dart' as p;

/// A small, repeatable local comparison. Times include native process startup.
/// This is a warm-cache synthetic workload, not a claim about all archives.
Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('jucier-benchmark-');
  final engine = SevenZipEngine(
    executablePath: p.absolute('assets/sevenzip/7zz'),
  );
  final measurements = <Map<String, Object>>[];
  Future<void> measure(String name, Future<void> Function() action) async {
    final watch = Stopwatch()..start();
    await action();
    measurements.add({
      'operation': name,
      'milliseconds': watch.elapsedMilliseconds,
    });
  }

  try {
    final input = await Directory(p.join(root.path, 'input')).create();
    final random = Random(42);
    final bytes = List<int>.generate(128 * 1024, (_) => random.nextInt(256));
    for (var index = 0; index < 32; index++) {
      await File(p.join(input.path, 'part-$index.bin')).writeAsBytes(bytes);
    }
    final archive = p.join(root.path, 'baseline.7z');
    await engine.create(
      CreateArchiveOptions(
        archivePath: archive,
        sources: [input.path],
        format: ArchiveFormat.sevenZip,
      ),
    );
    final newFile = await File(p.join(root.path, 'added.bin'))
        .writeAsBytes(bytes);
    for (final compact in [false, true]) {
      final output = p.join(
        root.path,
        compact ? 'compact.7z' : 'incremental.7z',
      );
      await File(archive).copy(output);
      await measure(
        compact ? 'add_with_recompression' : 'add_incrementally',
        () => engine.addEntries(
          AddEntriesOptions(
            archivePath: output,
            sources: [newFile.path],
            destinationDirectory: '',
            recompress: compact,
          ),
        ),
      );
      measurements.last['archiveBytes'] = await File(output).length();
    }
    final entries = (await engine.list(archive)).entries
        .where((entry) => !entry.isDirectory)
        .take(12)
        .map((e) => e.path)
        .toList();
    await measure('extract_sequentially', () async {
      for (final entry in entries) {
        await engine.extractEntries(
          ExtractEntriesOptions(
            archivePath: archive,
            entryPaths: [entry],
            outputDirectory: p.join(root.path, 'sequential'),
            withoutParentDirectories: true,
            selectedEntryPath: entry,
          ),
        );
      }
    });
    await measure(
      'extract_batch',
      () => engine.extractEntries(
        ExtractEntriesOptions(
          archivePath: archive,
          entryPaths: entries,
          selectedEntryPaths: entries,
          outputDirectory: p.join(root.path, 'batch'),
          withoutParentDirectories: true,
        ),
      ),
    );
    final listing = StringBuffer();
    for (var i = 0; i < 100000; i++) {
      listing.write(
        'Path = folder/file-$i.txt\nSize = 1024\nAttributes = A\n\n',
      );
    }
    await measure('parse_100000_entries', () async {
      final parsed = SevenZipEngine.parseTechnicalListing(
        'synthetic.zip',
        listing.toString(),
      );
      if (parsed.entries.length != 100000) {
        throw StateError('Incomplete listing');
      }
    });
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'workload': '32 identical 128 KiB files; 12 selected extractions; synthetic 100k listing',
        'measurements': measurements,
      }),
    );
  } finally {
    await root.delete(recursive: true);
  }
}
