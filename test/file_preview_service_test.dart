import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/platform/file_preview_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('opens an isolated file and reports each saved version once', () async {
    final launcher = _FakeFileLauncher();
    final changed = <PreviewSession>[];
    final service = FilePreviewService(
      launcher: launcher,
      onChanged: (session) async => changed.add(session),
      pollInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);

    final session = await service.open(
      archivePath: '/tmp/example.zip',
      entryPath: 'Docs/readme.txt',
      password: 'secret',
      extract: (outputDirectory) async {
        final file = File(p.join(outputDirectory, 'Docs', 'readme.txt'));
        await file.parent.create(recursive: true);
        await file.writeAsString('original');
      },
    );

    expect(launcher.paths, [session.filePath]);
    expect(await session.file.readAsString(), 'original');

    await session.file.writeAsString('first saved version');
    await session.checkNow();
    await session.checkNow();
    expect(changed, [session]);

    await session.file.writeAsString('second saved version is different');
    await session.checkNow();
    expect(changed, [session, session]);

    final previewRoot = session.file.parent.parent;
    await service.dispose();
    expect(await previewRoot.exists(), isFalse);
  });

  test('opens a parent-free preview from the temporary root', () async {
    final launcher = _FakeFileLauncher();
    final service = FilePreviewService(
      launcher: launcher,
      onChanged: (_) async {},
      pollInterval: const Duration(days: 1),
    );
    addTearDown(service.dispose);

    final session = await service.open(
      archivePath: '/tmp/example.zip',
      entryPath: 'Docs/readme.txt',
      password: null,
      preserveArchiveStructure: false,
      extract: (outputDirectory) async {
        await File(p.join(outputDirectory, 'readme.txt'))
            .writeAsString('flat preview');
      },
    );

    expect(p.basename(session.filePath), 'readme.txt');
    expect(
      p.basename(p.dirname(session.filePath)),
      startsWith('jucier-preview-'),
    );
    expect(await session.file.readAsString(), 'flat preview');
  });
}

class _FakeFileLauncher implements FileLauncher {
  final List<String> paths = [];

  @override
  Future<void> open(String path) async => paths.add(path);
}
