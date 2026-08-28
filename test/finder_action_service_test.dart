import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/platform/file_access_service.dart';
import 'package:jucier/platform/finder_action_service.dart';
import 'package:jucier/platform/archive_open_service.dart';

void main() {
  test('decodes a native Finder action request', () {
    final request = FinderActionRequest.fromPlatform({
      'action': 'compress',
      'paths': ['/tmp/one', '/tmp/two'],
    });

    expect(request.type, FinderActionType.compress);
    expect(request.paths, ['/tmp/one', '/tmp/two']);
  });

  testWidgets('Finder 解压 sends an archive to its current directory', (
    tester,
  ) async {
    final engine = _FinderActionArchiveEngine();
    final openService = _NoopArchiveOpenService();
    final service = _FakeFinderActionService(
      const FinderActionRequest(
        type: FinderActionType.extractHere,
        paths: ['/tmp/example.zip'],
      ),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: engine,
        fileAccessService: _GrantedFileAccessService(),
        finderActionService: service,
        archiveOpenService: openService,
      ),
    );
    unawaited(service.dispatch());
    for (
      var attempt = 0;
      attempt < 20 && engine.extractions.isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(engine.extractions, hasLength(1));
    expect(engine.extractions.single.archivePath, '/tmp/example.zip');
    expect(engine.extractions.single.outputDirectory, '/tmp');
    expect(find.text('解压完成'), findsOneWidget);
    expect(openService.quitCalls, 0);

    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(openService.quitCalls, 1);
  });

  testWidgets('Finder 解压 shows the failure reason and quits after closing', (
    tester,
  ) async {
    final engine = _FinderActionArchiveEngine(
      extractError: const ArchiveException('压缩包已损坏'),
    );
    final openService = _NoopArchiveOpenService();
    final service = _FakeFinderActionService(
      const FinderActionRequest(
        type: FinderActionType.extractHere,
        paths: ['/tmp/broken.zip'],
      ),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: engine,
        fileAccessService: _GrantedFileAccessService(),
        finderActionService: service,
        archiveOpenService: openService,
      ),
    );
    unawaited(service.dispatch());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('解压失败'), findsOneWidget);
    expect(find.textContaining('broken.zip：压缩包已损坏'), findsOneWidget);
    expect(openService.quitCalls, 0);

    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
    expect(openService.quitCalls, 1);
  });

  testWidgets('Finder 压缩成 ZIP creates beside the selected source', (
    tester,
  ) async {
    late Directory directory;
    late File source;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('jucier-finder-test-');
      source = File('${directory.path}/notes.txt');
      await source.writeAsString('hello');
    });
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final engine = _FinderActionArchiveEngine();
    final service = _FakeFinderActionService(
      FinderActionRequest(
        type: FinderActionType.compressZip,
        paths: [source.path],
      ),
    );

    await tester.pumpWidget(
      JucierApp(
        engine: engine,
        fileAccessService: _GrantedFileAccessService(),
        finderActionService: service,
      ),
    );
    await tester.runAsync(service.dispatch);
    for (var attempt = 0; attempt < 20 && engine.creations.isEmpty; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 400));

    expect(engine.creations, hasLength(1));
    expect(engine.creations.single.archivePath, '${directory.path}/notes.zip');
    expect(engine.creations.single.sources, [source.path]);
    expect(engine.creations.single.format, ArchiveFormat.zip);
    expect(engine.listCalls, isEmpty);
    expect(find.text('压缩完成'), findsOneWidget);
  });
}

class _FakeFinderActionService implements FinderActionService {
  _FakeFinderActionService(this.request);

  final FinderActionRequest request;
  FinderActionHandler? _handler;

  @override
  void setHandler(FinderActionHandler? handler) => _handler = handler;

  @override
  Future<void> synchronize() async {}

  Future<void> dispatch() async {
    await _handler?.call(request);
  }

  @override
  Future<bool> contextMenuAvailable() async => true;

  @override
  Future<void> repairContextMenu() async {}

  @override
  Future<void> uninstallContextMenu() async {}
}

class _FinderActionArchiveEngine implements ArchiveEngine {
  _FinderActionArchiveEngine({this.extractError});

  final ArchiveException? extractError;
  final List<CreateArchiveOptions> creations = [];
  final List<ExtractArchiveOptions> extractions = [];
  final List<String> listCalls = [];

  @override
  Future<void> create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    creations.add(options);
  }

  @override
  Future<void> extract(
    ExtractArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    if (extractError case final error?) throw error;
    extractions.add(options);
  }

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) async {
    listCalls.add(archivePath);
    return ArchiveListing(archivePath: archivePath, entries: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopArchiveOpenService implements ArchiveOpenService {
  ArchiveOpenHandler? handler;
  int quitCalls = 0;

  @override
  void setHandler(ArchiveOpenHandler? handler) => this.handler = handler;

  @override
  Future<void> synchronize() async {}

  @override
  Future<void> quitApplication() async {
    quitCalls++;
  }
}

class _GrantedFileAccessService implements FileAccessService {
  @override
  Future<FileAccessStatus> status() async =>
      const FileAccessStatus(requested: true, granted: true);

  @override
  Future<FileAccessStatus> requestAccess() => status();

  @override
  void setOpenSettingsHandler(VoidCallback? handler) {}
}
