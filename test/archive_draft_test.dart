import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/application/archive_draft.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'builds an archive-shaped listing from local files and folders',
    () async {
      final temporary = await Directory.systemTemp.createTemp('jucier-draft-');
      addTearDown(() => temporary.delete(recursive: true));
      final looseFile = File(p.join(temporary.path, 'loose.txt'));
      await looseFile.writeAsString('loose');
      final folder = Directory(p.join(temporary.path, 'Docs'));
      await folder.create();
      final nestedFile = File(p.join(folder.path, 'readme.txt'));
      await nestedFile.writeAsString('readme');

      final listing = await buildArchiveDraftListing([
        looseFile.path,
        folder.path,
      ]);

      expect(listing.archivePath, '新建压缩包');
      expect(listing.entries.map((entry) => entry.path), [
        'loose.txt',
        'Docs',
        'Docs/readme.txt',
      ]);
      expect(listing.physicalSize, 11);
    },
  );
}
