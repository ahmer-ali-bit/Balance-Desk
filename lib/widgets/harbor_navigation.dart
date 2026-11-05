import 'package:flutter/material.dart';

/// Provides the existing shell destinations to pushed ledger routes.
class HarborNavigationScope extends InheritedWidget {
  const HarborNavigationScope({
    super.key,
    required this.onNavigate,
    required super.child,
  });

  final ValueChanged<int> onNavigate;

  static ValueChanged<int>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HarborNavigationScope>()
      ?.onNavigate;

  @override
  bool updateShouldNotify(HarborNavigationScope oldWidget) =>
      oldWidget.onNavigate != onNavigate;
}

/// The Harbor navigation bar uses the app's existing destinations and actions.
class HarborNavigationBar extends StatelessWidget {
  const HarborNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    this.includeBackup = true,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool includeBackup;

  static const _labels = <String>[
    'Customers', 'Summary', 'Daily Logs', 'Backup & Restore',
  ];
  static const _icons = <IconData>[
    Icons.people_alt_outlined,
    Icons.assessment_outlined,
    Icons.history_outlined,
    Icons.backup_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = includeBackup ? _labels.length : _labels.length - 1;
    return Material(
      color: colors.primary,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 54,
          child: Row(
            children: <Widget>[
              for (var index = 0; index < count; index++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelected(index),
                    child: Container(
                      alignment: Alignment.center,
                      color: index == selectedIndex
                          ? colors.onPrimary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (constraints.maxWidth >= 105) ...<Widget>[
                              Icon(_icons[index], size: 17, color: colors.onPrimary),
                              const SizedBox(width: 7),
                            ],
                            Flexible(
                              child: Text(
                                _labels[index],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: colors.onPrimary,
                                  fontWeight: index == selectedIndex
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
