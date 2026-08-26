import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

abstract interface class ThemePreferenceStore {
  Future<ThemeMode> load();

  Future<void> save(ThemeMode mode);
}

/// Persists the selected appearance through the native macOS preferences.
class MacOSThemePreferenceStore implements ThemePreferenceStore {
  MacOSThemePreferenceStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/platform';

  final MethodChannel _channel;

  @override
  Future<ThemeMode> load() async {
    try {
      final value = await _channel.invokeMethod<String>('themeMode');
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ThemeMode.system,
      );
    } on MissingPluginException {
      return ThemeMode.system;
    } on PlatformException {
      return ThemeMode.system;
    }
  }

  @override
  Future<void> save(ThemeMode mode) async {
    try {
      await _channel.invokeMethod<void>('setThemeMode', mode.name);
    } on MissingPluginException {
      // Other platforms can still switch theme for the current session.
    } on PlatformException {
      // A preference write failure should not undo the visible selection.
    }
  }
}
