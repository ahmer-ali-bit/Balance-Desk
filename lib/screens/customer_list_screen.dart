import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../providers/customer_provider.dart';
import '../utils/platform_helper.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/customer_search_field.dart';
import '../widgets/scale_down_width.dart';
import 'ledger_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final ScrollController _tableVerticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final provider = context.read<CustomerProvider>();
      if (provider.customers.isEmpty && !provider.isLoading) {
        provider.loadCustomers();
      }
    });
  }

  void _scrollTable(double delta) {
    if (!_tableVerticalController.hasClients) {
      return;
    }
    final position = _tableVerticalController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _tableVerticalController.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    searchFocusNode.dispose();
    _tableVerticalController.dispose();
    super.dispose();
  }

  Future<void> _showAddCustomerDialog() async {
    final draft = await showDialog<_CustomerDraft>(
      context: context,
      builder: (BuildContext context) => const _AddCustomerDialog(),
    );

    if (!mounted || draft == null) {
      return;
    }

    final provider = context.read<CustomerProvider>();
    final newCustomer = await provider.addCustomerAndReturn(draft.name);

    if (!mounted) {
      return;
    }

    if (newCustomer != null) {
      await _openLedger(newCustomer);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer added successfully.')),
      );
      return;
    }

    final message = provider.errorMessage ?? 'Unable to add customer.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openLedger(Customer customer) async {
    final customerProvider = context.read<CustomerProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider<CustomerProvider>.value(
              value: customerProvider,
            ),
          ],
          child: LedgerScreen(customer: customer),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Customer customer) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete Customer'),
              content: Text('Delete ${customer.name}?'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete || !mounted) {
      return;
    }

    await context.read<CustomerProvider>().deleteCustomer(customer);

    if (!mounted) {
      return;
    }

    final message = context.read<CustomerProvider>().errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? '${customer.name} removed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomerProvider>(
      builder: (BuildContext context, CustomerProvider provider, _) {
        final customers = provider.filteredCustomers;

        return Shortcuts(
          shortcuts: <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
                const ActivateIntent(),
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
                const _CustomerIntent(_CustomerShortcut.add),
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR):
                const _CustomerIntent(_CustomerShortcut.refresh),
            LogicalKeySet(LogicalKeyboardKey.arrowDown): const _ScrollIntent(
              80,
            ),
            LogicalKeySet(LogicalKeyboardKey.arrowUp): const _ScrollIntent(-80),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<Intent>(
                onInvoke: (_) {
                  searchFocusNode.requestFocus();
                  return null;
                },
              ),
              _CustomerIntent: CallbackAction<_CustomerIntent>(
                onInvoke: (_CustomerIntent intent) {
                  if (intent.action == _CustomerShortcut.add) {
                      _showAddCustomerDialog();
                  } else if (intent.action == _CustomerShortcut.refresh) {
                    if (!provider.isLoading) {
                      provider.loadCustomers();
                    }
                  }
                  return null;
                },
              ),
              _ScrollIntent: CallbackAction<_ScrollIntent>(
                onInvoke: (_ScrollIntent intent) {
                  _scrollTable(intent.delta);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final isCompact = constraints.maxWidth < 720;
                  final isDesktop = PlatformHelper.isDesktop;
                  final pagePadding = EdgeInsets.fromLTRB(
                    isCompact ? 14 : 16,
                    12,
                    isCompact ? 14 : 16,
                    12,
                  );
                  final body = _buildDesktopCustomerBody(
                    context: context,
                    provider: provider,
                    customers: customers,
                    compactCards: !isDesktop && isCompact,
                    embedInParentScroll: !isDesktop && isCompact,
                  );

                  if (!isDesktop && isCompact) {
                    return SingleChildScrollView(
                      controller: _tableVerticalController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: pagePadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[

                          _buildCustomerHero(
                            context,
                            totalCount: provider.customers.length,
                            visibleCount: customers.length,
                            isLoading: provider.isLoading,
                          ),
                          const SizedBox(height: 12),
                          _buildCustomerToolbar(
                            context: context,
                            provider: provider,
                            isCompact: true,
                          ),
                          const SizedBox(height: 12),
                          body,
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: pagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[

                        if (!isDesktop) ...<Widget>[
                          _buildCustomerHero(
                            context,
                            totalCount: provider.customers.length,
                            visibleCount: customers.length,
                            isLoading: provider.isLoading,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _buildCustomerToolbar(
                          context: context,
                          provider: provider,
                          isCompact: isDesktop ? false : isCompact,
                        ),
                        const SizedBox(height: 12),
                        if (isDesktop) ...<Widget>[
                          _buildDesktopDirectoryHeading(
                            context,
                            count: customers.length,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Expanded(child: body),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchField(CustomerProvider provider) {
    return CustomerSearchField(
      controller: _searchController,
      focusNode: searchFocusNode,
      hintText: 'Search customer',
      optionsBuilder: (String query) => provider.filteredCustomers,
      onChanged: provider.updateSearchQuery,
      onClear: () {
        _searchController.clear();
        provider.updateSearchQuery('');
      },
    );
  }

  Widget _buildCustomerHero(
    BuildContext context, {
    required int totalCount,
    required int visibleCount,
    required bool isLoading,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.primary,
          child: const Icon(Icons.groups_2_outlined),
        ),
        title: Text(
          'Customer Directory',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '$visibleCount shown from $totalCount customers',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : null,
      ),
    );
  }

  Widget _buildCustomerToolbar({
    required BuildContext context,
    required CustomerProvider provider,
    required bool isCompact,
  }) {
    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: provider.isLoading ? null : provider.loadCustomers,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
        FilledButton.icon(
          onPressed: _showAddCustomerDialog,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add Customer'),
        ),
      ],
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchField(provider),
          const SizedBox(height: 10),
          buttons,
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: _buildSearchField(provider)),
        const SizedBox(width: 12),
        buttons,
      ],
    );
  }

  Widget _buildDesktopDirectoryHeading(
    BuildContext context, {
    required int count,
  }) {
    return Text(
      'Directory ($count)',
      style: Theme.of(
        context,
      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    );
  }

  Widget? _buildCustomerState({
    required CustomerProvider provider,
    required List<Customer> customers,
  }) {
    if (provider.isLoading && provider.customers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.customers.isEmpty) {
      return AppEmptyState(
        icon: Icons.people_outline,
        title: 'No customers yet',
        message: 'Add your first customer to start managing ledgers.',
        actionLabel: 'Add Customer',
        onAction: _showAddCustomerDialog,
      );
    }

    if (customers.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off,
        title: 'No search results',
        message: 'Try a different starting letter or clear the search filter.',
        actionLabel: 'Clear Search',
        onAction: () {
          _searchController.clear();
          provider.updateSearchQuery('');
        },
      );
    }

    return null;
  }

  Widget _buildDesktopCustomerBody({
    required BuildContext context,
    required CustomerProvider provider,
    required List<Customer> customers,
    required bool compactCards,
    required bool embedInParentScroll,
  }) {
    final state = _buildCustomerState(
      provider: provider,
      customers: customers,
    );
    if (state != null) {
      return state;
    }

    if (compactCards) {
      return _buildCustomerCardList(
        context: context,
        customers: customers,
        embedInParentScroll: embedInParentScroll,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompactTable = constraints.maxWidth < 720;
        final designWidth = isCompactTable ? 700.0 : 820.0;
        final tableWidth = constraints.maxWidth < designWidth
            ? designWidth
            : constraints.maxWidth;
        final dataTextStyle = Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontSize: isCompactTable ? 14 : null);
        final customerNameStyle = Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontSize: isCompactTable ? 18 : null);

        return ScaleDownWidth(
          designWidth: designWidth,
          child: SizedBox(
            width: double.infinity,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: tableWidth,
                child: Scrollbar(
                  controller: _tableVerticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _tableVerticalController,
                    child: DataTable(
                      dataTextStyle: dataTextStyle,
                      horizontalMargin: isCompactTable ? 0 : 12,
                      columnSpacing: isCompactTable ? 10 : 18,
                      showCheckboxColumn: false,
                      headingRowHeight: 56,
                      dataRowMinHeight: 54,
                      dataRowMaxHeight: 60,
                      headingRowColor: WidgetStatePropertyAll<Color?>(
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      columns: <DataColumn>[
                        DataColumn(
                          label: Padding(
                            padding: EdgeInsets.only(
                              left: isCompactTable ? 0 : 12,
                            ),
                            child: Text('Customer'),
                          ),
                        ),
                        const DataColumn(label: Text('Customer ID')),
                        const DataColumn(label: Text('Open Ledger')),
                        DataColumn(
                          label: Padding(
                            padding: EdgeInsets.only(
                              right: isCompactTable ? 0 : 12,
                            ),
                            child: Text('Actions'),
                          ),
                        ),
                      ],
                      rows: List<DataRow>.generate(customers.length, (
                        int index,
                      ) {
                        final customer = customers[index];

                        return DataRow.byIndex(
                          index: index,
                          onSelectChanged: (_) => _openLedger(customer),
                          cells: <DataCell>[
                            DataCell(
                              SizedBox(
                                width: isCompactTable ? 250 : 280,
                                child: Row(
                                  children: <Widget>[
                                    CircleAvatar(
                                      radius: isCompactTable ? 16 : 18,
                                      child: Text(
                                        customer.name.isEmpty
                                            ? '?'
                                            : customer.name[0].toUpperCase(),
                                      ),
                                    ),
                                    SizedBox(width: isCompactTable ? 10 : 12),
                                    Expanded(
                                      child: Text(
                                        customer.name,
                                        style: customerNameStyle,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(Text('${customer.id ?? '-'}')),
                            DataCell(
                              TextButton.icon(
                                onPressed: () => _openLedger(customer),
                                icon: const Icon(Icons.menu_book_outlined),
                                label: const Text('View'),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'Delete customer',
                                onPressed: () => _confirmDelete(customer),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomerCardList({
    required BuildContext context,
    required List<Customer> customers,
    required bool embedInParentScroll,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView.separated(
      controller: embedInParentScroll ? null : _tableVerticalController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      shrinkWrap: embedInParentScroll,
      physics: embedInParentScroll
          ? const NeverScrollableScrollPhysics()
          : null,
      padding: const EdgeInsets.only(bottom: 12),
      itemBuilder: (BuildContext context, int index) {
        final customer = customers[index];
        final initial = customer.name.trim().isEmpty
            ? '?'
            : customer.name.trim()[0].toUpperCase();

        return Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: () => _openLedger(customer),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.primary,
                    child: Text(
                      initial,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.primary,
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
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Customer ID: ${customer.id ?? '-'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open ledger',
                    onPressed: () => _openLedger(customer),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  IconButton(
                    tooltip: 'Delete customer',
                    onPressed: () => _confirmDelete(customer),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemCount: customers.length,
    );
  }
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog();

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(
        context,
      ).pop(_CustomerDraft(name: _nameController.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Add Customer'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Customer name'),
                  validator: (String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Customer name is required';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _CustomerDraft {
  const _CustomerDraft({required this.name});

  final String name;
}

enum _CustomerShortcut { add, refresh }

class _CustomerIntent extends Intent {
  const _CustomerIntent(this.action);

  final _CustomerShortcut action;
}

class _ScrollIntent extends Intent {
  const _ScrollIntent(this.delta);

  final double delta;
}
