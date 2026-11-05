import 'package:flutter/material.dart';

/// Consistent page heading for the Harbor workspace.
class HarborPageHeading extends StatelessWidget {
  const HarborPageHeading({super.key, required this.eyebrow, required this.title, required this.subtitle, this.trailing});
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: <Widget>[
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(eyebrow.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(
            color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ]),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Flat bordered surface, with no backdrop blur or heavy animation.
class HarborPanel extends StatelessWidget {
  const HarborPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.tint = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint ? colors.secondaryContainer.withValues(alpha: 0.48) : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}
