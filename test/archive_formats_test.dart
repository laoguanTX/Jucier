import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/archive/archive_formats.dart';

void main() {
  test('recognizes supported archive paths case-insensitively', () {
    expect(isSupportedArchivePath('/tmp/example.7z'), isTrue);
    expect(isSupportedArchivePath('/tmp/example.ZIP'), isTrue);
    expect(isSupportedArchivePath('/tmp/example.tar.gz'), isTrue);
    expect(isSupportedArchivePath('/tmp/example.txt'), isFalse);
    expect(isSupportedArchivePath('/tmp/example.zip.bak'), isFalse);
  });
}
