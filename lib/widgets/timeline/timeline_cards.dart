import 'package:flutter/material.dart';

import '../common/amount_chip.dart';
import '../mobile/mobile_premium.dart';
import '../../utils/number_format_utils.dart';

const double kMobileCardRadius = 20;

/// Reusable mobile premium customer card.
class MobilePremiumCustomerCard extends StatelessWidget {
  const MobilePremiumCustomerCard({
    super.key,
    required this.name,
    required this.ledgerPageNo,
    required this.isStockLedger,
    required this.onTap,
    required this.onDelete,
    required this.canEdit,
  });

  final String name;
  final String ledgerPageNo;
  final bool isStockLedger;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return MobilePremiumPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.18),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.menu_book_outlined,
                          size: 12,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Pg  ${ledgerPageNo.trim().isEmpty ? '-' : ledgerPageNo.trim()}',
                          style: const TextStyle(
                            fontFamily: 'IBM Plex Mono',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ).copyWith(color: colorScheme.tertiary),
                        ),
                        if (isStockLedger) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: colorScheme.secondary.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 11,
                                  color: colorScheme.secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'STOCK',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.secondary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Spacer(),
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('Open Ledger'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'Delete customer',
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable mobile premium customer hero card.
class MobilePremiumCustomerHero extends StatelessWidget {
  const MobilePremiumCustomerHero({
    super.key,
    required this.totalCount,
    required this.visibleCount,
    required this.isLoading,
  });

  final int totalCount;
  final int visibleCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return MobilePremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.groups_2_outlined,
                  color: colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Customer Directory',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$visibleCount shown from $totalCount customers',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable compact customer card.
class CustomerCompactCard extends StatelessWidget {
  const CustomerCompactCard({
    super.key,
    required this.name,
    required this.ledgerPageNo,
    required this.onTap,
    required this.onDelete,
    required this.canEdit,
  });

  final String name;
  final String ledgerPageNo;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return MobilePremiumPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Ledger Page: ${ledgerPageNo.trim().isEmpty ? '-' : ledgerPageNo.trim()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open ledger',
            onPressed: onTap,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
          ),
          if (canEdit)
            IconButton(
              tooltip: 'Delete customer',
              onPressed: () => onDelete!,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Reusable single metric tile.
class CustomerMetricTile extends StatelessWidget {
  const CustomerMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tag_rounded, color: accentColor, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable metric grid wrapping tiles side-by-side.
class CustomerMetricGrid extends StatelessWidget {
  const CustomerMetricGrid({super.key, required this.children});

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

/// Reusable mobile premium summary card (stat card with 3 metric strips).
class MobilePremiumSummaryCard extends StatelessWidget {
  const MobilePremiumSummaryCard({
    super.key,
    required this.name,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.balanceColor,
    required this.isStockLedger,
    required this.onTap,
  });

  final String name;
  final double debit;
  final double credit;
  final double balance;
  final Color balanceColor;
  final bool isStockLedger;
  final VoidCallback onTap;

  String _amount(double v) => v == 0 ? '-' : formatAmount(v);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return MobilePremiumPanel(
      onTap: onTap,
      accentColor: balanceColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AmountChip.debit(
                      _amount(debit),
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AmountChip.credit(
                      _amount(credit),
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AmountChip.balance(
                _amount(balance),
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable mobile premium timeline entry card.
class PremiumTimelineEntryCard extends StatelessWidget {
  const PremiumTimelineEntryCard({
    super.key,
    required this.customerName,
    required this.entryDate,
    required this.description,
    required this.debit,
    required this.credit,
    required this.onTap,
    required this.onRemove,
    required this.canEdit,
  });

  final String customerName;
  final String entryDate;
  final String description;
  final double debit;
  final double credit;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool canEdit;

  String _amount(double v) => v == 0 ? '-' : formatAmount(v);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return MobilePremiumPanel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    customerName.isEmpty ? '?' : customerName.trim()[0].toUpperCase(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$entryDate - $description',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                IconButton(
                  tooltip: 'Delete or Remove Entry',
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: AmountChip.debit(
                  _amount(debit),
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AmountChip.credit(
                  _amount(credit),
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable mobile premium snapshot card.
class PremiumSnapshotCard extends StatelessWidget {
  const PremiumSnapshotCard({
    super.key,
    required this.title,
    required this.snapshotDate,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.balanceColor,
    required this.dailyLogPageNo,
    required this.canEdit,
    required this.isExpanded,
    required this.onTap,
    required this.onEditPageNo,
    required this.onDelete,
  });

  final String title;
  final String snapshotDate;
  final double debit;
  final double credit;
  final double balance;
  final Color balanceColor;
  final String dailyLogPageNo;
  final bool canEdit;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback? onEditPageNo;
  final VoidCallback? onDelete;

  String _amount(double v) => v == 0 ? '-' : formatAmount(v);

  String _balanceText(double v) {
    if (v == 0) {
      return '0';
    }
    final formatted = formatAmount(v.abs());
    return v > 0 ? '+$formatted' : '-$formatted';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return MobilePremiumPanel(
      accentColor: balanceColor,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (dailyLogPageNo.isNotEmpty)
                MobileStatusPill(
                  icon: Icons.menu_book_outlined,
                  label: dailyLogPageNo,
                  color: colorScheme.tertiary,
                ),
              if (canEdit) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: dailyLogPageNo.isEmpty
                      ? 'Add DL Page No'
                      : 'Edit DL Page No',
                  onPressed: onEditPageNo,
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Delete snapshot',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            snapshotDate,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AmountChip.debit(
                      _amount(debit),
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AmountChip.credit(
                      _amount(credit),
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AmountChip.balance(
                _balanceText(balance),
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reusable mobile premium balance card.
class PremiumBalanceCard extends StatelessWidget {
  const PremiumBalanceCard({
    super.key,
    required this.title,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.balanceColor,
  });

  final String title;
  final double debit;
  final double credit;
  final double balance;
  final Color balanceColor;

  String _amount(double v) => v == 0 ? '-' : formatAmount(v);

  String _balanceText(double v) {
    if (v == 0) {
      return '0';
    }
    final formatted = formatAmount(v.abs());
    return v > 0 ? '+$formatted' : '-$formatted';
  }

  @override
  Widget build(BuildContext context) {
    return MobilePremiumPanel(
      accentColor: balanceColor,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: balanceColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AmountChip.debit(
                      _amount(debit),
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AmountChip.credit(
                      _amount(credit),
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AmountChip.balance(
                _balanceText(balance),
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
