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

final Set<String> _supportedArchiveSuffixes = {
  for (final extension in supportedArchiveExtensions) '.$extension',
};

bool isSupportedArchivePath(String path) =>
    _supportedArchiveSuffixes.contains(p.extension(path).toLowerCase());
