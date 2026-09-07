import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/application/archive_workflow_controller.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/archive/archive_options.dart';

void main() {
  test(
    'owns archive state and clears operation state after completion',
    () async {
      final engine = _FakeArchiveEngine();
      final controller = ArchiveWorkflowController(engine);

      await controller.open('/tmp/example.zip', password: 'secret');
      expect(controller.listing?.archivePath, '/tmp/example.zip');
      expect(controller.password, 'secret');

      final create = controller.create(
        const CreateArchiveOptions(
          archivePath: '/tmp/output.7z',
          sources: ['/tmp/input'],
          format: ArchiveFormat.sevenZip,
        ),
      );

      expect(controller.busy, isTrue);
      expect(controller.operationLabel, '正在创建 output.7z');
      expect(controller.progress, 0.4);

      engine.completeCreate();
      await create;
      expect(controller.listing?.archivePath, '/tmp/output.7z');
      expect(controller.password, isNull);
      expect(controller.busy, isFalse);
      expect(controller.operationLabel, isNull);
      expect(controller.progress, isNull);

      controller.closeArchive();
      expect(controller.listing, isNull);
      expect(controller.password, isNull);
    },
  );

  test('can create directly without opening the new archive', () async {
    final engine = _ImmediateArchiveEngine();
    final controller = ArchiveWorkflowController(engine);

    await controller.create(
      const CreateArchiveOptions(
        archivePath: '/tmp/output.zip',
        sources: ['/tmp/input'],
        format: ArchiveFormat.zip,
      ),
      openAfterCreate: false,
    );

    expect(engine.createCalls, 1);
    expect(engine.listCalls, 0);
    expect(controller.listing, isNull);
    expect(controller.busy, isFalse);
  });
  test('serializes tasks and stays busy until the queue is drained', () async {
    final engine = _QueuedEngine();
    final controller = ArchiveWorkflowController(engine);
    final first = controller.open('/tmp/first.zip');
    final second = controller.open('/tmp/second.zip');
    expect(engine.paths, ['/tmp/first.zip']);
    var idle = false;
    final waiting = controller.waitUntilIdle().then((_) => idle = true);
    engine.requests.first.complete(
      const ArchiveListing(archivePath: '/tmp/first.zip', entries: []),
    );
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(idle, isFalse);
    expect(controller.busy, isTrue);
    expect(engine.paths, ['/tmp/first.zip', '/tmp/second.zip']);
    engine.requests.last.complete(
      const ArchiveListing(archivePath: '/tmp/second.zip', entries: []),
    );
    await second;
    await waiting;
    expect(controller.busy, isFalse);
    expect(controller.listing?.archivePath, '/tmp/second.zip');
    controller.dispose();
  });

  test(
    'cancelling a task also cancels waiting tasks before they start',
    () async {
      final engine = _QueuedEngine();
      final controller = ArchiveWorkflowController(engine);
      final first = controller.open('/tmp/first.zip');
      final second = controller.open('/tmp/second.zip');
      final firstCheck = expectLater(
        first,
        throwsA(isA<ArchiveCancelledException>()),
      );
      final secondCheck = expectLater(
        second,
        throwsA(isA<ArchiveCancelledException>()),
      );
      await controller.cancel();
      await Future.wait([firstCheck, secondCheck]);
      expect(engine.paths, ['/tmp/first.zip']);
      expect(controller.busy, isFalse);
      controller.dispose();
    },
  );
}

class _FakeArchiveEngine implements ArchiveEngine {
  final Completer<void> _createCompleter = Completer<void>();

  void completeCreate() => _createCompleter.complete();

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) async =>
      ArchiveListing(archivePath: archivePath, entries: const []);

  @override
  Future<void> create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  }) {
    onProgress?.call(0.4);
    return _createCompleter.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImmediateArchiveEngine implements ArchiveEngine {
  int createCalls = 0;
  int listCalls = 0;

  @override
  Future<void> create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    createCalls++;
  }

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) async {
    listCalls++;
    return ArchiveListing(archivePath: archivePath, entries: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QueuedEngine implements ArchiveEngine {
  final paths = <String>[];
  final requests = <Completer<ArchiveListing>>[];
  @override
  Future<ArchiveListing> list(String path, {String? password}) {
    paths.add(path);
    final request = Completer<ArchiveListing>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> cancel() async {
    if (requests.isNotEmpty && !requests.last.isCompleted) {
      requests.last.completeError(const ArchiveCancelledException());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
