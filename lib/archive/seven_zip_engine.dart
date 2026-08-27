import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_engine.dart';
import 'archive_entry.dart';
import 'archive_options.dart';
import 'archive_path.dart';

class SevenZipEngine implements ArchiveEngine {
  SevenZipEngine({String? executablePath}) : _configuredPath = executablePath;

  final String? _configuredPath;
  Process? _activeProcess;
  bool _cancelRequested = false;

  static const _passwordMarkers = <String>[
    'wrong password',
    'enter password',
    'password is incorrect',
    'encrypted archive',
  ];

  static const _permissionMarkers = <String>[
    'permission denied',
    'operation not permitted',
    'errno=13',
  ];

  @override
  Future<bool> get isAvailable async {
    try {
      final executable = await _resolveExecutable();
      final result = await Process.run(executable, const [
        'i',
      ], runInShell: false);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) async {
    final args = <String>['l', '-slt', '-ba', '-sccUTF-8'];
    if (password != null && password.isNotEmpty) args.add('-p$password');
    args.add(archivePath);

    final output = await _run(args);
    final listing = parseTechnicalListing(archivePath, output);
    return ArchiveListing(
      archivePath: listing.archivePath,
      entries: listing.entries,
      type:
          listing.type ??
          p.extension(archivePath).replaceFirst('.', '').toUpperCase(),
      physicalSize: listing.physicalSize ?? await File(archivePath).length(),
    );
  }

  @override
  Future<void> create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (options.sources.isEmpty) {
      throw const ArchiveException('没有选择要压缩的文件');
    }
    if (options.format == ArchiveFormat.gzip && options.sources.length != 1) {
      throw const ArchiveException('GZIP 一次只能压缩一个文件');
    }
    if (options.password case final password?
        when password.isNotEmpty &&
            options.format != ArchiveFormat.sevenZip &&
            options.format != ArchiveFormat.zip) {
      throw ArchiveException('${options.format.label} 格式不支持密码加密');
    }

    final args = <String>[
      'a',
      '-t${options.format.sevenZipType}',
      '-mx=${options.compressionLevel}',
      '-y',
      '-bsp1',
      '-bb1',
    ];
    if (options.password case final password? when password.isNotEmpty) {
      args.add('-p$password');
      if (options.format == ArchiveFormat.sevenZip) args.add('-mhe=on');
    }
    if (options.volumeSize case final volume? when volume.isNotEmpty) {
      args.add('-v$volume');
    }
    args
      ..add(options.archivePath)
      ..addAll(options.sources);

    await _run(args, onProgress: onProgress);
  }

  @override
  Future<void> extract(
    ExtractArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    final args = <String>[
      'x',
      options.archivePath,
      '-o${options.outputDirectory}',
      options.conflict.switchValue,
      '-y',
      '-bsp1',
      '-bb1',
    ];
    if (options.password case final password? when password.isNotEmpty) {
      args.add('-p$password');
    }
    await _run(args, onProgress: onProgress);
  }

  @override
  Future<void> extractEntries(
    ExtractEntriesOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (options.entryPaths.isEmpty) {
      throw const ArchiveException('没有选择要解压的文件');
    }
    final entries = options.entryPaths.map(normalizeArchiveEntryPath).toList();
    if (options.withoutParentDirectories) {
      final selected = options.selectedEntryPath;
      if (selected == null) {
        throw const ArchiveException('缺少要解压的所选文件路径');
      }
      await _extractEntriesWithoutParents(
        options,
        entries,
        normalizeArchiveEntryPath(selected),
        onProgress: onProgress,
      );
      return;
    }
    final args = <String>[
      'x',
      options.archivePath,
      '-o${options.outputDirectory}',
      options.conflict.switchValue,
      '-y',
      '-bsp1',
      '-bb1',
    ];
    if (options.password case final password? when password.isNotEmpty) {
      args.add('-p$password');
    }
    args.addAll(entries);
    final output = await _run(args, onProgress: onProgress);
    _ensureFilesProcessed(output);
  }

