import 'package:path/path.dart' as p;

import 'archive_entry.dart';
import 'archive_path.dart';

/// Avoids an extra wrapper for a single file or existing top-level folder.
String smartExtractionDirectory(ArchiveListing listing, String destination) {
  final roots = listing.entries
      .map((entry) => normalizeArchiveEntryPath(entry.path).split('/').first)
      .toSet();
  if (roots.length <= 1) return destination;
  var name = p.basename(listing.archivePath);
  name = name.replaceFirst(RegExp(r'\.\d{3,}$'), '');
  name = name.replaceFirst(
    RegExp(r'\.(?:tar\.(?:gz|bz2|xz|zst)|[^.]+)$', caseSensitive: false),
    '',
  );
  if (name.isEmpty || name == '.' || name == '..') name = '解压文件';
  return p.join(destination, name);
}
