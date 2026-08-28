import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;
import 'package:pinyin/pinyin.dart';

import '../archive/archive_entry.dart';
import '../archive/archive_column.dart';

typedef ArchiveEntriesCallback = Future<bool> Function(
  List<ArchiveEntry> entries,
);
typedef ArchiveDropCallback = Future<void> Function(
  List<String> paths,
  String directory,
);
typedef ArchiveDragCallback = Future<void> Function(List<ArchiveEntry> entries);
typedef ArchiveImportCallback = Future<void> Function(String directory);

enum ArchiveScreenMode { browse, compose }

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({
    required this.listing,
    required this.enabled,
    required this.onClose,
    required this.onExtract,
    required this.onTest,
    required this.onPreviewEntry,
    required this.onExtractEntry,
    required this.onDeleteEntry,
    required this.onExtractEntries,
    required this.onDeleteEntries,
    required this.onDropped,
    required this.onDragEntries,
    this.mode = ArchiveScreenMode.browse,
    this.columns = defaultExtractionArchiveColumns,
    this.onImport,
    this.onCreate,
    super.key,
  });

  final ArchiveListing listing;
  final bool enabled;
  final VoidCallback onClose;
  final VoidCallback onExtract;
  final VoidCallback onTest;
  final ValueChanged<ArchiveEntry> onPreviewEntry;
  final ValueChanged<ArchiveEntry> onExtractEntry;
  final ValueChanged<ArchiveEntry> onDeleteEntry;
  final ArchiveEntriesCallback onExtractEntries;
  final ArchiveEntriesCallback onDeleteEntries;
  final ArchiveDropCallback onDropped;
  final ArchiveDragCallback onDragEntries;
  final ArchiveScreenMode mode;
  final List<ArchiveColumn> columns;
  final ArchiveImportCallback? onImport;
  final VoidCallback? onCreate;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  String _directory = '';
  late List<double> _columnFractions;
  ArchiveSort? _sort;
  bool _selectionMode = false;
  bool _draggingIntoArchive = false;
  bool _draggingEntriesOut = false;
  final Map<String, ArchiveEntry> _selectedEntries = {};

  List<ArchiveColumn> get _columns =>
      ArchiveColumnPreferences.normalize(widget.columns);

  @override
  void initState() {
    super.initState();
    _columnFractions = _initialColumnFractions(_columns);
  }

  @override
  void didUpdateWidget(covariant ArchiveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.columns, oldWidget.columns)) {
      _columnFractions = _initialColumnFractions(_columns);
      if (_sort != null && !_columns.contains(_sort!.column)) _sort = null;
    }
    if (widget.listing.archivePath != oldWidget.listing.archivePath) {
      _selectionMode = false;
      _selectedEntries.clear();
    } else {
      final available = widget.listing.entries
          .map((entry) => entry.path.replaceAll('\\', '/'))
          .toSet();
      _selectedEntries.removeWhere(
        (path, entry) =>
            !entry.isDirectory &&
            !available.contains(path.replaceAll('\\', '/')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final composing = widget.mode == ArchiveScreenMode.compose;
    final colors = context.theme.colors;
    final entries = visibleArchiveEntries(
      widget.listing.entries,
      _directory,
      sort: _sort,
    );

    final content = Column(
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
                key: const ValueKey('archive-close'),
                variant: FButtonVariant.ghost,
                onPress: widget.enabled ? widget.onClose : null,
                semanticsLabel: composing ? '取消创建压缩包' : '关闭压缩包',
                child: const Icon(FLucideIcons.x, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      composing
                          ? '新建压缩包'
                          : p.basename(widget.listing.archivePath),
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
              if (composing) ...[
                FButton(
                  key: const ValueKey('archive-import'),
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: widget.enabled && widget.onImport != null
                      ? () => widget.onImport!(_directory)
                      : null,
                  prefix: const Icon(FLucideIcons.plus, size: 16),
                  child: const Text('导入'),
                ),
                const SizedBox(width: 6),
                FButton(
                  key: const ValueKey('archive-create'),
                  size: FButtonSizeVariant.sm,
                  onPress:
                      widget.enabled &&
                          widget.listing.entries.isNotEmpty &&
                          widget.onCreate != null
                      ? widget.onCreate
                      : null,
                  prefix: const Icon(FLucideIcons.archive, size: 16),
                  child: const Text('创建压缩包'),
                ),
              ] else if (_selectionMode) ...[
                Text(
                  '已选择 ${_selectedEntries.length} 项',
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(width: 8),
                FButton(
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: widget.enabled
                      ? () => _toggleAllVisible(entries)
                      : null,
                  child: Text(_allVisibleSelected(entries) ? '取消全选' : '全选'),
                ),
                const SizedBox(width: 6),
                FButton(
                  key: const ValueKey('archive-batch-extract'),
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.outline,
                  onPress: widget.enabled && _selectedEntries.isNotEmpty
                      ? () => _runBatch(widget.onExtractEntries)
                      : null,
                  prefix: const Icon(FLucideIcons.archiveRestore, size: 15),
                  child: const Text('解压所选'),
                ),
                const SizedBox(width: 6),
                FButton(
                  key: const ValueKey('archive-batch-delete'),
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.destructive,
                  onPress: widget.enabled && _selectedEntries.isNotEmpty
                      ? () => _runBatch(widget.onDeleteEntries)
                      : null,
                  prefix: const Icon(FLucideIcons.trash2, size: 15),
                  child: const Text('删除所选'),
                ),
                const SizedBox(width: 6),
                FButton(
                  key: const ValueKey('archive-selection-done'),
                  size: FButtonSizeVariant.sm,
                  onPress: widget.enabled ? _leaveSelectionMode : null,
                  child: const Text('完成'),
                ),
              ] else ...[
                if (widget.onImport != null) ...[
                  FButton(
                    key: const ValueKey('archive-import'),
                    size: FButtonSizeVariant.sm,
                    variant: FButtonVariant.ghost,
                    onPress: widget.enabled
                        ? () => widget.onImport!(_directory)
                        : null,
                    prefix: const Icon(FLucideIcons.plus, size: 16),
                    child: const Text('导入'),
                  ),
                  const SizedBox(width: 6),
                ],
                FButton(
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: widget.enabled ? widget.onTest : null,
                  prefix: const Icon(FLucideIcons.shieldCheck, size: 16),
                  child: const Text('测试'),
                ),
                const SizedBox(width: 6),
                FButton(
                  key: const ValueKey('archive-selection-toggle'),
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: widget.enabled
                      ? () => setState(() => _selectionMode = true)
                      : null,
                  prefix: const Icon(FLucideIcons.listChecks, size: 16),
                  child: const Text('多选'),
                ),
                const SizedBox(width: 6),
                FButton(
                  size: FButtonSizeVariant.sm,
                  onPress: widget.enabled ? widget.onExtract : null,
                  prefix: const Icon(FLucideIcons.archiveRestore, size: 16),
                  child: const Text('解压'),
                ),
              ],
            ],
          ),
        ),
        _TableHeader(
          colors: colors,
          columns: _columns,
          columnFractions: _columnFractions,
          sort: _sort,
          onSort: _cycleSort,
          onResize: _resizeColumns,
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    composing ? '尚未导入文件' : '此文件夹为空',
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
                        columns: _columns,
                        columnFractions: _columnFractions,
                        onOpen: _goUp,
                      );
                    }
                    final offset = _directory.isEmpty ? index : index - 1;
                    final entry = entries[offset];
                    final directoryStats = entry.isDirectory
                        ? archiveDirectoryStats(
                            widget.listing.entries,
                            entry.path,
                          )
                        : null;
                    return _ArchiveRow(
                      name: entry.name,
                      isDirectory: entry.isDirectory,
                      columns: _columns,
                      columnFractions: _columnFractions,
                      size: entry.size,
                      packedSize: entry.packedSize,
                      modified: entry.modified,
                      path: entry.path,
                      totalSize: directoryStats?.totalSize,
                      itemCount: directoryStats?.itemCount,
                      method: entry.method,
                      encrypted: entry.encrypted,
                      crc: entry.crc,
                      sourcePath: entry.sourcePath,
                      attributes: entry.attributes,
                      selectionMode: !composing && _selectionMode,
                      selected: _selectedEntries.containsKey(entry.path),
                      onSelectionChanged: widget.enabled && !composing
                          ? (selected) => _setEntrySelected(entry, selected)
                          : null,
                      onOpen: entry.isDirectory
                          ? () => setState(() {
                              _directory = _directory.isEmpty
                                  ? entry.name
                                  : '$_directory/${entry.name}';
                            })
                          : composing
                          ? null
                          : () => widget.onPreviewEntry(entry),
                      onExtract: composing
                          ? null
                          : () => widget.onExtractEntry(entry),
                      onDelete: composing
                          ? null
                          : () => widget.onDeleteEntry(entry),
                      onDragStarted: widget.enabled && !composing
                          ? () => _startDraggingEntry(entry)
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
    return DropTarget(
      enable: widget.enabled && !_draggingEntriesOut,
      onDragEntered: (_) {
        if (_draggingEntriesOut) return;
        setState(() => _draggingIntoArchive = true);
      },
      onDragExited: (_) => setState(() => _draggingIntoArchive = false),
      onDragDone: (details) {
        setState(() => _draggingIntoArchive = false);
        if (_draggingEntriesOut) return;
        unawaited(
          widget.onDropped(
            details.files.map((file) => file.path).toList(),
            _directory,
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (_draggingIntoArchive)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('archive-drop-overlay'),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.08),
                    border: Border.all(color: colors.primary, width: 2),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: colors.background,
                      border: Border.all(color: colors.primary),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      composing
                          ? '导入到待压缩列表'
                          : _directory.isEmpty
                          ? '添加到压缩包根目录'
                          : '添加到 /$_directory',
                      style: context.theme.typography.body.md.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _goUp() {
    setState(() {
      final slash = _directory.lastIndexOf('/');
      _directory = slash < 0 ? '' : _directory.substring(0, slash);
    });
  }

  void _setEntrySelected(ArchiveEntry entry, bool selected) {
    setState(() {
      if (selected) {
        _selectedEntries[entry.path] = entry;
      } else {
        _selectedEntries.remove(entry.path);
      }
    });
  }

  bool _allVisibleSelected(List<ArchiveEntry> entries) =>
      entries.isNotEmpty &&
      entries.every((entry) => _selectedEntries.containsKey(entry.path));

  void _toggleAllVisible(List<ArchiveEntry> entries) {
    final deselect = _allVisibleSelected(entries);
    setState(() {
      for (final entry in entries) {
        if (deselect) {
          _selectedEntries.remove(entry.path);
        } else {
          _selectedEntries[entry.path] = entry;
        }
      }
    });
  }

  Future<void> _runBatch(ArchiveEntriesCallback callback) async {
    final entries = List<ArchiveEntry>.of(_selectedEntries.values);
    if (entries.isEmpty) return;
    final processed = await callback(entries);
    if (processed && mounted) {
      setState(() => _selectedEntries.clear());
    }
  }

  void _leaveSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedEntries.clear();
    });
  }

  Future<void> _startDraggingEntry(ArchiveEntry entry) async {
    if (_draggingEntriesOut) return;
    final entries = _selectionMode && _selectedEntries.containsKey(entry.path)
        ? List<ArchiveEntry>.of(_selectedEntries.values)
        : [entry];
    setState(() {
      _draggingEntriesOut = true;
      _draggingIntoArchive = false;
    });
    try {
      await widget.onDragEntries(entries);
    } finally {
      if (mounted) setState(() => _draggingEntriesOut = false);
    }
  }

  void _resizeColumns(int index, double delta, double availableWidth) {
    if (availableWidth <= 0) return;

    final pairTotal = _columnFractions[index] + _columnFractions[index + 1];
    final leftPreferred = _columns[index] == ArchiveColumn.name ? 0.20 : 0.08;
    final rightPreferred = _columns[index + 1] == ArchiveColumn.name
        ? 0.20
        : 0.08;
    final leftMinimum = math.min(leftPreferred, pairTotal * 0.45);
    final rightMinimum = math.min(rightPreferred, pairTotal * 0.45);
    final nextLeft = (_columnFractions[index] + delta / availableWidth)
        .clamp(leftMinimum, pairTotal - rightMinimum)
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
    required this.columns,
    required this.columnFractions,
    required this.sort,
    required this.onSort,
    required this.onResize,
  });

  final FColors colors;
  final List<ArchiveColumn> columns;
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
                return Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: [
                        for (var index = 0; index < columns.length; index++)
                          Expanded(
                            flex: _columnFlex(columnFractions[index]),
                            child: Padding(
                              padding: _columnPaddingFor(index, columns.length),
                              child: _SortableHeaderLabel(
                                key: ValueKey(
                                  'archive-sort-header-${columns[index].name}',
                                ),
                                label: columns[index].label,
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
                    for (var index = 0; index < columns.length - 1; index++)
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
                          semanticsLabel: '调整${columns[index].label}列宽',
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
            alignment: Alignment.centerLeft,
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
    required this.columns,
    required this.columnFractions,
    this.size,
    this.packedSize,
    this.modified,
    this.path,
    this.totalSize,
    this.itemCount,
    this.method,
    this.encrypted,
    this.crc,
    this.sourcePath,
    this.attributes,
    this.onOpen,
    this.onExtract,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
    this.onDragStarted,
  });

  final String name;
  final bool isDirectory;
  final List<ArchiveColumn> columns;
  final List<double> columnFractions;
  final int? size;
  final int? packedSize;
  final DateTime? modified;
  final String? path;
  final int? totalSize;
  final int? itemCount;
  final String? method;
  final bool? encrypted;
  final String? crc;
  final String? sourcePath;
  final String? attributes;
  final VoidCallback? onOpen;
  final VoidCallback? onExtract;
  final VoidCallback? onDelete;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final Future<void> Function()? onDragStarted;

  @override
  State<_ArchiveRow> createState() => _ArchiveRowState();
}

class _ArchiveRowState extends State<_ArchiveRow> {
  bool _hovered = false;
  Offset? _dragOrigin;
  bool _dragStarted = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final textStyle = context.theme.typography.body.sm;
    final row = Listener(
      onPointerDown: (event) {
        if (event.buttons & 1 != 0 && widget.onDragStarted != null) {
          _dragOrigin = event.position;
          _dragStarted = false;
        }
      },
      onPointerMove: (event) {
        final origin = _dragOrigin;
        if (origin != null &&
            !_dragStarted &&
            event.buttons & 1 != 0 &&
            (event.position - origin).distance >= 5) {
          setState(() => _dragStarted = true);
          unawaited(_beginDrag());
        }
      },
      onPointerUp: (_) => _resetDrag(),
      onPointerCancel: (_) => _resetDrag(),
      child: MouseRegion(
        key: ValueKey('archive-row-mouse-${widget.name}'),
        cursor: _dragStarted
            ? SystemMouseCursors.grab
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.selectionMode
              ? () => widget.onSelectionChanged?.call(!widget.selected)
              : null,
          onDoubleTap: widget.selectionMode ? null : widget.onOpen,
          child: Container(
            key: ValueKey('archive-row-${widget.name}'),
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hovered ? colors.secondary : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                for (var index = 0; index < widget.columns.length; index++)
                  Expanded(
                    flex: _columnFlex(widget.columnFractions[index]),
                    child: Padding(
                      padding: _columnPaddingFor(index, widget.columns.length),
                      child: _buildColumn(
                        widget.columns[index],
                        colors,
                        textStyle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.onExtract == null && widget.onDelete == null) return row;

    return FContextMenu(
      semanticsLabel: '${widget.name} 操作菜单',
      secondaryPress: true,
      longPress: false,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          divider: FItemDivider.full,
          children: [
            FItem(
              key: ValueKey('archive-context-extract-${widget.name}'),
              prefix: const Icon(FLucideIcons.archiveRestore, size: 16),
              title: Text(widget.isDirectory ? '解压该文件夹' : '解压该文件'),
              onPress: () {
                controller.hide();
                widget.onExtract?.call();
              },
            ),
            FItem(
              key: ValueKey('archive-context-delete-${widget.name}'),
              variant: FItemVariant.destructive,
              prefix: const Icon(FLucideIcons.trash2, size: 16),
              title: Text(widget.isDirectory ? '删除压缩包内文件夹' : '删除压缩包内文件'),
              onPress: () {
                controller.hide();
                widget.onDelete?.call();
              },
            ),
          ],
        ),
      ],
      child: row,
    );
  }

  Widget _buildColumn(
    ArchiveColumn column,
    FColors colors,
    TextStyle textStyle,
  ) => switch (column) {
    ArchiveColumn.name => Row(
      children: [
        if (widget.selectionMode) ...[
          FCheckbox(
            key: ValueKey('archive-select-${widget.name}'),
            semanticsLabel: '选择 ${widget.name}',
            value: widget.selected,
            onChange: widget.onSelectionChanged,
            enabled: widget.onSelectionChanged != null,
          ),
          const SizedBox(width: 10),
        ],
        Icon(
          widget.isDirectory
              ? FLucideIcons.folder
              : iconForArchiveEntry(widget.name),
          size: 17,
          color: widget.isDirectory ? colors.primary : colors.mutedForeground,
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
    ArchiveColumn.type => _ArchiveCellText(
      archiveEntryType(widget.name, widget.isDirectory),
      style: textStyle,
    ),
    ArchiveColumn.path => _ArchiveCellText(
      widget.path ?? '—',
      style: textStyle,
    ),
    ArchiveColumn.size => _ArchiveCellText(
      widget.isDirectory ? '—' : formatBytes(widget.size),
      style: textStyle,
    ),
    ArchiveColumn.totalSize => _ArchiveCellText(
      widget.isDirectory ? formatBytes(widget.totalSize) : '—',
      style: textStyle,
    ),
    ArchiveColumn.itemCount => _ArchiveCellText(
      widget.isDirectory && widget.itemCount != null
          ? '${widget.itemCount}'
          : '—',
      style: textStyle,
    ),
    ArchiveColumn.packedSize => _ArchiveCellText(
      widget.isDirectory ? '—' : formatBytes(widget.packedSize),
      style: textStyle,
    ),
    ArchiveColumn.compressionRatio => _ArchiveCellText(
      formatCompressionRatio(widget.size, widget.packedSize),
      style: textStyle,
    ),
    ArchiveColumn.modified => _ArchiveCellText(
      formatDate(widget.modified),
      style: textStyle,
    ),
    ArchiveColumn.method => _ArchiveCellText(
      widget.method ?? '—',
      style: textStyle,
    ),
    ArchiveColumn.encrypted => _ArchiveCellText(switch (widget.encrypted) {
      true => '已加密',
      false => '未加密',
      null => '—',
    }, style: textStyle),
    ArchiveColumn.crc => _ArchiveCellText(widget.crc ?? '—', style: textStyle),
    ArchiveColumn.sourcePath => _ArchiveCellText(
      widget.sourcePath ?? '—',
      style: textStyle,
    ),
    ArchiveColumn.attributes => _ArchiveCellText(
      widget.attributes ?? '—',
      style: textStyle,
    ),
  };

  void _resetDrag() {
    _dragOrigin = null;
    if (_dragStarted && mounted) {
      setState(() => _dragStarted = false);
    } else {
      _dragStarted = false;
    }
  }

  Future<void> _beginDrag() async {
    try {
      await widget.onDragStarted?.call();
    } finally {
      _dragOrigin = null;
      if (_dragStarted && mounted) setState(() => _dragStarted = false);
    }
  }
}

class _ArchiveCellText extends StatelessWidget {
  const _ArchiveCellText(this.value, {required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

EdgeInsets _columnPaddingFor(int index, int count) {
  if (count <= 1) return EdgeInsets.zero;
  if (index == 0) return const EdgeInsets.only(right: 16);
  if (index == count - 1) return const EdgeInsets.only(left: 16);
  return const EdgeInsets.symmetric(horizontal: 16);
}

List<double> _initialColumnFractions(List<ArchiveColumn> columns) {
  final weights = columns
      .map(
        (column) => switch (column) {
          ArchiveColumn.name => 5.0,
          ArchiveColumn.type => 2.0,
          ArchiveColumn.path => 4.0,
          ArchiveColumn.size => 2.0,
          ArchiveColumn.totalSize => 2.0,
          ArchiveColumn.itemCount => 2.0,
          ArchiveColumn.packedSize => 2.0,
          ArchiveColumn.compressionRatio => 2.0,
          ArchiveColumn.modified => 3.0,
          ArchiveColumn.method => 3.0,
          ArchiveColumn.encrypted => 2.0,
          ArchiveColumn.crc => 3.0,
          ArchiveColumn.sourcePath => 4.0,
          ArchiveColumn.attributes => 3.0,
        },
      )
      .toList();
  final total = weights.fold(0.0, (sum, weight) => sum + weight);
  return weights.map((weight) => weight / total).toList();
}

int _columnFlex(double fraction) => (fraction * 10000).round();

typedef ArchiveSortColumn = ArchiveColumn;

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
        path: normalized,
        isDirectory: entry.isDirectory,
        size: entry.size,
        packedSize: entry.packedSize,
        modified: entry.modified,
        crc: entry.crc,
        method: entry.method,
        encrypted: entry.encrypted,
        sourcePath: entry.sourcePath,
        attributes: entry.attributes,
      );
    }
  }
  final nameKeys = <String, String>{};
  final directoryStats = <String, ArchiveDirectoryStats>{};
  ArchiveDirectoryStats? statsFor(ArchiveEntry entry) => entry.isDirectory
      ? directoryStats.putIfAbsent(
          entry.path,
          () => archiveDirectoryStats(all, entry.path),
        )
      : null;
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
      ArchiveSortColumn.type => archiveEntryType(
        a.name,
        a.isDirectory,
      ).compareTo(archiveEntryType(b.name, b.isDirectory)),
      ArchiveSortColumn.path => a.path.compareTo(b.path),
      ArchiveSortColumn.size => _compareNullable(
        a.size,
        b.size,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.totalSize => _compareNullable(
        statsFor(a)?.totalSize,
        statsFor(b)?.totalSize,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.itemCount => _compareNullable(
        statsFor(a)?.itemCount,
        statsFor(b)?.itemCount,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.packedSize => _compareNullable(
        a.packedSize,
        b.packedSize,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.compressionRatio => _compareNullable(
        compressionRatio(a.size, a.packedSize),
        compressionRatio(b.size, b.packedSize),
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.modified => _compareNullable(
        a.modified,
        b.modified,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.method => _compareNullable(
        a.method,
        b.method,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.encrypted => _compareNullable(
        a.encrypted,
        b.encrypted,
        (left, right) => (left ? 1 : 0).compareTo(right ? 1 : 0),
      ),
      ArchiveSortColumn.crc => _compareNullable(
        a.crc,
        b.crc,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.sourcePath => _compareNullable(
        a.sourcePath,
        b.sourcePath,
        (left, right) => left.compareTo(right),
      ),
      ArchiveSortColumn.attributes => _compareNullable(
        a.attributes,
        b.attributes,
        (left, right) => left.compareTo(right),
      ),
    };
    final result = primary == 0 ? compareNames(a, b) : primary;
    return sort.direction == ArchiveSortDirection.ascending ? result : -result;
  }

  return visible.values.toList()
    ..sort(sort == null ? compareDefault : compareSorted);
}

class ArchiveDirectoryStats {
  const ArchiveDirectoryStats({
    required this.totalSize,
    required this.itemCount,
  });

  final int totalSize;
  final int itemCount;
}

ArchiveDirectoryStats archiveDirectoryStats(
  List<ArchiveEntry> entries,
  String directoryPath,
) {
  final normalizedDirectory = directoryPath
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/+'), '')
      .replaceFirst(RegExp(r'/+$'), '');
  final prefix = '$normalizedDirectory/';
  var totalSize = 0;
  var itemCount = 0;
  for (final entry in entries) {
    final path = entry.path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (entry.isDirectory || !path.startsWith(prefix)) continue;
    itemCount++;
    totalSize += entry.size ?? 0;
  }
  return ArchiveDirectoryStats(totalSize: totalSize, itemCount: itemCount);
}

String archiveEntryType(String name, bool isDirectory) {
  if (isDirectory) return '文件夹';
  final extension = p.extension(name).replaceFirst('.', '').toUpperCase();
  return extension.isEmpty ? '文件' : '$extension 文件';
}

double? compressionRatio(int? size, int? packedSize) {
  if (size == null || size <= 0 || packedSize == null) return null;
  return 1 - packedSize / size;
}

String formatCompressionRatio(int? size, int? packedSize) {
  final ratio = compressionRatio(size, packedSize);
  return ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(1)}%';
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
