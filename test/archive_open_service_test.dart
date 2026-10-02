import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/archive/archive_entry.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/platform/archive_open_preference_store.dart';
import 'package:jucier/platform/archive_open_service.dart';
import 'package:jucier/platform/file_access_service.dart';
import 'package:jucier/screens/home_screen.dart';
import 'package:jucier/widgets/operation_progress.dart';

import 'support/fake_desktop_window_service.dart';

void main() {
  const channel = MethodChannel('dev.jucier/platform');
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  const finderChannel = MethodChannel('dev.jucier/finder_action');
  setUp(
    () => messenger.setMockMethodCallHandler(
      finderChannel,
      (call) async =>
          call.method == 'takePendingFinderActions' ? <Object>[] : false,
    ),
  );
  tearDown(() => messenger.setMockMethodCallHandler(finderChannel, null));
  testWidgets('a macOS open event navigates directly to the archive tree', (
    tester,
  ) async {
    final openService = _FakeArchiveOpenService('/tmp/from-finder.zip');
    final engine = _ListingArchiveEngine();

    await tester.pumpWidget(
      JucierApp(
        engine: engine,
        desktopWindowService: FakeDesktopWindowService(),
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

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    for (final smart in [false, true]) {
      testWidgets(
        '${platform.name} cold double-click waits for preferences and extracts (smart: $smart)',
        (tester) async {
          final smartPreference = Completer<bool>();
          messenger.setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'smartExtractionEnabled'
                ? smartPreference.future
                : null,
          );
          final preference = Completer<ArchiveOpenMode>();
          final engine = _ExtractionArchiveEngine();
          final openService = _FakeArchiveOpenService('/tmp/from-finder.zip');
          await tester.pumpWidget(
            JucierApp(
              engine: engine,
              desktopWindowService: FakeDesktopWindowService(),
              fileAccessService: _GrantedFileAccessService(),
              archiveOpenService: openService,
              archiveOpenPreferenceStore: _FixedArchiveOpenPreferenceStore(
                preference.future,
              ),
              waitForInitialArchiveOpen: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(engine.extractions, isEmpty);
          expect(engine.listCalls, isEmpty);
          preference.complete(ArchiveOpenMode.extract);
          await tester.pumpAndSettle();
          expect(engine.extractions, isEmpty);
          expect(engine.listCalls, isEmpty);
          smartPreference.complete(smart);
          await tester.pumpAndSettle();
          expect(engine.extractions, hasLength(1));
          expect(engine.extractions.single.archivePath, '/tmp/from-finder.zip');
          expect(
            engine.extractions.single.outputDirectory,
            smart ? '/tmp/from-finder' : '/tmp',
          );
          expect(engine.listCalls, smart ? ['/tmp/from-finder.zip'] : isEmpty);
          expect(find.byKey(const ValueKey('archive-page')), findsNothing);
          expect(find.text('解压文件'), findsNothing);
          expect(find.text('解压完成'), findsOneWidget);
          expect(openService.quitCalls, 0);
          await tester.tap(find.text('好'));
          await tester.pumpAndSettle();
          expect(openService.quitCalls, 1);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final cancelPassword in [false, true]) {
    testWidgets(
      'direct extraction ${cancelPassword ? 'cancels' : 'prompts for'} an encrypted archive',
      (tester) async {
        final engine = _ExtractionArchiveEngine(requiredPassword: 'secret');
        final openService = _FakeArchiveOpenService('/tmp/from-finder.zip');
        await tester.pumpWidget(
          JucierApp(
            engine: engine,
            desktopWindowService: FakeDesktopWindowService(),
            fileAccessService: _GrantedFileAccessService(),
            archiveOpenService: openService,
            archiveOpenPreferenceStore: _FixedArchiveOpenPreferenceStore(
              Future.value(ArchiveOpenMode.extract),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('输入 from-finder.zip 的密码'), findsOneWidget);
        expect(engine.extractions, isEmpty);
        if (cancelPassword) {
          await tester.tap(find.text('取消').last);
        } else {
          await tester.enterText(find.byType(EditableText), 'secret');
          await tester.tap(find.text('继续'));
        }
        await tester.pumpAndSettle();
        if (cancelPassword) {
          expect(engine.extractions, isEmpty);
          expect(find.text('解压已取消'), findsOneWidget);
        } else {
          expect(engine.extractions.single.password, 'secret');
          expect(find.text('解压完成'), findsOneWidget);
        }
        expect(openService.quitCalls, 0);
        await tester.tap(find.text('好'));
        await tester.pumpAndSettle();
        expect(openService.quitCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a running app uses a newly changed double-click preference', (
    tester,
  ) async {
    final engine = _ExtractionArchiveEngine();
    final openService = _FakeArchiveOpenService(null);
    await tester.pumpWidget(
      JucierApp(
        engine: engine,
        desktopWindowService: FakeDesktopWindowService(),
        fileAccessService: _GrantedFileAccessService(),
        archiveOpenService: openService,
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<JucierShell>(find.byType(JucierShell))
        .onArchiveOpenModeChanged!(ArchiveOpenMode.extract);
    await tester.pumpAndSettle();
    unawaited(openService.dispatch('/tmp/from-finder.zip'));
    await tester.pumpAndSettle();
    expect(engine.extractions, hasLength(1));
    expect(find.text('解压完成'), findsOneWidget);
    await tester.tap(find.text('好'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'dropping into the app still opens the tree in direct extraction mode',
    (tester) async {
      final engine = _ExtractionArchiveEngine();
      await tester.pumpWidget(
        JucierApp(
          engine: engine,
          desktopWindowService: FakeDesktopWindowService(),
          fileAccessService: _GrantedFileAccessService(),
          archiveOpenService: _FakeArchiveOpenService(null),
          archiveOpenPreferenceStore: _FixedArchiveOpenPreferenceStore(
            Future.value(ArchiveOpenMode.extract),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.widget<HomeScreen>(find.byType(HomeScreen)).onDropped([
        '/tmp/from-finder.zip',
      ]);
      await tester.pumpAndSettle();
      expect(engine.extractions, isEmpty);
      expect(find.byKey(const ValueKey('archive-page')), findsOneWidget);
    },
  );

  testWidgets(
    'cold extraction shows live progress then the result in one window',
    (tester) async {
      final extraction = Completer<void>();
      final engine = _ExtractionArchiveEngine(extraction: extraction);
      final windows = FakeDesktopWindowService();
      final openService = _FakeArchiveOpenService('/tmp/from-finder.zip');
      await tester.pumpWidget(
        JucierApp(
          engine: engine,
          desktopWindowService: windows,
          fileAccessService: _GrantedFileAccessService(),
          archiveOpenService: openService,
          archiveOpenPreferenceStore: _FixedArchiveOpenPreferenceStore(
            Future.value(ArchiveOpenMode.extract),
          ),
          waitForInitialArchiveOpen: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('external-operation-window')),
        findsOneWidget,
      );
      expect(find.byType(HomeScreen), findsNothing);
      expect(windows.mainShows, 0);
      expect(windows.operationShows, 1);
      engine.reportProgress!(0.42);
      await tester.pump();
      expect(find.text('42%'), findsOneWidget);
      extraction.complete();
      await tester.pumpAndSettle();
      expect(find.text('解压完成'), findsOneWidget);
      expect(find.byType(OperationProgress), findsNothing);
      expect(windows.finishCalls, 0);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(windows.finishCalls, 1);
      expect(openService.quitCalls, 1);
      expect(windows.mainShows, 0);
    },
  );

  for (final compact in [false, true]) {
    testWidgets(
      'external extraction preserves an existing ${compact ? 'hidden' : 'visible'} workspace',
      (tester) async {
        final engine = _ExtractionArchiveEngine();
        final windows = FakeDesktopWindowService(
          compact: compact,
          quitAfterOperation: false,
        );
        final openService = _FakeArchiveOpenService(null);
        await tester.pumpWidget(
          JucierApp(
            engine: engine,
            desktopWindowService: windows,
            fileAccessService: _GrantedFileAccessService(),
            archiveOpenService: openService,
            archiveOpenPreferenceStore: _FixedArchiveOpenPreferenceStore(
              Future.value(ArchiveOpenMode.extract),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.widget<HomeScreen>(find.byType(HomeScreen)).onDropped([
          '/tmp/workspace.zip',
        ]);
        await tester.pumpAndSettle();
        final mainShows = windows.mainShows;
        unawaited(openService.dispatch('/tmp/from-finder.zip'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('external-operation-window')),
          compact ? findsOneWidget : findsNothing,
        );
        expect(find.text('解压完成'), findsOneWidget);
        await tester.tap(find.text('好'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('archive-page')), findsOneWidget);
        expect(
          engine.listCalls.where((path) => path == '/tmp/workspace.zip'),
          hasLength(1),
        );
        expect(windows.mainShows, mainShows);
        expect(windows.finishCalls, compact ? 1 : 0);
        expect(openService.quitCalls, 0);
      },
    );
  }

  testWidgets(
    'cancel during smart extraction preparation prevents extraction',
    (tester) async {
      final listing = Completer<void>();
      final engine = _ExtractionArchiveEngine(listing: listing);
      final openService = _FakeArchiveOpenService('/tmp/from-finder.zip');
      await tester.pumpWidget(
        JucierApp(
          engine: engine,
          desktopWindowService: FakeDesktopWindowService(),
          fileAccessService: _GrantedFileAccessService(),
          archiveOpenService: openService,
          archiveOpenPreferenceStore: _FixedArchiveOpenPreferenceStore(
            Future.value(ArchiveOpenMode.extract),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      listing.complete();
      await tester.pumpAndSettle();
      expect(engine.extractions, isEmpty);
      expect(find.text('解压已取消'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
    },
  );
}

class _FixedArchiveOpenPreferenceStore implements ArchiveOpenPreferenceStore {
  _FixedArchiveOpenPreferenceStore(this.mode);
  final Future<ArchiveOpenMode> mode;

  @override
  Future<ArchiveOpenMode> load() => mode;

  @override
  Future<void> save(ArchiveOpenMode mode) async {}
}

class _ExtractionArchiveEngine implements ArchiveEngine {
  _ExtractionArchiveEngine({
    this.requiredPassword,
    this.extraction,
    this.listing,
  });
  final String? requiredPassword;
  final Completer<void>? extraction;
  final Completer<void>? listing;
  ProgressCallback? reportProgress;
  final extractions = <ExtractArchiveOptions>[];
  final listCalls = <String>[];

  @override
  Future<ArchiveListing> list(String archivePath, {String? password}) async {
    listCalls.add(archivePath);
    await listing?.future;
    if (requiredPassword != null && password != requiredPassword) {
      throw const ArchivePasswordRequiredException();
    }
    return ArchiveListing(
      archivePath: archivePath,
      entries: const [
        ArchiveEntry(path: 'one.txt', isDirectory: false),
        ArchiveEntry(path: 'two.txt', isDirectory: false),
      ],
    );
  }

  @override
  Future<void> extract(
    ExtractArchiveOptions options, {
    ProgressCallback? onProgress,
  }) async {
    extractions.add(options);
    reportProgress = onProgress;
    onProgress?.call(0);
    await extraction?.future;
  }

  @override
  Future<void> cancel() async {
    if (extraction?.isCompleted == false) {
      extraction!.completeError(const ArchiveCancelledException());
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArchiveOpenService implements ArchiveOpenService {
  _FakeArchiveOpenService(this.initialPath);

  final String? initialPath;
  ArchiveOpenHandler? _handler;
  int quitCalls = 0;

  @override
  void setHandler(ArchiveOpenHandler? handler) => _handler = handler;

  @override
  Future<void> synchronize() async {
    if (initialPath case final path?) await dispatch(path);
  }

  Future<void> dispatch(String path) async => _handler?.call(path);

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
