import 'package:flutter/services.dart';

class ArchiveFileAssociationStatus {
  const ArchiveFileAssociationStatus({
    required this.available,
    this.defaultExtensions = const <String>{},
  });

  const ArchiveFileAssociationStatus.unavailable()
    : available = false,
      defaultExtensions = const <String>{};

  factory ArchiveFileAssociationStatus.fromPlatform(Object? value) {
    if (value is! Map) {
      return const ArchiveFileAssociationStatus.unavailable();
    }
    return ArchiveFileAssociationStatus(
      available: value['available'] == true,
      defaultExtensions: (value['defaults'] as List<Object?>? ?? const [])
          .whereType<String>()
          .map((extension) => extension.toLowerCase())
          .toSet(),
    );
  }

  final bool available;
  final Set<String> defaultExtensions;
}

abstract interface class ArchiveFileAssociationService {
  Future<ArchiveFileAssociationStatus> status(List<String> extensions);

  Future<ArchiveFileAssociationStatus> setAsDefault(List<String> extensions);
}

/// Reads and changes the default macOS handler for selected archive types.
class MacOSArchiveFileAssociationService
    implements ArchiveFileAssociationService {
  MacOSArchiveFileAssociationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'dev.jucier/platform';

  final MethodChannel _channel;

  @override
  Future<ArchiveFileAssociationStatus> status(List<String> extensions) =>
      _invoke('archiveFileAssociationStatus', extensions);

  @override
  Future<ArchiveFileAssociationStatus> setAsDefault(List<String> extensions) =>
      _invoke('setDefaultArchiveFormats', extensions);

  Future<ArchiveFileAssociationStatus> _invoke(
    String method,
    List<String> extensions,
  ) async {
    try {
      final value = await _channel.invokeMethod<Object?>(method, extensions);
      return ArchiveFileAssociationStatus.fromPlatform(value);
    } on MissingPluginException {
      return const ArchiveFileAssociationStatus.unavailable();
    }
  }
}
