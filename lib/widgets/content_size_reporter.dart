import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports laid-out content after the frame, without changing its constraints.
class ContentSizeReporter extends SingleChildRenderObjectWidget {
  const ContentSizeReporter({
    required super.child,
    this.onSizeChanged,
    super.key,
  });

  final ValueChanged<Size>? onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderContentSizeReporter(onSizeChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderContentSizeReporter renderObject,
  ) => renderObject.onSizeChanged = onSizeChanged;
}

class RenderContentSizeReporter extends RenderProxyBox {
  RenderContentSizeReporter(this.onSizeChanged);

  ValueChanged<Size>? onSizeChanged;
  Size? _reportedSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _reportedSize) return;
    final measured = _reportedSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && _reportedSize == measured) onSizeChanged?.call(measured);
    });
  }
}
