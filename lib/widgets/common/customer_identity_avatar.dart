import 'package:flutter/material.dart';

/// Reusable avatar showing the first letter of a customer name.
class CustomerIdentityAvatar extends StatelessWidget {
  const CustomerIdentityAvatar({
    super.key,
    required this.name,
    this.radius = 22,
    this.backgroundColor,
    this.foregroundColor,
    this.showStockBadge = false,
    this.isStockLedger = false,
  });

  final String name;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showStockBadge;
  final bool isStockLedger;

  String get _initial => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? colorScheme.primaryContainer,
      foregroundColor: foregroundColor ?? colorScheme.primary,
      child: Text(
        _initial,
        style: theme.textTheme.titleMedium?.copyWith(
          color: foregroundColor ?? colorScheme.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    if (!showStockBadge || !isStockLedger) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: radius * 0.7,
            height: radius * 0.7,
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.surface, width: 2),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: radius * 0.5,
              color: colorScheme.onSecondary,
            ),
          ),
        ),
      ],
    );
  }
}