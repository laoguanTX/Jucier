import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import '../platform/file_access_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.fileAccessService,
    required this.themeMode,
    required this.onBack,
    this.onThemeModeChanged,
    super.key,
  });

  final FileAccessService fileAccessService;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  FileAccessStatus? _status;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
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

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final granted = status?.granted ?? false;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: FButton(
              key: const ValueKey('settings-back-button'),
              size: FButtonSizeVariant.sm,
              variant: FButtonVariant.ghost,
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
          Center(
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
        ],
      ),
    );
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
      padding: const EdgeInsets.all(20),
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
