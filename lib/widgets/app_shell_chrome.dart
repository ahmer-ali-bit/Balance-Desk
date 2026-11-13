import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presentation-only building blocks for the Balance Desk shell.
///
/// Nothing in this file talks to a database, a provider or a service. Every
/// interactive element is driven by a callback supplied by the caller, so the
/// shell chrome can be restyled without touching app logic.
///
/// Visual language — "modern professional ledger":
///  * the navigation rail is always a deep emerald gradient panel (both
///    brightnesses), carrying the brand mark, fiscal-year selector and
///    workspace switcher as engraved dark insets;
///  * the content canvas is warm paper in light mode and deep green-ink in
///    dark mode, with crisp white/lifted cards, hairline borders and a single
///    controlled mint accent;
///  * numerals live in IBM Plex Mono (tabular figures) for ledger clarity.
class ShellMetrics {
  ShellMetrics._();

  static const double sidebarWidth = 272;
  static const double sidebarRailWidth = 84;
  static const double desktopBreakpoint = 980;
  static const double pageRadius = 16;
  static const double panelRadius = 14;
  static const double tileRadius = 10;
}

/// Deep-emerald rail palette. The sidebar reads as a permanent branded panel,
/// distinct from the user-selectable content brightness.
class _Rail {
  _Rail._();

  static const Color gradientTopLight = Color(0xFF12402E);
  static const Color gradientBottomLight = Color(0xFF0C2B20);

  static const Color gradientTopDark = Color(0xFF141F18);
  static const Color gradientBottomDark = Color(0xFF0D1712);

  static const Color ivory = Color(0xFFEFF6EF);
  static const Color muted = Color(0xFF9DB8A8);
  static const Color faint = Color(0xFF6E8A7B);
  static const Color mint = Color(0xFF7CF2B4);
  static const Color mintSoft = Color(0x267CF2B4);
  static const Color mintBorder = Color(0x3D7CF2B4);
  static const Color hairline = Color(0x1AFFFFFF);
  static const Color inset = Color(0x17FFFFFF);
  static const Color insetBorder = Color(0x24FFFFFF);
  static const Color hover = Color(0x12FFFFFF);
  static const Color danger = Color(0xFFFB7A95);
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

/// Warm paper canvas with a faint ledger dot grid and one quiet radial
/// emerald glow. Keeps the content area tactile without competing with data.
class AppShellBackdrop extends StatelessWidget {
  const AppShellBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? const [Color(0xFFF6F7F2), Color(0xFFEEF0E8)]
                  : const [Color(0xFF101713), Color(0xFF0C120E)],
            ),
          ),
        ),
        CustomPaint(
          painter: _LedgerGridPainter(isLight: isLight),
          size: Size.infinite,
        ),
        child,
      ],
    );
  }
}

class _LedgerGridPainter extends CustomPainter {
  const _LedgerGridPainter({required this.isLight});

  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final dotColor = isLight
        ? const Color(0xFF182420).withValues(alpha: 0.055)
        : const Color(0xFF7CF2B4).withValues(alpha: 0.05);
    final paint = Paint()..color = dotColor;
    const spacing = 22.0;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.05, paint);
      }
    }

    // A single, quiet mint aura rising from the top-right corner.
    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(1.15, -1.1),
        radius: 1.15,
        colors: isLight
            ? const [Color(0x1F0E5F3D), Color(0x000E5F3D)]
            : const [Color(0x2E5BE0A4), Color(0x005BE0A4)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant _LedgerGridPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}

/// Floating content panel — crisp card on the paper canvas.
class ShellContentSheet extends StatelessWidget {
  const ShellContentSheet({
    super.key,
    required this.child,
    this.radius = ShellMetrics.panelRadius,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLight = colorScheme.brightness == Brightness.light;
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: borderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isLight
                ? const Color(0xFF182420).withValues(alpha: 0.055)
                : Colors.black.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

/// Logo lockup — transparent emblem set on a glassy disc with a hairline
/// mint ring; reads on both the emerald rail and light surfaces.
class ShellBrandMark extends StatelessWidget {
  const ShellBrandMark({super.key, required this.logo, this.size = 46});

  final Widget? logo;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.35, -0.35),
          radius: 1.15,
          colors: [Color(0x2E7CF2B4), Color(0x0F7CF2B4)],
        ),
        border: Border.fromBorderSide(
          BorderSide(color: _Rail.mintBorder, width: 1),
        ),
      ),
      padding: EdgeInsets.all(size * 0.09),
      child: ClipOval(
        child: logo ??
            Icon(
              Icons.menu_book_rounded,
              size: size * 0.46,
              color: _Rail.mint,
            ),
      ),
    );
  }
}

