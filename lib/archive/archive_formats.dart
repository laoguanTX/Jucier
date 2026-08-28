import 'package:path/path.dart' as p;

/// Archive formats accepted by the open panel and drag-and-drop workflow.
const supportedArchiveExtensions = <String>[
  // Common archive types first so native file pickers present them in a
  // useful order where the platform exposes extension filters.
  'zip',
  '7z',
  'rar',
  'tar',
  'gz',
  'tgz',
  'bz2',
  'tbz2',
  'tbz',
  'xz',
  'txz',
  'zst',
  'tzst',
  'zipx',
  'jar',
  'apk',
  'xpi',
  'epub',
  'cab',
  'iso',
  'dmg',
  'wim',
  'swm',
  'esd',
  'lzh',
  'lha',
  'arj',
  'cpio',
  'deb',
  'rpm',
  'xar',
  'xip',
  '001',
];

const _archiveExtensionLabels = <String, String>{
  '7z': '7-Zip 压缩包 (.7z)',
  'zip': 'ZIP 压缩包 (.zip)',
  'rar': 'RAR 压缩包 (.rar)',
  'tar': 'TAR 压缩包 (.tar)',
  'gz': 'Gzip 压缩包 (.gz)',
  'tgz': 'Gzip TAR 压缩包 (.tgz)',
  'bz2': 'Bzip2 压缩包 (.bz2)',
  'xz': 'XZ 压缩包 (.xz)',
  'zst': 'Zstandard 压缩包 (.zst)',
  'iso': 'ISO 磁盘映像 (.iso)',
  'dmg': 'Apple 磁盘映像 (.dmg)',
};

String archiveExtensionLabel(String extension) =>
    _archiveExtensionLabels[extension] ??
    '${extension.toUpperCase()} 文件 (.$extension)';

final Set<String> _supportedArchiveSuffixes = {
  for (final extension in supportedArchiveExtensions) '.$extension',
};

bool isSupportedArchivePath(String path) =>
    _supportedArchiveSuffixes.contains(p.extension(path).toLowerCase());
