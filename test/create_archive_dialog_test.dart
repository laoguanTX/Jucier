import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
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
    expect(find.byType(TextField), findsNWidgets(3));
  });
}