/// Micro caps label used for rail section headers (Nav / Ledger year / Tools).
class ShellSectionLabel extends StatelessWidget {
  const ShellSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'Lato',
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: _Rail.faint,
          ),
        ),
        if (trailing != null) ...<Widget>[
          const Spacer(),
          trailing!,
        ],
      ],
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
    final selected = widget.selected;
    final entry = widget.entry;

    if (widget.compact) {
      return Tooltip(
        message: entry.label,
        child: Semantics(
          button: true,
          selected: selected,
          label: entry.label,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
                  gradient: selected
                      ? const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [_Rail.mintSoft, Color(0x0F7CF2B4)],
                        )
                      : null,
                  color: !selected && _hovered ? _Rail.hover : null,
                  border: Border.all(
                    color: selected ? _Rail.mintBorder : Colors.transparent,
                  ),
                ),
                child: Icon(
                  selected ? entry.selectedIcon : entry.icon,
                  size: 21,
                  color: selected ? _Rail.mint : _Rail.muted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final showDescription = entry.description.trim().isNotEmpty;

    return Semantics(
      button: true,
      selected: selected,
      label: entry.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [_Rail.mintSoft, Color(0x0A7CF2B4)],
                    )
                  : null,
              color: !selected && _hovered ? _Rail.hover : null,
              border: Border.all(
                color: selected ? _Rail.mintBorder : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: selected ? const Color(0x1F7CF2B4) : _Rail.inset,
                  ),
                  child: Icon(
                    selected ? entry.selectedIcon : entry.icon,
                    size: 19,
                    color: selected ? _Rail.mint : _Rail.muted,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                          color: _Rail.ivory,
                        ),
                      ),
                      if (showDescription) ...<Widget>[
                        const SizedBox(height: 1),
                        Text(
                          entry.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Lato',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: _Rail.faint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: _Rail.mint),
              ],
            ),
          ),
        ),
      ),
    );
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
    final entry = widget.entry;

    if (widget.compact) {
      return Tooltip(
        message: entry.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: entry.onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Container(
              width: 46,
              height: 46,
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
                color: _hovered ? _Rail.hover : Colors.transparent,
                border: Border.all(color: _Rail.hairline),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(entry.icon, size: 18, color: _Rail.muted),
                  if (entry.badge)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: _Rail.mint,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: entry.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
            color: _hovered ? _Rail.hover : Colors.transparent,
          ),
          child: Row(
            children: <Widget>[
              Icon(entry.icon, size: 17, color: _Rail.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: _Rail.ivory,
                  ),
                ),
              ),
              if (entry.badge)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: _RailDot(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailDot extends StatelessWidget {
  const _RailDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: _Rail.mint,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Engraved dark inset used for the fiscal-year and workspace selectors on
/// the emerald rail.
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
    if (compact) {
      return Tooltip(
        message: value,
        child: Container(
          width: 46,
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _Rail.inset,
            borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
            border: Border.all(color: _Rail.insetBorder),
          ),
          child: isBusy
              ? const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _Rail.mint,
                    ),
                  ),
                )
              : Icon(icon, size: 18, color: _Rail.mint),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: _Rail.inset,
        borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
        border: Border.all(color: _Rail.insetBorder),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: _Rail.mint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Lato',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.15,
                color: _Rail.ivory,
              ),
            ),
          ),
          if (isBusy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _Rail.mint,
              ),
            )
          else
            const Icon(
              Icons.unfold_more_rounded,
              size: 17,
              color: _Rail.muted,
            ),
        ],
      ),
    );
  }
}

