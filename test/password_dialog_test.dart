import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:jucier/dialogs/password_dialog.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final submitWithKeyboard in [false, true]) {
    testWidgets(
      'password dialog submits using ${submitWithKeyboard ? 'keyboard' : 'button'}',
      (tester) async {
        final theme = FTheme.neutral.light.desktop;
        String? result;
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
                  result = await showPasswordDialog(context, title: '输入压缩包密码');
                },
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final field = find.descendant(
          of: find.byKey(const ValueKey('password-dialog-field')),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(field).obscureText, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(find.text('输入压缩包密码'), findsOneWidget);

        await tester.enterText(field, 'secret');
        if (submitWithKeyboard) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          await tester.tap(find.text('继续'));
        }
        await tester.pumpAndSettle();
        expect(result, 'secret');
        expect(find.text('输入压缩包密码'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
