import '../archive/archive_engine.dart';
import '../widgets/content_size_reporter.dart';

import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? details,
  Future<void> Function()? onOpenDirectory,
  ValueChanged<Size>? onSizeChanged,
}) => showFDialog<void>(
  context: context,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: BoxConstraints(
      minWidth: 380,
      maxWidth: 480,
      maxHeight: MediaQuery.sizeOf(context).height - 48,
    ),
    builder: (context, style) => SingleChildScrollView(
      child: ContentSizeReporter(
        onSizeChanged: onSizeChanged,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: style.titleTextStyle),
              const SizedBox(height: 10),
              SelectableText(message, style: style.bodyTextStyle),
              if (details != null && details.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                FAccordion(
                  children: [
                    FAccordionItem(
                      title: const Text('查看详情'),
                      child: SelectableText(
                        details.length > 6000
                            ? details.substring(details.length - 6000)
                            : details,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  if (onOpenDirectory != null) ...[
                    Expanded(
                      child: FButton(
                        size: FButtonSizeVariant.sm,
                        variant: FButtonVariant.outline,
                        prefix: const Icon(FLucideIcons.folderOpen, size: 16),
                        onPress: onOpenDirectory,
                        child: const Text('打开所在文件夹'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FButton(
                      size: FButtonSizeVariant.sm,
                      onPress: () => Navigator.of(context).pop(),
                      child: const Text('好'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<void> showArchiveErrorDialog(
  BuildContext context, {
  required String title,
  required ArchiveException error,
}) => showMessageDialog(
  context,
  title: error is ArchiveWarningException ? '部分完成' : title,
  message: error.message,
  details: error.output,
);
