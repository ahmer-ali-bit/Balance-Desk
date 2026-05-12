import 'package:flutter/material.dart';

class ScaleDownWidth extends StatelessWidget {
  const ScaleDownWidth({
    super.key,
    required this.designWidth,
    required this.child,
    this.alignment = Alignment.topLeft,
  });

  final double designWidth;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;

        // If width is infinite, non-positive, or already large enough, just return the child.
        // non-positive width can cause invalid transformation matrices.
        if (!maxWidth.isFinite || maxWidth <= 0 || maxWidth >= designWidth) {
          return child;
        }

        // Calculate scale factor to maintain proportions.
        final scale = maxWidth / designWidth;

        return Align(
          alignment: alignment,
          child: SizedBox(
            width: maxWidth,
            height: maxHeight.isFinite ? maxHeight : null,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: alignment,
              child: SizedBox(
                width: designWidth,
                height: maxHeight.isFinite ? maxHeight / scale : null,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
