// Dashboard sidebar panel used by LedgerScreen on the mobile shell.
//
// Kept intentionally small and self-contained. It reads the in-memory customer
// pool from CustomerProvider (the same source LedgerScreen refreshes before
// building its entry list) and shows the customers that are not currently
// active on this ledger.
//
// This widget is stateful by choice: tapping a customer immediately selects it
// on the underlying LedgerProvider. The side column itself only re-renders when
// the selected customer changes, which keeps rebuilds cheap while still giving
// immediate feedback.

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../providers/customer_provider.dart';
import '../providers/ledger_provider.dart';

class DashboardSidebar extends StatefulWidget {
  const DashboardSidebar({super.key});

  @override
  State<DashboardSidebar> createState() => _DashboardSidebarState();
}

class _DashboardSidebarState extends State<DashboardSidebar> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = _remainingCustomers(context);
    final count = remaining.length;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(label: 'Other Customers', count: count),
          const SizedBox(height: 10),
          if (count == 0)
            _EmptyPanel(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 4,
                ),
                itemCount: count,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                ),
                itemBuilder: (context, index) {
                  final customer = remaining[index];
                  return _CustomerTile(customer: customer);
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Customer> _remainingCustomers(BuildContext context) {
    final customerProvider =
        Provider.of<CustomerProvider>(context, listen: false);
    final ledgerProvider =
        Provider.of<LedgerProvider>(context, listen: false);
    final active = ledgerProvider.customer;

    return customerProvider.customers.where((customer) {
      final id = customer.id;
      final name = customer.name.trim().toLowerCase();
      final activeName = active.name.trim().toLowerCase();
      if (id != null) {
        return id != active.id;
      }
      return name != activeName;
    }).toList(growable: false);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Text(
        'No other customers yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          height: 1.35,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectCustomer(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    customer.name.trim().isNotEmpty
                        ? customer.name.trim()[0].toUpperCase()
                        : '?',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${customer.displayAddress} · ${customer.displayPhone}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectCustomer(BuildContext context) {
    final ledgerProvider =
        Provider.of<LedgerProvider>(context, listen: false);
    if (ledgerProvider.customer.id == customer.id) {
      return;
    }
    ledgerProvider.customer = customer;
  }
}
