import 'package:flutter/material.dart';

class SummaryStatCard extends StatelessWidget {
  const SummaryStatCard({
    super.key,
    required this.label,
    required this.value,
    this.stretch = false,
    this.compact = false,
    this.height,
    this.backgroundColor,
    this.labelColor,
    this.icon,
  });

  final String label;
  final String value;
  final bool stretch;
  final bool compact;
  final double? height;
  final Color? backgroundColor;
  final Color? labelColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = compact
        ? theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600);
    final valueStyle = compact
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final resolvedHeight = height ?? (compact ? 56 : 76);

    final isMetric = backgroundColor != null;
    final borderRadius = BorderRadius.circular(compact ? 12 : 16);

    return SizedBox(
      width: stretch
          ? double.infinity
          : compact
          ? 110
          : 176,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: resolvedHeight,
          maxHeight: height != null ? height! : double.infinity,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: height != null ? (compact ? 4 : 6) : (compact ? 8 : 14),
          ),
          decoration: BoxDecoration(
            color: isMetric
                ? backgroundColor!.withValues(alpha: 0.12)
                : colorScheme.surfaceContainer,
            borderRadius: borderRadius,
            border: isMetric
                ? Border.all(
                    color: backgroundColor!.withValues(alpha: 0.2),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isMetric
                        ? Colors.white.withValues(alpha: 0.15)
                        : colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: compact ? 16 : 20,
                    color: labelColor ??
                        (isMetric ? Colors.white : colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label.toUpperCase(),
                      style: labelStyle?.copyWith(
                        letterSpacing: 0.5,
                        fontSize: compact ? 9 : 10,
                        color: labelColor ??
                            (isMetric
                                ? Colors.white.withValues(alpha: 0.7)
                                : colorScheme.onSurfaceVariant),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: height != null ? 1 : (compact ? 2 : 4)),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: valueStyle?.copyWith(
                            fontSize: compact ? 14 : 16,
                            color: labelColor ??
                                (isMetric ? Colors.white : null),
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
