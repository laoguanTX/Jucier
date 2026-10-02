import 'package:flutter/services.dart';

import 'desktop_request_drain.dart';

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

typedef DesktopFinderActionService = MacOSFinderActionService;

/// Receives contextual-menu requests from Finder and Windows Explorer.
class MacOSFinderActionService implements FinderActionService {
  MacOSFinderActionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/finder_action';

  final MethodChannel _channel;
  FinderActionHandler? _handler;
  late final _requests = DesktopRequestDrain<Object?>(
    readPending: () =>
        _channel.invokeListMethod<Object?>('takePendingFinderActions'),
    hasHandler: () => _handler != null,
    dispatch: (value) async {
      try {
        await _handler?.call(FinderActionRequest.fromPlatform(value));
      } on FormatException {
        // Ignore malformed requests without blocking later ones.
      }
    },
  );

  @override
  void setHandler(FinderActionHandler? handler) {
    _handler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  @override
  Future<void> synchronize() => _requests.synchronize();

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
      await synchronize();
    }
    return null;
  }
}
