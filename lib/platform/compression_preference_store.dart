import 'package:flutter/services.dart';

import '../archive/archive_options.dart';

abstract interface class CompressionPreferenceStore {
  Future<CompressionPerformance> load();
  Future<void> save(CompressionPerformance performance);
}

class DesktopCompressionPreferenceStore implements CompressionPreferenceStore {
  DesktopCompressionPreferenceStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.jucier/platform');

  final MethodChannel _channel;

  @override
  Future<CompressionPerformance> load() async {
    try {
      final value = await _channel.invokeMethod<String>(
        'compressionPerformance',
      );
      return CompressionPerformance.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => CompressionPerformance.balanced,
      );
    } on MissingPluginException {
      return CompressionPerformance.balanced;
    } on PlatformException {
      return CompressionPerformance.balanced;
    }
  }

  @override
  Future<void> save(CompressionPerformance performance) async {
    try {
      await _channel.invokeMethod<void>(
        'setCompressionPerformance',
        performance.name,
      );
    } on MissingPluginException {
      // The choice remains active for this session if persistence is unavailable.
    } on PlatformException {
      // Match the other desktop preferences: retain the visible selection.
    }
  }
}
