import 'package:flutter/services.dart';

import 'desktop_request_drain.dart';

typedef ArchiveOpenHandler = Future<void> Function(String path);

abstract interface class ArchiveOpenService {
  void setHandler(ArchiveOpenHandler? handler);

  Future<void> synchronize();

  Future<void> quitApplication();
}

typedef MacOSArchiveOpenService = DesktopArchiveOpenService;

/// Delivers Finder/Open With events and Windows launch arguments to the shell.
class DesktopArchiveOpenService implements ArchiveOpenService {
  DesktopArchiveOpenService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/archive_open';

  final MethodChannel _channel;
  ArchiveOpenHandler? _handler;
  late final _requests = DesktopRequestDrain<String>(
    readPending: () =>
        _channel.invokeListMethod<String>('takePendingOpenFiles'),
    hasHandler: () => _handler != null,
    dispatch: (path) async => _handler?.call(path),
  );

  @override
  void setHandler(ArchiveOpenHandler? handler) {
    _handler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  @override
  Future<void> synchronize() => _requests.synchronize();

  @override
  Future<void> quitApplication() async {
    try {
      await _channel.invokeMethod<void>('quitApplication');
    } on MissingPluginException {
      // Runners without this channel cannot terminate the application.
    } on PlatformException {
      // Closing an externally opened archive should not crash the UI.
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'archiveFilesAvailable') {
      await synchronize();
    }
    return null;
  }
}
