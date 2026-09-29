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
        duration: const Duration(milliseconds: 520),
        reverseDuration: const Duration(milliseconds: 360),
        // Apply easing once below, so the reveal and its wave stay in step.
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.linear,
        layoutBuilder: _buildPageLayers,
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

  Widget _buildPageLayers(Widget? currentChild, List<Widget> previousChildren) {
    final layers = [...previousChildren, ?currentChild];
    // Settings remains the covering surface in both directions. The default
    // switcher puts the incoming workspace above settings when closing it.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the switcher's entry key on the outermost widget. Otherwise
        // adding/removing the workspace changes the settings slot, remounts
        // its State, and briefly hides rows backed by asynchronous status.
        for (final layer in layers.where((layer) => !_isSettingsLayer(layer)))
          IgnorePointer(
            key: layer.key,
            ignoring: layer != currentChild,
            child: layer,
          ),
        for (final layer in layers.where(_isSettingsLayer))
          IgnorePointer(
            key: layer.key,
            ignoring: layer != currentChild,
            child: layer,
          ),
      ],
    );
  }

  bool _isSettingsLayer(Widget layer) {
    // AnimatedSwitcher wraps each transition to retain its entry identity.
    while (layer is KeyedSubtree) {
      layer = layer.child;
    }
    return layer.key == const ValueKey('settings-circular-reveal');
  }

  Widget _buildTransition(Widget child, Animation<double> animation) {
    if (child.key != const ValueKey('settings-page')) {
      return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: child,
      );
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
        final progress = const Cubic(0.2, 0, 0.2, 1).transform(animation.value);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _revealProgress.value = progress;
        });
        return ClipPath(
          clipper: _CircularRevealClipper(progress),
          child: ColoredBox(
            color: context.theme.colors.background,
            child: child,
          ),
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

    final origin = _revealOrigin(size);
    final radius = _revealRadius(size) * progress;
    // A soft crest with a wider, quieter wake feels like a water ripple.
    // Fade both ends so the first frame never flashes a dark ring.
    final strength = math.sin(math.pi * progress);
    final width = math.min(radius, 12 + 24 * progress);
    final outerRadius = radius + width * 0.3;
    final innerStop = (radius - width) / outerRadius;
    final crestStop = radius / outerRadius;

    canvas.drawCircle(
      origin,
      outerRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.025 * strength),
            color.withValues(alpha: 0.09 * strength),
            color.withValues(alpha: 0),
          ],
          stops: [0, innerStop, (innerStop + crestStop) / 2, crestStop, 1],
        ).createShader(Rect.fromCircle(center: origin, radius: outerRadius)),
    );
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.12 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 + 0.6 * (1 - progress),
    );
  }

  @override
  bool shouldRepaint(_CircularRipplePainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
