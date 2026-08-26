import 'package:flutter/services.dart';

class FileAccessStatus {
  const FileAccessStatus({
    required this.requested,
    required this.granted,
    this.directory,
  });

  const FileAccessStatus.unavailable()
    : requested = true,
      granted = false,
      directory = null;

  factory FileAccessStatus.fromPlatform(Object? value) {
    if (value is! Map) return const FileAccessStatus.unavailable();
    return FileAccessStatus(
      requested: value['requested'] == true,
      granted: value['granted'] == true,
      directory: value['directory'] as String?,
    );
  }

  final bool requested;
  final bool granted;
  final String? directory;
}

abstract interface class FileAccessService {
  Future<FileAccessStatus> status();

  Future<FileAccessStatus> requestAccess();

  void setOpenSettingsHandler(VoidCallback? handler);
}

class MacOSFileAccessService implements FileAccessService {
  MacOSFileAccessService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/platform';

  final MethodChannel _channel;
  VoidCallback? _openSettingsHandler;

  @override
  Future<FileAccessStatus> status() => _invoke('fileAccessStatus');

  @override
  Future<FileAccessStatus> requestAccess() => _invoke('requestFileAccess');

  Future<FileAccessStatus> _invoke(String method) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method);
      return FileAccessStatus.fromPlatform(value);
    } on MissingPluginException {
      return const FileAccessStatus.unavailable();
    } on PlatformException {
      return const FileAccessStatus.unavailable();
    }
  }

  @override
  void setOpenSettingsHandler(VoidCallback? handler) {
    _openSettingsHandler = handler;
    _channel.setMethodCallHandler(handler == null ? null : _handleNativeCall);
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'openSettings') _openSettingsHandler?.call();
    return null;
  }
}
