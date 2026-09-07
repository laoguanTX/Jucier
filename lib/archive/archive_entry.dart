import 'package:path/path.dart' as p;

class ArchiveEntry {
  const ArchiveEntry({
    required this.path,
    required this.isDirectory,
    this.size,
    this.packedSize,
    this.modified,
    this.crc,
    this.method,
    this.encrypted,
    this.sourcePath,
    this.attributes,
  });

  final String path;
  final bool isDirectory;
  final int? size;
  final int? packedSize;
  final DateTime? modified;
  final String? crc;
  final String? method;
  final bool? encrypted;
  final String? sourcePath;
  final String? attributes;

  String get name => p.basename(path);
}

class ArchiveListing {
  const ArchiveListing({
    required this.archivePath,
    required this.entries,
    this.type,
    this.physicalSize,
    this.method,
    this.solid,
    this.blocks,
  });

  String get detectedType =>
      (type ?? p.extension(archivePath).replaceFirst('.', '')).toLowerCase();
  bool get isSplit => RegExp(r'\.[0-9]{3,}$').hasMatch(archivePath);
  bool get canUpdate =>
      !isSplit && const {'7z', 'zip', 'tar', 'wim'}.contains(detectedType);
  bool get canOptimize =>
      canUpdate &&
      detectedType == '7z' &&
      (method?.toUpperCase().contains('LZMA2') ?? false);

  final String archivePath;
  final List<ArchiveEntry> entries;
  final String? type;
  final int? physicalSize;
  final String? method;
  final bool? solid;
  final int? blocks;
}
