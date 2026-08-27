import 'package:flutter/services.dart';

import '../archive/archive_column.dart';

abstract interface class ArchiveColumnPreferenceStore {
  Future<ArchiveColumnPreferences> load();

  Future<void> save(ArchiveColumnPreferences preferences);
}

class MacOSArchiveColumnPreferenceStore
    implements ArchiveColumnPreferenceStore {
  MacOSArchiveColumnPreferenceStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/platform';

  final MethodChannel _channel;

  @override
  Future<ArchiveColumnPreferences> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'archiveColumnPreferences',
      );
      if (value == null) return const ArchiveColumnPreferences();
      return ArchiveColumnPreferences(
        compressionColumns: _decode(
          value['compression'],
          defaultCompressionArchiveColumns,
          compressionAvailableArchiveColumns,
        ),
        extractionColumns: _decode(
          value['extraction'],
          defaultExtractionArchiveColumns,
          extractionAvailableArchiveColumns,
        ),
      );
    } on MissingPluginException {
      return const ArchiveColumnPreferences();
    } on PlatformException {
      return const ArchiveColumnPreferences();
    }
  }

  @override
  Future<void> save(ArchiveColumnPreferences preferences) async {
    try {
      await _channel.invokeMethod<void>('setArchiveColumnPreferences', {
        'compression': preferences.compressionColumns
            .map((column) => column.name)
            .toList(),
        'extraction': preferences.extractionColumns
            .map((column) => column.name)
            .toList(),
      });
    } on MissingPluginException {
      // Other platforms can still use the selection for the current session.
    } on PlatformException {
      // A preference write failure should not undo the visible selection.
    }
  }

  static List<ArchiveColumn> _decode(
    dynamic value,
    List<ArchiveColumn> fallback,
    List<ArchiveColumn> available,
  ) {
    if (value is! List) return fallback;
    final columns = value
        .whereType<String>()
        .map(
          (name) => ArchiveColumn.values.cast<ArchiveColumn?>().firstWhere(
            (column) => column?.name == name,
            orElse: () => null,
          ),
        )
        .whereType<ArchiveColumn>()
        .where(available.contains);
    return ArchiveColumnPreferences.normalize(columns);
  }
}
