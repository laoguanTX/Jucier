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

    final locationField = find.byKey(const ValueKey('extract-location-field'));
    final locationButton = find.byKey(
      const ValueKey('extract-location-button'),
    );
    final inputBounds = tester.getRect(
      find.descendant(of: locationField, matching: find.byType(InputDecorator)),
    );
    final buttonBounds = tester.getRect(locationButton);
    expect(inputBounds.top, buttonBounds.top);
    expect(inputBounds.bottom, buttonBounds.bottom);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('extract-conflict-select')))
          .height,
      inputBounds.height,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('extract-password-field')))
          .height,
      inputBounds.height,
    );

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

  for (final dark in [false, true]) {
    testWidgets(
      'path field and button both select a directory (${dark ? 'dark' : 'light'})',
      (tester) async {
        final theme = dark
            ? FTheme.neutral.dark.desktop
            : FTheme.neutral.light.desktop;
        final initialDirectories = <String>[];
        ExtractArchiveOptions? result;

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
                    initialPassword: 'initial',
                    directoryPicker: ({required initialDirectory}) async {
                      initialDirectories.add(initialDirectory);
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

        final field = find.byKey(const ValueKey('extract-location-field'));
        final button = find.byKey(const ValueKey('extract-location-button'));
        final inputBounds = tester.getRect(
          find.descendant(of: field, matching: find.byType(InputDecorator)),
        );
        expect(inputBounds.top, tester.getRect(button).top);
        expect(inputBounds.bottom, tester.getRect(button).bottom);

        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(initialDirectories, ['/tmp', '/tmp/extracted']);

        await tester.tap(find.byKey(const ValueKey('extract-conflict-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('自动重命名'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('extract-password-field')),
            matching: find.byType(TextField),
          ),
          'updated',
        );
        await tester.tap(find.text('解压'));
        await tester.pumpAndSettle();

        expect(result?.outputDirectory, '/tmp/extracted');
        expect(result?.conflict, ExtractionConflict.rename);
        expect(result?.password, 'updated');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
