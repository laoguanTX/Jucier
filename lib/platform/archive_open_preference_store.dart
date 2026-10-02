import 'package:flutter/services.dart';

enum ArchiveOpenMode {
  open('双击打开', '双击压缩包时打开文件列表。'),
  extract('双击直接解压', '双击压缩包时解压到所在位置，并遵循智能解压设置。');

  const ArchiveOpenMode(this.label, this.description);

  final String label;
  final String description;
}

typedef ArchiveOpenPreferences = ({
  ArchiveOpenMode mode,
  bool smartExtractionEnabled,
});

abstract interface class ArchiveOpenPreferenceStore {
  Future<ArchiveOpenMode> load();
  Future<void> save(ArchiveOpenMode mode);
}

class DesktopArchiveOpenPreferenceStore implements ArchiveOpenPreferenceStore {
  DesktopArchiveOpenPreferenceStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.jucier/platform');

  final MethodChannel _channel;

  @override
  Future<ArchiveOpenMode> load() async {
    try {
      final value = await _channel.invokeMethod<String>('archiveOpenMode');
      return ArchiveOpenMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ArchiveOpenMode.open,
      );
    } on MissingPluginException {
      return ArchiveOpenMode.open;
    } on PlatformException {
      return ArchiveOpenMode.open;
    }
  }

  @override
  Future<void> save(ArchiveOpenMode mode) async {
    try {
      await _channel.invokeMethod<void>('setArchiveOpenMode', mode.name);
    } on MissingPluginException {
      // Keep the choice for the current session if persistence is unavailable.
    } on PlatformException {
      // A failed preference write should not undo the visible selection.
    }
  }
}
