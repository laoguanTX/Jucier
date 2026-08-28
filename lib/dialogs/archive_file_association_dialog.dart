import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../archive/archive_formats.dart';

Future<List<String>?> showArchiveFileAssociationDialog(
  BuildContext context, {
  required Set<String> defaultExtensions,
}) => showFDialog<List<String>>(
  context: context,
  barrierDismissible: false,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 460, maxWidth: 520),
    builder: (context, style) => _ArchiveFileAssociationForm(
      defaultExtensions: defaultExtensions,
      style: style,
    ),
  ),
);

class _ArchiveFileAssociationForm extends StatefulWidget {
  const _ArchiveFileAssociationForm({
    required this.defaultExtensions,
    required this.style,
  });

  final Set<String> defaultExtensions;
  final FDialogStyle style;

  @override
  State<_ArchiveFileAssociationForm> createState() =>
      _ArchiveFileAssociationFormState();
}

class _ArchiveFileAssociationFormState
    extends State<_ArchiveFileAssociationForm> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('默认打开方式', style: widget.style.titleTextStyle),
          const SizedBox(height: 6),
          Text(
            '勾选本次要绑定的格式。未勾选格式的现有默认应用不会更改；macOS 可能要求确认。',
            style: widget.style.bodyTextStyle,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: Row(
              children: [
                FCheckbox(
                  key: const ValueKey('associate-select-all'),
                  value: _selected.length == supportedArchiveExtensions.length,
                  onChange: (selected) => setState(() {
                    _selected
                      ..clear()
                      ..addAll(
                        selected
                            ? supportedArchiveExtensions
                            : const <String>[],
                      );
                  }),
                  semanticsLabel: '全选压缩包格式',
                ),
                const SizedBox(width: 10),
                const Text('全选'),
                const Spacer(),
                Text(
                  '已选择 ${_selected.length} 项',
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 300,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                itemCount: supportedArchiveExtensions.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemBuilder: (context, index) {
                  final extension = supportedArchiveExtensions[index];
                  final isDefault = widget.defaultExtensions.contains(
                    extension,
                  );
                  return SizedBox(
                    height: 46,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          FCheckbox(
                            key: ValueKey('associate-format-$extension'),
                            value: _selected.contains(extension),
                            onChange: (selected) => setState(() {
                              if (selected) {
                                _selected.add(extension);
                              } else {
                                _selected.remove(extension);
                              }
                            }),
                            semanticsLabel: '绑定 $extension 格式',
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(archiveExtensionLabel(extension)),
                          ),
                          if (isDefault)
                            Text(
                              '当前默认',
                              style: context.theme.typography.body.sm.copyWith(
                                color: colors.mutedForeground,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
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
                key: const ValueKey('apply-archive-associations'),
                size: FButtonSizeVariant.sm,
                onPress: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                        supportedArchiveExtensions
                            .where(_selected.contains)
                            .toList(),
                      ),
                child: const Text('设为默认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
