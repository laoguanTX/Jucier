import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../archive/archive_engine.dart';
import '../archive/archive_entry.dart';
import '../archive/archive_options.dart';

/// Holds archive workflow state independently from the widget tree.
///
/// Presentation concerns such as pickers, password prompts, and result dialogs
/// remain in the presentation shell; engine state and progress are managed
/// here.
class ArchiveWorkflowController extends ChangeNotifier {
  ArchiveWorkflowController(this._engine);

  final ArchiveEngine _engine;

  ArchiveListing? _listing;
  String? _password;
  String? _operationLabel;
  double? _progress;
  bool _disposed = false;
  final List<Completer<void>> _idleWaiters = [];

  ArchiveListing? get listing => _listing;
  String? get password => _password;
  String? get operationLabel => _operationLabel;
  double? get progress => _progress;
  bool get busy => _operationLabel != null;

  Future<void> open(String path, {String? password}) async {
    _beginOperation('正在打开 ${p.basename(path)}');
    try {
      _listing = await _engine.list(path, password: password);
      _password = password;
      _notifyListeners();
    } finally {
      _endOperation();
    }
  }

  Future<void> create(CreateArchiveOptions options) async {
    _beginOperation('正在创建 ${p.basename(options.archivePath)}', progress: 0);
    try {
      await _engine.create(options, onProgress: _updateProgress);
    } finally {
      _endOperation();
    }
  }

  Future<void> extract(ExtractArchiveOptions options) async {
    _beginOperation('正在解压 ${p.basename(options.archivePath)}', progress: 0);
    try {
      await _engine.extract(options, onProgress: _updateProgress);
    } finally {
      _endOperation();
    }
  }

  Future<void> extractEntries(ExtractEntriesOptions options) async {
    _beginOperation('正在解压所选文件', progress: 0);
    try {
      await _engine.extractEntries(options, onProgress: _updateProgress);
    } finally {
      _endOperation();
    }
  }

  Future<void> updateEntry({
    required String archivePath,
    required String entryPath,
    required String sourcePath,
    String? password,
  }) async {
    _beginOperation('正在更新 ${p.basename(entryPath)}', progress: 0);
    try {
      await _engine.updateEntry(
        archivePath: archivePath,
        entryPath: entryPath,
        sourcePath: sourcePath,
        password: password,
        onProgress: _updateProgress,
      );
      await _refreshIfCurrent(archivePath);
    } finally {
      _endOperation();
    }
  }

  Future<void> deleteEntries(List<String> entryPaths) async {
    final current = _listing;
    if (current == null) return;
    _beginOperation('正在从压缩包删除文件', progress: 0);
    try {
      await _engine.deleteEntries(
        archivePath: current.archivePath,
        entryPaths: entryPaths,
        password: _password,
        onProgress: _updateProgress,
      );
      await _refreshIfCurrent(current.archivePath);
    } finally {
      _endOperation();
    }
  }

  Future<void> testCurrent() async {
    final current = _listing;
    if (current == null) return;

    _beginOperation('正在测试 ${p.basename(current.archivePath)}', progress: 0);
    try {
      await _engine.test(
        current.archivePath,
        password: _password,
        onProgress: _updateProgress,
      );
    } finally {
      _endOperation();
    }
  }

  void closeArchive() {
    _listing = null;
    _password = null;
    _notifyListeners();
  }

  Future<void> cancel() => _engine.cancel();

  Future<void> waitUntilIdle() {
    if (!busy) return Future.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  Future<void> _refreshIfCurrent(String archivePath) async {
    if (_listing?.archivePath != archivePath) return;
    _listing = await _engine.list(archivePath, password: _password);
    _notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
    super.dispose();
  }

  void _updateProgress(double value) {
    _progress = value;
    _notifyListeners();
  }

  void _beginOperation(String label, {double? progress}) {
    _operationLabel = label;
    _progress = progress;
    _notifyListeners();
  }

  void _endOperation() {
    _operationLabel = null;
    _progress = null;
    _notifyListeners();
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }
}