  @override
  Future<void> addEntries(
    AddEntriesOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (options.sources.isEmpty) {
      throw const ArchiveException('没有可添加到压缩包的文件');
    }
    final destination = options.destinationDirectory.isEmpty
        ? ''
        : normalizeArchiveEntryPath(options.destinationDirectory);
    final staging = await Directory.systemTemp.createTemp('jucier-add-');
    try {
      final relativePaths = <String>[];
      for (final sourcePath in options.sources) {
        final sourceType = await FileSystemEntity.type(sourcePath);
        if (sourceType == FileSystemEntityType.notFound) {
          throw ArchiveException('找不到要添加的文件：${p.basename(sourcePath)}');
        }
        final baseName = p.basename(sourcePath);
        var relativePath = destination.isEmpty
            ? baseName
            : p.posix.join(destination, baseName);
        var linkPath = p.joinAll([
          staging.path,
          ...p.posix.split(relativePath),
        ]);
        for (
          var suffix = 1;
          await FileSystemEntity.type(linkPath, followLinks: false) !=
              FileSystemEntityType.notFound;
          suffix++
        ) {
          final isDirectory = sourceType == FileSystemEntityType.directory;
          final extension = isDirectory ? '' : p.extension(baseName);
          final stem = isDirectory
              ? baseName
              : p.basenameWithoutExtension(baseName);
          final uniqueName = '$stem ($suffix)$extension';
          relativePath = destination.isEmpty
              ? uniqueName
              : p.posix.join(destination, uniqueName);
          linkPath = p.joinAll([staging.path, ...p.posix.split(relativePath)]);
        }
        await Directory(p.dirname(linkPath)).create(recursive: true);
        await Link(linkPath).create(File(sourcePath).absolute.path);
        relativePaths.add(relativePath);
      }

      final args = <String>['a', options.archivePath, '-y', '-bsp1', '-bb1'];
      if (options.password case final password? when password.isNotEmpty) {
        args.add('-p$password');
      }
      args.addAll(relativePaths);
      await _run(args, onProgress: onProgress, workingDirectory: staging.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _extractEntriesWithoutParents(
    ExtractEntriesOptions options,
    List<String> entries,
    String selectedEntry, {
    ProgressCallback? onProgress,
  }) async {
    final staging = await Directory.systemTemp.createTemp(
      'jucier-single-extract-',
    );
    try {
      final args = <String>[
        'x',
        options.archivePath,
        '-o${staging.path}',
        '-aoa',
        '-y',
        '-bsp1',
        '-bb1',
      ];
      if (options.password case final password? when password.isNotEmpty) {
        args.add('-p$password');
      }
      args.addAll(entries);
      final output = await _run(args, onProgress: onProgress);
      _ensureFilesProcessed(output);

      final sourcePath = p.joinAll([
        staging.path,
        ...p.posix.split(selectedEntry),
      ]);
      await _copySelectedEntry(
        sourcePath,
        options.outputDirectory,
        options.conflict,
        outputPath: options.outputPath,
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _copySelectedEntry(
    String sourcePath,
    String outputDirectory,
    ExtractionConflict conflict, {
    String? outputPath,
  }) async {
    final sourceType = await FileSystemEntity.type(
      sourcePath,
      followLinks: false,
    );
    if (sourceType == FileSystemEntityType.notFound) {
      throw const ArchiveException('7-Zip 未能解压所选文件');
    }
    if (sourceType == FileSystemEntityType.link) {
      throw const ArchiveException('暂不支持单独解压符号链接');
    }

    final targetPath =
        outputPath ?? p.join(outputDirectory, p.basename(sourcePath));
    await Directory(p.dirname(targetPath)).create(recursive: true);
    if (sourceType == FileSystemEntityType.file) {
      await _copyFile(File(sourcePath), targetPath, conflict);
      return;
    }

    var targetRoot = targetPath;
    final targetType = await FileSystemEntity.type(
      targetRoot,
      followLinks: false,
    );
    if (targetType != FileSystemEntityType.notFound) {
      if (conflict == ExtractionConflict.rename) {
        targetRoot = await _uniquePath(targetRoot, isDirectory: true);
      } else if (targetType != FileSystemEntityType.directory &&
          conflict == ExtractionConflict.skip) {
        return;
      } else if (targetType != FileSystemEntityType.directory) {
        await File(targetRoot).delete();
      }
    }
    await Directory(targetRoot).create(recursive: true);

    final sourceRoot = Directory(sourcePath);
    await for (final entity in sourceRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: sourceRoot.path);
      final destination = p.join(targetRoot, relative);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(destination).create(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await _copyFile(File(entity.path), destination, conflict);
      }
    }
  }

  Future<void> _copyFile(
    File source,
    String requestedTarget,
    ExtractionConflict conflict,
  ) async {
    var target = requestedTarget;
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType != FileSystemEntityType.notFound) {
      if (conflict == ExtractionConflict.skip) return;
      if (conflict == ExtractionConflict.rename) {
        target = await _uniquePath(target, isDirectory: false);
      } else if (targetType == FileSystemEntityType.directory) {
        await Directory(target).delete(recursive: true);
      } else {
        await File(target).delete();
      }
    }
    await Directory(p.dirname(target)).create(recursive: true);
    final copied = await source.copy(target);
    final stat = await source.stat();
    await copied.setLastModified(stat.modified);
  }

  Future<String> _uniquePath(
    String requestedPath, {
    required bool isDirectory,
  }) async {
    final directory = p.dirname(requestedPath);
    final extension = isDirectory ? '' : p.extension(requestedPath);
    final base = isDirectory
        ? p.basename(requestedPath)
        : p.basenameWithoutExtension(requestedPath);
    for (var index = 1; ; index++) {
      final candidate = p.join(directory, '$base ($index)$extension');
      if (await FileSystemEntity.type(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return candidate;
      }
    }
  }

  void _ensureFilesProcessed(String output) {
    if (output.toLowerCase().contains('no files to process')) {
      throw const ArchiveException('压缩包中找不到所选文件');
    }
  }

  @override
  Future<void> updateEntry({
    required String archivePath,
    required String entryPath,
    required String sourcePath,
    String? password,
    ProgressCallback? onProgress,
  }) async {
    final normalizedEntry = normalizeArchiveEntryPath(entryPath);
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const ArchiveException('预览文件已被移动或删除，无法应用修改');
    }

    final staging = await Directory.systemTemp.createTemp('jucier-update-');
    try {
      final stagedPath = p.joinAll([
        staging.path,
        ...p.posix.split(normalizedEntry),
      ]);
      final staged = File(stagedPath);
      await staged.parent.create(recursive: true);
      await source.copy(staged.path);

      final args = <String>['u', archivePath, '-y', '-bsp1', '-bb1'];
      if (password case final value? when value.isNotEmpty) {
        args.add('-p$value');
      }
      args.add(normalizedEntry);
      await _run(args, onProgress: onProgress, workingDirectory: staging.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  @override
  Future<void> deleteEntries({
    required String archivePath,
    required List<String> entryPaths,
    String? password,
    ProgressCallback? onProgress,
  }) async {
    if (entryPaths.isEmpty) {
      throw const ArchiveException('没有选择要删除的文件');
    }
    final entries = entryPaths.map(normalizeArchiveEntryPath).toList();
    final args = <String>['d', archivePath, '-y', '-bsp1', '-bb1'];
    if (password case final value? when value.isNotEmpty) {
      args.add('-p$value');
    }
    args.addAll(entries);
    await _run(args, onProgress: onProgress);
  }

  @override
  Future<void> test(
    String archivePath, {
    String? password,
    ProgressCallback? onProgress,
  }) async {
    final args = <String>['t', archivePath, '-bsp1', '-bb1'];
    if (password != null && password.isNotEmpty) args.add('-p$password');
    await _run(args, onProgress: onProgress);
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _activeProcess?.kill(ProcessSignal.sigterm);
  }

  Future<String> _run(
    List<String> arguments, {
    ProgressCallback? onProgress,
    String? workingDirectory,
  }) async {
    if (_activeProcess != null) {
      throw const ArchiveException('已有操作正在进行');
    }

    final executable = await _resolveExecutable();
    _cancelRequested = false;
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
      mode: ProcessStartMode.normal,
      workingDirectory: workingDirectory,
    );
    _activeProcess = process;

    final output = StringBuffer();
    final subscriptions = <StreamSubscription<String>>[];
    void consume(String text) {
      output.write(text);
      if (onProgress != null) {
        for (final match in RegExp(r'(?<!\d)(\d{1,3})%').allMatches(text)) {
          final value = int.tryParse(match.group(1)!);
          if (value != null) onProgress((value.clamp(0, 100)) / 100);
        }
      }
    }

    subscriptions
      ..add(process.stdout.transform(utf8.decoder).listen(consume))
      ..add(process.stderr.transform(utf8.decoder).listen(consume));

    final exitCode = await process.exitCode;
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
    _activeProcess = null;

    if (_cancelRequested || exitCode == 255) {
      _cancelRequested = false;
      throw const ArchiveCancelledException();
    }

    final text = output.toString();
    if (exitCode != 0) _throwForFailure(exitCode, text);
    onProgress?.call(1);
    return text;
  }

  Never _throwForFailure(int exitCode, String output) {
    final normalized = output.toLowerCase();
    if (_passwordMarkers.any(normalized.contains)) {
      throw ArchivePasswordRequiredException(output: output);
    }
    if (_permissionMarkers.any(normalized.contains)) {
      throw ArchiveException(
        '无法写入解压位置，请重新选择文件夹',
        output: output,
        exitCode: exitCode,
      );
    }

    final message = switch (exitCode) {
      1 => '操作完成，但 7-Zip 返回了警告',
      2 => '压缩文件损坏或操作失败',
      7 => '7-Zip 命令参数错误',
      8 => '内存不足，无法完成操作',
      _ => '7-Zip 操作失败（错误码 $exitCode）',
    };
    throw ArchiveException(message, output: output, exitCode: exitCode);
  }

  Future<String> _resolveExecutable() async {
    final candidates = <String?>[
      _configuredPath,
      Platform.environment['JUCIER_7ZZ_PATH'],
      if (Platform.isMacOS)
        p.normalize(
          p.join(
            p.dirname(Platform.resolvedExecutable),
            '..',
            'Resources',
            'bin',
            '7zz',
          ),
        ),
      if (Platform.isMacOS)
        p.normalize(
          p.join(
            p.dirname(Platform.resolvedExecutable),
            '..',
            'Frameworks',
            'App.framework',
            'Resources',
            'flutter_assets',
            'assets',
            'sevenzip',
            '7zz',
          ),
        ),
      p.join(Directory.current.path, 'assets', 'sevenzip', '7zz'),
    ];

    for (final candidate in candidates) {
      if (candidate != null &&
          candidate.isNotEmpty &&
          await File(candidate).exists()) {
        return candidate;
      }
    }

    final pathProbe = await Process.run('which', const [
      '7zz',
    ], runInShell: false);
    if (pathProbe.exitCode == 0) {
      final path = (pathProbe.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
    throw const ArchiveException('找不到 7-Zip 引擎。请先运行 tool/build_7zip_macos.sh');
  }

  static ArchiveListing parseTechnicalListing(
    String archivePath,
    String output,
  ) {
    final records = <Map<String, String>>[];
    var current = <String, String>{};

    for (final line in const LineSplitter().convert(output)) {
      if (line.trim().isEmpty) {
        if (current.isNotEmpty) records.add(current);
        current = <String, String>{};
        continue;
      }
      final separator = line.indexOf(' = ');
      if (separator <= 0) continue;
      current[line.substring(0, separator)] = line.substring(separator + 3);
    }
    if (current.isNotEmpty) records.add(current);

    String? type;
    int? physicalSize;
    final entries = <ArchiveEntry>[];
    for (final record in records) {
      final path = record['Path'];
      if (path == null) continue;

      if (p.equals(path, archivePath) || record.containsKey('Type')) {
        type ??= record['Type'];
        physicalSize ??= int.tryParse(record['Physical Size'] ?? '');
        if (record.containsKey('Type')) continue;
      }

      final attributes = record['Attributes'] ?? '';
      entries.add(
        ArchiveEntry(
          path: path,
          isDirectory: attributes.startsWith('D') || record['Folder'] == '+',
          size: int.tryParse(record['Size'] ?? ''),
          packedSize: int.tryParse(record['Packed Size'] ?? ''),
          modified: DateTime.tryParse(record['Modified'] ?? ''),
          crc: record['CRC'],
          method: record['Method'],
          encrypted: record['Encrypted'] == '+',
          attributes: attributes.isEmpty ? null : attributes,
        ),
      );
    }

    return ArchiveListing(
      archivePath: archivePath,
      entries: entries,
      type: type,
      physicalSize: physicalSize,
    );
  }
}
