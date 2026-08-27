enum ArchiveFormat {
  // Keep this list in user-facing popularity order. The create-format menu
  // intentionally follows enum order so the most useful choices stay close
  // to the pointer and keyboard focus.
  zip(
    label: 'ZIP',
    sevenZipType: 'zip',
    extension: 'zip',
    supportsPassword: true,
  ),
  sevenZip(
    label: '7Z',
    sevenZipType: '7z',
    extension: '7z',
    supportsPassword: true,
  ),
  tar(label: 'TAR', sevenZipType: 'tar', extension: 'tar'),
  gzip(
    label: 'GZIP',
    sevenZipType: 'gzip',
    extension: 'gz',
    singleSourceOnly: true,
  ),
  xz(label: 'XZ', sevenZipType: 'xz', extension: 'xz', singleSourceOnly: true),
  bzip2(
    label: 'BZIP2',
    sevenZipType: 'bzip2',
    extension: 'bz2',
    singleSourceOnly: true,
  ),
  wim(label: 'WIM', sevenZipType: 'wim', extension: 'wim');

  const ArchiveFormat({
    required this.label,
    required this.sevenZipType,
    required this.extension,
    this.supportsPassword = false,
    this.singleSourceOnly = false,
  });

  final String label;
  final String sevenZipType;
  final String extension;
  final bool supportsPassword;
  final bool singleSourceOnly;
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
