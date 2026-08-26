import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Switches between the current workspace and settings using the circular
/// reveal that originates at the settings button.
class SettingsPageTransition extends StatefulWidget {
  const SettingsPageTransition({required this.child, super.key});

  final Widget child;

  @override
  State<SettingsPageTransition> createState() => _SettingsPageTransitionState();
}

class _SettingsPageTransitionState extends State<SettingsPageTransition> {
  final ValueNotifier<double> _revealProgress = ValueNotifier<double>(0);
  final Set<Animation<double>> _listenedTransitions = {};

  @override
  void dispose() {
    _revealProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 460),
        reverseDuration: const Duration(milliseconds: 340),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _buildTransition,
        child: widget.child,
      ),
      IgnorePointer(
        child: ValueListenableBuilder<double>(
          valueListenable: _revealProgress,
          builder: (context, progress, _) => CustomPaint(
            painter: _CircularRipplePainter(
              progress,
              context.theme.colors.primary,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildTransition(Widget child, Animation<double> animation) {
    if (child.key != const ValueKey('settings-page')) {
      return FadeTransition(opacity: animation, child: child);
    }

    if (_listenedTransitions.add(animation)) {
      // AnimatedSwitcher removes an outgoing entry before its last build.
      // Publish the terminal values from the status listener so the ripple
      // cannot remain visible after the settings page closes.
      animation.addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.dismissed) {
          _listenedTransitions.remove(animation);
          _revealProgress.value = 0;
        } else if (status == AnimationStatus.completed) {
          _revealProgress.value = 1;
        }
      });
    }

    return AnimatedBuilder(
      key: const ValueKey('settings-circular-reveal'),
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(animation.value);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _revealProgress.value = progress;
        });
        return ClipPath(
          clipper: _CircularRevealClipper(progress),
          child: child,
        );
      },
    );
  }
}

Offset _revealOrigin(Size size) => Offset(size.width - 52, 42);

double _revealRadius(Size size) {
  final origin = _revealOrigin(size);
  return math.sqrt(
    origin.dx * origin.dx +
        (size.height - origin.dy) * (size.height - origin.dy),
  );
}

class _CircularRevealClipper extends CustomClipper<Path> {
  const _CircularRevealClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: _revealOrigin(size),
        radius: _revealRadius(size) * progress,
      ),
    );

  @override
  bool shouldReclip(_CircularRevealClipper oldClipper) =>
      progress != oldClipper.progress;
}

class _CircularRipplePainter extends CustomPainter {
  const _CircularRipplePainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    canvas.drawCircle(
      _revealOrigin(size),
      _revealRadius(size) * progress,
      Paint()
        ..color = color.withValues(alpha: (1 - progress) * 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_CircularRipplePainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
