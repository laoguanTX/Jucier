import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showFDialog<void>(
  context: context,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 380, maxWidth: 480),
    builder: (context, style) => Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: style.titleTextStyle),
          const SizedBox(height: 10),
          SelectableText(message, style: style.bodyTextStyle),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerRight,
            child: FButton(
              size: FButtonSizeVariant.sm,
              onPress: () => Navigator.of(context).pop(),
              child: const Text('好'),
            ),
          ),
        ],
      ),
    ),
  ),
);
