import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';

/// Reusable horizontal strip showing Debit/Credit/(Balance) values.
class AmountStrip extends StatelessWidget {
  const AmountStrip({
    super.key,
    required this.debit,
    required this.credit,
    this.balance,
    this.balanceColor,
    this.isStock = false,
    this.compact = false,
  });

  final String debit;
  final String credit;
  final String? balance;
  final Color? balanceColor;
  final bool isStock;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StripItem(
              label: isStock ? 'Buy' : 'Debit',
              value: debit,
              icon: Icons.south_west_rounded,
              color: isStock ? AppColors.credit : AppColors.debit,
              compact: compact,
            ),
          ),
          _Divider(compact: compact),
          Expanded(
            child: _StripItem(
              label: isStock ? 'Sell' : 'Credit',
              value: credit,
              icon: Icons.north_east_rounded,
              color: isStock ? AppColors.debit : AppColors.credit,
              compact: compact,
            ),
          ),
          if (balance != null) ...[
            _Divider(compact: compact),
            Expanded(
              child: _StripItem(
                label: 'Balance',
                value: balance!,
                icon: balance!.startsWith('-')
                    ? Icons.arrow_upward_rounded
                    : (balance == '-' || balance == '0'
                        ? Icons.account_balance_wallet_outlined
                        : Icons.arrow_downward_rounded),
                color: balanceColor ?? colorScheme.tertiary,
                compact: compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: compact ? 24 : 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _StripItem extends StatelessWidget {
  const _StripItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: compact ? 10 : 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 9 : null,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: compact ? 12 : null,
            ),
          ),
        ),
      ],
    );
  }
}