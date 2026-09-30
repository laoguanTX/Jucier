import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/archive/seven_zip_engine.dart';
import 'package:jucier/application/archive_draft.dart';
import 'package:path/path.dart' as p;

/// Compare the real create path with the same native executable and parameters.
/// Synthetic, warm-cache data; results do not generalize to all input files.
Future<void> main(List<String> arguments) async {
  final executable = p.absolute('assets/sevenzip/windows/7z.exe');
  final root = await Directory(p.absolute('build/compression-diagnosis'))
      .create(recursive: true);
  if (arguments.contains('--metadata')) {
    final report = jsonDecode(
      await File(p.join(root.path, 'results.json')).readAsString(),
    ) as Map<String, dynamic>;
    final data = report['environment']['dataDirectory'] as String;
    final metadata = <Map<String, Object>>[];
    for (final name in ['mixed-256MiB', 'small-1000-files']) {
      final source = p.join(data, name);
      final archive = p.join(data, '$name-metadata.7z');
      final engine = SevenZipEngine(executablePath: executable);
      await engine.create(
        CreateArchiveOptions(
          archivePath: archive,
          sources: [source],
          format: ArchiveFormat.sevenZip,
        ),
      );
      for (var repetition = 0; repetition < 3; repetition++) {
        final watch = Stopwatch()..start();
        final draft = await buildArchiveDraftListing([source]);
        final draftMs = watch.elapsedMicroseconds / 1000;
        watch.reset();
        final listing = await engine.list(archive);
        final row = <String, Object>{
          'workload': name,
          'repetition': repetition,
          'draftMs': draftMs,
          'listMs': watch.elapsedMicroseconds / 1000,
          'draftEntries': draft.entries.length,
          'archiveEntries': listing.entries.length,
        };
        metadata.add(row);
        stdout.writeln(jsonEncode(row));
      }
      await File(archive).delete();
    }
    await File(p.join(root.path, 'metadata.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));
    return;
  }
  // A unique directory prevents updating an archive from a previous run.
  final run = await root.createTemp('run-');
  final large = await Directory(p.join(run.path, 'mixed-256MiB')).create();
  final small = await Directory(p.join(run.path, 'small-1000-files')).create();
  final random = Random(42);
  final pattern = Uint8List.fromList(
    List.generate(64 * 1024, (_) => random.nextInt(256)),
  );
  final block = Uint8List(1024 * 1024);
  for (var offset = 0; offset < block.length; offset += pattern.length) {
    block.setRange(offset, offset + pattern.length, pattern);
  }
  // Three quarters repeated 64 KiB data. Refresh the remaining random quarter
  // every four 1 MiB chunks, so the corpus also includes local repetition.
  for (var fileIndex = 0; fileIndex < 16; fileIndex++) {
    final file = await File(p.join(large.path, 'part-$fileIndex.bin'))
        .open(mode: FileMode.write);
    try {
      for (var chunk = 0; chunk < 16; chunk++) {
        if (chunk % 4 == 0) {
          for (var i = 0; i < block.length ~/ 4; i++) {
            block[i] = random.nextInt(256);
          }
        }
        await file.writeFrom(block);
      }
    } finally {
      await file.close();
    }
  }
  for (var i = 0; i < 1000; i++) {
    await File(p.join(small.path, 'file-$i.txt')).writeAsString(
      List.generate(
        64,
        (line) => 'record=$i line=$line value=${i % 31}\n',
      ).join(),
    );
  }
  final rows = <Map<String, Object?>>[];
  final engines = <String, ArchiveFormat>{
    'engine_7z': ArchiveFormat.sevenZip,
    'engine_zip': ArchiveFormat.zip,
  };
  final nativeCases = <String, List<String>>{
    'native_7z_matched': ['-t7z', '-mx=5', '-mmt=8', '-md=16m', '-ms=128m'],
    'native_7z_threads32': ['-t7z', '-mx=5', '-mmt=32', '-md=16m', '-ms=128m'],
    'native_7z_threads32_solid': [
      '-t7z',
      '-mx=5',
      '-mmt=32',
      '-md=16m',
      '-ms=on',
    ],
    'native_7z_default': ['-t7z', '-mx=5'],
    'native_zip_matched': ['-tzip', '-mx=5', '-mmt=8'],
    'native_zip_auto': ['-tzip', '-mx=5'],
  };
  final cases = [...engines.keys, ...nativeCases.keys];
  final version = await Process.run(executable, ['i']);
  final environment = {
    'processors': Platform.numberOfProcessors,
    'executable': executable,
    'version': (version.stdout as String).trim().split('\n').first.trim(),
    'workload': '256 MiB, 16 binary files; 1000 small text files',
    'repetitions': 3,
    'dataDirectory': run.path,
  };
  stdout.writeln(jsonEncode(environment));
  for (final input in [large, small]) {
    for (var repetition = 0; repetition < 3; repetition++) {
      // Rotate case order to reduce systematic cache/order bias.
      final offset = repetition * 3;
      final order = [...cases.skip(offset), ...cases.take(offset)];
      for (final name in order) {
        final output = p.join(
          run.path,
          '${p.basename(input.path)}-$name-$repetition.${name.contains('zip') ? 'zip' : '7z'}',
        );
        final watch = Stopwatch()..start();
        final phases = <String, int>{};
        int? verifyStart;
        int progressEvents = 0;
        if (engines[name] case final format?) {
          final engine = SevenZipEngine(executablePath: executable);
          engine.onPhaseChanged = (phase) {
            phases[phase] = watch.elapsedMicroseconds;
            if (phase == '正在校验') verifyStart = watch.elapsedMicroseconds;
          };
          await engine.create(
            CreateArchiveOptions(
              archivePath: output,
              sources: [input.path],
              format: format,
            ),
            onProgress: (_) => progressEvents++,
          );
        } else {
          final result = await Process.run(executable, [
            '-sccUTF-8',
            'a',
            ...nativeCases[name]!,
            '-y',
            '-bsp1',
            '-bb0',
            output,
            '-spd',
            '--',
            input.path,
          ]);
          if (result.exitCode != 0) {
            throw StateError(
              '${result.exitCode}: ${result.stderr} ${result.stdout}',
            );
          }
        }
        final total = watch.elapsedMicroseconds;
        final row = <String, Object?>{
          'workload': p.basename(input.path),
          'case': name,
          'repetition': repetition,
          'totalMs': total / 1000,
          'archiveBytes': await File(output).length(),
          if (verifyStart != null)
            'compressPhaseMs': (verifyStart! - phases['正在压缩']!) / 1000,
          if (verifyStart != null)
            'verifyAndPublishMs': (total - verifyStart!) / 1000,
          if (engines.containsKey(name)) 'progressEvents': progressEvents,
        };
        rows.add(row);
        stdout.writeln(jsonEncode(row));
        // Verify native output outside the timed creation section as well.
        if (!engines.containsKey(name)) {
          final check = Stopwatch()..start();
          final result = await Process.run(executable, ['t', '-bb0', output]);
          if (result.exitCode != 0) {
            throw StateError('Integrity check failed: $output');
          }
          row['verificationMs'] = check.elapsedMicroseconds / 1000;
        }
        await File(output).delete();
      }
    }
  }
  final report = File(p.join(root.path, 'results.json'));
  await report.writeAsString(
    const JsonEncoder.withIndent('  ')
        .convert({'environment': environment, 'measurements': rows}),
  );
  stdout.writeln('Results: ${report.path}');
  // Generated input is kept in the ignored build directory for inspection.
}
