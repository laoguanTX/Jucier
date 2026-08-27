import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;
import 'package:pinyin/pinyin.dart';

import '../archive/archive_entry.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({
    required this.listing,
    required this.enabled,
    required this.onClose,
    required this.onExtract,
    required this.onTest,
    super.key,
  });

  final ArchiveListing listing;
  final bool enabled;
  final VoidCallback onClose;
  final VoidCallback onExtract;
  final VoidCallback onTest;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  String _directory = '';
  List<double> _columnFractions = const [5 / 12, 2 / 12, 2 / 12, 3 / 12];
  ArchiveSort? _sort;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final entries = visibleArchiveEntries(
      widget.listing.entries,
      _directory,
      sort: _sort,
    );

    return Column(
      children: [
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: widget.enabled ? widget.onClose : null,
                semanticsLabel: '关闭压缩包',
                child: const Icon(FLucideIcons.x, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.basename(widget.listing.archivePath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.typography.body.lg.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _ArchiveBreadcrumb(
                      directory: _directory,
                      onNavigate: (directory) {
                        if (directory == _directory) return;
                        setState(() => _directory = directory);
                      },
                    ),
                  ],
                ),
              ),
              FButton(
                size: FButtonSizeVariant.sm,
                variant: FButtonVariant.ghost,
                onPress: widget.enabled ? widget.onTest : null,
                prefix: const Icon(FLucideIcons.shieldCheck, size: 16),
                child: const Text('测试'),
              ),
              const SizedBox(width: 6),
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: widget.enabled ? widget.onExtract : null,
                prefix: const Icon(FLucideIcons.archiveRestore, size: 16),
                child: const Text('解压'),
              ),
            ],
          ),
        ),
        _TableHeader(
          colors: colors,
          columnFractions: _columnFractions,
          sort: _sort,
          onSort: _cycleSort,
          onResize: _resizeColumns,
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '此文件夹为空',
                    style: context.theme.typography.body.md.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  itemCount: entries.length + (_directory.isEmpty ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (_directory.isNotEmpty && index == 0) {
                      return _ArchiveRow(
                        name: '..',
                        isDirectory: true,
                        columnFractions: _columnFractions,
                        onOpen: _goUp,
                      );
                    }
                    final offset = _directory.isEmpty ? index : index - 1;
                    final entry = entries[offset];
                    return _ArchiveRow(
                      name: entry.name,
                      isDirectory: entry.isDirectory,
                      columnFractions: _columnFractions,
                      size: entry.size,
                      packedSize: entry.packedSize,
                      modified: entry.modified,
                      onOpen: entry.isDirectory
                          ? () => setState(() {
                              _directory = _directory.isEmpty
                                  ? entry.name
                                  : '$_directory/${entry.name}';
                            })
                          : null,
                    );
                  },
                ),
        ),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Text(
            '${widget.listing.entries.length} 个项目 · ${formatBytes(widget.listing.physicalSize)}',
            style: context.theme.typography.body.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }

  void _goUp() {
    setState(() {
      final slash = _directory.lastIndexOf('/');
      _directory = slash < 0 ? '' : _directory.substring(0, slash);
    });
  }

  void _resizeColumns(int index, double delta, double availableWidth) {
    if (availableWidth <= 0) return;

    const minimumFractions = [0.20, 0.10, 0.10, 0.16];
    final pairTotal = _columnFractions[index] + _columnFractions[index + 1];
    final nextLeft = (_columnFractions[index] + delta / availableWidth)
        .clamp(minimumFractions[index], pairTotal - minimumFractions[index + 1])
        .toDouble();
    if (nextLeft == _columnFractions[index]) return;

    setState(() {
      final next = List<double>.of(_columnFractions);
      next[index] = nextLeft;
      next[index + 1] = pairTotal - nextLeft;
      _columnFractions = next;
    });
  }

  void _cycleSort(ArchiveSortColumn column) {
    setState(() {
      if (_sort?.column != column) {
        _sort = ArchiveSort(
          column: column,
          direction: ArchiveSortDirection.ascending,
        );
      } else if (_sort!.direction == ArchiveSortDirection.ascending) {
        _sort = ArchiveSort(
          column: column,
          direction: ArchiveSortDirection.descending,
        );
      } else {
        _sort = null;
      }
    });
  }
}

class _ArchiveBreadcrumb extends StatelessWidget {
  const _ArchiveBreadcrumb({required this.directory, required this.onNavigate});

  final String directory;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final segments = directory.isEmpty
        ? const <String>[]
        : directory.split('/');
    final children = <Widget>[
      _BreadcrumbItem(
        key: const ValueKey('archive-breadcrumb-root'),
        semanticsLabel: '根目录',
        onTap: () => onNavigate(''),
        child: Icon(
          FLucideIcons.house,
          size: 13,
          color: directory.isEmpty ? colors.foreground : colors.mutedForeground,
        ),
      ),
    ];

