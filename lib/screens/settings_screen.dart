import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../platform/file_access_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.fileAccessService,
    required this.onBack,
    super.key,
  });

  final FileAccessService fileAccessService;
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
    final colors = context.theme.colors;
    final status = _status;
    final granted = status?.granted ?? false;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FButton(
                  key: const ValueKey('settings-back-button'),
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: widget.onBack,
                  prefix: const Icon(FLucideIcons.arrowLeft, size: 17),
                  child: const Text('返回'),
                ),
              ],
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
              child: Container(
                key: const ValueKey('settings-permission-card'),
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
                      child: Icon(
                        FLucideIcons.folderOpen,
                        key: const ValueKey('settings-permission-icon'),
                        size: 22,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '文件与文件夹访问',
                            style: context.theme.typography.body.lg.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            granted
                                ? '已授权：${status?.directory ?? '已选择的文件夹'}'
                                : '选择 Jucier 可以打开、创建和解压文件的位置。',
                            style: context.theme.typography.body.sm.copyWith(
                              color: colors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    FButton(
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
