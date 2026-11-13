import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// Reusable small amount chip showing a label + value with accent color.
class AmountChip extends StatelessWidget {
  const AmountChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final bool compact;

  factory AmountChip.debit(String value, {bool compact = false}) => AmountChip(
        label: 'Debit',
        value: value,
        icon: Icons.arrow_downward_rounded,
        color: AppColors.debit,
        compact: compact,
      );

  factory AmountChip.credit(String value, {bool compact = false}) => AmountChip(
        label: 'Credit',
        value: value,
        icon: Icons.arrow_upward_rounded,
        color: AppColors.credit,
        compact: compact,
      );

  factory AmountChip.balance(String value, {bool compact = false}) {
    final color = AppColors.balanceColor(
      double.tryParse(value.replaceAll(',', '')) ?? 0,
    );
    return AmountChip(
      label: 'Balance',
      value: value,
      icon: color == AppColors.debit
          ? Icons.arrow_downward_rounded
          : (color == AppColors.credit
              ? Icons.arrow_upward_rounded
              : Icons.account_balance_wallet_outlined),
      color: color,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = color ?? theme.colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 80),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: compact ? 10 : 12, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 9 : 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: primaryColor,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }
}