import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/seven_zip_engine.dart';

void main() {
  group('SevenZipEngine.parseTechnicalListing', () {
    test('parses metadata, files, folders, and encryption state', () {
      const output = '''
Path = /tmp/example.7z
Type = 7z
Physical Size = 1450
Method = LZMA2:24m
Solid = +
Blocks = 1

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
      expect(listing.method, 'LZMA2:24m');
      expect(listing.solid, isTrue);
      expect(listing.blocks, 1);
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

    test(
      'keeps timestamp precision, local-time semantics and format fallbacks',
      () {
        final timestamps = <String?>[
          null,
          '',
          'invalid',
          '2026-10-25 12:34:56',
          for (final fraction in [
            '0',
            '1',
            '012',
            '123456',
            '1234567',
            '999999999',
          ])
            '2026-10-25 12:34:56.$fraction',
          '2026-10-25 12:34:56.123456789123',
          '2026-10-25 12:34:57.9999999',
          '2026-10-25 12:34:57.0000001',
          '2026-10-25 12:34:57',
          '2026-10-25T12:34:56.123456Z',
          '2026-10-25 12:34:56.123456+08:00',
          '2026-10-25T12:34:56.123456-04:00',
          '2024-02-29 23:59:59.9999999',
          '2026-01-42 25:90:90.1234567',
          // Gap and overlap boundaries when run under America/New_York.
          for (final hour in ['01', '02', '03'])
            for (final fraction in ['9999999', '0000001', '0'])
              '2026-03-08 $hour:30:00.$fraction',
          for (final hour in ['00', '01', '02'])
            for (final fraction in ['9999999', '0000001', '0'])
              '2026-11-01 $hour:30:00.$fraction',
          '2026-10-25 12:34:56.invalid',
          '2026-10-25 12:34:56.1Zinvalid',
        ];
        final output = StringBuffer();
        for (var i = 0; i < timestamps.length; i++) {
          output.writeln('Path = file-$i.txt');
          output.writeln('Size = $i');
          if (timestamps[i] case final timestamp?) {
            output.writeln('Modified = $timestamp');
          }
          output.writeln();
        }
        final listing = SevenZipEngine.parseTechnicalListing(
          'times.7z',
          '$output',
        );
        expect(listing.entries, hasLength(timestamps.length));
        for (var i = 0; i < timestamps.length; i++) {
          final expected = DateTime.tryParse(timestamps[i] ?? '');
          final actual = listing.entries[i].modified;
          expect(actual, expected, reason: 'timestamp: ${timestamps[i]}');
          expect(actual?.isUtc, expected?.isUtc);
        }
      },
    );

    test(
      'time cache eviction preserves unrelated dates and entry metadata',
      () {
        final timestamps = [
          for (var second = 0; second < 300; second++)
            DateTime(2026, 1, 1).add(Duration(seconds: second)).toString(),
          '2026-01-01 00:00:00.1234567',
          '2026-01-01 00:00:00.7654321',
        ];
        final output = timestamps.indexed
            .map(
              (pair) =>
                  '''
Path = folder/file-${pair.$1}.txt
Size = ${pair.$1}
Packed Size = 1
Modified = ${pair.$2}
Attributes = A_ -rw-r--r--
CRC = 1234ABCD
Encrypted = +
Method = LZMA2:24 7zAES

''',
            )
            .join();
        final listing = SevenZipEngine.parseTechnicalListing(
          'times.7z',
          output,
        );
        expect(listing.entries, hasLength(timestamps.length));
        for (var i = 0; i < timestamps.length; i++) {
          final entry = listing.entries[i];
          expect(entry.path, 'folder/file-$i.txt');
          expect(entry.size, i);
          expect(entry.packedSize, 1);
          expect(entry.modified, DateTime.parse(timestamps[i]));
          expect(entry.attributes, 'A_ -rw-r--r--');
          expect(entry.crc, '1234ABCD');
          expect(entry.encrypted, isTrue);
          expect(entry.method, 'LZMA2:24 7zAES');
          expect(entry.isDirectory, isFalse);
        }
      },
    );
  });
}
