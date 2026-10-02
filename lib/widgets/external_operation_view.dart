import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show SelectableText;

import 'operation_progress.dart';

/// The entire content of the small window used by desktop quick actions.
class ExternalOperationView extends StatelessWidget {
  const ExternalOperationView({
    super.key,
    required this.title,
    required this.label,
    required this.progress,
    required this.onCancel,
    required this.onClose,
    this.message,
    this.failed = false,
  });

  final String title;
  final String label;
  final double? progress;
  final Future<void> Function() onCancel;
  final VoidCallback onClose;
  final String? message;
  final bool failed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
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
          const Spacer(),
          OperationProgress(
            label: label,
            progress: progress,
            onCancel: onCancel,
          ),
        ] else ...[
          Expanded(
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
          Align(
            alignment: Alignment.centerRight,
            child: FButton(
              size: FButtonSizeVariant.sm,
              onPress: onClose,
              child: const Text('好'),
            ),
          ),
        ],
      ],
    ),
  );
}