    for (var index = 0; index < segments.length; index++) {
      final path = segments.take(index + 1).join('/');
      children
        ..add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '/',
              style: context.theme.typography.body.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ),
        )
        ..add(
          _BreadcrumbItem(
            key: ValueKey('archive-breadcrumb-$path'),
            semanticsLabel: '打开 $path',
            onTap: () => onNavigate(path),
            child: Text(
              segments[index],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.theme.typography.body.xs.copyWith(
                color: index == segments.length - 1
                    ? colors.foreground
                    : colors.mutedForeground,
              ),
            ),
          ),
        );
    }

    return SizedBox(
      height: 20,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      ),
    );
  }
}

class _BreadcrumbItem extends StatefulWidget {
  const _BreadcrumbItem({
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_BreadcrumbItem> createState() => _BreadcrumbItemState();
}

class _BreadcrumbItemState extends State<_BreadcrumbItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: _hovered ? colors.secondary : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.colors,
    required this.columnFractions,
    required this.sort,
    required this.onSort,
    required this.onResize,
  });

  final FColors colors;
  final List<double> columnFractions;
  final ArchiveSort? sort;
  final ValueChanged<ArchiveSortColumn> onSort;
  final void Function(int index, double delta, double availableWidth) onResize;

  @override
  Widget build(BuildContext context) {
    final labelStyle = context.theme.typography.body.xs.copyWith(
      color: colors.mutedForeground,
      fontWeight: FontWeight.w600,
    );
    final borderColor = colors.brightness == Brightness.dark
        ? colors.foreground.withValues(alpha: 0.28)
        : colors.border.withValues(alpha: 0.75);
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        child: DecoratedBox(
          key: const ValueKey('archive-table-header-surface'),
          decoration: BoxDecoration(
            color: colors.secondary.withValues(alpha: 0.55),
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const labels = ['名称', '大小', '压缩后', '修改时间'];
                const columns = ArchiveSortColumn.values;
                return Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: [
                        for (var index = 0; index < labels.length; index++)
                          Expanded(
                            flex: _columnFlex(columnFractions[index]),
                            child: Padding(
                              padding: _columnPadding[index],
                              child: _SortableHeaderLabel(
                                key: ValueKey(
                                  'archive-sort-header-${columns[index].name}',
                                ),
                                label: labels[index],
                                column: columns[index],
                                direction: sort?.column == columns[index]
                                    ? sort?.direction
                                    : null,
                                colors: colors,
                                labelStyle: labelStyle,
                                onSort: onSort,
                              ),
                            ),
                          ),
                      ],
                    ),
                    for (var index = 0; index < labels.length - 1; index++)
                      Positioned(
                        left:
                            constraints.maxWidth *
                                columnFractions
                                    .take(index + 1)
                                    .fold(0.0, (sum, value) => sum + value) -
                            6,
                        top: 0,
                        bottom: 0,
                        width: 12,
                        child: _ColumnResizeHandle(
                          key: ValueKey('archive-column-resizer-$index'),
                          colors: colors,
                          semanticsLabel: '调整${labels[index]}列宽',
                          onDrag: (delta) =>
                              onResize(index, delta, constraints.maxWidth),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SortableHeaderLabel extends StatelessWidget {
  const _SortableHeaderLabel({
    required this.label,
    required this.column,
    required this.direction,
    required this.colors,
    required this.labelStyle,
    required this.onSort,
    super.key,
  });

  final String label;
  final ArchiveSortColumn column;
  final ArchiveSortDirection? direction;
  final FColors colors;
  final TextStyle labelStyle;
  final ValueChanged<ArchiveSortColumn> onSort;

  @override
  Widget build(BuildContext context) {
    final nextAction = switch (direction) {
      null => '升序排序',
      ArchiveSortDirection.ascending => '降序排序',
      ArchiveSortDirection.descending => '恢复默认排序',
    };
    return Semantics(
      button: true,
      label: '$label，$nextAction',
      sortKey: OrdinalSortKey(column.index.toDouble()),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSort(column),
          child: Align(
            alignment: _columnAlignment[column.index],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                if (direction != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    direction == ArchiveSortDirection.ascending
                        ? FLucideIcons.chevronUp
                        : FLucideIcons.chevronDown,
                    key: ValueKey('archive-sort-indicator-${column.name}'),
                    size: 13,
                    color: colors.foreground,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.colors,
    required this.semanticsLabel,
    required this.onDrag,
    super.key,
  });

  final FColors colors;
  final String semanticsLabel;
  final ValueChanged<double> onDrag;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hovered || _dragging;
    return Semantics(
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: highlighted ? 2 : 1,
              height: highlighted ? 24 : 18,
              decoration: BoxDecoration(
                color: highlighted
                    ? widget.colors.primary
                    : widget.colors.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArchiveRow extends StatefulWidget {
  const _ArchiveRow({
    required this.name,
    required this.isDirectory,
    required this.columnFractions,
    this.size,
    this.packedSize,
    this.modified,
    this.onOpen,
  });

  final String name;
  final bool isDirectory;
  final List<double> columnFractions;
  final int? size;
  final int? packedSize;
  final DateTime? modified;
  final VoidCallback? onOpen;

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textStyle = context.theme.typography.body.sm;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onOpen,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? colors.secondary : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _columnFlex(widget.columnFractions[0]),
                child: Padding(
                  padding: _columnPadding[0],
                  child: Row(
                    children: [
                      Icon(
                        widget.isDirectory
                            ? FLucideIcons.folder
                            : iconForArchiveEntry(widget.name),
                        size: 17,
                        color: widget.isDirectory
                            ? colors.primary
                            : colors.mutedForeground,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.name,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: _columnFlex(widget.columnFractions[1]),
                child: Padding(
                  padding: _columnPadding[1],
                  child: Align(
                    alignment: _columnAlignment[1],
                    child: Text(
                      widget.isDirectory ? '—' : formatBytes(widget.size),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: _columnFlex(widget.columnFractions[2]),
                child: Padding(
                  padding: _columnPadding[2],
                  child: Align(
                    alignment: _columnAlignment[2],
                    child: Text(
                      widget.isDirectory ? '—' : formatBytes(widget.packedSize),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: _columnFlex(widget.columnFractions[3]),
                child: Padding(
                  padding: _columnPadding[3],
                  child: Align(
                    alignment: _columnAlignment[3],
                    child: Text(
                      formatDate(widget.modified),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _columnPadding = [
  EdgeInsets.only(right: 16),
  EdgeInsets.symmetric(horizontal: 16),
  EdgeInsets.symmetric(horizontal: 16),
  EdgeInsets.only(left: 16),
];

const _columnAlignment = [
  Alignment.centerLeft,
  Alignment.centerLeft,
  Alignment.centerLeft,
  Alignment.centerLeft,
];

int _columnFlex(double fraction) => (fraction * 10000).round();

enum ArchiveSortColumn { name, size, packedSize, modified }

enum ArchiveSortDirection { ascending, descending }

class ArchiveSort {
  const ArchiveSort({required this.column, required this.direction});

  final ArchiveSortColumn column;
  final ArchiveSortDirection direction;
}

List<ArchiveEntry> visibleArchiveEntries(
  List<ArchiveEntry> all,
  String directory, {
  ArchiveSort? sort,
}) {
  final prefix = directory.isEmpty ? '' : '$directory/';
  final visible = <String, ArchiveEntry>{};
  for (final entry in all) {
    final normalized = entry.path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (!normalized.startsWith(prefix)) continue;
    final relative = normalized.substring(prefix.length);
    if (relative.isEmpty) continue;
    final slash = relative.indexOf('/');
    if (slash >= 0) {
      final name = relative.substring(0, slash);
      visible.putIfAbsent(
        name,
        () => ArchiveEntry(path: '$prefix$name', isDirectory: true),
      );
    } else {
      visible[relative] = ArchiveEntry(
        path: relative,
        isDirectory: entry.isDirectory,
        size: entry.size,
        packedSize: entry.packedSize,
        modified: entry.modified,
        crc: entry.crc,
        method: entry.method,
        encrypted: entry.encrypted,
      );
    }
  }
  final nameKeys = <String, String>{};
  int compareNames(ArchiveEntry a, ArchiveEntry b) {
    final aKey = nameKeys.putIfAbsent(a.name, () => _pinyinSortKey(a.name));
    final bKey = nameKeys.putIfAbsent(b.name, () => _pinyinSortKey(b.name));
    final byPinyin = aKey.compareTo(bKey);
    if (byPinyin != 0) return byPinyin;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int compareDefault(ArchiveEntry a, ArchiveEntry b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return compareNames(a, b);
  }

  int compareSorted(ArchiveEntry a, ArchiveEntry b) {
    final primary = switch (sort!.column) {
      ArchiveSortColumn.name => compareNames(a, b),
      ArchiveSortColumn.size => _compareNullable(
        a.size,
        b.size,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.packedSize => _compareNullable(
        a.packedSize,
        b.packedSize,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.modified => _compareNullable(
        a.modified,
        b.modified,
        (left, right) => left.compareTo(right),
      ),
    };
    final result = primary == 0 ? compareNames(a, b) : primary;
    return sort.direction == ArchiveSortDirection.ascending ? result : -result;
  }

  return visible.values.toList()
    ..sort(sort == null ? compareDefault : compareSorted);
}

int _compareNullable<T>(
  T? left,
  T? right,
  int Function(T left, T right) compare,
) {
  if (left == null) return right == null ? 0 : -1;
  if (right == null) return 1;
  return compare(left, right);
}

String _pinyinSortKey(String value) {
  try {
    return PinyinHelper.getPinyin(value, separator: '').toLowerCase();
  } on PinyinException {
    return value.toLowerCase();
  }
}

IconData iconForArchiveEntry(String name) {
  final extension = p.extension(name).toLowerCase();
  if ({'.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'}.contains(extension)) {
    return FLucideIcons.image;
  }
  if ({'.mp3', '.m4a', '.wav', '.flac'}.contains(extension)) {
    return FLucideIcons.music;
  }
  if ({'.mp4', '.mov', '.mkv', '.avi'}.contains(extension)) {
    return FLucideIcons.video;
  }
  return FLucideIcons.file;
}

String formatBytes(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
}

String formatDate(DateTime? value) {
  if (value == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}
