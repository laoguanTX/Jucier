import 'dart:io';

import 'package:path/path.dart' as p;

import '../archive/archive_entry.dart';

/// Builds the archive-shaped listing shown while a new archive is composed.
Future<ArchiveListing> buildArchiveDraftListing(List<String> sources) async {
  final entries = <ArchiveEntry>[];
  var totalSize = 0;

  for (final source in sources) {
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) continue;

    final sourceParent = p.dirname(source);
    if (sourceType == FileSystemEntityType.directory) {
      final rootStat = await FileStat.stat(source);
      entries.add(
        ArchiveEntry(
          path: p.basename(source),
          isDirectory: true,
          modified: rootStat.modified,
          sourcePath: source,
          attributes: rootStat.modeString(),
        ),
      );
      await for (final entity in Directory(
        source,
      ).list(recursive: true, followLinks: false)) {
        final stat = await entity.stat();
        final isDirectory = stat.type == FileSystemEntityType.directory;
        final relativePath = p
            .relative(entity.path, from: sourceParent)
            .replaceAll('\\', '/');
        if (!isDirectory) totalSize += stat.size;
        entries.add(
          ArchiveEntry(
            path: relativePath,
            isDirectory: isDirectory,
            size: isDirectory ? null : stat.size,
            modified: stat.modified,
            sourcePath: entity.path,
            attributes: stat.modeString(),
          ),
        );
      }
    } else {
      final stat = await FileStat.stat(source);
      totalSize += stat.size;
      entries.add(
        ArchiveEntry(
          path: p.basename(source),
          isDirectory: false,
          size: stat.size,
          modified: stat.modified,
          sourcePath: source,
          attributes: stat.modeString(),
        ),
      );
    }
  }

  return ArchiveListing(
    archivePath: '新建压缩包',
    entries: entries,
    physicalSize: totalSize,
  );
}
