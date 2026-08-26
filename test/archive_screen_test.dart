import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/screens/archive_screen.dart';

void main() {
  test(
    'archive browser creates implicit directories and sorts folders first',
    () {
      const entries = [
        ArchiveEntry(path: 'z.txt', isDirectory: false, size: 2),
        ArchiveEntry(path: 'Pictures/photo.jpg', isDirectory: false, size: 10),
        ArchiveEntry(path: 'a.txt', isDirectory: false, size: 1),
      ];

      final root = visibleArchiveEntries(entries, '');
      expect(root.map((entry) => entry.name), ['Pictures', 'a.txt', 'z.txt']);
      expect(root.first.isDirectory, isTrue);

      final pictures = visibleArchiveEntries(entries, 'Pictures');
      expect(pictures.single.name, 'photo.jpg');
      expect(pictures.single.size, 10);
    },
  );

  test('byte formatting stays compact', () {
    expect(formatBytes(null), '—');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1.00 KB');
    expect(formatBytes(12 * 1024), '12.0 KB');
  });
}
