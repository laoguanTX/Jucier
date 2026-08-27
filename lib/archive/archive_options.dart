enum ArchiveFormat {
  sevenZip('7z', '7z'),
  zip('ZIP', 'zip'),
  tar('TAR', 'tar'),
  gzip('GZIP', 'gzip');

  const ArchiveFormat(this.label, this.sevenZipType);

  final String label;
  final String sevenZipType;

  String get extension => switch (this) {
    ArchiveFormat.sevenZip => '7z',
    ArchiveFormat.zip => 'zip',
    ArchiveFormat.tar => 'tar',
    ArchiveFormat.gzip => 'gz',
  };
}

enum ExtractionConflict {
  overwrite('覆盖已有文件', '-aoa'),
  skip('跳过已有文件', '-aos'),
  rename('自动重命名', '-aou');

  const ExtractionConflict(this.label, this.switchValue);

  final String label;
  final String switchValue;
}

class CreateArchiveOptions {
  const CreateArchiveOptions({
    required this.archivePath,
    required this.sources,
    required this.format,
    this.compressionLevel = 5,
    this.password,
    this.volumeSize,
  });

  final String archivePath;
  final List<String> sources;
  final ArchiveFormat format;
  final int compressionLevel;
  final String? password;
  final String? volumeSize;
}

class ExtractArchiveOptions {
  const ExtractArchiveOptions({
    required this.archivePath,
    required this.outputDirectory,
    this.password,
    this.conflict = ExtractionConflict.overwrite,
  });

  final String archivePath;
  final String outputDirectory;
  final String? password;
  final ExtractionConflict conflict;
}

class ExtractEntriesOptions {
  const ExtractEntriesOptions({
    required this.archivePath,
    required this.entryPaths,
    required this.outputDirectory,
    this.password,
    this.conflict = ExtractionConflict.overwrite,
    this.withoutParentDirectories = false,
    this.selectedEntryPath,
    this.outputPath,
  });

  final String archivePath;
  final List<String> entryPaths;
  final String outputDirectory;
  final String? password;
  final ExtractionConflict conflict;
  final bool withoutParentDirectories;
  final String? selectedEntryPath;
  final String? outputPath;
}

class AddEntriesOptions {
  const AddEntriesOptions({
    required this.archivePath,
    required this.sources,
    required this.destinationDirectory,
    this.password,
  });

  final String archivePath;
  final List<String> sources;
  final String destinationDirectory;
  final String? password;
}
