import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  bool destructive = false,
}) async =>
    await showFDialog<bool>(
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
              Text(message, style: style.bodyTextStyle),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    size: FButtonSizeVariant.sm,
                    variant: FButtonVariant.ghost,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    size: FButtonSizeVariant.sm,
                    variant: destructive
                        ? FButtonVariant.destructive
                        : FButtonVariant.primary,
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;
