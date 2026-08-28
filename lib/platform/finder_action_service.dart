import 'dart:async';

import 'package:flutter/services.dart';

enum FinderActionType {
  extractHere,
  extractTo,
  compressZip,
  compress;

  static FinderActionType? fromPlatform(String value) {
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

class FinderActionRequest {
  const FinderActionRequest({required this.type, required this.paths});

  factory FinderActionRequest.fromPlatform(Object? value) {
    if (value is! Map) {
      throw const FormatException('Finder action must be a map');
    }
    final type = FinderActionType.fromPlatform(
      value['action'] as String? ?? '',
    );
    final paths = (value['paths'] as List?)?.whereType<String>().toList();
    if (type == null || paths == null || paths.isEmpty) {
      throw const FormatException('Finder action is incomplete');
    }
    return FinderActionRequest(type: type, paths: paths);
  }

  final FinderActionType type;
  final List<String> paths;
}

typedef FinderActionHandler = Future<void> Function(
  FinderActionRequest request,
);

abstract interface class FinderActionService {
  void setHandler(FinderActionHandler? handler);

  Future<void> synchronize();

  Future<bool> contextMenuAvailable();

  Future<void> repairContextMenu();

  Future<void> uninstallContextMenu();
}

/// Receives contextual-menu requests from the bundled macOS Finder extension.
class MacOSFinderActionService implements FinderActionService {
  MacOSFinderActionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/finder_action';

  final MethodChannel _channel;
  FinderActionHandler? _handler;
  bool _draining = false;
  bool _drainRequested = false;

  @override
  void setHandler(FinderActionHandler? handler) {
    _handler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  @override
  Future<void> synchronize() {
    _drainRequested = true;
    return _drainPendingActions();
  }

  @override
  Future<bool> contextMenuAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('finderContextMenuAvailable') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> repairContextMenu() async {
    await _channel.invokeMethod<void>('repairFinderContextMenu');
  }

  @override
  Future<void> uninstallContextMenu() async {
    await _channel.invokeMethod<void>('uninstallFinderContextMenu');
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'finderActionsAvailable') {
      _drainRequested = true;
      await _drainPendingActions();
    }
    return null;
  }

  Future<void> _drainPendingActions() async {
    if (_draining || _handler == null) return;
    _draining = true;
    _drainRequested = false;
    try {
      while (_handler != null) {
        final values = await _channel.invokeListMethod<Object?>(
          'takePendingFinderActions',
        );
        if (values == null || values.isEmpty) break;
        for (final value in values) {
          final handler = _handler;
          if (handler == null) return;
          try {
            await handler(FinderActionRequest.fromPlatform(value));
          } on FormatException {
            // Ignore malformed extension requests without blocking later ones.
          }
        }
      }
    } on MissingPluginException {
      // Finder actions are only available in the macOS runner.
    } on PlatformException {
      // A later native event will retry the pending-action drain.
    } finally {
      _draining = false;
      if (_drainRequested && _handler != null) {
        _drainRequested = false;
        unawaited(_drainPendingActions());
      }
    }
  }
}
