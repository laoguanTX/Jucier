import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_engine.dart';
import '../archive/archive_path.dart';

abstract interface class FileLauncher {
  Future<void> open(String path);
}

class MacOSFileLauncher implements FileLauncher {
  MacOSFileLauncher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.jucier/platform');

  final MethodChannel _channel;

  @override
  Future<void> open(String path) async {
    try {
      await _channel.invokeMethod<void>('openFile', path);
    } on PlatformException catch (error) {
      throw ArchiveException(error.message ?? '无法使用默认应用打开该文件');
    } on MissingPluginException {
      throw const ArchiveException('当前平台不支持打开预览文件');
    }
  }
}

typedef PreviewChangedCallback = Future<void> Function(PreviewSession session);

class FilePreviewService {
  FilePreviewService({
    required this.launcher,
    required this.onChanged,
    this.pollInterval = const Duration(milliseconds: 750),
  });

  final FileLauncher launcher;
  final PreviewChangedCallback onChanged;
  final Duration pollInterval;
  final List<PreviewSession> _sessions = [];
  bool _disposed = false;

  Future<PreviewSession> open({
    required String archivePath,
    required String entryPath,
    required String? password,
    required Future<void> Function(String outputDirectory) extract,
    bool preserveArchiveStructure = true,
  }) async {
    if (_disposed) throw StateError('FilePreviewService is disposed');
    final normalizedEntry = normalizeArchiveEntryPath(entryPath);
    final root = await Directory.systemTemp.createTemp('jucier-preview-');
    try {
      await extract(root.path);
      final file = File(
        preserveArchiveStructure
            ? p.joinAll([root.path, ...p.posix.split(normalizedEntry)])
            : p.join(root.path, p.posix.basename(normalizedEntry)),
      );
      if (!await file.exists()) {
        throw const ArchiveException('无法从压缩包中解压该预览文件');
      }
      final session = PreviewSession._(
        archivePath: archivePath,
        entryPath: normalizedEntry,
        password: password,
        file: file,
        root: root,
        pollInterval: pollInterval,
        onChanged: onChanged,
      );
      await session._initialize();
      await launcher.open(file.path);
      if (_disposed) {
        await session.dispose();
        throw StateError('FilePreviewService is disposed');
      }
      _sessions.add(session);
      session._start();
      return session;
    } catch (_) {
      if (await root.exists()) await root.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final sessions = List<PreviewSession>.of(_sessions);
    _sessions.clear();
    await Future.wait(sessions.map((session) => session.dispose()));
  }
}

class PreviewSession {
  PreviewSession._({
    required this.archivePath,
    required this.entryPath,
    required this.password,
    required this.file,
    required this._root,
    required this._pollInterval,
    required this._onChanged,
  });

  final String archivePath;
  final String entryPath;
  final String? password;
  final File file;
  final Directory _root;
  final Duration _pollInterval;
  final PreviewChangedCallback _onChanged;

  Timer? _timer;
  _FileSignature? _baseline;
  bool _checking = false;
  bool _disposed = false;

  String get filePath => file.path;

  Future<void> _initialize() async {
    _baseline = await _signature();
  }

  void _start() {
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  Future<void> checkNow() => _check();

  Future<void> _check() async {
    if (_disposed || _checking) return;
    _checking = true;
    try {
      final current = await _signature();
      if (current == null || current == _baseline) return;
      _baseline = current;
      await _onChanged(this);
    } finally {
      _checking = false;
    }
  }

  Future<_FileSignature?> _signature() async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      return _FileSignature(stat.modified.microsecondsSinceEpoch, stat.size);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    try {
      if (await _root.exists()) await _root.delete(recursive: true);
    } on FileSystemException {
      // The OS or the previewing app may still briefly hold the file.
    }
  }
}

class _FileSignature {
  const _FileSignature(this.modifiedMicros, this.size);

  final int modifiedMicros;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is _FileSignature &&
      modifiedMicros == other.modifiedMicros &&
      size == other.size;

  @override
  int get hashCode => Object.hash(modifiedMicros, size);
}
