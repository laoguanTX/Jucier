import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class OperationProgress extends StatelessWidget {
  const OperationProgress({
    required this.label,
    required this.progress,
    required this.onCancel,
    super.key,
  });

  final String label;
  final double? progress;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (progress != null)
                        Text(
                          '${(progress! * 100).round()}%',
                          style: context.theme.typography.body.xs.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (progress == null)
                    const FProgress()
                  else
                    FDeterminateProgress(value: progress!),
                ],
              ),
            ),
            const SizedBox(width: 14),
            FButton(
              size: FButtonSizeVariant.sm,
              variant: FButtonVariant.ghost,
              onPress: onCancel,
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
