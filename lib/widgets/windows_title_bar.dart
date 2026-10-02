import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// The native runner hit-tests the empty band for dragging and the middle
/// button for Windows Snap Layouts. Keep its dimensions in sync with
/// kTitleBarHeight/kCaptionButtonWidth in win32_window.cpp.
class WindowsTitleBar extends StatefulWidget {
  const WindowsTitleBar({super.key});

  @override
  State<WindowsTitleBar> createState() => _WindowsTitleBarState();
}

class _WindowsTitleBarState extends State<WindowsTitleBar> {
  static const _channel = MethodChannel('dev.jucier/window');
  bool _maximized = false;
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'windowStateChanged' && mounted) {
        setState(() => _maximized = call.arguments == true);
      } else if (call.method == 'operationWindowStateChanged' && mounted) {
        setState(() => _compact = call.arguments == true);
      }
    });
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    try {
      final maximized = await _channel.invokeMethod<bool>('windowState');
      if (mounted) setState(() => _maximized = maximized ?? false);
    } on MissingPluginException {
      // The title bar can also be rendered in widget tests.
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.theme.colors.background,
    child: SizedBox(
      key: const ValueKey('windows-title-bar'),
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!_compact)
            _CaptionButton(
              label: '最小化',
              icon: FLucideIcons.minus,
              method: 'minimize',
            ),
          if (!_compact)
            _CaptionButton(
              label: _maximized ? '还原' : '最大化',
              icon: _maximized ? FLucideIcons.copy : FLucideIcons.square,
              method: 'toggleMaximize',
            ),
          const _CaptionButton(
            label: '关闭',
            icon: FLucideIcons.x,
            method: 'close',
            destructive: true,
          ),
        ],
      ),
    ),
  );
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.method,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final String method;
  final bool destructive;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  Future<void> _activate() async {
    try {
      await const MethodChannel('dev.jucier/window')
          .invokeMethod<void>(widget.method);
    } on MissingPluginException {
      // No native window in widget tests.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_activate());
              return null;
            },
          ),
        },
        child: GestureDetector(
          key: ValueKey('window-${widget.method}'),
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          child: Container(
            width: 46,
            height: 32,
            color: _hovered
                ? widget.destructive
                      ? const Color(0xffc42b1c)
                      : colors.secondary
                : colors.background,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovered && widget.destructive
                  ? const Color(0xffffffff)
                  : colors.foreground,
            ),
          ),
        ),
      ),
    );
  }
}
