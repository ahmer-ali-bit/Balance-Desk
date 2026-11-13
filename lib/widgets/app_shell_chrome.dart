import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Presentation-only building blocks for the Balance Desk shell.
///
/// Nothing in this file talks to a database, a provider or a service. Every
/// interactive element is driven by a callback supplied by the caller, so the
/// shell chrome can be restyled without touching app logic.
class ShellMetrics {
  ShellMetrics._();

  static const double sidebarWidth = 272;
  static const double sidebarRailWidth = 84;
  static const double desktopBreakpoint = 980;
  static const double pageRadius = 24;
  static const double panelRadius = 16;
  static const double tileRadius = 12;
}

class ShellNavEntry {
  const ShellNavEntry({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.description = '',
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String description;
}

class ShellToolEntry {
  const ShellToolEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Draws a small accent dot, e.g. when the sidebar notes are not empty.
  final bool badge;
}

/// Soft studio backdrop: deep canvas, two blurred accent glows.
class AppShellBackdrop extends StatelessWidget {
  const AppShellBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerLowest,
            colorScheme.surface,
            colorScheme.surfaceContainerLowest,
          ],
          stops: const <double>[0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -180,
            left: -140,
            child: _Glow(
              size: 520,
              color: colorScheme.primary.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            bottom: -220,
            right: -160,
            child: _Glow(
              size: 600,
              color: colorScheme.tertiary.withValues(alpha: 0.10),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

/// Raised sheet used for the working area.
class ShellContentSheet extends StatelessWidget {
  const ShellContentSheet({
    super.key,
    required this.child,
    this.radius = ShellMetrics.pageRadius,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: borderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

class ShellBrandMark extends StatelessWidget {
  const ShellBrandMark({super.key, required this.logo, this.size = 46});

  final Widget? logo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primary,
            Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.5)!,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child:
            logo ??
            Icon(
              Icons.account_balance_wallet_rounded,
              color: colorScheme.onPrimary,
              size: size * 0.52,
            ),
      ),
    );
  }
}

class ShellSectionLabel extends StatelessWidget {
  const ShellSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class ShellNavTile extends StatefulWidget {
  const ShellNavTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final ShellNavEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<ShellNavTile> createState() => _ShellNavTileState();
}

class _ShellNavTileState extends State<ShellNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = widget.selected;

    final foreground = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final background = selected
        ? colorScheme.primary.withValues(alpha: 0.14)
        : (_hovered
              ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.7)
              : Colors.transparent);

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 0 : 14,
            10,
            widget.compact ? 0 : 12,
            10,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.28)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: widget.compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              Icon(
                selected ? widget.entry.selectedIcon : widget.entry.icon,
                size: 19,
                color: selected ? colorScheme.primary : foreground,
              ),
              if (!widget.compact) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.compact) {
      return Tooltip(message: widget.entry.label, child: tile);
    }
    return tile;
  }
}

class ShellToolTile extends StatefulWidget {
  const ShellToolTile({super.key, required this.entry, this.compact = false});

  final ShellToolEntry entry;
  final bool compact;

  @override
  State<ShellToolTile> createState() => _ShellToolTileState();
}

class _ShellToolTileState extends State<ShellToolTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.entry.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 0 : 14,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.7)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
          ),
          child: Row(
            mainAxisAlignment: widget.compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: <Widget>[
              Icon(
                widget.entry.icon,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              if (!widget.compact) ...<Widget>[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.entry.badge)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.compact) {
      return Tooltip(message: widget.entry.label, child: tile);
    }
    return tile;
  }
}

/// Visual shell for a dropdown/select control. Pass it as the `child` of a
/// [PopupMenuButton] so the menu keeps its original behaviour.
class ShellSelectField extends StatelessWidget {
  const ShellSelectField({
    super.key,
    required this.icon,
    required this.value,
    this.isBusy = false,
    this.compact = false,
  });

