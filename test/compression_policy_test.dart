import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/archive/compression_policy.dart';

void main() {
  CreateArchiveOptions options({
    CompressionPerformance mode = CompressionPerformance.balanced,
    ArchiveFormat format = ArchiveFormat.sevenZip,
    CompressionPreset preset = CompressionPreset.balanced,
    int? maxThreads,
    int level = 5,
  }) => CreateArchiveOptions(
    archivePath: 'test.${format.extension}',
    sources: ['input'],
    format: format,
    performance: mode,
    preset: preset,
    maxThreads: maxThreads,
    compressionLevel: level,
  );

  test('balanced retains existing limits and purpose presets', () {
    expect(compressionMethodArguments(options(), processorCount: 32), [
      '-mx=5',
      '-mmt=8',
      '-md=16m',
      '-ms=128m',
    ]);
    expect(
      compressionMethodArguments(
        options(preset: CompressionPreset.compact),
        processorCount: 4,
      ),
      ['-mx=5', '-mmt=4', '-md=32m', '-ms=256m', '-mqs=on'],
    );
  });
  test('speed lets native runtime choose threads and larger solid blocks', () {
    expect(
      compressionMethodArguments(
        options(mode: CompressionPerformance.speed),
        processorCount: 32,
      ),
      ['-mx=5', '-mmt=on', '-md=16m', '-ms=on'],
    );
    expect(
      compressionMethodArguments(
        options(mode: CompressionPerformance.speed, format: ArchiveFormat.zip),
        processorCount: 8,
      ),
      ['-mx=5', '-mmt=on'],
    );
  });
  test(
    'resource saving bounds threads and dictionary with a single-core fallback',
    () {
      expect(
        compressionMethodArguments(
          options(mode: CompressionPerformance.resourceSaving),
          processorCount: 32,
        ),
        ['-mx=5', '-mmt=2', '-md=8m', '-ms=64m'],
      );
      expect(
        compressionMethodArguments(
          options(mode: CompressionPerformance.resourceSaving),
          processorCount: 1,
        ),
        contains('-mmt=1'),
      );
    },
  );
  test(
    'every mode respects editable archives, explicit threads and store level',
    () {
      for (final mode in CompressionPerformance.values) {
        expect(
          compressionMethodArguments(
            options(mode: mode, preset: CompressionPreset.editable),
            processorCount: 32,
          ),
          contains('-ms=off'),
        );
        expect(
          compressionMethodArguments(
            options(mode: mode, maxThreads: 3, level: 0),
            processorCount: 32,
          ),
          ['-mx=0', '-mmt=3'],
        );
      }
    },
  );
}
