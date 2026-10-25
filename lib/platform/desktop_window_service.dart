import 'package:flutter/services.dart';

abstract interface class DesktopWindowService {
  /// Returns true when the main window is hidden and a compact window is used.
  Future<bool> prepareOperation();
  Future<void> showPreparedWindow();

  /// Fits the compact window to Flutter content; native code caps screen height.
  Future<void> resizeOperationWindow(double height);
  Future<void> showMainWindow({bool explicit = true});

  /// Restores main-window geometry; returns true for a cold launch.
  Future<bool> finishOperation();
}

class NativeDesktopWindowService implements DesktopWindowService {
  const NativeDesktopWindowService();

  static const _channel = MethodChannel('dev.jucier/window');

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> prepareOperation() async =>
      await _invoke<bool>('prepareOperationWindow') ?? false;

  @override
  Future<void> showPreparedWindow() => _invoke<void>('showPreparedWindow');

  @override
  Future<void> resizeOperationWindow(double height) =>
      _invoke<void>('resizeOperationWindow', height);

  @override
  Future<void> showMainWindow({bool explicit = true}) =>
      _invoke<void>('showMainWindow', explicit);

  @override
  Future<bool> finishOperation() async =>
      await _invoke<bool>('finishOperationWindow') ?? true;
}
