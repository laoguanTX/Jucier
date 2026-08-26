import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'archive_engine.dart';
import 'archive_entry.dart';
import 'archive_options.dart';

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
