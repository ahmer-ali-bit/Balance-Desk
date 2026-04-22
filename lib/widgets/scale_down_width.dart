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
        if (!maxWidth.isFinite || maxWidth >= designWidth) {
          return child;
        }

        return Align(
          alignment: alignment,
          child: SizedBox(
            width: maxWidth,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: alignment,
              child: SizedBox(width: designWidth, child: child),
            ),
          ),
        );
      },
    );
  }
}
