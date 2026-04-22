import 'package:flutter/material.dart';

import '../models/customer.dart';

class CustomerListTile extends StatelessWidget {
  const CustomerListTile({
    super.key,
    required this.customer,
    required this.onDelete,
  });

  final Customer customer;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.primary,
          child: Text(
            customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text('Customer ID: ${customer.id ?? '-'}'),
        trailing: IconButton(
          tooltip: 'Delete customer',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}
