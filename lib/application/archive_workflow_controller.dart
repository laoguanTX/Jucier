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
  ArchiveWorkflowController(this._engine, {this.compressionPerformance}) {
    if (_engine case final ArchiveOperationEvents events) {
      events.onPhaseChanged = (phase) {
        if (_operationLabel == phase) return;
        _operationLabel = phase;
        _notifyListeners();
      };
    }
  }

  final ArchiveEngine _engine;
  final CompressionPerformance Function()? compressionPerformance;

  ArchiveListing? _listing;
  String? _password;
  String? _operationLabel;
  double? _progress;
  final ValueNotifier<double?> progressChanges = ValueNotifier(null);
  bool _disposed = false;
  Future<void>? _queue;
  int _queued = 0;
  int _cancelGeneration = 0;
  bool _currentCancelled = false;
  final List<Completer<void>> _idleWaiters = [];

  ArchiveListing? get listing => _listing;
  String? get password => _password;
  String? get operationLabel => _operationLabel;
  double? get progress => _progress;
  bool get busy => _queued > 0 || _operationLabel != null;

  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed) return Future.error(const ArchiveCancelledException());
    final generation = _cancelGeneration;
    final previous = _queue;
    _queued++;
    Future<void> run() async {
      try {
        if (previous != null) await previous;
        if (_disposed || generation != _cancelGeneration) {
          throw const ArchiveCancelledException();
        }
        _currentCancelled = false;
        await action();
      } finally {
        _queued--;
        if (_queued == 0) {
          _queue = null;
          for (final waiter in _idleWaiters) {
            if (!waiter.isCompleted) waiter.complete();
          }
          _idleWaiters.clear();
        }
        _notifyListeners();
      }
    }

    final operation = run();
    _queue = operation.onError((_, _) {});
    return operation;
  }

  Future<void> open(String path, {String? password}) =>
      _enqueue(() => _open(path, password: password));
  Future<void> create(
    CreateArchiveOptions options, {
    bool openAfterCreate = true,
  }) {
    // Capture the setting at enqueue time so later changes do not alter a
    // pending or running operation. Finder and the create dialog share this path.
    final performance = compressionPerformance?.call();
    final effective = performance == null
        ? options
        : options.withPerformance(performance);
    return _enqueue(() => _create(effective, openAfterCreate: openAfterCreate));
  }

  Future<void> extract(ExtractArchiveOptions options) =>
      _enqueue(() => _extract(options));
  Future<void> extractEntries(ExtractEntriesOptions options) =>
      _enqueue(() => _extractEntries(options));
  Future<void> addEntries(AddEntriesOptions options) =>
      _enqueue(() => _addEntries(options));
  Future<void> updateEntry({
    required String archivePath,
    required String entryPath,
    required String sourcePath,
    String? password,
  }) => _enqueue(
    () => _updateEntry(
      archivePath: archivePath,
      entryPath: entryPath,
      sourcePath: sourcePath,
      password: password,
    ),
  );
  Future<void> deleteEntries(List<String> paths) =>
      _enqueue(() => _deleteEntries(paths));
  Future<void> testCurrent() => _enqueue(_testCurrent);

  void rememberPassword(String password) {
    _password = password;
  }

  Future<void> _open(String path, {String? password}) async {
    _beginOperation('正在打开 ${p.basename(path)}');
    try {
      _listing = await _engine.list(path, password: password);
      _password = password;
      _notifyListeners();
    } finally {
      _endOperation();
    }
  }

  Future<void> _create(
    CreateArchiveOptions options, {
    bool openAfterCreate = true,
  }) async {
    _beginOperation('正在创建 ${p.basename(options.archivePath)}', progress: 0);
    try {
      await _engine.create(options, onProgress: _updateProgress);
      if (_currentCancelled) throw const ArchiveCancelledException();
      if (openAfterCreate) {
        final listingPath = options.volumeSize?.isNotEmpty == true
            ? '${options.archivePath}.001'
            : options.archivePath;
        _listing = await _engine.list(listingPath, password: options.password);
        _password = options.password;
        _notifyListeners();
      }
    } finally {
      _endOperation();
    }
  }

  Future<void> _extract(ExtractArchiveOptions options) async {
    _beginOperation('正在解压 ${p.basename(options.archivePath)}', progress: 0);
    try {
      await _engine.extract(options, onProgress: _updateProgress);
    } finally {
      _endOperation();
    }
  }

  Future<void> _extractEntries(ExtractEntriesOptions options) async {
    _beginOperation('正在解压所选文件', progress: 0);
    try {
      await _engine.extractEntries(options, onProgress: _updateProgress);
    } finally {
      _endOperation();
    }
  }

  Future<void> _addEntries(AddEntriesOptions options) async {
    _beginOperation('正在添加到 ${p.basename(options.archivePath)}', progress: 0);
    try {
      await _engine.addEntries(options, onProgress: _updateProgress);
      await _refreshIfCurrent(options.archivePath);
    } finally {
      _endOperation();
    }
  }

  Future<void> _updateEntry({
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

  Future<void> _deleteEntries(List<String> entryPaths) async {
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

  Future<void> _testCurrent() async {
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

  Future<void> cancel() async {
    _cancelGeneration++;
    _currentCancelled = true;
    await _engine.cancel();
  }

  Future<void> waitUntilIdle() {
    if (!busy) return Future.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  Future<void> _refreshIfCurrent(String archivePath) async {
    if (_currentCancelled) throw const ArchiveCancelledException();
    if (_listing?.archivePath != archivePath) return;
    _listing = await _engine.list(archivePath, password: _password);
    _notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (busy) unawaited(cancel().catchError((Object _) {}));
    if (_engine case final ArchiveOperationEvents events) {
      events.onPhaseChanged = null;
    }
    progressChanges.dispose();
    for (final waiter in _idleWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _idleWaiters.clear();
    super.dispose();
  }

  void _updateProgress(double value) {
    _progress = value.clamp(0, 0.99);
    if (!_disposed) progressChanges.value = _progress;
  }

  void _beginOperation(String label, {double? progress}) {
    _operationLabel = label;
    _progress = progress;
    if (!_disposed) progressChanges.value = progress;
    _notifyListeners();
  }

  void _endOperation() {
    _operationLabel = null;
    _progress = null;
    if (!_disposed) progressChanges.value = null;
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }
}
