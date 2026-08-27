import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:path/path.dart' as p;

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

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final entries = visibleArchiveEntries(widget.listing.entries, _directory);

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
        _TableHeader(colors: colors),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  itemCount: entries.length + (_directory.isEmpty ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (_directory.isNotEmpty && index == 0) {
                      return _ArchiveRow(
                        name: '..',
                        isDirectory: true,
                        onOpen: _goUp,
                      );
                    }
                    final offset = _directory.isEmpty ? index : index - 1;
                    final entry = entries[offset];
                    return _ArchiveRow(
                      name: entry.name,
                      isDirectory: entry.isDirectory,
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
  const _TableHeader({required this.colors});

  final FColors colors;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    padding: const EdgeInsets.symmetric(horizontal: 26),
    color: colors.secondary.withValues(alpha: 0.45),
    child: const Row(
      children: [
        Expanded(flex: 5, child: Text('名称')),
        Expanded(flex: 2, child: Text('大小')),
        Expanded(flex: 2, child: Text('压缩后')),
        Expanded(flex: 3, child: Text('修改时间')),
      ],
    ),
  );
}

class _ArchiveRow extends StatefulWidget {
  const _ArchiveRow({
    required this.name,
    required this.isDirectory,
    this.size,
    this.packedSize,
    this.modified,
    this.onOpen,
  });

  final String name;
  final bool isDirectory;
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
                flex: 5,
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
              Expanded(
                flex: 2,
                child: Text(
                  widget.isDirectory ? '—' : formatBytes(widget.size),
                  style: textStyle,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  widget.isDirectory ? '—' : formatBytes(widget.packedSize),
                  style: textStyle,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(formatDate(widget.modified), style: textStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<ArchiveEntry> visibleArchiveEntries(
  List<ArchiveEntry> all,
  String directory,
) {
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
  return visible.values.toList()..sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
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
