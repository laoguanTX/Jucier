import 'package:path/path.dart' as p;

import 'archive_engine.dart';

/// Normalizes an archive member path while preventing it from escaping an
/// extraction or update directory.
String normalizeArchiveEntryPath(String entryPath) {
  final normalized = entryPath.replaceAll('\\', '/');
  final segments = p.posix.split(normalized);
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      segments.any((segment) => segment == '..')) {
    throw const ArchiveException('压缩包内包含不安全的文件路径');
  }
  final result = p.posix.normalize(normalized);
  if (result == '.' || normalized.contains('\u0000')) {
    throw const ArchiveException('压缩包内包含不安全的文件路径');
  }
  return result;
}
