import 'package:flutter/material.dart';

const double kMobilePremiumRadius = 14;

/// Page-level wrapper for mobile screens.
///
/// Warm paper canvas; individual sections bring their own white cards.
class MobilePremiumPage extends StatelessWidget {
  const MobilePremiumPage({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// White content card with hairline border and a whisper of shadow.
class MobilePremiumPanel extends StatelessWidget {
  const MobilePremiumPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.accentColor,
    this.onTap,
    this.showAccentBar = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accentColor;
  final VoidCallback? onTap;
  final bool showAccentBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLight = colorScheme.brightness == Brightness.light;
    final accent = accentColor ?? colorScheme.primary;
    final radius = BorderRadius.circular(kMobilePremiumRadius);

    Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: radius,
        border: Border.all(
          color: onTap != null
              ? accent.withValues(alpha: 0.32)
              : colorScheme.outlineVariant,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isLight
                ? const Color(0xFF182420).withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.34),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: showAccentBar
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 3.5,
                  constraints: const BoxConstraints(minHeight: 24),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: child),
              ],
            )
          : child,
    );

    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: radius, child: panel),
    );
  }
}

/// Section header panel — icon tile, title, subtitle, optional trailing.
class MobilePremiumHeader extends StatelessWidget {
  const MobilePremiumHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.children = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MobilePremiumPanel(
      padding: const EdgeInsets.all(15),
      showAccentBar: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
          if (children.isNotEmpty) ...<Widget>[
            const SizedBox(height: 13),
            ...children,
          ],
        ],
      ),
    );
  }
}

/// Responsive 2/3-column grid for metric tiles.
class MobileMetricGrid extends StatelessWidget {
  const MobileMetricGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        const spacing = 10.0;
        final width =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// Compact metric tile — micro caps label, mono figure, tinted icon.
class MobileMetricTile extends StatelessWidget {
  const MobileMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: color, size: 13),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    fontSize: 9,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: -0.2,
              ).copyWith(color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section divider label — caps micro type, optional count pill and action.
class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.action,
  });

  final String title;
  final String? count;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 11,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              count!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        if (action != null) ...<Widget>[const SizedBox(width: 8), action!],
      ],
    );
  }
}

/// Small status pill with icon.
class MobileStatusPill extends StatelessWidget {
  const MobileStatusPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
