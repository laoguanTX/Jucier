import 'dart:async';

import 'package:flutter/services.dart';

typedef ArchiveOpenHandler = Future<void> Function(String path);

abstract interface class ArchiveOpenService {
  void setHandler(ArchiveOpenHandler? handler);

  Future<void> synchronize();

  Future<void> quitApplication();
}

/// Delivers Finder/Open With events from the macOS runner to the app shell.
class MacOSArchiveOpenService implements ArchiveOpenService {
  MacOSArchiveOpenService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/archive_open';

  final MethodChannel _channel;
  ArchiveOpenHandler? _handler;
  bool _draining = false;
  bool _drainRequested = false;

  @override
  void setHandler(ArchiveOpenHandler? handler) {
    _handler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  @override
  Future<void> synchronize() {
    _drainRequested = true;
    return _drainPendingFiles();
  }

  @override
  Future<void> quitApplication() async {
    try {
      await _channel.invokeMethod<void>('quitApplication');
    } on MissingPluginException {
      // Only the macOS runner can terminate the desktop application.
    } on PlatformException {
      // Closing an externally opened archive should not crash the UI.
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'archiveFilesAvailable') {
      _drainRequested = true;
      await _drainPendingFiles();
    }
    return null;
  }

  Future<void> _drainPendingFiles() async {
    if (_draining || _handler == null) return;
    _draining = true;
    _drainRequested = false;
    try {
      while (_handler != null) {
        final paths = await _channel.invokeListMethod<String>(
          'takePendingOpenFiles',
        );
        if (paths == null || paths.isEmpty) break;
        for (final path in paths) {
          final handler = _handler;
          if (handler == null) return;
          await handler(path);
        }
      }
    } on MissingPluginException {
      // Finder open events are only available in the macOS runner.
    } on PlatformException {
      // A later native event will retry the pending-file drain.
    } finally {
      _draining = false;
      if (_drainRequested && _handler != null) {
        _drainRequested = false;
        unawaited(_drainPendingFiles());
      }
    }
  }
}