/// Small square icon button used next to the year selector on the rail.
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
    final enabled = onPressed != null;
    final accent = destructive ? _Rail.danger : _Rail.ivory;

    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: _Rail.inset,
          borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
            child: Container(
              width: compact ? 46 : 38,
              height: compact ? 46 : 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
                border: Border.all(color: _Rail.insetBorder),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// Appearance (Light / System / Dark) segmented control for the rail footer.
/// Wired by the caller to its theme controller.
class ShellAppearanceSwitch extends StatelessWidget {
  const ShellAppearanceSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = <(ThemeMode, IconData, String)>[
      (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
      (ThemeMode.system, Icons.contrast_rounded, 'Auto'),
      (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _Rail.inset,
        borderRadius: BorderRadius.circular(ShellMetrics.tileRadius),
        border: Border.all(color: _Rail.insetBorder),
      ),
      child: Row(
        children: <Widget>[
          for (final (value, icon, label) in items)
            Expanded(
              child: _AppearanceSegment(
                icon: icon,
                label: label,
                selected: mode == value,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppearanceSegment extends StatelessWidget {
  const _AppearanceSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label theme',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: selected ? _Rail.mintSoft : Colors.transparent,
            border: Border.all(
              color: selected ? _Rail.mintBorder : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 13,
                color: selected ? _Rail.mint : _Rail.muted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0.3,
                  color: selected ? _Rail.mint : _Rail.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Emerald navigation rail used by both the desktop shell and the mobile
/// drawer. All data arrives via constructor arguments.
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
    this.appearanceControl,
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

  /// Optional [ShellAppearanceSwitch] (or any widget) pinned above the
  /// footer. Hidden in [compact] mode.
  final Widget? appearanceControl;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(compact ? 0 : ShellMetrics.pageRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isLight
              ? const [_Rail.gradientTopLight, _Rail.gradientBottomLight]
              : const [_Rail.gradientTopDark, _Rail.gradientBottomDark],
        ),
        border: compact ? null : Border.all(color: const Color(0x330E5F3D)),
        boxShadow: compact
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF0C2B20).withValues(
                    alpha: isLight ? 0.28 : 0.55,
                  ),
                  blurRadius: 26,
                  offset: const Offset(6, 0),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildBrand(context),
            Container(height: 1, color: _Rail.hairline),
            Expanded(
              child: Scrollbar(
                controller: scrollController,
                thickness: 5,
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    compact ? 6 : 14,
                    14,
                    compact ? 6 : 14,
                    10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (showNavEntries && navEntries.isNotEmpty) ...<Widget>[
                        if (!compact)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 2, 4, 8),
                            child: ShellSectionLabel('Menu'),
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
                        SizedBox(height: compact ? 12 : 18),
                      ],
                      if (!compact) ...<Widget>[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: ShellSectionLabel('Ledger year'),
                        ),
                        yearControl,
                        const SizedBox(height: 14),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: ShellSectionLabel('Workspace'),
                        ),
                        workspaceControl,
                        const SizedBox(height: 18),
                      ] else ...<Widget>[
                        yearControl,
                        const SizedBox(height: 10),
                        workspaceControl,
                        const SizedBox(height: 12),
                      ],
                      if (tools.isNotEmpty) ...<Widget>[
                        if (!compact)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                            child: ShellSectionLabel('Tools'),
                          ),
                        for (final ShellToolEntry tool in tools)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: ShellToolTile(entry: tool, compact: compact),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!compact && appearanceControl != null) ...<Widget>[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: appearanceControl!,
              ),
            ],
            Container(height: 1, color: _Rail.hairline),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: ShellBrandMark(logo: logo, size: 42)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Row(
        children: <Widget>[
          ShellBrandMark(logo: logo, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  companyName.trim().isEmpty ? 'Balance Desk' : companyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.1,
                    color: _Rail.ivory,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: _Rail.faint,
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
    if (compact) {
      return const SizedBox(height: 12);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: _Rail.inset,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: _Rail.insetBorder),
              ),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 13,
              color: _Rail.mint,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  footerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _Rail.muted,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  footerSubLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 8.5,
                    fontWeight: FontWeight.w500,
                    color: _Rail.faint,
                    letterSpacing: 0.2,
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

/// Pill chip used in the desktop header for FY / workspace glance state.
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
    final colorScheme = Theme.of(context).colorScheme;
    final isLight = colorScheme.brightness == Brightness.light;
    final accent = color ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isLight ? 0.09 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: accent),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: accent,
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
