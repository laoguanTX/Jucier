import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.enabled,
    required this.onOpen,
    required this.onCreate,
    required this.onSettings,
    required this.onDropped,
    super.key,
  });

  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final VoidCallback onSettings;
  final Future<void> Function(List<String> paths) onDropped;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        widget.onDropped(details.files.map((file) => file.path).toList());
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'jucier',
                  style: context.theme.typography.display.xl2.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                FButton(
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.ghost,
                  onPress: widget.onSettings,
                  prefix: const Icon(FLucideIcons.settings, size: 17),
                  child: const Text('设置'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _dragging ? colors.secondary : colors.background,
                  border: Border.all(
                    color: _dragging ? colors.primary : colors.border,
                    width: _dragging ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: colors.secondary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            FLucideIcons.archive,
                            size: 26,
                            color: colors.foreground,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          _dragging ? '松开以继续' : '将文件拖到这里',
                          style: context.theme.typography.display.xl.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '拖入压缩包以打开，或拖入文件和文件夹创建压缩包',
                          textAlign: TextAlign.center,
                          style: context.theme.typography.body.md.copyWith(
                            color: colors.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FButton(
                              onPress: widget.enabled ? widget.onCreate : null,
                              prefix: const Icon(FLucideIcons.plus, size: 17),
                              child: const Text('创建压缩包'),
                            ),
                            const SizedBox(width: 10),
                            FButton(
                              variant: FButtonVariant.outline,
                              onPress: widget.enabled ? widget.onOpen : null,
                              prefix: const Icon(
                                FLucideIcons.folderOpen,
                                size: 17,
                              ),
                              child: const Text('打开压缩包'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
