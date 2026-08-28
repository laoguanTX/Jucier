import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/platform/archive_open_service.dart';
import 'package:jucier/platform/file_access_service.dart';

void main() {
  testWidgets('a macOS open event navigates directly to the archive tree', (
    tester,
  ) async {
    final openService = _FakeArchiveOpenService('/tmp/from-finder.zip');
    final engine = _ListingArchiveEngine();

    await tester.pumpWidget(
      JucierApp(
        engine: engine,
        fileAccessService: _GrantedFileAccessService(),
        archiveOpenService: openService,
        waitForInitialArchiveOpen: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('external-archive-launch-page')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-page')), findsNothing);

    engine.completeOpen();
    await tester.pumpAndSettle();

    expect(engine.openedPaths, ['/tmp/from-finder.zip']);
    expect(find.byKey(const ValueKey('archive-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-page')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('archive-close')));
    await tester.pumpAndSettle();
    expect(openService.quitCalls, 1);
    expect(find.byKey(const ValueKey('home-page')), findsNothing);
  });
}

class _FakeArchiveOpenService implements ArchiveOpenService {
  _FakeArchiveOpenService(this.initialPath);

  final String initialPath;
  ArchiveOpenHandler? _handler;
  int quitCalls = 0;

  @override
  void setHandler(ArchiveOpenHandler? handler) => _handler = handler;

  @override
  Future<void> synchronize() async {
    await _handler?.call(initialPath);
  }

  @override
  Future<void> quitApplication() async {
    quitCalls++;
  }
}

class _ListingArchiveEngine implements ArchiveEngine {
  final List<String> openedPaths = [];
  final Completer<ArchiveListing> _openCompleter = Completer<ArchiveListing>();

  void completeOpen() {
    _openCompleter.complete(
      const ArchiveListing(archivePath: '/tmp/from-finder.zip', entries: []),
    );
  }

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) async {
    openedPaths.add(archivePath);
    return _openCompleter.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
