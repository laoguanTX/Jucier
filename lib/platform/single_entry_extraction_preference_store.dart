import 'package:flutter/services.dart';

enum SingleEntryExtractionMode { preserveArchiveStructure, selectedOnly }

abstract interface class SingleEntryExtractionPreferenceStore {
  Future<SingleEntryExtractionMode> load();

  Future<void> save(SingleEntryExtractionMode mode);
}

class MacOSSingleEntryExtractionPreferenceStore
    implements SingleEntryExtractionPreferenceStore {
  MacOSSingleEntryExtractionPreferenceStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/platform';

  final MethodChannel _channel;

  @override
  Future<SingleEntryExtractionMode> load() async {
    try {
      final value = await _channel.invokeMethod<String>(
        'singleEntryExtractionMode',
      );
      return SingleEntryExtractionMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => SingleEntryExtractionMode.preserveArchiveStructure,
      );
    } on MissingPluginException {
      return SingleEntryExtractionMode.preserveArchiveStructure;
    } on PlatformException {
      return SingleEntryExtractionMode.preserveArchiveStructure;
    }
  }

  @override
  Future<void> save(SingleEntryExtractionMode mode) async {
    try {
      await _channel.invokeMethod<void>(
        'setSingleEntryExtractionMode',
        mode.name,
      );
    } on MissingPluginException {
      // Other platforms can still use the selection for the current session.
    } on PlatformException {
      // A preference write failure should not undo the visible selection.
    }
  }
}
