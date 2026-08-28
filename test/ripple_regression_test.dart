import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/app.dart';
import 'package:jucier/archive/archive_engine.dart';
import 'package:jucier/platform/file_access_service.dart';

void main() {
  testWidgets('ripple ring fully hides after settings closes', (tester) async {
    final permissions = _FakeFileAccessService(
      initialStatus: const FileAccessStatus(
        requested: true,
        granted: true,
        directory: '/Users/example',
      ),
    );

    await tester.pumpWidget(
      JucierApp(engine: _UnusedArchiveEngine(), fileAccessService: permissions),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(_rippleProgress(tester), 1);

    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    // The AnimatedSwitcher detaches the outgoing settings entry before its
    // final animation tick is built, so the ripple progress must be driven to
    // zero by the transition status rather than left a fraction above it.
    expect(_rippleProgress(tester), 0);
  });
}

double? _rippleProgress(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(
    find.byType(CustomPaint),
  )) {
    if (paint.painter.runtimeType.toString().contains('Ripple')) {
      return (paint.painter as dynamic).progress as double;
    }
  }
  return null;
}

class _FakeFileAccessService implements FileAccessService {
  _FakeFileAccessService({required this.initialStatus});

  final FileAccessStatus initialStatus;

  @override
  Future<FileAccessStatus> status() async => initialStatus;

  @override
  Future<FileAccessStatus> requestAccess() async => initialStatus;

  @override
  void setOpenSettingsHandler(VoidCallback? handler) {}
}

class _UnusedArchiveEngine implements ArchiveEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
