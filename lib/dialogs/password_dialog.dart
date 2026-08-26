import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

Future<String?> showPasswordDialog(
  BuildContext context, {
  required String title,
}) {
  final controller = TextEditingController();
  return showFDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context, _, animation) => FDialog(
      animation: animation,
      constraints: const BoxConstraints(minWidth: 400, maxWidth: 460),
      builder: (context, style) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: style.titleTextStyle),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码'),
              onSubmitted: (value) {
                if (value.isNotEmpty) Navigator.of(context).pop(value);
              },
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FButton(
                  size: FButtonSizeVariant.sm,
                  onPress: () {
                    if (controller.text.isNotEmpty) {
                      Navigator.of(context).pop(controller.text);
                    }
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ).whenComplete(controller.dispose);
}
