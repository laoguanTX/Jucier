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
  });

  final String archivePath;
  final List<ArchiveEntry> entries;
  final String? type;
  final int? physicalSize;
}
