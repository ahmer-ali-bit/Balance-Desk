import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../models/customer.dart';
import '../models/entry.dart';
import '../models/snapshot_opening_balance.dart';
import '../services/export_service.dart';
import '../services/linked_devices_controller.dart';
import '../services/pdf_service.dart';
import '../utils/platform_helper.dart';
import '../widgets/customer_search_field.dart';
import '../widgets/summary_stat_card.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

enum _SummaryExportChoice { pdf, excel }

class _SummaryScreenState extends State<SummaryScreen> {
  final AppDatabase _database = AppDatabase.instance;
  final PdfService _pdfService = const PdfService();
  final ExportService _exportService = const ExportService();
  final LinkedDevicesController _linkedDevices =
      LinkedDevicesController.instance;
  final ScrollController _tableVerticalController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = true;
  String? _errorMessage;
  _SummaryData _summaryData = const _SummaryData.empty();
  int _lastSeenLinkedDataVersion = 0;
  String _searchQuery = '';
  bool _showSummaryTools = false;
  bool _showSummaryTotals = false;

  @override
  void initState() {
    super.initState();
    _linkedDevices.addListener(_handleLinkedDevicesChanged);
    _loadSummary();
  }

  @override
  void dispose() {
    _linkedDevices.removeListener(_handleLinkedDevicesChanged);
    _tableVerticalController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleLinkedDevicesChanged() {
    if (_lastSeenLinkedDataVersion == _linkedDevices.dataVersion) {
      return;
    }

    _lastSeenLinkedDataVersion = _linkedDevices.dataVersion;
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final customerRows = await _database.getCustomers();
      final customers = customerRows
          .map<Customer>((Map<String, Object?> row) => Customer.fromMap(row))
          .toList(growable: false);

      final summaries = <_CustomerSummary>[];

      for (final customer in customers) {
        final customerId = customer.id;
        if (customerId == null) {
          continue;
        }

        final entryRows = await _database.getEntriesByCustomer(customerId);
        final openingBalance =
            await _database.getCustomerLedgerOpeningBalance(customerId) ??
            const SnapshotOpeningBalance(debit: 0, credit: 0);
        final entries = entryRows
            .map<Entry>((Map<String, Object?> row) => Entry.fromMap(row))
            .toList(growable: false);
        if (entries.isEmpty && !openingBalance.hasValue) {
          continue;
        }

        final totalDebit = entries.fold<double>(
          openingBalance.debit,
          (double sum, Entry entry) => sum + entry.debit,
        );
        final totalCredit = entries.fold<double>(
          openingBalance.credit,
          (double sum, Entry entry) => sum + entry.credit,
        );
        final latestPageNo = entries.isEmpty ? '' : entries.last.pageNo;

        summaries.add(
          _CustomerSummary(
            customer: customer,
            pageNo: latestPageNo,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
          ),
        );
      }
      summaries.sort(
        (_CustomerSummary a, _CustomerSummary b) => a.customer.name
            .trim()
            .toLowerCase()
            .compareTo(b.customer.name.trim().toLowerCase()),
      );

      final overallDebit = summaries.fold<double>(
        0,
        (double sum, _CustomerSummary item) => sum + item.totalDebit,
      );
      final overallCredit = summaries.fold<double>(
        0,
        (double sum, _CustomerSummary item) => sum + item.totalCredit,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _summaryData = _SummaryData(
          customers: summaries,
          overallDebit: overallDebit,
          overallCredit: overallCredit,
        );
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unable to load summary data.';
        _isLoading = false;
      });
    }
  }

  Future<void> _exportSummaryPdf() async {
    final rows = _buildSummaryPdfRows();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customer summary to export.')),
      );
      return;
    }

    try {
      await _pdfService.exportSnapshotPdf(
        title: 'Customer Summary',
        headers: const <String>[
          'Sr #',
          'Customer',
          'Page No',
          'Total Debit',
          'Total Credit',
          'Balance',
        ],
        rows: rows,
        fileName: 'customer_summary.pdf',
        summaryItems: <({String label, String value})>[
          (
            label: 'Customer Qty',
            value: _summaryData.customers.length.toString(),
          ),
          (
            label: 'Overall Debit',
            value: _formatAmount(_summaryData.overallDebit),
          ),
          (
            label: 'Overall Credit',
            value: _formatAmount(_summaryData.overallCredit),
          ),
          (
            label: 'Final Balance',
            value: _formatBalance(_summaryData.finalBalance),
          ),
        ],
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to export PDF right now.')),
      );
    }
  }

  Future<void> _exportSummaryExcel() async {
    final rows = _buildSummaryExportRows();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customer summary to export.')),
      );
      return;
    }

    try {
      await _exportService.saveCsv(
        dialogTitle: 'Export Summary (Excel)',
        fileName: 'customer_summary.csv',
        headers: const <String>[
          'Customer',
          'Page No',
          'Total Debit',
          'Total Credit',
          'Balance',
        ],
        rows: rows,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to export Excel right now.')),
      );
    }
  }

  Future<void> _exportSummary() async {
    final choice = await showDialog<_SummaryExportChoice>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Export Summary'),
          content: const Text('Choose an export format.'),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SummaryExportChoice.excel),
              child: const Text('Excel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SummaryExportChoice.pdf),
              child: const Text('PDF'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == _SummaryExportChoice.pdf) {
      await _exportSummaryPdf();
    } else {
      await _exportSummaryExcel();
    }
  }

  List<List<String>> _buildSummaryExportRows() {
    if (_summaryData.customers.isEmpty) {
      return const <List<String>>[];
    }

    return <List<String>>[
      ..._summaryData.customers.map<List<String>>(
        (_CustomerSummary item) => <String>[
          item.customer.name,
          item.pageNo.isEmpty ? '-' : item.pageNo,
          _formatAmount(item.totalDebit),
          _formatAmount(item.totalCredit),
          _formatBalance(item.balance),
        ],
      ),
      <String>[
        'Overall Totals',
        '-',
        _formatAmount(_summaryData.overallDebit),
        _formatAmount(_summaryData.overallCredit),
        _formatBalance(_summaryData.finalBalance),
      ],
    ];
  }

  List<List<String>> _buildSummaryPdfRows() {
    if (_summaryData.customers.isEmpty) {
      return const <List<String>>[];
    }

    final rows = <List<String>>[];
    for (var index = 0; index < _summaryData.customers.length; index++) {
      final item = _summaryData.customers[index];
      rows.add(<String>[
        '${index + 1}',
        item.customer.name,
        item.pageNo.isEmpty ? '-' : item.pageNo,
        _formatAmount(item.totalDebit),
        _formatAmount(item.totalCredit),
        _formatBalance(item.balance),
      ]);
    }

    rows.add(<String>[
      '',
      'Overall Totals',
      '-',
      _formatAmount(_summaryData.overallDebit),
      _formatAmount(_summaryData.overallCredit),
      _formatBalance(_summaryData.finalBalance),
    ]);

    return rows;
  }

  String _formatAmount(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String _formatBalance(double balance) {
    if (balance > 0) {
      return '${_formatAmount(balance)} Debit';
    }
    if (balance < 0) {
      return '${_formatAmount(balance.abs())} Credit';
    }
    return '0';
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR):
            const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const _SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _ScrollIntent(80),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _ScrollIntent(-80),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (_) {
              if (!_isLoading) {
                _loadSummary();
              }
              return null;
            },
          ),
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              _searchFocusNode.requestFocus();
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
              final bottomPadding =
                  12.0 + MediaQuery.viewInsetsOf(context).bottom;

              final page = SingleChildScrollView(
                controller: _tableVerticalController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 14 : 16,
                  12,
                  isCompact ? 14 : 16,
                  bottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!isDesktop && isCompact)
                      _buildCompactSummaryControls(context)
                    else ...<Widget>[
                      _buildSummaryToolbar(isCompact: !isDesktop && isCompact),
                    ],
                    const SizedBox(height: 12),
                    _buildMainContent(
                      context,
                      compactLayout: !isDesktop && isCompact,
                    ),
                  ],
                ),
              );
              return page;
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryToolbar({required bool isCompact}) {
    final isDesktop = PlatformHelper.isDesktop;
    final searchField = CustomerSearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: 'Search customers',
      onChanged: (String value) {
        setState(() {
          _searchQuery = value;
        });
      },
      onClear: () {
        _searchController.clear();
        setState(() {
          _searchQuery = '';
        });
      },
    );
    final actionButtons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _loadSummary,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
        if (isDesktop)
          OutlinedButton.icon(
            onPressed: _isLoading || _summaryData.customers.isEmpty
                ? null
                : _exportSummary,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export'),
          )
        else
          FilledButton.icon(
            onPressed: _isLoading || _summaryData.customers.isEmpty
                ? null
                : _exportSummary,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export'),
          ),
      ],
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          searchField,
          const SizedBox(height: 10),
          actionButtons,
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(child: searchField),
        const SizedBox(width: 12),
        actionButtons,
      ],
    );
  }

  Widget _buildCompactSummaryControls(BuildContext context) {
    final totalsLabel = _formatBalance(_summaryData.finalBalance);

    return Column(
      children: <Widget>[
        _buildSummaryToggleHeader(
          context,
          icon: Icons.manage_search_rounded,
          title: 'Search & Export',
          value: _searchQuery.trim().isEmpty ? 'All customers' : _searchQuery,
          expanded: _showSummaryTools,
          onTap: () {
            setState(() {
              _showSummaryTools = !_showSummaryTools;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showSummaryTools
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildSummaryToolbar(isCompact: true),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        _buildSummaryToggleHeader(
          context,
          icon: Icons.analytics_outlined,
          title: 'Totals',
          value: totalsLabel,
          expanded: _showSummaryTotals,
          onTap: () {
            setState(() {
              _showSummaryTotals = !_showSummaryTotals;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showSummaryTotals
              ? Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 10),
                  child: _buildSummaryMetrics(
                    context,
                    overallBalance: _summaryData.finalBalance,
                  ),
                )
              : const SizedBox(height: 10),
        ),
      ],
    );
  }

  Widget _buildSummaryToggleHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildMainContent(
    BuildContext context, {
    required bool compactLayout,
  }) {
    if (_isLoading) {
      return const SizedBox(
        height: 240,
        child: Card(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (_errorMessage != null) {
      return SizedBox(
        height: 260,
        child: Card(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadSummary,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final overallBalance =
        _summaryData.overallDebit - _summaryData.overallCredit;

    final filteredCustomers = _filteredCustomers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!compactLayout) ...<Widget>[
          _buildSummaryMetrics(context, overallBalance: overallBalance),
          const SizedBox(height: 16),
        ],
        _buildSummarySectionHeader(
          context,
          count: filteredCustomers.length,
          compactLayout: compactLayout,
        ),
        SizedBox(height: compactLayout ? 10 : 12),
        filteredCustomers.isEmpty
            ? _buildEmptyState(context)
            : _buildSummaryTable(context, filteredCustomers),
      ],
    );
  }

  Widget _buildSummaryMetrics(
    BuildContext context, {
    required double overallBalance,
  }) {
    final items = <({String label, String value})>[
      (label: 'Overall Debit', value: _formatAmount(_summaryData.overallDebit)),
      (
        label: 'Overall Credit',
        value: _formatAmount(_summaryData.overallCredit),
      ),
      (label: 'Final Balance', value: _formatBalance(overallBalance)),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: width,
                child: SummaryStatCard(
                  label: item.label,
                  value: item.value,
                  stretch: true,
                  height: 76,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSummarySectionHeader(
    BuildContext context, {
    required int count,
    bool compactLayout = false,
  }) {
    if (PlatformHelper.isDesktop && !compactLayout) {
      return Text(
        'Customers ($count)',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: compactLayout ? 12 : 16,
          vertical: compactLayout ? 2 : 4,
        ),
        title: Text(
          'Customer Summary',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: CircleAvatar(
          radius: 16,
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.primary,
          child: Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const SizedBox(
      height: 240,
      child: Card(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.groups_2_outlined, size: 52),
              SizedBox(height: 12),
              Text('No summary entries available.'),
              SizedBox(height: 8),
              Text('Add ledger entries to see the summary.'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryTable(
    BuildContext context,
    List<_CustomerSummary> customers,
  ) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompactTable = constraints.maxWidth < 760;
        if (isCompactTable) {
          return _buildSummaryCardList(context, customers);
        }
        final tableMinWidth = PlatformHelper.isDesktop
            ? math.max(940.0, constraints.maxWidth - 16)
            : 940.0;

        final dataTextStyle = Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontSize: 14);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: tableMinWidth),
                child: DataTable(
                  dataTextStyle: dataTextStyle,
                  horizontalMargin: 12,
                  columnSpacing: 18,
                  headingRowHeight: 56,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 58,
                  headingRowColor: WidgetStatePropertyAll<Color?>(
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Customer')),
                    DataColumn(label: Text('Page No')),
                    DataColumn(label: Text('Total Debit'), numeric: true),
                    DataColumn(label: Text('Total Credit'), numeric: true),
                    DataColumn(label: Text('Balance')),
                  ],
                  rows: <DataRow>[
                    ...customers.map((item) {
                      return DataRow(
                        cells: <DataCell>[
                          DataCell(
                            SizedBox(
                              width: 240,
                              child: Text(
                                item.customer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(item.pageNo.isEmpty ? '-' : item.pageNo),
                          ),
                          DataCell(Text(_formatAmount(item.totalDebit))),
                          DataCell(Text(_formatAmount(item.totalCredit))),
                          DataCell(Text(_formatBalance(item.balance))),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCardList(
    BuildContext context,
    List<_CustomerSummary> customers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < customers.length; index++) ...<Widget>[
          if (index != 0) const SizedBox(height: 10),
          _buildSummaryListCard(context, customers[index]),
        ],
      ],
    );
  }

  Widget _buildSummaryListCard(BuildContext context, _CustomerSummary item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final balanceColor = item.balance >= 0
        ? colorScheme.primary
        : colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  item.customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Page ${item.pageNo.isEmpty ? '-' : item.pageNo}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSummaryAmountStrip(
            context,
            debit: _formatAmount(item.totalDebit),
            credit: _formatAmount(item.totalCredit),
            balance: _formatBalance(item.balance),
            balanceColor: balanceColor,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAmountStrip(
    BuildContext context, {
    required String debit,
    required String credit,
    required String balance,
    required Color balanceColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SummaryStripItem(
              label: 'Debit',
              value: debit,
              color: colorScheme.primary,
            ),
          ),
          _summaryStripDivider(context),
          Expanded(
            child: _SummaryStripItem(
              label: 'Credit',
              value: credit,
              color: colorScheme.secondary,
            ),
          ),
          _summaryStripDivider(context),
          Expanded(
            child: _SummaryStripItem(
              label: 'Balance',
              value: balance,
              color: balanceColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStripDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  List<_CustomerSummary> _filteredCustomers() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _summaryData.customers;
    }
    return _summaryData.customers
        .where(
          (_CustomerSummary item) =>
              item.customer.name.trim().toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
}

class _SummaryStripItem extends StatelessWidget {
  const _SummaryStripItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollIntent extends Intent {
  const _ScrollIntent(this.delta);

  final double delta;
}

class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _SummaryData {
  const _SummaryData({
    required this.customers,
    required this.overallDebit,
    required this.overallCredit,
  });

  const _SummaryData.empty()
    : customers = const <_CustomerSummary>[],
      overallDebit = 0,
      overallCredit = 0;

  final List<_CustomerSummary> customers;
  final double overallDebit;
  final double overallCredit;

  double get finalBalance => overallDebit - overallCredit;
}

class _CustomerSummary {
  const _CustomerSummary({
    required this.customer,
    required this.pageNo,
    required this.totalDebit,
    required this.totalCredit,
  });

  final Customer customer;
  final String pageNo;
  final double totalDebit;
  final double totalCredit;

  double get balance => totalDebit - totalCredit;
}
