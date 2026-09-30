import 'package:flutter/services.dart';

typedef MacOSSmartExtractionPreferenceStore =
    DesktopSmartExtractionPreferenceStore;

class DesktopSmartExtractionPreferenceStore {
  DesktopSmartExtractionPreferenceStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.jucier/platform');

  final MethodChannel _channel;

  Future<bool> load() async {
    try {
      return await _channel.invokeMethod<bool>('smartExtractionEnabled') ??
          true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  Future<void> save(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSmartExtractionEnabled', enabled);
    } on MissingPluginException {
      // Keep the choice for this session on other platforms.
    } on PlatformException {
      // Keep the visible choice if persistence is unavailable.
    }
  }
}
