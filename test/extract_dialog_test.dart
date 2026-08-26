import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/dialogs/extract_dialog.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('requires a system-selected extraction directory', (
    tester,
  ) async {
    final theme = FTheme.neutral.light.desktop;
    ExtractArchiveOptions? result;
    String? pickerInitialDirectory;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: theme,
          child: Material(type: MaterialType.transparency, child: child!),
        ),
        home: Builder(
          builder: (context) => FButton(
            onPress: () async {
              result = await showExtractDialog(
                context,
                archivePath: '/tmp/sample.7z',
                directoryPicker: ({required initialDirectory}) async {
                  pickerInitialDirectory = initialDirectory;
                  return '/tmp/extracted';
                },
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final directoryField = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    expect(directoryField.readOnly, isTrue);
    expect(find.text('请选择或新建一个文件夹'), findsOneWidget);

    await tester.tap(find.text('解压').last);
    await tester.pumpAndSettle();

    expect(pickerInitialDirectory, '/tmp');
    expect(result?.outputDirectory, '/tmp/extracted');
  });

  testWidgets(
    'does not start extraction when directory selection is canceled',
    (tester) async {
      final theme = FTheme.neutral.light.desktop;
      var dialogCompleted = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: theme,
            child: Material(type: MaterialType.transparency, child: child!),
          ),
          home: Builder(
            builder: (context) => FButton(
              onPress: () async {
                await showExtractDialog(
                  context,
                  archivePath: '/tmp/sample.7z',
                  directoryPicker: ({required initialDirectory}) async => null,
                );
                dialogCompleted = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('解压').last);
      await tester.pumpAndSettle();

      expect(find.text('解压文件'), findsOneWidget);
      expect(dialogCompleted, isFalse);
    },
  );
}
