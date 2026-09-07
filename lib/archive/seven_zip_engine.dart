import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_engine.dart';
import 'archive_entry.dart';
import 'archive_options.dart';
import 'archive_path.dart';

class SevenZipEngine implements ArchiveEngine, ArchiveOperationEvents {
  SevenZipEngine({String? executablePath}) : _configuredPath = executablePath;

  @override
  void Function(String phase)? onPhaseChanged;

  final String? _configuredPath;
  Process? _activeProcess;
  bool _cancelRequested = false;
  bool _operationActive = false;
  String? _executableCache;

  Future<T> _operation<T>(Future<T> Function() action) async {
    if (_operationActive) throw const ArchiveException('已有操作正在进行');
    _operationActive = true;
    _cancelRequested = false;
    try {
      return await action();
    } on FileSystemException catch (error) {
      throw ArchiveException(
        '文件操作失败：${error.message}',
        output: error.toString(),
      );
    } on ProcessException catch (error) {
      throw ArchiveException(
        '无法运行压缩引擎：${error.message}',
        exitCode: error.errorCode,
      );
    } finally {
      _operationActive = false;
    }
  }

  void _checkCancelled() {
    if (_cancelRequested) throw const ArchiveCancelledException();
  }

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) =>
      _operation(() => _list(archivePath, password: password));

  @override
  Future<void> create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  }) => _operation(() => _create(options, onProgress: onProgress));

  @override
  Future<void> extract(
    ExtractArchiveOptions options, {
    ProgressCallback? onProgress,
  }) => _operation(() => _extract(options, onProgress: onProgress));

  @override
  Future<void> extractEntries(
    ExtractEntriesOptions options, {
    ProgressCallback? onProgress,
  }) => _operation(() => _extractEntries(options, onProgress: onProgress));

  @override
  Future<void> addEntries(
    AddEntriesOptions options, {
    ProgressCallback? onProgress,
  }) => _operation(() => _addEntries(options, onProgress: onProgress));

  @override
  Future<void> updateEntry({
    required String archivePath,
    required String entryPath,
    required String sourcePath,
    String? password,
    ProgressCallback? onProgress,
  }) => _operation(
    () => _updateEntry(
      archivePath: archivePath,
      entryPath: entryPath,
      sourcePath: sourcePath,
      password: password,
      onProgress: onProgress,
    ),
  );

  @override
  Future<void> deleteEntries({
    required String archivePath,
    required List<String> entryPaths,
    String? password,
    ProgressCallback? onProgress,
  }) => _operation(
    () => _deleteEntries(
      archivePath: archivePath,
      entryPaths: entryPaths,
      password: password,
      onProgress: onProgress,
    ),
  );

  @override
  Future<void> test(
    String archivePath, {
    String? password,
    ProgressCallback? onProgress,
  }) => _operation(
    () => _test(archivePath, password: password, onProgress: onProgress),
  );

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

  static final _progressPattern = RegExp(r'(?<!\d)(\d{1,3})%');

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

  Future<ArchiveListing> _list(String archivePath, {String? password}) async {
    final args = <String>['l', '-slt'];
    if (password != null && password.isNotEmpty) args.add('-p$password');
    args.add(p.absolute(archivePath));

    final output = await _run(args);
    final listing = output.length > 512 * 1024
        ? await Isolate.run(() => parseTechnicalListing(archivePath, output))
        : parseTechnicalListing(archivePath, output);
    return ArchiveListing(
      archivePath: listing.archivePath,
      entries: listing.entries,
      type: (listing.type ?? p.extension(archivePath).replaceFirst('.', ''))
          .toUpperCase(),
      physicalSize: listing.physicalSize ?? await File(archivePath).length(),
      method: listing.method,
      solid: listing.solid,
      blocks: listing.blocks,
    );
  }

  Future<void> _create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (options.sources.isEmpty) throw const ArchiveException('没有选择要压缩的文件');
    if (options.compressionLevel < 0 ||
        options.compressionLevel > 9 ||
        (options.maxThreads != null && options.maxThreads! < 1)) {
      throw const ArchiveException('压缩等级或线程数量无效');
    }
    final volume = options.volumeSize;
    if (volume != null &&
        volume.isNotEmpty &&
        !RegExp(
          r'^[1-9][0-9]*[bkmg]?$',
          caseSensitive: false,
        ).hasMatch(volume)) {
      throw const ArchiveException('分卷大小必须是大于零的整数');
    }
    if (options.format.singleSourceOnly &&
        (options.sources.length != 1 ||
            await FileSystemEntity.type(
                  options.sources.first,
                  followLinks: false,
                ) !=
                FileSystemEntityType.file)) {
      throw ArchiveException(
        '${options.format.label} 只能压缩一个普通文件；文件夹请选择 TAR.GZ 或 TAR.XZ',
      );
    }
    if (options.password?.isNotEmpty == true &&
        !options.format.supportsPassword) {
      throw ArchiveException('${options.format.label} 格式不支持密码加密');
    }
    final target = p.absolute(options.archivePath);
    for (final source in options.sources) {
      if (p.equals(p.absolute(source), target)) {
        throw const ArchiveException('压缩包不能覆盖输入文件本身');
      }
      if (await FileSystemEntity.type(source, followLinks: false) ==
          FileSystemEntityType.notFound) {
        throw ArchiveException('找不到输入文件：${p.basename(source)}');
      }
    }
    await Directory(p.dirname(target)).create(recursive: true);
    final workspace = await Directory(p.dirname(target))
        .createTemp('.jucier-create-');
    try {
      final output = p.join(workspace.path, p.basename(target));
      var sources = options.sources.map(p.absolute).toList();
      final excludedPaths = [target];
      final oldVolume = RegExp(
        '^${RegExp.escape(p.basename(target))}\\.[0-9]{3,}\$',
      );
      await for (final entity in Directory(
        p.dirname(target),
      ).list(followLinks: false)) {
        if (oldVolume.hasMatch(p.basename(entity.path))) {
          excludedPaths.add(entity.path);
        }
      }
      final exclusions = ['-xr!${p.basename(workspace.path)}'];
      for (final source in sources) {
        for (final excluded in excludedPaths) {
          if (p.isWithin(source, excluded)) {
            exclusions.add(
              '-x!${p.relative(excluded, from: p.dirname(source))}',
            );
          }
        }
      }
      if (options.format.usesTarContainer) {
        final tar = p.join(
          workspace.path,
          '${p.basename(target).substring(0, p.basename(target).length - options.format.extension.length)}tar',
        );
        await _run([
          'a',
          '-ttar',
          '-snl',
          '-y',
          '-bsp1',
          ...exclusions,
          tar,
          '-spd',
          '--',
          ...sources,
        ], onProgress: _scaleProgress(onProgress, 0, 0.2));
        sources = [tar];
      }
      final threads =
          options.maxThreads ?? Platform.numberOfProcessors.clamp(1, 8);
      final args = <String>[
        'a',
        '-t${options.format.sevenZipType}',
        '-mx=${options.compressionLevel}',
        '-mmt=$threads',
        '-y',
        '-bsp1',
        '-bb0',
        ...exclusions,
      ];
      if (Platform.isMacOS && options.format.supportsSymbolicLinks) {
        args.add('-snl');
      }
      if (options.format == ArchiveFormat.sevenZip &&
          options.compressionLevel > 0) {
        args.addAll(switch (options.preset) {
          CompressionPreset.compact => ['-md=32m', '-ms=256m', '-mqs=on'],
          CompressionPreset.editable => ['-md=16m', '-ms=off'],
          CompressionPreset.fast => ['-md=8m', '-ms=64m'],
          CompressionPreset.balanced => ['-md=16m', '-ms=128m'],
        });
      }
      if (options.password case final password? when password.isNotEmpty) {
        args.add('-p$password');
        if (options.format == ArchiveFormat.sevenZip) args.add('-mhe=on');
        if (options.format == ArchiveFormat.zip) {
          args.add('-mem=${options.zipEncryption.method}');
        }
      }
      if (volume?.isNotEmpty == true) args.add('-v$volume');
      args
        ..add(output)
        ..addAll(['-spd', '--'])
        ..addAll(sources);
      final start = options.format.usesTarContainer ? 0.2 : 0.0;
      await _run(
        args,
        onProgress: _scaleProgress(onProgress, start, 0.9 - start),
      );
      final firstOutput = volume?.isNotEmpty == true ? '$output.001' : output;
      await _run([
        't',
        firstOutput,
        '-bsp1',
        '-bb0',
        if (options.password?.isNotEmpty == true) '-p${options.password}',
      ], onProgress: _scaleProgress(onProgress, 0.9, 0.09));
      _checkCancelled();
      await _installArchiveOutputs(
        workspace,
        output,
        target,
        split: volume?.isNotEmpty == true,
      );
      onProgress?.call(1);
    } finally {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    }
  }

  Future<void> _installArchiveOutputs(
    Directory workspace,
    String output,
    String target, {
    required bool split,
  }) async {
    final volumePattern = RegExp(
      '^${RegExp.escape(p.basename(target))}\\.[0-9]{3,}\$',
    );
    final generated = <File>[];
    await for (final entity in workspace.list(followLinks: false)) {
      if (entity is File &&
          (split
              ? volumePattern.hasMatch(p.basename(entity.path))
              : entity.path == output)) {
        generated.add(entity);
      }
    }
    if (generated.isEmpty) throw const ArchiveException('未生成压缩包');
    final old = <String>[];
    await for (final entity in Directory(
      p.dirname(target),
    ).list(followLinks: false)) {
      if (entity.path == target ||
          volumePattern.hasMatch(p.basename(entity.path))) {
        if (entity is! File) throw const ArchiveException('保存位置存在同名文件夹或符号链接');
        old.add(entity.path);
      }
    }
    final backup = await Directory(p.join(workspace.path, 'backup')).create();
    final moved = <String, String>{};
    final installed = <String>[];
    try {
      for (final path in old) {
        final saved = p.join(backup.path, p.basename(path));
        await File(path).rename(saved);
        moved[path] = saved;
      }
      for (final file in generated) {
        final destination = p.join(p.dirname(target), p.basename(file.path));
        await file.rename(destination);
        installed.add(destination);
      }
    } catch (_) {
      for (final path in installed) {
        await File(path).delete();
      }
      for (final entry in moved.entries) {
        await File(entry.value).rename(entry.key);
      }
      rethrow;
    }
  }

  Future<void> _extract(
    ExtractArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    final args = <String>[
      'x',
      p.absolute(options.archivePath),
      '-o${options.outputDirectory}',
      options.conflict.switchValue,
      '-y',
      '-bsp1',
      '-bb0',
    ];
    if (options.password case final password? when password.isNotEmpty) {
      args.add('-p$password');
    }
    await _run(args, onProgress: onProgress);
  }

  Future<void> _extractEntries(
    ExtractEntriesOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (options.entryPaths.isEmpty) {
      throw const ArchiveException('没有选择要解压的文件');
    }
    final entries = options.entryPaths.map(normalizeArchiveEntryPath).toList();
    if (options.withoutParentDirectories) {
      final selected =
          options.selectedEntryPath ?? options.selectedEntryPaths.firstOrNull;
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
      p.absolute(options.archivePath),
      '-o${options.outputDirectory}',
      options.conflict.switchValue,
      '-y',
      '-bsp1',
      '-bb0',
    ];
    if (options.password case final password? when password.isNotEmpty) {
      args.add('-p$password');
    }
    final output = await _runMembers(args, entries, onProgress: onProgress);
    _ensureFilesProcessed(output);
  }

  String _zipEncryptionMethod(ArchiveListing listing) {
    final encrypted = listing.entries.where((entry) => entry.encrypted == true);
    return encrypted.isEmpty ||
            encrypted.any((entry) => entry.method?.contains('AES') == true)
        ? 'AES256'
        : 'ZipCrypto';
  }

  Future<ArchiveListing> _requireWritable(
    String archivePath,
    String? password,
  ) async {
    final listing = await _list(archivePath, password: password);
    if (!listing.canUpdate) {
      throw const ArchiveException('此压缩格式或分卷压缩包不支持修改');
    }
    final encrypted = listing.entries
        .where((entry) => entry.encrypted == true && !entry.isDirectory)
        .firstOrNull;
    if (encrypted != null) {
      if (password == null || password.isEmpty) {
        throw const ArchivePasswordRequiredException();
      }
      // Verify against existing data before adding files under a different key.
      await _runMembers(
        ['t', p.absolute(archivePath), '-p$password', '-bb0'],
        [encrypted.path],
      );
    }
    return listing;
  }

  Future<void> _addEntries(
    AddEntriesOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (options.sources.isEmpty && !options.recompress) {
      throw const ArchiveException('没有可添加到压缩包的文件');
    }
    final destination = options.destinationDirectory.isEmpty
        ? ''
        : normalizeArchiveEntryPath(options.destinationDirectory);

    final listing = await _requireWritable(
      options.archivePath,
      options.password,
    );
    if (options.recompress) {
      if (!_canCompactSevenZip(listing)) {
        throw const ArchiveException('仅支持整理 LZMA2 格式的 7z 压缩包');
      }
      final encrypted = listing.entries.any((entry) => entry.encrypted == true);
      if (_canCompactSevenZip(listing) &&
          (!encrypted || options.password?.isNotEmpty == true)) {
        final encryptHeaders = encrypted
            ? await _usesEncryptedHeaders(options.archivePath)
            : false;
        await _rebuildSevenZipWithEntries(
          options,
          destination,
          encryptHeaders: encryptHeaders,
          originalListing: listing,
          onProgress: onProgress,
        );
        return;
      }
    }

    await _addEntriesIncrementally(
      options,
      destination,
      listing: listing,
      onProgress: onProgress,
    );
  }

  bool _canCompactSevenZip(ArchiveListing listing) =>
      listing.type?.toLowerCase() == '7z' &&
      (listing.method?.toUpperCase().contains('LZMA2') ?? false);

  Future<bool> _usesEncryptedHeaders(String archivePath) async {
    try {
      await _list(archivePath);
      return false;
    } on ArchivePasswordRequiredException {
      return true;
    }
  }

  Future<void> _addEntriesIncrementally(
    AddEntriesOptions options,
    String destination, {
    required ArchiveListing listing,
    ProgressCallback? onProgress,
  }) async {
    final staging = await Directory.systemTemp.createTemp('jucier-add-');
    try {
      final relativePaths = await _stageSources(
        staging,
        options.sources,
        destination,
        mergeExistingDirectories: false,
      );

      final args = <String>[
        'a',
        p.absolute(options.archivePath),
        '-y',
        '-bsp1',
        '-bb0',
      ];
      if (Platform.isMacOS) args.add('-snl');
      if (options.password case final password? when password.isNotEmpty) {
        args.add('-p$password');
        if (listing.detectedType == 'zip') {
          args.add('-mem=${_zipEncryptionMethod(listing)}');
        }
      }
      args
        ..addAll(['-spd', '--'])
        ..addAll(relativePaths.map(_literalMember));
      await _run(args, onProgress: onProgress, workingDirectory: staging.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _checkTemporarySpace(ArchiveListing listing) async {
    final requiredBytes = listing.entries
        .where((entry) => !entry.isDirectory)
        .fold(0, (sum, entry) => sum + (entry.size ?? 0));
    if (requiredBytes < 64 * 1024 * 1024 ||
        !(Platform.isMacOS || Platform.isLinux)) {
      return;
    }
    String output;
    try {
      output = await _run([
        '-Pk',
        Directory.systemTemp.path,
      ], executableOverride: '/bin/df');
    } on ArchiveCancelledException {
      rethrow;
    } on ArchiveException {
      return;
    } // Some filesystems cannot report free space.
    final match = RegExp(
      r'^.*?\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+',
      multiLine: true,
    ).firstMatch(output);
    final available = match == null ? null : int.tryParse(match.group(1)!);
    if (available != null && requiredBytes > available * 1024) {
      throw ArchiveException(
        '临时空间不足，整理此压缩包至少需要 ${(requiredBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB 可用空间',
      );
    }
  }

  Future<void> _rebuildSevenZipWithEntries(
    AddEntriesOptions options,
    String destination, {
    required bool encryptHeaders,
    required ArchiveListing originalListing,
    ProgressCallback? onProgress,
  }) async {
    await _checkTemporarySpace(originalListing);
    final workspace = await Directory.systemTemp.createTemp(
      'jucier-compact-7z-',
    );
    final content = Directory(p.join(workspace.path, 'content'));
    final replacement = File(
      p.join(
        p.dirname(options.archivePath),
        '.${p.basename(options.archivePath)}.jucier-'
        '$pid-${DateTime.now().microsecondsSinceEpoch}.7z',
      ),
    );
    try {
      await content.create();
      final extractArgs = <String>[
        'x',
        p.absolute(options.archivePath),
        '-o${content.path}',
        '-aoa',
        '-y',
        '-bsp1',
        '-bb0',
      ];
      if (options.password case final password? when password.isNotEmpty) {
        extractArgs.add('-p$password');
      }
      await _run(extractArgs, onProgress: _scaleProgress(onProgress, 0, 0.35));

      if (await _pathTraversesLink(content.path, destination)) {
        throw const ArchiveException('不能向压缩包内的符号链接目录添加文件');
      }

      final replacedRoots = await _stageSources(
        content,
        options.sources,
        destination,
        mergeExistingDirectories: true,
      );

      final createArgs = <String>[
        'a',
        '-t7z',
        '-mx=5',
        '-ms=on',
        '-y',
        '-bsp1',
        '-bb0',
      ];
      if (Platform.isMacOS) createArgs.add('-snl');
      if (options.password case final password? when password.isNotEmpty) {
        createArgs.add('-p$password');
        if (encryptHeaders) createArgs.add('-mhe=on');
      }
      createArgs
        ..add(replacement.path)
        ..add('.');
      await _run(
        createArgs,
        workingDirectory: content.path,
        onProgress: _scaleProgress(onProgress, 0.35, 0.6),
      );

      await _run([
        't',
        replacement.path,
        '-bb0',
        if (options.password case final password? when password.isNotEmpty)
          '-p$password',
      ]);

      final rebuilt = await _list(replacement.path, password: options.password);
      final byPath = {for (final entry in rebuilt.entries) entry.path: entry};
      for (final previous in originalListing.entries) {
        if (replacedRoots.any(
          (root) => previous.path == root || previous.path.startsWith('$root/'),
        )) {
          continue;
        }
        final current = byPath[previous.path];
        if (current == null ||
            current.isDirectory != previous.isDirectory ||
            (!previous.isDirectory &&
                (current.size != previous.size ||
                    (previous.crc != null && current.crc != previous.crc)))) {
          throw const ArchiveException('整理后的文件清单与原包不一致，已保留原压缩包');
        }
      }
      _checkCancelled();
      await replacement.rename(options.archivePath);
      onProgress?.call(1);
    } finally {
      if (await replacement.exists()) await replacement.delete();
      if (await workspace.exists()) await workspace.delete(recursive: true);
    }
  }

  ProgressCallback? _scaleProgress(
    ProgressCallback? callback,
    double start,
    double span,
  ) => callback == null ? null : (value) => callback(start + value * span);

  Future<bool> _pathTraversesLink(String root, String relativePath) async {
    var current = root;
    for (final component in p.posix.split(relativePath)) {
      current = p.join(current, component);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        return true;
      }
    }
    return false;
  }

  Future<List<String>> _stageSources(
    Directory root,
    List<String> sources,
    String destination, {
    required bool mergeExistingDirectories,
  }) async {
    final claimedPaths = <String>{};
    final relativePaths = <String>[];
    for (final sourcePath in sources) {
      _checkCancelled();
      final sourceType = await FileSystemEntity.type(
        sourcePath,
        followLinks: false,
      );
      if (sourceType == FileSystemEntityType.notFound) {
        throw ArchiveException('找不到要添加的文件：${p.basename(sourcePath)}');
      }
      final baseName = p.basename(sourcePath);
      var relativePath = destination.isEmpty
          ? baseName
          : p.posix.join(destination, baseName);
      for (var suffix = 1; !_claimPath(claimedPaths, relativePath); suffix++) {
        final isDirectory = sourceType == FileSystemEntityType.directory;
        final extension = isDirectory ? '' : p.extension(baseName);
        final stem = isDirectory
            ? baseName
            : p.basenameWithoutExtension(baseName);
        final uniqueName = '$stem ($suffix)$extension';
        relativePath = destination.isEmpty
            ? uniqueName
            : p.posix.join(destination, uniqueName);
      }

      final stagedPath = p.joinAll([root.path, ...p.posix.split(relativePath)]);
      await _copySourceIntoStaging(
        sourcePath,
        sourceType,
        stagedPath,
        mergeExistingDirectories: mergeExistingDirectories,
      );
      relativePaths.add(relativePath);
    }
    return relativePaths;
  }

  bool _claimPath(Set<String> claimedPaths, String path) {
    final key = Platform.isMacOS ? path.toLowerCase() : path;
    return claimedPaths.add(key);
  }

  Future<void> _copySourceIntoStaging(
    String sourcePath,
    FileSystemEntityType sourceType,
    String stagedPath, {
    required bool mergeExistingDirectories,
  }) async {
    _checkCancelled();
    final targetType = await FileSystemEntity.type(
      stagedPath,
      followLinks: false,
    );
    final mergeDirectory =
        mergeExistingDirectories &&
        sourceType == FileSystemEntityType.directory &&
        targetType == FileSystemEntityType.directory;

    if (!mergeDirectory && targetType != FileSystemEntityType.notFound) {
      await _deleteEntity(stagedPath, targetType);
    }
    await Directory(mergeDirectory ? stagedPath : p.dirname(stagedPath))
        .create(recursive: true);

    if (Platform.isMacOS) {
      final sourceArgument = mergeDirectory
          ? '$sourcePath${p.separator}.'
          : sourcePath;
      await _runCopy(['-ac', sourceArgument, stagedPath]);
      return;
    }

    await _copyEntityRecursively(
      sourcePath,
      stagedPath,
      mergeExistingDirectories: mergeDirectory,
    );
  }

  Future<void> _copyEntityRecursively(
    String sourcePath,
    String targetPath, {
    required bool mergeExistingDirectories,
  }) async {
    _checkCancelled();
    final type = await FileSystemEntity.type(sourcePath, followLinks: false);
    if (type == FileSystemEntityType.link) {
      await Link(targetPath).create(await Link(sourcePath).target());
      return;
    }
    if (type == FileSystemEntityType.file) {
      final copied = await File(sourcePath).copy(targetPath);
      await copied.setLastModified((await File(sourcePath).stat()).modified);
      return;
    }
    if (type != FileSystemEntityType.directory) return;

    final target = Directory(targetPath);
    await target.create(recursive: true);
    await for (final child in Directory(sourcePath).list(followLinks: false)) {
      final childTarget = p.join(target.path, p.basename(child.path));
      final childTargetType = await FileSystemEntity.type(
        childTarget,
        followLinks: false,
      );
      if (!mergeExistingDirectories &&
          childTargetType != FileSystemEntityType.notFound) {
        await _deleteEntity(childTarget, childTargetType);
      }
      await _copyEntityRecursively(
        child.path,
        childTarget,
        mergeExistingDirectories: mergeExistingDirectories,
      );
    }
  }

  Future<void> _deleteEntity(String path, FileSystemEntityType type) async {
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type == FileSystemEntityType.link) {
      await Link(path).delete();
    } else {
      await File(path).delete();
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
        p.absolute(options.archivePath),
        '-o${staging.path}',
        '-aoa',
        '-y',
        '-bsp1',
        '-bb0',
      ];
      if (options.password case final password? when password.isNotEmpty) {
        args.add('-p$password');
      }
      final output = await _runMembers(
        args,
        entries,
        onProgress: _scaleProgress(onProgress, 0, 0.8),
      );
      _ensureFilesProcessed(output);

      final selectedPaths = options.selectedEntryPaths.isEmpty
          ? [selectedEntry]
          : options.selectedEntryPaths;
      var completed = 0;
      for (final selected in selectedPaths) {
        _checkCancelled();
        final normalized = normalizeArchiveEntryPath(selected);
        final sourcePath = p.joinAll([
          staging.path,
          ...p.posix.split(normalized),
        ]);
        if (await _pathTraversesLink(
          staging.path,
          p.posix.dirname(normalized),
        )) {
          throw const ArchiveException('不能通过压缩包内的符号链接读取所选文件');
        }
        await _copySelectedEntry(
          sourcePath,
          options.outputDirectory,
          options.conflict,
          outputPath: options.outputPath,
        );
        onProgress?.call(0.8 + 0.2 * ++completed / selectedPaths.length);
      }
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
    _checkCancelled();
    final root = Directory(outputDirectory);
    await root.create(recursive: true);
    final safeRoot = await root.resolveSymbolicLinks();
    final requested = outputPath == null
        ? p.join(safeRoot, p.basename(sourcePath))
        : p.join(safeRoot, p.basename(outputPath));
    await _copyTree(sourcePath, requested, conflict, safeRoot);
  }

  Future<void> _checkTargetParents(String root, String target) async {
    if (!p.isWithin(root, target)) {
      throw const ArchiveException('解压目标超出了所选文件夹');
    }
    var current = root;
    for (final component in p.split(
      p.relative(p.dirname(target), from: root),
    )) {
      if (component == '.') continue;
      current = p.join(current, component);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const ArchiveException('目标路径包含符号链接，请选择其他解压位置');
      }
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const ArchiveException('目标路径中有同名文件阻挡文件夹');
      }
    }
  }

  Future<void> _copyTree(
    String source,
    String requested,
    ExtractionConflict conflict,
    String safeRoot,
  ) async {
    _checkCancelled();
    await _checkTargetParents(safeRoot, requested);
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const ArchiveException('7-Zip 未能解压所选文件');
    }
    var target = requested;
    final existing = await FileSystemEntity.type(target, followLinks: false);
    if (existing != FileSystemEntityType.notFound) {
      if (conflict == ExtractionConflict.rename) {
        target = await _uniquePath(
          target,
          isDirectory: type == FileSystemEntityType.directory,
        );
      } else if (existing == FileSystemEntityType.link) {
        // Never merge through links already present in the destination.
        if (conflict == ExtractionConflict.skip) return;
        throw const ArchiveException('目标位置存在符号链接，请选择跳过或自动重命名');
      } else if (!(type == FileSystemEntityType.directory &&
          existing == type)) {
        if (conflict == ExtractionConflict.skip) return;
        if (existing == FileSystemEntityType.directory) {
          throw const ArchiveException('不能用文件覆盖非空文件夹，请选择自动重命名');
        }
        if (type != FileSystemEntityType.file) {
          await _deleteEntity(target, existing);
        }
      }
    }
    await _checkTargetParents(safeRoot, target);
    await Directory(p.dirname(target)).create(recursive: true);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).create(recursive: true);
      await for (final child in Directory(source).list(followLinks: false)) {
        await _copyTree(
          child.path,
          p.join(target, p.basename(child.path)),
          conflict,
          safeRoot,
        );
      }
    } else if (type == FileSystemEntityType.link) {
      final link = await Link(source).target();
      final resolved = p.normalize(p.join(p.dirname(target), link));
      if (p.isAbsolute(link) ||
          !(resolved == safeRoot || p.isWithin(safeRoot, resolved))) {
        throw const ArchiveException('压缩包包含指向解压目录之外的符号链接');
      }
      await _checkTargetParents(safeRoot, resolved);
      await Link(target).create(link);
    } else if (type == FileSystemEntityType.file) {
      final temporary = await Directory(p.dirname(target))
          .createTemp('.jucier-copy-');
      try {
        final staged = p.join(temporary.path, 'file');
        if (Platform.isMacOS) {
          await _runCopy(['-ac', source, staged]);
        } else {
          await File(source).copy(staged);
          await File(staged)
              .setLastModified((await File(source).stat()).modified);
        }
        _checkCancelled();
        await _checkTargetParents(safeRoot, target);
        await File(staged).rename(target);
      } finally {
        await temporary.delete(recursive: true);
      }
    } else {
      throw const ArchiveException('压缩包包含不支持的特殊文件');
    }
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

  String _literalMember(String path) => path.startsWith('@') ? './$path' : path;

  void _ensureFilesProcessed(String output) {
    if (output.toLowerCase().contains('no files to process')) {
      throw const ArchiveException('压缩包中找不到所选文件');
    }
  }

  Future<void> _updateEntry({
    required String archivePath,
    required String entryPath,
    required String sourcePath,
    String? password,
    ProgressCallback? onProgress,
  }) async {
    final listing = await _requireWritable(archivePath, password);
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

      final args = <String>[
        'u',
        p.absolute(archivePath),
        '-y',
        '-bsp1',
        '-bb0',
      ];
      if (password case final value? when value.isNotEmpty) {
        args.add('-p$value');
        if (listing.detectedType == 'zip') {
          args.add('-mem=${_zipEncryptionMethod(listing)}');
        }
      }
      args
        ..addAll(['-spd', '--'])
        ..add(_literalMember(normalizedEntry));
      await _run(args, onProgress: onProgress, workingDirectory: staging.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _deleteEntries({
    required String archivePath,
    required List<String> entryPaths,
    String? password,
    ProgressCallback? onProgress,
  }) async {
    if (entryPaths.isEmpty) {
      throw const ArchiveException('没有选择要删除的文件');
    }
    await _requireWritable(archivePath, password);
    final entries = entryPaths.map(normalizeArchiveEntryPath).toList();
    final args = <String>['d', p.absolute(archivePath), '-y', '-bsp1', '-bb0'];
    if (password case final value? when value.isNotEmpty) {
      args.add('-p$value');
    }
    await _runMembers(args, entries, onProgress: onProgress);
  }

  Future<void> _test(
    String archivePath, {
    String? password,
    ProgressCallback? onProgress,
  }) async {
    final args = <String>['t', p.absolute(archivePath), '-bsp1', '-bb0'];
    if (password != null && password.isNotEmpty) args.add('-p$password');
    await _run(args, onProgress: onProgress);
  }

  @override
  Future<void> cancel() async {
    if (!_operationActive) return;
    _cancelRequested = true;
    final process = _activeProcess;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(milliseconds: 800));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  Future<String> _runMembers(
    List<String> args,
    List<String> entries, {
    ProgressCallback? onProgress,
  }) async {
    final length = entries.fold(
      0,
      (sum, entry) => sum + utf8.encode(entry).length + 8,
    );
    if (length < 24000) {
      return _run([
        ...args,
        '-spd',
        ...entries.map((entry) => '-i!$entry'),
      ], onProgress: onProgress);
    }
    if (entries.any((entry) => entry.contains('\n') || entry.contains('\r'))) {
      throw const ArchiveException('含换行符的文件名不能用于大批量操作，请单独处理');
    }
    final directory = await Directory.systemTemp.createTemp('jucier-members-');
    try {
      final list = File(p.join(directory.path, 'members.txt'));
      await list.writeAsString(entries.join('\n'));
      return await _run([
        ...args,
        '-spd',
        '-scsUTF-8',
        '-i@${list.path}',
      ], onProgress: onProgress);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _runCopy(List<String> arguments) async {
    await _run(arguments, executableOverride: '/bin/cp');
  }

  Future<String> _run(
    List<String> arguments, {
    ProgressCallback? onProgress,
    String? workingDirectory,
    String? executableOverride,
  }) async {
    _checkCancelled();
    if (_activeProcess != null) throw const ArchiveException('已有操作正在进行');
    final executable = executableOverride ?? await _resolveExecutable();
    _checkCancelled();
    onPhaseChanged?.call(
      executableOverride != null
          ? (executableOverride == '/bin/df' ? '正在检查可用空间' : '正在复制文件')
          : switch (arguments.firstOrNull) {
              'l' => '正在读取目录',
              'a' => '正在压缩',
              'u' => '正在更新文件',
              'd' => '正在删除文件',
              'x' => '正在解压',
              't' => '正在校验',
              _ => '正在处理',
            },
    );
    final process = await Process.start(
      executable,
      executableOverride == null ? ['-sccUTF-8', ...arguments] : arguments,
      runInShell: false,
      workingDirectory: workingDirectory,
    );
    _activeProcess = process;
    if (_cancelRequested) process.kill(ProcessSignal.sigkill);
    // 7-Zip must report a password request to the UI instead of waiting on stdin.
    unawaited(process.stdin.close().catchError((Object _) {}));
    final listing = arguments.firstOrNull == 'l';
    final output = StringBuffer();
    var tail = '';
    var progressTail = '';
    var lastProgress = -1;
    void consume(String text) {
      if (listing) {
        output.write(text);
      } else {
        tail += text;
        if (tail.length > 65536) tail = tail.substring(tail.length - 65536);
      }
      final chunk = progressTail + text;
      if (onProgress != null) {
        for (final match in _progressPattern.allMatches(chunk)) {
          final value = int.parse(match.group(1)!).clamp(0, 100);
          if (value > lastProgress) {
            lastProgress = value;
            onProgress(value / 100);
          }
        }
      }
      progressTail = chunk.substring(chunk.length > 4 ? chunk.length - 4 : 0);
    }

    final streams = [
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(consume),
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach(consume),
    ];
    late int exitCode;
    try {
      await Future.wait<void>([
        ...streams,
        process.exitCode.then((code) {
          exitCode = code;
        }),
      ]);
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
    _checkCancelled();
    final text = listing ? output.toString() : tail;
    if (exitCode != 0) _throwForFailure(exitCode, text);
    if (lastProgress != 100) onProgress?.call(1);
    return text;
  }

  Never _throwForFailure(int exitCode, String output) {
    final normalized = output.toLowerCase();
    if (_passwordMarkers.any(normalized.contains)) {
      throw ArchivePasswordRequiredException(output: output);
    }
    if (exitCode == 255) throw const ArchiveCancelledException();
    if (_permissionMarkers.any(normalized.contains)) {
      throw ArchiveException(
        '没有足够的文件访问权限，请检查输入文件和保存位置',
        output: output,
        exitCode: exitCode,
      );
    }

    if (exitCode == 1) throw ArchiveWarningException(output: output);
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
    if (_executableCache case final cached?) return cached;
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
        return _executableCache = candidate;
      }
    }

    final pathProbe = await Process.run('which', const [
      '7zz',
    ], runInShell: false);
    if (pathProbe.exitCode == 0) {
      final path = (pathProbe.stdout as String).trim();
      if (path.isNotEmpty) return _executableCache = path;
    }
    throw const ArchiveException('找不到 7-Zip 引擎。请先运行 tool/build_7zip_macos.sh');
  }

  static ArchiveListing parseTechnicalListing(
    String archivePath,
    String output,
  ) {
    var current = <String, String>{};

    String? type;
    int? physicalSize;
    String? method;
    bool? solid;
    int? blocks;
    final entries = <ArchiveEntry>[];
    void finishRecord() {
      final record = current;
      current = <String, String>{};
      final path = record['Path'];
      if (path == null) return;

      if (p.equals(path, archivePath) || record.containsKey('Type')) {
        type ??= record['Type'];
        physicalSize ??= int.tryParse(record['Physical Size'] ?? '');
        method ??= record['Method'];
        solid ??= switch (record['Solid']) {
          '+' => true,
          '-' => false,
          _ => null,
        };
        blocks ??= int.tryParse(record['Blocks'] ?? '');
        if (record.containsKey('Type')) return;
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

    // Consume records as they arrive instead of retaining a second full set
    // of maps and a materialized list of every output line.
    for (final line in LineSplitter.split(output)) {
      if (line.trim().isEmpty) {
        finishRecord();
        continue;
      }
      final separator = line.indexOf(' = ');
      if (separator <= 0) continue;
      current[line.substring(0, separator)] = line.substring(separator + 3);
    }
    finishRecord();

    return ArchiveListing(
      archivePath: archivePath,
      entries: entries,
      type: type,
      physicalSize: physicalSize,
      method: method,
      solid: solid,
      blocks: blocks,
    );
  }
}
