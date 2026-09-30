enum ArchiveFormat {
  // Keep this list in user-facing popularity order. The create-format menu
  // intentionally follows enum order so the most useful choices stay close
  // to the pointer and keyboard focus.
  zip(
    label: 'ZIP',
    sevenZipType: 'zip',
    extension: 'zip',
    supportsPassword: true,
    supportsSymbolicLinks: true,
  ),
  sevenZip(
    label: '7Z',
    sevenZipType: '7z',
    extension: '7z',
    supportsPassword: true,
    supportsSymbolicLinks: true,
  ),
  tar(
    label: 'TAR',
    sevenZipType: 'tar',
    extension: 'tar',
    supportsSymbolicLinks: true,
  ),
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
  tarGzip(label: 'TAR.GZ', sevenZipType: 'gzip', extension: 'tar.gz'),
  tarXz(label: 'TAR.XZ', sevenZipType: 'xz', extension: 'tar.xz'),
  wim(
    label: 'WIM',
    sevenZipType: 'wim',
    extension: 'wim',
    supportsSymbolicLinks: true,
  );

  const ArchiveFormat({
    required this.label,
    required this.sevenZipType,
    required this.extension,
    this.supportsPassword = false,
    this.singleSourceOnly = false,
    this.supportsSymbolicLinks = false,
  });

  bool get usesTarContainer => this == tarGzip || this == tarXz;

  final String label;
  final String sevenZipType;
  final String extension;
  final bool supportsPassword;
  final bool singleSourceOnly;
  final bool supportsSymbolicLinks;
}

enum ExtractionConflict {
  overwrite('覆盖已有文件', '-aoa'),
  skip('跳过已有文件', '-aos'),
  rename('自动重命名', '-aou');

  const ExtractionConflict(this.label, this.switchValue);

  final String label;
  final String switchValue;
}

enum CompressionPreset {
  balanced('日常压缩', 5),
  fast('快速打包', 1),
  compact('更小体积', 7),
  editable('经常预览与修改', 5);

  const CompressionPreset(this.label, this.level);
  final String label;
  final int level;
}

enum ZipEncryption {
  aes256('AES-256 加密', 'AES256'),
  compatible('传统 ZIP 加密（兼容旧软件）', 'ZipCrypto');

  const ZipEncryption(this.label, this.method);
  final String label;
  final String method;
}

enum CompressionPerformance {
  balanced('均衡', '新建压缩包时适度使用系统资源，完成后进行完整校验。'),
  speed('速度优先', '新建压缩包时充分使用系统资源，跳过完成后的完整校验；7z 单文件预览和修改可能更慢。'),
  resourceSaving('节省资源', '新建压缩包时减少处理器和内存占用，保留完整校验，压缩可能更慢。');

  const CompressionPerformance(this.label, this.description);
  final String label;
  final String description;
}

class CreateArchiveOptions {
  const CreateArchiveOptions({
    required this.archivePath,
    required this.sources,
    required this.format,
    this.compressionLevel = 5,
    this.preset = CompressionPreset.balanced,
    this.zipEncryption = ZipEncryption.aes256,
    this.maxThreads,
    this.performance = CompressionPerformance.balanced,
    this.password,
    this.volumeSize,
  });

  final String archivePath;
  final List<String> sources;
  final ArchiveFormat format;
  final int compressionLevel;
  final CompressionPreset preset;
  final ZipEncryption zipEncryption;
  final int? maxThreads;
  final CompressionPerformance performance;
  final String? password;
  final String? volumeSize;

  CreateArchiveOptions withPerformance(CompressionPerformance performance) =>
      CreateArchiveOptions(
        archivePath: archivePath,
        sources: sources,
        format: format,
        compressionLevel: compressionLevel,
        preset: preset,
        zipEncryption: zipEncryption,
        maxThreads: maxThreads,
        performance: performance,
        password: password,
        volumeSize: volumeSize,
      );
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
    this.selectedEntryPaths = const [],
    this.outputPath,
  });

  final String archivePath;
  final List<String> entryPaths;
  final String outputDirectory;
  final String? password;
  final ExtractionConflict conflict;
  final bool withoutParentDirectories;
  final String? selectedEntryPath;
  final List<String> selectedEntryPaths;
  final String? outputPath;
}

class AddEntriesOptions {
  const AddEntriesOptions({
    required this.archivePath,
    required this.sources,
    required this.destinationDirectory,
    this.password,
    this.recompress = false,
  });

  final String archivePath;
  final List<String> sources;
  final String destinationDirectory;
  final bool recompress;
  final String? password;
}
