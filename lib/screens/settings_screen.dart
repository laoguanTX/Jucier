import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../archive/archive_column.dart';
import '../archive/archive_formats.dart';
import '../dialogs/archive_columns_dialog.dart';
import '../dialogs/archive_file_association_dialog.dart';
import '../dialogs/message_dialog.dart';
import '../platform/archive_file_association_service.dart';
import '../platform/file_access_service.dart';
import '../platform/finder_action_service.dart';
import '../platform/single_entry_extraction_preference_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.fileAccessService,
    required this.archiveFileAssociationService,
    required this.finderActionService,
    required this.themeMode,
    required this.onBack,
    this.onThemeModeChanged,
    this.singleEntryExtractionMode =
        SingleEntryExtractionMode.preserveArchiveStructure,
    this.onSingleEntryExtractionModeChanged,
    this.archiveColumnPreferences = const ArchiveColumnPreferences(),
    this.onArchiveColumnPreferencesChanged,
    super.key,
  });

  final FileAccessService fileAccessService;
  final ArchiveFileAssociationService archiveFileAssociationService;
  final FinderActionService finderActionService;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final SingleEntryExtractionMode singleEntryExtractionMode;
  final ValueChanged<SingleEntryExtractionMode>?
  onSingleEntryExtractionModeChanged;
  final ArchiveColumnPreferences archiveColumnPreferences;
  final ValueChanged<ArchiveColumnPreferences>?
  onArchiveColumnPreferencesChanged;
  final VoidCallback onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  FileAccessStatus? _status;
  ArchiveFileAssociationStatus? _associationStatus;
  bool _requesting = false;
  bool _bindingFormats = false;
  bool? _finderContextMenuAvailable;
  bool _repairingFinderContextMenu = false;
  bool _uninstallingFinderContextMenu = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadAssociationStatus();
    _loadFinderContextMenuStatus();
  }

  Future<void> _loadStatus() async {
    final status = await widget.fileAccessService.status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _requestAccess() async {
    setState(() => _requesting = true);
    final status = await widget.fileAccessService.requestAccess();
    if (mounted) {
      setState(() {
        _status = status;
        _requesting = false;
      });
    }
  }

  Future<void> _loadAssociationStatus() async {
    final status = await widget.archiveFileAssociationService.status(
      supportedArchiveExtensions,
    );
    if (mounted) setState(() => _associationStatus = status);
  }

  Future<void> _loadFinderContextMenuStatus() async {
    final available = await widget.finderActionService.contextMenuAvailable();
    if (mounted) setState(() => _finderContextMenuAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final granted = status?.granted ?? false;
    final colors = context.theme.colors;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          SingleChildScrollView(
            key: const ValueKey('settings-scroll-view'),
            padding: const EdgeInsets.only(top: 68, bottom: 8),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SettingsCard(
                      key: const ValueKey('settings-appearance-card'),
                      icon: FLucideIcons.sun,
                      title: '外观',
                      description: '选择跟随系统、浅色或深色外观。',
                      trailing: SizedBox(
                        width: 294,
                        child: Row(
                          children: [
                            _ThemeModeButton(
                              mode: ThemeMode.system,
                              label: '系统',
                              icon: FLucideIcons.monitor,
                              selectedMode: widget.themeMode,
                              onChanged: widget.onThemeModeChanged,
                            ),
                            const SizedBox(width: 6),
                            _ThemeModeButton(
                              mode: ThemeMode.light,
                              label: '浅色',
                              icon: FLucideIcons.sun,
                              selectedMode: widget.themeMode,
                              onChanged: widget.onThemeModeChanged,
                            ),
                            const SizedBox(width: 6),
                            _ThemeModeButton(
                              mode: ThemeMode.dark,
                              label: '深色',
                              icon: FLucideIcons.moon,
                              selectedMode: widget.themeMode,
                              onChanged: widget.onThemeModeChanged,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_associationStatus?.available == true) ...[
                      _SettingsCard(
                        key: const ValueKey('settings-file-association-card'),
                        icon: FLucideIcons.fileArchive,
                        title: '默认打开方式',
                        description: _associationDescription(),
                        trailing: FButton(
                          key: const ValueKey(
                            'settings-file-association-action',
                          ),
                          size: FButtonSizeVariant.sm,
                          variant: FButtonVariant.outline,
                          onPress: _bindingFormats
                              ? null
                              : _configureFileAssociations,
                          child: Text(_bindingFormats ? '正在绑定…' : '选择格式…'),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _SettingsCard(
                      key: const ValueKey('settings-finder-menu-card'),
                      icon: FLucideIcons.mousePointerClick,
                      title: 'Finder 右键菜单支持',
                      description: _finderContextMenuAvailable == true
                          ? 'Finder 扩展已安装，可在文件右键菜单中使用 Jucier。'
                          : '安装 Finder 扩展，在文件右键菜单中显示 Jucier。',
                      trailing: _finderContextMenuAvailable == true
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FButton(
                                  key: const ValueKey(
                                    'settings-finder-menu-action',
                                  ),
                                  size: FButtonSizeVariant.sm,
                                  variant: FButtonVariant.outline,
                                  onPress: null,
                                  child: const Text('已安装'),
                                ),
                                const SizedBox(width: 6),
                                FButton(
                                  key: const ValueKey(
                                    'settings-finder-menu-uninstall',
                                  ),
                                  size: FButtonSizeVariant.sm,
                                  variant: FButtonVariant.outline,
                                  onPress: _uninstallingFinderContextMenu
                                      ? null
                                      : _uninstallFinderContextMenu,
                                  child: Text(
                                    _uninstallingFinderContextMenu
                                        ? '正在卸载…'
                                        : '卸载…',
                                  ),
                                ),
                              ],
                            )
                          : FButton(
                              key: const ValueKey(
                                'settings-finder-menu-action',
                              ),
                              size: FButtonSizeVariant.sm,
                              variant: FButtonVariant.outline,
                              onPress: _repairingFinderContextMenu
                                  ? null
                                  : _repairFinderContextMenu,
                              child: Text(
                                _repairingFinderContextMenu ? '正在安装…' : '安装…',
                              ),
                            ),
                    ),
                    const SizedBox(height: 14),
                    _SettingsCard(
                      key: const ValueKey('settings-archive-columns-card'),
                      icon: FLucideIcons.listTree,
                      title: '文件树菜单栏',
                      description: '分别选择压缩和解压文件树显示的信息与顺序。',
                      trailing: SizedBox(
                        width: 210,
                        child: Row(
                          children: [
                            Expanded(
                              child: FButton(
                                key: const ValueKey(
                                  'configure-compression-columns',
                                ),
                                size: FButtonSizeVariant.sm,
                                variant: FButtonVariant.outline,
                                onPress: () =>
                                    _configureColumns(compression: true),
                                child: const Text('压缩…'),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: FButton(
                                key: const ValueKey(
                                  'configure-extraction-columns',
                                ),
                                size: FButtonSizeVariant.sm,
                                variant: FButtonVariant.outline,
                                onPress: () =>
                                    _configureColumns(compression: false),
                                child: const Text('解压…'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SettingsCard(
                      key: const ValueKey('settings-single-entry-card'),
                      icon: FLucideIcons.fileArchive,
                      title: '单文件解压/预览模式',
                      description:
                          widget.singleEntryExtractionMode ==
                              SingleEntryExtractionMode.preserveArchiveStructure
                          ? '单独解压时保留压缩包中的完整父目录。'
                          : '仅解压所选文件或文件夹，不包含其父目录。',
                      trailing: SizedBox(
                        width: 244,
                        child: Row(
                          children: [
                            _ExtractionModeButton(
                              mode: SingleEntryExtractionMode
                                  .preserveArchiveStructure,
                              label: '保留目录结构',
                              selectedMode: widget.singleEntryExtractionMode,
                              onChanged:
                                  widget.onSingleEntryExtractionModeChanged,
                            ),
                            const SizedBox(width: 6),
                            _ExtractionModeButton(
                              mode: SingleEntryExtractionMode.selectedOnly,
                              label: '不含父目录',
                              selectedMode: widget.singleEntryExtractionMode,
                              onChanged:
                                  widget.onSingleEntryExtractionModeChanged,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SettingsCard(
                      key: const ValueKey('settings-permission-card'),
                      icon: FLucideIcons.folderOpen,
                      iconKey: const ValueKey('settings-permission-icon'),
                      title: '文件与文件夹访问',
                      description: granted
                          ? '已授权：${status?.directory ?? '已选择的文件夹'}'
                          : '选择 Jucier 可以打开、创建和解压文件的位置。',
                      trailing: FButton(
                        key: const ValueKey('settings-permission-action'),
                        size: FButtonSizeVariant.sm,
                        variant: granted
                            ? FButtonVariant.outline
                            : FButtonVariant.primary,
                        onPress: _requesting ? null : _requestAccess,
                        child: Text(
                          _requesting
                              ? '等待授权…'
                              : granted
                              ? '更改…'
                              : '授权…',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 52,
            child: Container(
              key: const ValueKey('settings-header-background'),
              decoration: BoxDecoration(
                color: colors.background,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    child: FButton(
                      key: const ValueKey('settings-back-button'),
                      size: FButtonSizeVariant.sm,
                      variant: FButtonVariant.outline,
                      onPress: widget.onBack,
                      prefix: const Icon(FLucideIcons.arrowLeft, size: 17),
                      child: const Text('返回'),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      '设置',
                      style: context.theme.typography.display.xl2.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _configureColumns({required bool compression}) async {
    final preferences = widget.archiveColumnPreferences;
    final columns = compression
        ? preferences.compressionColumns
        : preferences.extractionColumns;
    final updated = await showArchiveColumnsDialog(
      context,
      title: compression ? '压缩文件树' : '解压文件树',
      columns: columns,
      availableColumns: compression
          ? compressionAvailableArchiveColumns
          : extractionAvailableArchiveColumns,
    );
    if (updated == null || !mounted) return;
    widget.onArchiveColumnPreferencesChanged?.call(
      compression
          ? preferences.copyWith(compressionColumns: updated)
          : preferences.copyWith(extractionColumns: updated),
    );
  }

  Future<void> _repairFinderContextMenu() async {
    setState(() => _repairingFinderContextMenu = true);
    try {
      await widget.finderActionService.repairContextMenu();
      if (mounted) {
        setState(() {
          _repairingFinderContextMenu = false;
          _finderContextMenuAvailable = true;
        });
        await showMessageDialog(
          context,
          title: 'Finder 右键菜单支持已安装',
          message: '已注册并启用“Jucier Finder Extension”。你也可以在系统设置中检查其状态。',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法安装 Finder 右键菜单支持',
          message: error.message ?? 'macOS 未能注册 Finder 扩展。',
        );
      }
    } on MissingPluginException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法安装 Finder 右键菜单支持',
          message: error.message ?? '当前版本缺少 Finder 扩展安装接口。',
        );
      }
    } finally {
      if (mounted) setState(() => _repairingFinderContextMenu = false);
    }
  }

  Future<void> _uninstallFinderContextMenu() async {
    setState(() => _uninstallingFinderContextMenu = true);
    try {
      await widget.finderActionService.uninstallContextMenu();
      if (mounted) {
        setState(() {
          _uninstallingFinderContextMenu = false;
          _finderContextMenuAvailable = false;
        });
        await showMessageDialog(
          context,
          title: 'Finder 右键菜单支持已卸载',
          message: 'Jucier Finder Extension 已停用并从扩展注册表移除。',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法卸载 Finder 右键菜单支持',
          message: error.message ?? 'macOS 未能卸载 Finder 扩展。',
        );
      }
    } on MissingPluginException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法卸载 Finder 右键菜单支持',
          message: error.message ?? '当前版本缺少 Finder 扩展卸载接口。',
        );
      }
    } finally {
      if (mounted) setState(() => _uninstallingFinderContextMenu = false);
    }
  }

  String _associationDescription() {
    final count = _associationStatus?.defaultExtensions.length ?? 0;
    return count == 0
        ? '选择由 Jucier 默认打开的压缩包格式。'
        : 'Jucier 已是 $count 种压缩包格式的默认打开方式。';
  }

  Future<void> _configureFileAssociations() async {
    final selected = await showArchiveFileAssociationDialog(
      context,
      defaultExtensions:
          _associationStatus?.defaultExtensions ?? const <String>{},
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() => _bindingFormats = true);
    try {
      final status = await widget.archiveFileAssociationService.setAsDefault(
        selected,
      );
      if (mounted) {
        setState(() {
          _associationStatus = ArchiveFileAssociationStatus(
            available: status.available,
            defaultExtensions: {
              ...?_associationStatus?.defaultExtensions,
              ...status.defaultExtensions,
            },
          );
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        await showMessageDialog(
          context,
          title: '无法更改默认打开方式',
          message: error.message ?? 'macOS 未能完成文件格式绑定。',
        );
      }
    } finally {
      if (mounted) setState(() => _bindingFormats = false);
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.trailing,
    this.iconKey,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget trailing;
  final Key? iconKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, key: iconKey, size: 22, color: colors.foreground),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.theme.typography.body.lg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: context.theme.typography.body.sm.copyWith(
                    color: colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          trailing,
        ],
      ),
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selectedMode,
    required this.onChanged,
  });

  final ThemeMode mode;
  final String label;
  final IconData icon;
  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) => Expanded(
    child: FButton(
      key: ValueKey('theme-mode-${mode.name}'),
      size: FButtonSizeVariant.sm,
      variant: mode == selectedMode
          ? FButtonVariant.primary
          : FButtonVariant.outline,
      onPress: onChanged == null ? null : () => onChanged!(mode),
      prefix: Icon(icon, size: 15),
      child: Text(label),
    ),
  );
}

class _ExtractionModeButton extends StatelessWidget {
  const _ExtractionModeButton({
    required this.mode,
    required this.label,
    required this.selectedMode,
    required this.onChanged,
  });

  final SingleEntryExtractionMode mode;
  final String label;
  final SingleEntryExtractionMode selectedMode;
  final ValueChanged<SingleEntryExtractionMode>? onChanged;

  @override
  Widget build(BuildContext context) => Expanded(
    child: FButton(
      key: ValueKey('single-entry-mode-${mode.name}'),
      size: FButtonSizeVariant.sm,
      variant: mode == selectedMode
          ? FButtonVariant.primary
          : FButtonVariant.outline,
      onPress: onChanged == null ? null : () => onChanged!(mode),
      child: Text(label),
    ),
  );
}
