import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show SelectableText;

import 'operation_progress.dart';
import 'content_size_reporter.dart';

/// The entire content of the small window used by desktop quick actions.
class ExternalOperationView extends StatelessWidget {
  const ExternalOperationView({
    super.key,
    required this.title,
    required this.label,
    required this.progress,
    required this.onCancel,
    required this.onClose,
    this.onOpenDirectory,
    this.onSizeChanged,
    this.message,
    this.failed = false,
  });

  final String title;
  final String label;
  final double? progress;
  final Future<void> Function() onCancel;
  final VoidCallback onClose;
  final Future<void> Function()? onOpenDirectory;
  final ValueChanged<Size>? onSizeChanged;
  final String? message;
  final bool failed;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: ContentSizeReporter(
      onSizeChanged: onSizeChanged,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [
            for (final child in previous)
              IgnorePointer(child: ExcludeSemantics(child: child)),
            ?current,
          ],
        ),
        child: Padding(
          key: ValueKey(
            message == null
                ? 'external-operation-progress'
                : 'external-operation-result',
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.theme.typography.display.xl.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              if (message == null) ...[
                Text('正在处理，请稍候。', style: context.theme.typography.body.sm),
                const SizedBox(height: 16),
                OperationProgress(
                  label: label,
                  progress: progress,
                  onCancel: onCancel,
                ),
              ] else ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      message!,
                      style: context.theme.typography.body.sm.copyWith(
                        color: failed ? context.theme.colors.error : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                        onPress: onClose,
                        child: const Text('好'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
