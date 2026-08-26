import 'package:path/path.dart' as p;

/// Archive formats accepted by the open panel and drag-and-drop workflow.
const supportedArchiveExtensions = <String>[
  '7z',
  'zip',
  'rar',
  'tar',
  'gz',
  'bz2',
  'xz',
  'zst',
  'cab',
  'iso',
  'dmg',
];

final Set<String> _supportedArchiveSuffixes = {
  for (final extension in supportedArchiveExtensions) '.$extension',
};

bool isSupportedArchivePath(String path) =>
    _supportedArchiveSuffixes.contains(p.extension(path).toLowerCase());