  final IconData icon;
  final String value;
  final bool isBusy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (compact) {
      return Tooltip(
        message: value,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: isBusy
              ? const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(icon, size: 18, color: colorScheme.primary),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              Icons.unfold_more_rounded,
              size: 17,
              color: colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

/// Small square icon button used next to the year selector.
class ShellIconAction extends StatelessWidget {
  const ShellIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.destructive = false,
    this.compact = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final accent = destructive ? colorScheme.error : colorScheme.primary;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
          child: Ink(
            width: compact ? 38 : 40,
            height: compact ? 38 : 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Icon(
              icon,
              size: 18,
              color: enabled
                  ? accent
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left navigation rail / drawer body shared by desktop and mobile.
class AppShellSidebar extends StatelessWidget {
  const AppShellSidebar({
    super.key,
    required this.companyName,
    required this.subtitle,
    required this.logo,
    required this.yearControl,
    required this.workspaceControl,
    required this.navEntries,
    required this.selectedIndex,
    required this.onSelectIndex,
    required this.tools,
    required this.showNavEntries,
    this.compact = false,
    this.footerLabel = 'Balance Desk',
    this.footerSubLabel = 'Developer: Ahmer Abid',
    this.scrollController,
  });

  final String companyName;
  final String subtitle;
  final Widget? logo;
  final Widget yearControl;
  final Widget workspaceControl;
  final List<ShellNavEntry> navEntries;
  final int selectedIndex;
  final ValueChanged<int> onSelectIndex;
  final List<ShellToolEntry> tools;
  final bool showNavEntries;
  final bool compact;
  final String footerLabel;
  final String footerSubLabel;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(ShellMetrics.pageRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.92),
        borderRadius: radius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildBrand(context),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Expanded(
              child: Scrollbar(
                controller: scrollController,
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 10 : 14,
                    16,
                    compact ? 10 : 14,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (showNavEntries && navEntries.isNotEmpty) ...<Widget>[
                        if (!compact)
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 8),
                            child: _ShellMicroLabel('Navigate'),
                          ),
                        for (var i = 0; i < navEntries.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ShellNavTile(
                              entry: navEntries[i],
                              selected: i == selectedIndex,
                              compact: compact,
                              onTap: () => onSelectIndex(i),
                            ),
                          ),
                        SizedBox(height: compact ? 14 : 20),
                      ],
                      if (!compact) ...<Widget>[
                        const _ShellMicroLabel('Ledger year'),
                        yearControl,
                        const SizedBox(height: 14),
                        const _ShellMicroLabel('Workspace'),
                        workspaceControl,
                        const SizedBox(height: 20),
                      ] else ...<Widget>[
                        compact ? yearControl : const SizedBox.shrink(),
                        const SizedBox(height: 10),
                        workspaceControl,
                        const SizedBox(height: 14),
                      ],
                      if (!compact) const _ShellMicroLabel('Tools'),
                      for (final ShellToolEntry tool in tools)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: ShellToolTile(entry: tool, compact: compact),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(child: ShellBrandMark(logo: logo, size: 40)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Row(
        children: <Widget>[
          ShellBrandMark(logo: logo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  companyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  footerLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  footerSubLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellMicroLabel extends StatelessWidget {
  const _ShellMicroLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          letterSpacing: 1.3,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Desktop page heading shown above the working sheet.
class ShellPageHeader extends StatelessWidget {
  const ShellPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  eyebrow.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary.withValues(alpha: 0.9),
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Compact top bar used by the mobile/tablet layout.
class ShellMobileHeader extends StatelessWidget {
  const ShellMobileHeader({
    super.key,
    required this.onMenu,
    required this.companyName,
    required this.title,
    required this.icon,
    this.avatar,
  });

  final VoidCallback onMenu;
  final String companyName;
  final String title;
  final IconData icon;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        _RoundGlassButton(
          icon: Icons.menu_rounded,
          tooltip: 'Open menu',
          onTap: onMenu,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.primary.withValues(alpha: 0.28),
                colorScheme.tertiary.withValues(alpha: 0.16),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: avatar ?? Icon(icon, color: colorScheme.primary, size: 21),
          ),
        ),
      ],
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Icon(icon, color: colorScheme.onSurface, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Floating bottom navigation used on phones.
class ShellMobileDock extends StatelessWidget {
  const ShellMobileDock({
    super.key,
    required this.entries,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ShellNavEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < entries.length; i++) ...<Widget>[
                Expanded(
                  child: _ShellDockItem(
                    entry: entries[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
                if (i != entries.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellDockItem extends StatelessWidget {
  const _ShellDockItem({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final ShellNavEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: selected ? 1.06 : 1,
                child: Icon(
                  selected ? entry.selectedIcon : entry.icon,
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill used by the sidebar footer status / header chips.
class ShellChip extends StatelessWidget {
  const ShellChip({
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper used by the shell to keep the desktop sidebar fluid on short windows.
class ShellMinHeight extends StatelessWidget {
  const ShellMinHeight({
    super.key,
    required this.minHeight,
    required this.child,
  });

  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final height = constraints.maxHeight.isFinite
            ? math.max(constraints.maxHeight, minHeight)
            : minHeight;
        return SizedBox(height: height, child: child);
      },
    );
  }
}
