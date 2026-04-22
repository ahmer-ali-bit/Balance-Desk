import 'package:flutter/material.dart';

class SummaryStatCard extends StatelessWidget {
  const SummaryStatCard({
    super.key,
    required this.label,
    required this.value,
    this.stretch = false,
    this.compact = false,
    this.height,
  });

  final String label;
  final String value;
  final bool stretch;
  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = compact
        ? theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
    final valueStyle = compact
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    final resolvedHeight = height ?? (compact ? 50.0 : 70.0);

    return SizedBox(
      width: stretch
          ? double.infinity
          : compact
          ? 110
          : 176,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: resolvedHeight),
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 8 : 14,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: labelStyle?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                ),
                SizedBox(height: compact ? 4 : 6),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: valueStyle, maxLines: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
