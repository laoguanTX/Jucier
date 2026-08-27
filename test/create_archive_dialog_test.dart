import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/archive/archive_options.dart';
import 'package:jucier/dialogs/create_archive_dialog.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('create archive form has a Material ancestor', (tester) async {
    final theme = FTheme.neutral.light.desktop;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: theme,
          child: Material(type: MaterialType.transparency, child: child!),
        ),
        home: Builder(
          builder: (context) => FButton(
            onPress: () => showCreateArchiveDialog(
              context,
              sources: const ['/tmp/example.txt'],
            ),
            child: const Text('Create'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('创建压缩包'), findsOneWidget);
    // The archive format and volume unit selects each use a read-only
    // TextField internally.
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.text(' .zip'), findsOneWidget);

    final locationField = find.byKey(const ValueKey('save-location-field'));
    final locationButton = find.byKey(const ValueKey('save-location-button'));
    expect(
      tester.getSize(locationField).height,
      tester.getSize(locationButton).height,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: locationField,
              matching: find.byType(TextField),
            ),
          )
          .decoration
          ?.labelText,
      isNull,
    );
    final locationBounds = tester.getRect(locationField);
    final editableBounds = tester.getRect(
      find.descendant(of: locationField, matching: find.byType(EditableText)),
    );
    expect(editableBounds.top, greaterThanOrEqualTo(locationBounds.top));
    expect(editableBounds.bottom, lessThanOrEqualTo(locationBounds.bottom));
    final compressionRow = find.byKey(
      const ValueKey('compression-controls-row'),
    );
    final saveTitle = find.byKey(const ValueKey('save-location-title'));
    expect(
      tester.getSize(compressionRow).height,
      moreOrLessEquals(
        tester.getSize(saveTitle).height +
            6 +
            tester.getSize(locationField).height,
        epsilon: 1,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('advanced-options-title')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final volumeField = find.byKey(const ValueKey('volume-size-field'));
    final volumeUnit = find.byKey(const ValueKey('volume-unit-select'));
    expect(
      tester.getSize(locationField).height,
      tester.getSize(volumeField).height,
    );
    final passwordField = find.byKey(
      const ValueKey('compression-password-field'),
    );
    expect(
      tester.getSize(passwordField).height,
      tester.getSize(volumeField).height,
    );
    expect(
      tester
          .getSize(
            find.descendant(
              of: volumeField,
              matching: find.byType(InputDecorator),
            ),
          )
          .height,
      tester
          .getSize(
            find.descendant(
              of: volumeUnit,
              matching: find.byType(InputDecorator),
            ),
          )
          .height,
    );
    final volumeDecoration = tester
        .widget<TextField>(
          find.descendant(of: volumeField, matching: find.byType(TextField)),
        )
        .decoration;
    expect(volumeDecoration?.labelText, isNull);
    expect(find.text('分卷大小'), findsOneWidget);
    expect(find.text('MB'), findsOneWidget);
    await tester.tap(volumeUnit);
    await tester.pumpAndSettle();
    expect(find.text('KB'), findsOneWidget);
    expect(find.text('GB'), findsOneWidget);
    await tester.tap(find.text('GB'));
    await tester.pumpAndSettle();
    expect(find.text('GB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('compression-password-title')));
    await tester.pumpAndSettle();
    expect(volumeField.hitTestable(), findsOneWidget);

    expect(
      tester.getSize(find.byKey(const ValueKey('archive-format-select'))).width,
      lessThan(tester.getSize(find.byType(Slider)).width),
    );

    final password = tester.widget<TextField>(
      find.descendant(of: passwordField, matching: find.byType(TextField)),
    );
    expect(password.decoration?.labelText, isNull);
    expect(password.decoration?.hintText, '可选');

    final smallTitleFontSizes =
        [
          'save-location-title',
          'archive-format-title',
          'compression-level-title',
          'compression-password-title',
          'volume-size-title',
        ].map(
          (key) =>
              tester.widget<Text>(find.byKey(ValueKey(key))).style?.fontSize,
        );
    expect(smallTitleFontSizes.toSet(), hasLength(1));

    final pageTitle = tester.widget<Text>(
      find.byKey(const ValueKey('create-archive-title')),
    );
    expect(pageTitle.style?.fontSize, greaterThan(smallTitleFontSizes.first!));

    final advancedTitle = tester.widget<Text>(
      find.byKey(const ValueKey('advanced-options-title')),
    );
    expect(advancedTitle.style?.decoration, TextDecoration.none);
  });

  testWidgets('format menu is plain and follows popularity order', (
    tester,
  ) async {
    final theme = FTheme.neutral.light.desktop;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.toApproximateMaterialTheme(),
        builder: (context, child) => FTheme(
          data: theme,
          child: Material(type: MaterialType.transparency, child: child!),
        ),
        home: Builder(
          builder: (context) => FButton(
            onPress: () => showCreateArchiveDialog(
              context,
              sources: const ['/tmp/example.txt'],
            ),
            child: const Text('Create'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-format-select')));
    await tester.pumpAndSettle();

    expect(find.text('兼容性最佳，适合分享'), findsNothing);
    expect(find.text('高压缩率，适合归档'), findsNothing);
    expect(
      tester
          .widget<FSelectItem<ArchiveFormat>>(
            find.byKey(const ValueKey('archive-format-zip')),
          )
          .prefix,
      isNull,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('archive-format-zip'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('archive-format-7z'))).dy,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('archive-format-xz')));
    await tester.pumpAndSettle();
    expect(find.text(' .xz'), findsOneWidget);
    expect(find.text('可选'), findsOneWidget);
  });

  test('creation formats are ordered by everyday usefulness', () {
    expect(ArchiveFormat.values, [
      ArchiveFormat.zip,
      ArchiveFormat.sevenZip,
      ArchiveFormat.tar,
      ArchiveFormat.gzip,
      ArchiveFormat.xz,
      ArchiveFormat.bzip2,
      ArchiveFormat.wim,
    ]);
  });
}
