import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../archive/archive_column.dart';

Future<List<ArchiveColumn>?> showArchiveColumnsDialog(
  BuildContext context, {
  required String title,
  required List<ArchiveColumn> columns,
  required List<ArchiveColumn> availableColumns,
}) => showFDialog<List<ArchiveColumn>>(
  context: context,
  barrierDismissible: false,
  builder: (context, _, animation) => FDialog(
    animation: animation,
    constraints: const BoxConstraints(minWidth: 440, maxWidth: 500),
    builder: (context, style) => _ArchiveColumnsForm(
      title: title,
      columns: columns,
      availableColumns: availableColumns,
      style: style,
    ),
  ),
);

class _ArchiveColumnsForm extends StatefulWidget {
  const _ArchiveColumnsForm({
    required this.title,
    required this.columns,
    required this.availableColumns,
    required this.style,
  });

  final String title;
  final List<ArchiveColumn> columns;
  final List<ArchiveColumn> availableColumns;
  final FDialogStyle style;

  @override
  State<_ArchiveColumnsForm> createState() => _ArchiveColumnsFormState();
}

class _ArchiveColumnsFormState extends State<_ArchiveColumnsForm> {
  late final List<ArchiveColumn> _order;
  late final Set<ArchiveColumn> _visible;

  @override
  void initState() {
    super.initState();
    final normalized = ArchiveColumnPreferences.normalize(
      widget.columns.where(widget.availableColumns.contains),
    );
    _order = [
      ...normalized,
      ...widget.availableColumns.where(
        (column) => !normalized.contains(column),
      ),
    ];
    _visible = normalized.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.title}菜单栏', style: widget.style.titleTextStyle),
          const SizedBox(height: 6),
          Text(
            '选择显示的信息，并调整从左到右的排列顺序。名称用于识别和操作文件，始终显示。',
            style: widget.style.bodyTextStyle,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < _order.length; index++) ...[
                      _ColumnOptionRow(
                        column: _order[index],
                        visible: _visible.contains(_order[index]),
                        canHide: _order[index] != ArchiveColumn.name,
                        canMoveUp: index > 0,
                        canMoveDown: index < _order.length - 1,
                        onVisibilityChanged: (visible) => setState(() {
                          if (visible) {
                            _visible.add(_order[index]);
                          } else {
                            _visible.remove(_order[index]);
                          }
                        }),
                        onMoveUp: () => _move(index, index - 1),
                        onMoveDown: () => _move(index, index + 1),
                      ),
                      if (index < _order.length - 1)
                        Divider(height: 1, color: colors.border),
                    ],
                  ],
                ),
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
                key: ValueKey('save-${widget.title}-columns'),
                size: FButtonSizeVariant.sm,
                onPress: () =>
                    Navigator.of(context)
                        .pop(_order.where(_visible.contains).toList()),
                child: const Text('完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _order.length) return;
    setState(() {
      final column = _order.removeAt(from);
      _order.insert(to, column);
    });
  }
}

class _ColumnOptionRow extends StatelessWidget {
  const _ColumnOptionRow({
    required this.column,
    required this.visible,
    required this.canHide,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onVisibilityChanged,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ArchiveColumn column;
  final bool visible;
  final bool canHide;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          FCheckbox(
            key: ValueKey('archive-column-visible-${column.name}'),
            value: visible,
            enabled: canHide,
            onChange: canHide ? onVisibilityChanged : null,
            semanticsLabel: '显示${column.label}',
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(column.label)),
          FButton(
            key: ValueKey('archive-column-up-${column.name}'),
            size: FButtonSizeVariant.sm,
            variant: FButtonVariant.ghost,
            onPress: canMoveUp ? onMoveUp : null,
            child: const Text('上移'),
          ),
          const SizedBox(width: 4),
          FButton(
            key: ValueKey('archive-column-down-${column.name}'),
            size: FButtonSizeVariant.sm,
            variant: FButtonVariant.ghost,
            onPress: canMoveDown ? onMoveDown : null,
            child: const Text('下移'),
          ),
        ],
      ),
    ),
  );
}
