import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/seven_zip_engine.dart';

void main() {
  group('SevenZipEngine.parseTechnicalListing', () {
    test('parses metadata, files, folders, and encryption state', () {
      const output = '''
Path = /tmp/example.7z
Type = 7z
Physical Size = 1450

Path = Documents
Size = 0
Packed Size = 0
Modified = 2026-08-20 12:30:00
Attributes = D_ drwxr-xr-x
Encrypted = -

Path = Documents/notes.txt
Size = 1024
Packed Size = 440
Modified = 2026-08-20 12:31:00
Attributes = A_ -rw-r--r--
CRC = 1234ABCD
Encrypted = +
Method = LZMA2:24 7zAES
''';

      final listing = SevenZipEngine.parseTechnicalListing(
        '/tmp/example.7z',
        output,
      );

      expect(listing.type, '7z');
      expect(listing.physicalSize, 1450);
      expect(listing.entries, hasLength(2));
      expect(listing.entries.first.isDirectory, isTrue);
      expect(listing.entries.last.path, 'Documents/notes.txt');
      expect(listing.entries.last.size, 1024);
      expect(listing.entries.last.packedSize, 440);
      expect(listing.entries.last.encrypted, isTrue);
      expect(listing.entries.last.crc, '1234ABCD');
    });

    test('keeps entry values that contain equals characters', () {
      const output = '''
Path = name = value.txt
Size = 12
Attributes = A
''';

      final listing = SevenZipEngine.parseTechnicalListing(
        '/tmp/example.zip',
        output,
      );

      expect(listing.entries.single.path, 'name = value.txt');
    });
  });
}
