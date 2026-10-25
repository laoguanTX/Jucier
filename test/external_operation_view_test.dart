import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/widgets/external_operation_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'quick-action height follows content and keeps actions accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(560, 240));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final theme = FTheme.neutral.light.desktop;
      final heights = <double>[];
      String? message;
      late StateSetter update;
      var opened = 0;
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toApproximateMaterialTheme(),
          home: FTheme(
            data: theme,
            child: Material(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return ExternalOperationView(
                    title: message == null ? '压缩文件' : '压缩完成',
                    label: '正在压缩一个很长名称的文件.txt',
                    progress: 0.5,
                    message: message,
                    onCancel: () async {},
                    onClose: () => closed++,
                    onOpenDirectory: () async => opened++,
                    onSizeChanged: (size) => heights.add(size.height),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final progressHeight = heights.last;
      expect(progressHeight, lessThan(240));
      expect(tester.takeException(), isNull);

      update(() => message = '压缩包已保存到 /tmp/example.zip');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        find.byKey(const ValueKey('external-operation-progress')),
        findsOneWidget,
      );
      final result = find.byKey(const ValueKey('external-operation-result'));
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: result, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, greaterThan(0));
      expect(fade.opacity.value, lessThan(1));
      expect(find.text('取消').hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('external-operation-progress')),
        findsNothing,
      );
      final shortHeight = heights.last;
      expect(shortHeight, lessThan(240));

      update(() => message = List.filled(100, '很长的目录名称和文件路径').join('/'));
      await tester.pumpAndSettle();
      final longHeight = heights.last;
      expect(longHeight, greaterThan(shortHeight));
      expect(longHeight, lessThan(440));
      await tester.binding.setSurfaceSize(Size(560, longHeight.ceilToDouble()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开所在文件夹'));
      await tester.tap(find.text('好'));
      expect(opened, 1);
      expect(closed, 1);
      expect(tester.takeException(), isNull);

      update(() => message = '压缩包已保存到 /tmp/example.zip');
      await tester.pumpAndSettle();
      expect(heights.last, shortHeight);
    },
  );
}
