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

  /// Accent hue for metric cards (debit/credit/balance semantics). Tints the
  /// icon tile and border; the figure itself stays ink-colored for contrast.
  final Color? backgroundColor;

  /// Legacy override for text color. Prefer leaving null so the card picks
  /// theme-readable colors on its own tinted surface.
  final Color? labelColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLight = colorScheme.brightness == Brightness.light;

    final labelStyle = compact
        ? theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800);
    final resolvedHeight = height ?? (compact ? 56 : 76);

    final accent = backgroundColor;
    final isMetric = accent != null;
    final borderRadius = BorderRadius.circular(compact ? 12 : 14);

    final effectiveLabelColor = labelColor ??
        (isMetric ? accent.withValues(alpha: 1) : colorScheme.onSurfaceVariant);
    final effectiveValueColor = labelColor ?? colorScheme.onSurface;

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
                ? accent.withValues(alpha: isLight ? 0.085 : 0.14)
                : colorScheme.surface,
            borderRadius: borderRadius,
            border: Border.all(
              color: isMetric
                  ? accent.withValues(alpha: isLight ? 0.22 : 0.3)
                  : colorScheme.outlineVariant,
            ),
            boxShadow: isLight
                ? <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF182420).withValues(alpha: 0.035),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
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
                        ? accent.withValues(alpha: isLight ? 0.14 : 0.2)
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: compact ? 15 : 18,
                    color: isMetric ? accent : colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label.toUpperCase(),
                          style: labelStyle?.copyWith(
                            letterSpacing: 0.9,
                            fontSize: compact ? 9 : 9.5,
                            fontWeight: FontWeight.w800,
                            color: effectiveLabelColor.withValues(
                              alpha: labelColor != null ? 1 : 0.85,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: height != null ? 2 : (compact ? 2 : 4)),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontFamily: 'IBM Plex Mono',
                            letterSpacing: -0.3,
                          ).copyWith(
                            color: effectiveValueColor,
                            fontWeight: FontWeight.w600,
                            fontSize: compact ? 14 : 16.5,
                          ),
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
