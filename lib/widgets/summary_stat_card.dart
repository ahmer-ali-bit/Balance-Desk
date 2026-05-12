import 'dart:ui';
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
        ? theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
    final valueStyle = compact
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);
    final resolvedHeight = height ?? (compact ? 60.0 : 84.0);

    final bool isMetric = backgroundColor != null;
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
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: isMetric
                    ? backgroundColor!.withValues(alpha: 0.15)
                    : theme.cardTheme.color?.withValues(alpha: 0.1) ??
                        colorScheme.surfaceContainerLow.withValues(alpha: 0.1),
                gradient: isMetric
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          backgroundColor!.withValues(alpha: 0.25),
                          backgroundColor!.withValues(alpha: 0.15),
                          backgroundColor!.withValues(alpha: 0.2),
                        ],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          colorScheme.surface.withValues(alpha: 0.2),
                          colorScheme.surfaceContainerLow.withValues(alpha: 0.1),
                        ],
                      ),
                borderRadius: borderRadius,
                border: Border.all(
                  color: isMetric
                      ? backgroundColor!.withValues(alpha: 0.4)
                      : colorScheme.outlineVariant.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: isMetric
                    ? <BoxShadow>[
                        BoxShadow(
                          color: backgroundColor!.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 16,
                  vertical: height != null ? (compact ? 4 : 6) : (compact ? 8 : 14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (isMetric ? Colors.white : colorScheme.primary).withValues(alpha: 0.1),
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
          ),
        ),
      ),
    );
  }
}
