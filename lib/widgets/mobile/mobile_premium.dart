import 'package:flutter/material.dart';

const double kMobilePremiumRadius = 16;

class MobilePremiumPage extends StatelessWidget {
  const MobilePremiumPage({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 24)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: <Color>[colorScheme.surfaceContainerLowest, colorScheme.surface, colorScheme.surfaceContainerLow.withValues(alpha: 0.35)],
          stops: const <double>[0, 0.45, 1],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class MobilePremiumPanel extends StatelessWidget {
  const MobilePremiumPanel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.accentColor, this.onTap, this.showAccentBar = false});
  final Widget child; final EdgeInsetsGeometry padding; final Color? accentColor; final VoidCallback? onTap; final bool showAccentBar;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme; final accent = accentColor ?? colorScheme.primary; final radius = BorderRadius.circular(kMobilePremiumRadius);
    Widget panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow, borderRadius: radius,
        border: Border.all(color: onTap != null ? accent.withValues(alpha: 0.28) : colorScheme.outlineVariant.withValues(alpha: 0.9)),
        boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: showAccentBar ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Container(width: 4, constraints: const BoxConstraints(minHeight: 20), decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999))),
        const SizedBox(width: 12), Expanded(child: child),
      ]) : child,
    );
    if (onTap == null) return panel;
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: radius, child: panel));
  }
}

class MobilePremiumHeader extends StatelessWidget {
  const MobilePremiumHeader({super.key, required this.icon, required this.title, required this.subtitle, this.trailing, this.children = const <Widget>[]});
  final IconData icon; final String title; final String subtitle; final Widget? trailing; final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); final colorScheme = theme.colorScheme;
    return MobilePremiumPanel(padding: const EdgeInsets.all(16), showAccentBar: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Container(width: 46, height: 46, decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[colorScheme.primary.withValues(alpha: 0.28), colorScheme.secondary.withValues(alpha: 0.18)]),
          borderRadius: BorderRadius.circular(14), border: Border.all(color: colorScheme.primary.withValues(alpha: 0.28)),
        ), child: Icon(icon, color: colorScheme.primary, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 3),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.3)),
        ])),
        if (trailing != null) ...<Widget>[const SizedBox(width: 10), trailing!],
      ]),
      if (children.isNotEmpty) ...<Widget>[const SizedBox(height: 14), ...children],
    ]));
  }
}

class MobileMetricGrid extends StatelessWidget {
  const MobileMetricGrid({super.key, required this.children}); final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final columns = constraints.maxWidth >= 520 ? 3 : 2; const spacing = 10.0;
      final width = (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
      return Wrap(spacing: spacing, runSpacing: spacing, children: <Widget>[for (final child in children) SizedBox(width: width, child: child)]);
    });
  }
}

class MobileMetricTile extends StatelessWidget {
  const MobileMetricTile({super.key, required this.label, required this.value, required this.icon, required this.color});
  final String label; final String value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); final colorScheme = theme.colorScheme;
    return Container(constraints: const BoxConstraints(minHeight: 82), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.22))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
        Row(children: <Widget>[
          Container(width: 26, height: 26, decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 14)),
          const SizedBox(width: 8),
          Expanded(child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.6, fontSize: 10))),
        ]),
        const SizedBox(height: 8),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w800, letterSpacing: -0.2))),
      ]),
    );
  }
}

class MobileSectionHeader extends StatelessWidget {
  const MobileSectionHeader({super.key, required this.title, this.count, this.action});
  final String title; final String? count; final Widget? action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); final colorScheme = theme.colorScheme;
    return Row(children: <Widget>[
      Container(width: 4, height: 18, decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(999))),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2))),
      if (count != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22))), child: Text(count!, style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w800))),
      if (action != null) ...<Widget>[const SizedBox(width: 8), action!],
    ]);
  }
}

class MobileStatusPill extends StatelessWidget {
  const MobileStatusPill({super.key, required this.icon, required this.label, this.color});
  final IconData icon; final String label; final Color? color;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme; final accent = color ?? colorScheme.primary;
    return Container(constraints: const BoxConstraints(maxWidth: 240), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: accent.withValues(alpha: 0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 13, color: accent), const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: accent, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
