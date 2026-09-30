import 'archive_options.dart';

/// Native compression policy shared by the Windows and macOS runtimes.
List<String> compressionMethodArguments(
  CreateArchiveOptions options, {
  required int processorCount,
}) {
  final threads =
      options.maxThreads?.toString() ??
      switch (options.performance) {
        CompressionPerformance.balanced =>
          processorCount.clamp(1, 8).toString(),
        CompressionPerformance.speed => 'on',
        CompressionPerformance.resourceSaving =>
          processorCount.clamp(1, 2).toString(),
      };
  final arguments = ['-mx=${options.compressionLevel}', '-mmt=$threads'];
  if (options.format != ArchiveFormat.sevenZip ||
      options.compressionLevel == 0) {
    return arguments;
  }
  // The purpose preset still owns the solid/non-solid choice. In particular,
  // editable archives remain non-solid even when speed is preferred.
  final presetArguments = switch (options.preset) {
    CompressionPreset.compact => ['-md=32m', '-ms=256m', '-mqs=on'],
    CompressionPreset.editable => ['-md=16m', '-ms=off'],
    CompressionPreset.fast => ['-md=8m', '-ms=64m'],
    CompressionPreset.balanced => ['-md=16m', '-ms=128m'],
  };
  if (options.performance == CompressionPerformance.speed &&
      options.preset != CompressionPreset.editable) {
    presetArguments[1] = '-ms=on';
  } else if (options.performance == CompressionPerformance.resourceSaving) {
    presetArguments[0] = '-md=8m';
    if (options.preset != CompressionPreset.editable) {
      presetArguments[1] = '-ms=64m';
    }
  }
  return [...arguments, ...presetArguments];
}
