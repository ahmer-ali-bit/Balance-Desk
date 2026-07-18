import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../models/customer.dart';
import '../models/entry.dart';
import '../models/snapshot_opening_balance.dart';
import '../models/summary_snapshot.dart';
import '../providers/customer_provider.dart';
import '../providers/ledger_provider.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../utils/app_colors.dart';
import '../utils/number_format_utils.dart' as number_format_utils;
import '../utils/platform_helper.dart';
import '../widgets/amount_input_field.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/decimal_text_input_formatter.dart';
import '../widgets/scale_down_width.dart';

enum _ExportChoice { pdf, excel }

enum _LedgerShortcut { addEntry, export, print, goBack }

enum _LedgerAppBarAction { export, print, editCustomer, filterAndBalance }

class _LedgerIntent extends Intent {
  const _LedgerIntent(this.action);

  final _LedgerShortcut action;
}

class _ScrollIntent extends Intent {
  const _ScrollIntent(this.delta);

  final double delta;
}

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({
    super.key,
    required this.customer,
    this.autoOpenAddEntry = true,
  });

  final Customer customer;
  final bool autoOpenAddEntry;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LedgerProvider>(
      create: (_) => LedgerProvider(customer: customer)..loadEntries(),
      child: _LedgerView(
        customer: customer,
        autoOpenAddEntry: autoOpenAddEntry,
      ),
    );
  }
}

class _LedgerView extends StatefulWidget {
  const _LedgerView({required this.customer, required this.autoOpenAddEntry});

  final Customer customer;
  final bool autoOpenAddEntry;

  @override
  State<_LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends State<_LedgerView> {
  final PdfService _pdfService = const PdfService();
  final ExportService _exportService = const ExportService();
  final ScrollController _tableVerticalController = ScrollController();
  final TextEditingController _openingDebitController = TextEditingController();
  final TextEditingController _openingCreditController =
      TextEditingController();
  final TextEditingController _openingBuyBagsController =
      TextEditingController();
  final TextEditingController _openingSellBagsController =
      TextEditingController();
  final FocusNode _openingDebitFocusNode = FocusNode();
  final FocusNode _openingCreditFocusNode = FocusNode();
  final FocusNode _openingBuyBagsFocusNode = FocusNode();
  final FocusNode _openingSellBagsFocusNode = FocusNode();
  String _lastOpeningBalanceSignature = '';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _didAutoOpenAddEntry = false;
  Timer? _obDebounceTimer;

  @override
  void initState() {
    super.initState();
    // Feature 3: Auto-open Add Entry dialog when ledger opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didAutoOpenAddEntry || !widget.autoOpenAddEntry) return;
      _didAutoOpenAddEntry = true;
      final canEdit = true;
      if (canEdit) {
        _showAddEntryDialog();
      }
    });
  }

  @override
  void dispose() {
    _tableVerticalController.dispose();
    _openingDebitController.dispose();
    _openingCreditController.dispose();
    _openingBuyBagsController.dispose();
    _openingSellBagsController.dispose();
    _openingDebitFocusNode.dispose();
    _openingCreditFocusNode.dispose();
    _openingBuyBagsFocusNode.dispose();
    _openingSellBagsFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showAddEntryDialog() async {
    final customerId = widget.customer.id;
    final provider = context.read<LedgerProvider>();
    final draft = await showDialog<_EntryDraft>(
      context: context,
      builder: (BuildContext dialogContext) => ChangeNotifierProvider.value(
        value: provider,
        child: _AddEntryDialog(
          customerId: customerId,
          isStockLedger: provider.isStockLedger,
        ),
      ),
    );

    if (!mounted || draft == null) {
      return;
    }

    final isSaved = provider.isStockLedger
        ? await provider.addStockEntry(
            entryDate: draft.entryDate,
            pageNo: draft.pageNo,
            description: draft.description,
            buyAmount: draft.debit,
            sellAmount: draft.credit,
            buyBags: draft.buyBags,
            sellBags: draft.sellBags,
          )
        : await provider.addEntry(
            entryDate: draft.entryDate,
            pageNo: draft.pageNo,
            description: draft.description,
            debit: draft.debit,
            credit: draft.credit,
          );

    if (!mounted) {
      return;
    }

    final message = isSaved
        ? 'Entry saved successfully.'
        : (provider.errorMessage ?? 'Unable to save entry.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showEditEntryDialog(Entry entry) async {
    final provider = context.read<LedgerProvider>();
    final isStockLedger = provider.isStockLedger;
    final draft = await showDialog<_EntryDraft>(
      context: context,
      builder: (BuildContext dialogContext) => ChangeNotifierProvider.value(
        value: provider,
        child: _EditEntryDialog(entry: entry, isStockLedger: isStockLedger),
      ),
    );

    if (!mounted || draft == null) {
      return;
    }

    final isUpdated = provider.isStockLedger
        ? await provider.updateStockEntry(
            entry: entry,
            entryDate: draft.entryDate,
            pageNo: draft.pageNo,
            description: draft.description,
            buyAmount: draft.debit,
            sellAmount: draft.credit,
            buyBags: draft.buyBags,
            sellBags: draft.sellBags,
          )
        : await provider.updateEntry(
            entry: entry,
            entryDate: draft.entryDate,
            pageNo: draft.pageNo,
            description: draft.description,
            debit: draft.debit,
            credit: draft.credit,
          );

    if (!mounted) {
      return;
    }

    final message = isUpdated
        ? 'Entry updated successfully.'
        : (provider.errorMessage ?? 'Unable to update entry.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDeleteEntry(Entry entry) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete Entry'),
              content: const Text(
                'Are you sure you want to delete this entry?',
              ),
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

    final provider = context.read<LedgerProvider>();
    final isDeleted = await provider.deleteEntry(entry);

    if (!mounted) {
      return;
    }

    final message = isDeleted
        ? 'Entry deleted successfully.'
        : (provider.errorMessage ?? 'Unable to delete entry.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addEntryToDailyLog(LedgerProvider provider, Entry entry) async {
    if (entry.id == null) return;
    try {
      // 1. Fetch saved snapshots
      final snapshotRows = await AppDatabase.instance.getSummarySnapshots();
      final snapshots =
          snapshotRows
              .map<SummarySnapshot>((row) => SummarySnapshot.fromMap(row))
              .toList()
            ..sort((a, b) => b.savedAt.compareTo(a.savedAt)); // Newest first

      if (!mounted) return;

      if (snapshots.isEmpty) {
        // If there are no saved snapshots, add directly to daily log
        await AppDatabase.instance.updateEntryDailyLogVisibility(
          entryId: entry.id!,
          show: true,
        );
        await provider.loadEntries();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry added to Daily Logs')),
        );
        return;
      }

      // 2. Show choice dialog
      final choice = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Add to Daily Logs'),
            content: const Text(
              'Do you want to add this entry to the current active Daily Log, or do you want to add it into a previously saved snapshot?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop('cancel'),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('active'),
                child: const Text('Current Daily Log'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop('snapshot'),
                child: const Text('Saved Snapshot'),
              ),
            ],
          );
        },
      );

      if (!mounted || choice == null || choice == 'cancel') return;

      if (choice == 'active') {
        // Option 1: Add to current daily log
        await AppDatabase.instance.updateEntryDailyLogVisibility(
          entryId: entry.id!,
          show: true,
        );
        await provider.loadEntries();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry added to Daily Logs')),
        );
      } else if (choice == 'snapshot') {
        // Option 2: Add to a specific saved snapshot
        if (!mounted) return;

        final selectedSnapshot = await showDialog<SummarySnapshot>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Select Saved Snapshot'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: snapshots.length,
                  itemBuilder: (BuildContext context, int index) {
                    final snapshot = snapshots[index];
                    final dateStr = snapshot.savedAt.split('T')[0];
                    final timeParts = snapshot.savedAt.split('T')[1].split(':');
                    final timeStr = '${timeParts[0]}:${timeParts[1]}';
                    final pageNo = snapshot.dailyLogPageNo;
                    final pageSuffix = pageNo.isNotEmpty
                        ? ' (Page: $pageNo)'
                        : '';
                    return ListTile(
                      leading: const Icon(Icons.history_toggle_off),
                      title: Text('$dateStr $timeStr$pageSuffix'),
                      subtitle: Text(
                        'Debit: ${provider.formatAmount(snapshot.overallDebit)} | Credit: ${provider.formatAmount(snapshot.overallCredit)}',
                      ),
                      onTap: () {
                        Navigator.of(context).pop(snapshot);
                      },
                    );
                  },
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );

        if (selectedSnapshot == null) return;

        // Perform the update
        await AppDatabase.instance.addEntryToSavedSnapshot(
          entryId: entry.id!,
          savedAt: selectedSnapshot.savedAt,
          dailyLogPageNo: selectedSnapshot.dailyLogPageNo.isNotEmpty
              ? selectedSnapshot.dailyLogPageNo
              : null,
        );

        await provider.loadEntries();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Entry added to the selected Saved Snapshot successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add entry to Daily Logs: $e')),
      );
    }
  }

  void _showEntryMenu(
    BuildContext context,
    LedgerProvider provider,
    Entry entry,
  ) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 16,
                    left: 24,
                    right: 24,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.tune_rounded, color: colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Entry Actions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                if (true) ...[
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: const Text(
                      'Edit Entry',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showEditEntryDialog(entry);
                    },
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    title: const Text(
                      'Transfer to another customer',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _showTransferDialog(provider, entry);
                    },
                  ),
                  if (!entry.showInDailyLog)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.playlist_add_rounded,
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                      title: const Text(
                        'Add to Daily Log',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _addEntryToDailyLog(provider, entry);
                      },
                    ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                    title: Text(
                      'Delete Entry',
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _confirmDeleteEntry(entry);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditCustomerDialog(LedgerProvider provider) async {
    final draft = await showDialog<_CustomerProfileDraft>(
      context: context,
      builder: (BuildContext context) {
        return _EditCustomerDialog(
          initialName: provider.customerName,
          initialAddress: provider.customer.address,
          initialPhone: provider.customer.phone,
        );
      },
    );

    if (!mounted || draft == null) {
      return;
    }

    final isUpdated = await _updateCustomerDetails(provider, draft);
    if (!mounted) {
      return;
    }

    final customerProvider = context.read<CustomerProvider>();
    if (isUpdated) {
      await customerProvider.loadCustomers();

      if (!mounted) {
        return;
      }
    }

    final message = isUpdated
        ? 'Customer details updated successfully.'
        : (provider.errorMessage ?? 'Unable to update customer details.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _updateCustomerDetails(
    LedgerProvider provider,
    _CustomerProfileDraft draft,
  ) async {
    final dynamic dynamicProvider = provider;

    try {
      final result = await dynamicProvider.updateCustomerNameWithDetails(
        draft.name,
        draft.address,
        draft.phone,
      );
      return result == true;
    } catch (_) {}

    try {
      final result = await dynamicProvider.updateCustomerProfile(
        name: draft.name,
        address: draft.address,
        phone: draft.phone,
      );
      return result == true;
    } catch (_) {}

    try {
      final result = await dynamicProvider.updateCustomerName(
        draft.name,
        address: draft.address,
        phone: draft.phone,
      );
      return result == true;
    } catch (_) {}

    return false;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatStoredDate(String value) {
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate == null) {
      return value;
    }
    return _formatDate(parsedDate);
  }

  String _shortActiveFilterLabel(LedgerProvider provider) {
    return switch (provider.activeFilter) {
      LedgerDateFilter.all => 'All',
      LedgerDateFilter.today => 'Today',
      LedgerDateFilter.thisWeek => 'This Week',
      LedgerDateFilter.thisMonth => 'This Month',
      LedgerDateFilter.customRange => 'Custom Range',
    };
  }

  String _buildExportFileName(String customerName, String suffix, String ext) {
    final safeName = customerName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final base = safeName.isEmpty ? 'customer' : safeName;
    return '${base}_$suffix.$ext';
  }

  Future<void> _exportPdf() async {
    final provider = context.read<LedgerProvider>();
    if (provider.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add entries before exporting the ledger.'),
        ),
      );
      return;
    }

    try {
      await _pdfService.exportCustomerLedgerPdf(
        customer: provider.customer,
        entries: provider.entries,
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

  Future<void> _exportExcel() async {
    final provider = context.read<LedgerProvider>();
    if (provider.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add entries before exporting the ledger.'),
        ),
      );
      return;
    }

    final rows = <List<String>>[];
    double? runningBalance;
    for (final entry in provider.entries) {
      final debit = entry.debit;
      final credit = entry.credit;
      final hasValue = debit != 0 || credit != 0;
      final currentBalance = hasValue
          ? (runningBalance ?? 0) + debit - credit
          : runningBalance;
      runningBalance = currentBalance;

      rows.add(<String>[
        _formatStoredDate(entry.entryDate),
        _formatStoredDate(entry.createdAt),
        entry.pageNo.isEmpty ? '-' : entry.pageNo,
        entry.displayDescription,
        provider.formatAmount(debit),
        provider.formatAmount(credit),
        currentBalance == null ? '' : provider.formatBalance(currentBalance),
      ]);
    }

    final fileName = _buildExportFileName(
      provider.customer.name,
      'ledger',
      'csv',
    );

    try {
      await _exportService.saveCsv(
        dialogTitle: 'Export Ledger (Excel)',
        fileName: fileName,
        headers: const <String>[
          'Entry Date',
          'Created Date',
          'Page No',
          'Description',
          'Debit',
          'Credit',
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

  Future<void> _exportWithOptions() async {
    final choice = await showDialog<_ExportChoice>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Export Ledger'),
          content: const Text('Choose an export format.'),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExportChoice.excel),
              child: const Text('Excel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ExportChoice.pdf),
              child: const Text('PDF'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == _ExportChoice.pdf) {
      await _exportPdf();
    } else {
      await _exportExcel();
    }
  }

  Future<void> _printPdf() async {
    final provider = context.read<LedgerProvider>();
    if (provider.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add entries before printing the ledger.'),
        ),
      );
      return;
    }

    try {
      await _pdfService.printCustomerLedgerPdf(
        customer: provider.customer,
        entries: provider.entries,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the print dialog right now.'),
        ),
      );
    }
  }

  double? _parseOpeningBalanceValue(String value, {bool asWeight = false}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    if (asWeight && trimmed.contains('-')) {
      return number_format_utils.parseWeight(trimmed);
    }
    return double.tryParse(trimmed);
  }

  bool _amountEquals(double first, double second) {
    return (first - second).abs() < 0.0001;
  }

  String _openingBalanceSignature(
    double debit,
    double credit, [
    double buyBags = 0,
    double sellBags = 0,
  ]) {
    return '${debit.toStringAsFixed(2)}|${credit.toStringAsFixed(2)}|'
        '${buyBags.toStringAsFixed(2)}|${sellBags.toStringAsFixed(2)}';
  }

  SnapshotOpeningBalance _readOpeningBalance(LedgerProvider provider) {
    final dynamic dynamicProvider = provider;

    try {
      final value = dynamicProvider.openingBalance;
      if (value is SnapshotOpeningBalance) {
        return value;
      }
    } catch (_) {}

    return SnapshotOpeningBalance(debit: 0, credit: 0);
  }

  Future<bool> _saveProviderOpeningBalance(
    LedgerProvider provider, {
    required double debit,
    required double credit,
    double buyBags = 0,
    double sellBags = 0,
  }) async {
    final dynamic dynamicProvider = provider;

    try {
      final result = await dynamicProvider.setOpeningBalance(
        debit: debit,
        credit: credit,
        buyBags: buyBags,
        sellBags: sellBags,
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  bool _isOpeningBalanceEntry(LedgerProvider provider, Entry entry) {
    final dynamic dynamicProvider = provider;

    try {
      return dynamicProvider.isOpeningBalanceEntry(entry) == true;
    } catch (_) {
      return entry.id == null &&
          entry.entryDate == '-' &&
          entry.createdAt == '-' &&
          entry.description.trim().toLowerCase() == 'opening balance';
    }
  }

  void _restoreOpeningBalanceDraft(LedgerProvider provider) {
    final openingBalance = _readOpeningBalance(provider);
    final debitText = openingBalance.debit == 0
        ? ''
        : provider.formatAmount(openingBalance.debit);
    final creditText = openingBalance.credit == 0
        ? ''
        : provider.formatAmount(openingBalance.credit);
    final buyBagsText = openingBalance.buyBags == 0
        ? ''
        : (provider.useWeight
              ? number_format_utils.formatWeight(openingBalance.buyBags)
              : number_format_utils.formatAmount(openingBalance.buyBags));
    final sellBagsText = openingBalance.sellBags == 0
        ? ''
        : (provider.useWeight
              ? number_format_utils.formatWeight(openingBalance.sellBags)
              : number_format_utils.formatAmount(openingBalance.sellBags));

    _openingDebitController.text = debitText;
    _openingCreditController.text = creditText;
    _openingBuyBagsController.text = buyBagsText;
    _openingSellBagsController.text = sellBagsText;

    _lastOpeningBalanceSignature = _openingBalanceSignature(
      openingBalance.debit,
      openingBalance.credit,
      openingBalance.buyBags,
      openingBalance.sellBags,
    );
  }

  void _syncOpeningBalanceControllers(LedgerProvider provider) {
    final openingBalance = _readOpeningBalance(provider);
    final signature = _openingBalanceSignature(
      openingBalance.debit,
      openingBalance.credit,
      openingBalance.buyBags,
      openingBalance.sellBags,
    );
    final isEditing =
        _openingDebitFocusNode.hasFocus ||
        _openingCreditFocusNode.hasFocus ||
        _openingBuyBagsFocusNode.hasFocus ||
        _openingSellBagsFocusNode.hasFocus;
    final debitText = openingBalance.debit == 0
        ? ''
        : provider.formatAmount(openingBalance.debit);
    final creditText = openingBalance.credit == 0
        ? ''
        : provider.formatAmount(openingBalance.credit);
    final buyBagsText = openingBalance.buyBags == 0
        ? ''
        : (provider.useWeight
              ? number_format_utils.formatWeight(openingBalance.buyBags)
              : number_format_utils.formatAmount(openingBalance.buyBags));
    final sellBagsText = openingBalance.sellBags == 0
        ? ''
        : (provider.useWeight
              ? number_format_utils.formatWeight(openingBalance.sellBags)
              : number_format_utils.formatAmount(openingBalance.sellBags));

    final matchesController =
        _openingDebitController.text == debitText &&
        _openingCreditController.text == creditText &&
        _openingBuyBagsController.text == buyBagsText &&
        _openingSellBagsController.text == sellBagsText;

    if (isEditing ||
        (_lastOpeningBalanceSignature == signature && matchesController)) {
      return;
    }

    _openingDebitController.text = debitText;
    _openingCreditController.text = creditText;
    _openingBuyBagsController.text = buyBagsText;
    _openingSellBagsController.text = sellBagsText;
    _lastOpeningBalanceSignature = signature;
  }

  void _debounceOpeningBalanceUpdate() {
    _obDebounceTimer?.cancel();
    _obDebounceTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() {});
    });
  }

  bool _hasOpeningBalanceDraftChanged(LedgerProvider provider) {
    final debit = _parseOpeningBalanceValue(_openingDebitController.text);
    final credit = _parseOpeningBalanceValue(_openingCreditController.text);
    final useWt = provider.useWeight;
    final buyBags = _parseOpeningBalanceValue(
      _openingBuyBagsController.text,
      asWeight: useWt,
    );
    final sellBags = _parseOpeningBalanceValue(
      _openingSellBagsController.text,
      asWeight: useWt,
    );

    final openingBalance = _readOpeningBalance(provider);

    if (debit == null ||
        credit == null ||
        buyBags == null ||
        sellBags == null) {
      return false;
    }

    return !_amountEquals(debit, openingBalance.debit) ||
        !_amountEquals(credit, openingBalance.credit) ||
        !_amountEquals(buyBags, openingBalance.buyBags) ||
        !_amountEquals(sellBags, openingBalance.sellBags);
  }

  Future<void> _saveOpeningBalance() async {
    FocusScope.of(context).unfocus();

    final debit = _parseOpeningBalanceValue(_openingDebitController.text);
    final credit = _parseOpeningBalanceValue(_openingCreditController.text);
    final provider = context.read<LedgerProvider>();
    final useWt = provider.useWeight;
    final buyBags = _parseOpeningBalanceValue(
      _openingBuyBagsController.text,
      asWeight: useWt,
    );
    final sellBags = _parseOpeningBalanceValue(
      _openingSellBagsController.text,
      asWeight: useWt,
    );

    if (debit == null ||
        credit == null ||
        buyBags == null ||
        sellBags == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid opening balance values.')),
      );
      return;
    }

    final isSaved = await _saveProviderOpeningBalance(
      provider,
      debit: debit,
      credit: credit,
      buyBags: buyBags,
      sellBags: sellBags,
    );

    if (!mounted) {
      return;
    }

    final message = isSaved
        ? (debit == 0 && credit == 0
              ? 'Opening balance cleared.'
              : 'Opening balance saved successfully.')
        : (provider.errorMessage ?? 'Unable to save opening balance.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearOpeningBalance(LedgerProvider provider) async {
    final openingBalance = _readOpeningBalance(provider);
    if (!openingBalance.hasValue) {
      return;
    }

    FocusScope.of(context).unfocus();

    final shouldClear =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Clear Opening Balance'),
              content: const Text(
                'Reset the opening balance to zero for this customer ledger?',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Clear'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldClear || !mounted) {
      return;
    }

    final isCleared = await _saveProviderOpeningBalance(
      provider,
      debit: 0,
      credit: 0,
    );

    if (!mounted) {
      return;
    }

    if (isCleared) {
      _openingDebitController.clear();
      _openingCreditController.clear();
      _openingBuyBagsController.clear();
      _openingSellBagsController.clear();
      _lastOpeningBalanceSignature = _openingBalanceSignature(0, 0, 0, 0);
      setState(() {});
    }

    final message = isCleared
        ? 'Opening balance cleared.'
        : (provider.errorMessage ?? 'Unable to clear opening balance.');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _handleAppBarAction(
    _LedgerAppBarAction action, {
    required LedgerProvider provider,
  }) async {
    switch (action) {
      case _LedgerAppBarAction.export:
        await _exportWithOptions();
        break;
      case _LedgerAppBarAction.print:
        await _printPdf();
        break;
      case _LedgerAppBarAction.editCustomer:
        if (true) {
          await _showEditCustomerDialog(provider);
        }
        break;
      case _LedgerAppBarAction.filterAndBalance:
        _scaffoldKey.currentState?.openEndDrawer();
        break;
    }
  }

  List<Widget> _buildAppBarActions({
    required BuildContext context,
    required LedgerProvider provider,
    required bool isCompact,
  }) {
    final hasEntries = provider.entries.isNotEmpty;
    if (isCompact) {
      return <Widget>[
        IconButton(
          tooltip: 'Refresh ledger',
          onPressed: provider.isLoading ? null : provider.loadEntries,
          icon: const Icon(Icons.refresh_rounded),
        ),
        PopupMenuButton<_LedgerAppBarAction>(
          tooltip: 'More actions',
          onSelected: (_LedgerAppBarAction action) {
            unawaited(_handleAppBarAction(action, provider: provider));
          },
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<_LedgerAppBarAction>>[
                PopupMenuItem<_LedgerAppBarAction>(
                  value: _LedgerAppBarAction.export,
                  enabled: hasEntries,
                  child: _buildAppBarMenuItem(
                    context,
                    icon: Icons.file_download_outlined,
                    label: 'Export',
                  ),
                ),
                PopupMenuItem<_LedgerAppBarAction>(
                  value: _LedgerAppBarAction.print,
                  enabled: hasEntries,
                  child: _buildAppBarMenuItem(
                    context,
                    icon: Icons.print_outlined,
                    label: 'Print',
                  ),
                ),
                if (true)
                  PopupMenuItem<_LedgerAppBarAction>(
                    value: _LedgerAppBarAction.editCustomer,
                    child: _buildAppBarMenuItem(
                      context,
                      icon: Icons.edit_outlined,
                      label: 'Edit Customer',
                    ),
                  ),
                PopupMenuItem<_LedgerAppBarAction>(
                  value: _LedgerAppBarAction.filterAndBalance,
                  child: _buildAppBarMenuItem(
                    context,
                    icon: Icons.tune_rounded,
                    label: 'Menu',
                  ),
                ),
              ],
        ),
        const SizedBox(width: 4),
      ];
    }

    final maxWidth = math.min(MediaQuery.sizeOf(context).width * 0.72, 540.0);

    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: provider.isLoading ? null : provider.loadEntries,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: hasEntries ? _exportWithOptions : null,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: hasEntries ? _printPdf : null,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('Menu'),
                ),
                if (true) ...[
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _showAddEntryDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Entry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildAppBarMenuItem(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildFilterBar({
    required BuildContext context,
    required LedgerProvider provider,
    bool compactForDesktop = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final containerPadding = compactForDesktop ? 10.0 : 12.0;
    final headerIconSize = compactForDesktop ? 32.0 : 38.0;
    final headerIconRadius = compactForDesktop ? 12.0 : 14.0;
    final headerIconInnerSize = compactForDesktop ? 16.0 : 18.0;
    final verticalGap = compactForDesktop ? 6.0 : 8.0;
    final filterSpacing = compactForDesktop ? 6.0 : 8.0;
    final compactActiveLabel = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        _shortActiveFilterLabel(provider),
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surface,
            colorScheme.secondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(containerPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: headerIconSize,
                  height: headerIconSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        colorScheme.primary.withValues(alpha: 0.18),
                        colorScheme.tertiary.withValues(alpha: 0.14),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(headerIconRadius),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: colorScheme.primary,
                    size: headerIconInnerSize,
                  ),
                ),
                SizedBox(width: compactForDesktop ? 8 : 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Date Filters',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (compactForDesktop) ...<Widget>[
                  const SizedBox(width: 8),
                  compactActiveLabel,
                ],
              ],
            ),
            SizedBox(height: verticalGap),
            ScaleDownWidth(
              designWidth: compactForDesktop ? 560 : 620,
              child: Wrap(
                spacing: filterSpacing,
                runSpacing: filterSpacing,
                children: <Widget>[
                  if (PlatformHelper.isDesktop)
                    _buildFilterChip(
                      context: context,
                      label: 'All',
                      icon: Icons.view_list_rounded,
                      isSelected: provider.activeFilter == LedgerDateFilter.all,
                      onSelected: (_) =>
                          provider.applyFilter(LedgerDateFilter.all),
                      compact: compactForDesktop,
                    ),
                  _buildFilterChip(
                    context: context,
                    label: 'Today',
                    icon: Icons.today_rounded,
                    isSelected: provider.activeFilter == LedgerDateFilter.today,
                    onSelected: (_) =>
                        provider.applyFilter(LedgerDateFilter.today),
                    compact: compactForDesktop,
                  ),
                  _buildFilterChip(
                    context: context,
                    label: 'This Week',
                    icon: Icons.date_range_rounded,
                    isSelected:
                        provider.activeFilter == LedgerDateFilter.thisWeek,
                    onSelected: (_) =>
                        provider.applyFilter(LedgerDateFilter.thisWeek),
                    compact: compactForDesktop,
                  ),
                  _buildFilterChip(
                    context: context,
                    label: 'This Month',
                    icon: Icons.calendar_month_rounded,
                    isSelected:
                        provider.activeFilter == LedgerDateFilter.thisMonth,
                    onSelected: (_) =>
                        provider.applyFilter(LedgerDateFilter.thisMonth),
                    compact: compactForDesktop,
                  ),
                  _buildFilterChip(
                    context: context,
                    label: 'Custom Range',
                    icon: Icons.timeline_rounded,
                    isSelected:
                        provider.activeFilter == LedgerDateFilter.customRange,
                    onSelected: (_) => _pickCustomRange(provider),
                    compact: compactForDesktop,
                  ),
                ],
              ),
            ),
            if (!compactForDesktop) ...<Widget>[
              SizedBox(height: verticalGap),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.insights_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Active filter: ${provider.activeFilterLabel}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOpeningBalanceSection({
    required BuildContext context,
    required LedgerProvider provider,
    bool compactForDesktop = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canEdit = true;
    final readOnly = !canEdit;
    final hasInvalidAmount =
        _parseOpeningBalanceValue(_openingDebitController.text) == null ||
        _parseOpeningBalanceValue(_openingCreditController.text) == null;
    final hasChanges = _hasOpeningBalanceDraftChanged(provider);
    final statusLabel = hasChanges ? 'Unsaved changes' : 'Saved';
    final containerPadding = compactForDesktop ? 10.0 : 12.0;
    final headerIconSize = compactForDesktop ? 34.0 : 40.0;
    final headerIconRadius = compactForDesktop ? 13.0 : 15.0;
    final headerIconInnerSize = compactForDesktop ? 18.0 : 20.0;
    final verticalGap = compactForDesktop ? 8.0 : 10.0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.secondary.withValues(alpha: 0.08),
            colorScheme.surface,
            colorScheme.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(containerPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final headerContent = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: headerIconSize,
                      height: headerIconSize,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            colorScheme.secondary.withValues(alpha: 0.18),
                            colorScheme.primary.withValues(alpha: 0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(headerIconRadius),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: colorScheme.primary,
                        size: headerIconInnerSize,
                      ),
                    ),
                    SizedBox(width: compactForDesktop ? 8 : 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Opening Balance',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                final statusChip = Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compactForDesktop ? 10 : 12,
                    vertical: compactForDesktop ? 6 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );

                if (compactForDesktop) {
                  final compactActions = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.end,
                    children: <Widget>[
                      statusChip,
                      IconButton(
                        tooltip: 'Reset opening balance draft',
                        onPressed: provider.isLoading
                            ? null
                            : () {
                                _restoreOpeningBalanceDraft(provider);
                                setState(() {});
                              },
                        style: IconButton.styleFrom(
                          foregroundColor: colorScheme.onSurfaceVariant,
                          backgroundColor: colorScheme.surface,
                          side: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      ),
                      if (true) ...[
                        IconButton(
                          tooltip: 'Clear opening balance',
                          onPressed: !provider.hasOpeningBalance
                              ? null
                              : () => _clearOpeningBalance(provider),
                          style: IconButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            backgroundColor: colorScheme.surface,
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                        ),
                        IconButton.filled(
                          tooltip: 'Save opening balance',
                          onPressed: hasInvalidAmount || !hasChanges
                              ? null
                              : _saveOpeningBalance,
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                          ),
                          icon: provider.isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 18),
                        ),
                      ],
                    ],
                  );

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: headerContent),
                      const SizedBox(width: 8),
                      Flexible(child: compactActions),
                    ],
                  );
                }

                if (constraints.maxWidth < 430) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      headerContent,
                      const SizedBox(height: 10),
                      statusChip,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: headerContent),
                    const SizedBox(width: 10),
                    statusChip,
                  ],
                );
              },
            ),
            if (!compactForDesktop) ...<Widget>[
              SizedBox(height: verticalGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: provider.isLoading
                        ? null
                        : () {
                            _restoreOpeningBalanceDraft(provider);
                            setState(() {});
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset'),
                  ),
                  TextButton.icon(
                    onPressed:
                        readOnly ||
                            provider.isLoading ||
                            !_readOpeningBalance(provider).hasValue ||
                            !true
                        ? null
                        : () => _clearOpeningBalance(provider),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        readOnly ||
                            provider.isLoading ||
                            hasInvalidAmount ||
                            !hasChanges ||
                            !true
                        ? null
                        : _saveOpeningBalance,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    icon: provider.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
            SizedBox(height: verticalGap),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final isStock = provider.isStockLedger;

                Widget buildDebitField() => _buildOpeningBalanceField(
                  context: context,
                  controller: _openingDebitController,
                  focusNode: _openingDebitFocusNode,
                  label: isStock
                      ? 'Buy Amount Opening'
                      : 'Debit Opening Balance',
                  icon: Icons.arrow_downward_rounded,
                  accentColor: isStock ? AppColors.credit : AppColors.debit,
                  readOnly: readOnly,
                  compact: compactForDesktop,
                );

                Widget buildCreditField() => _buildOpeningBalanceField(
                  context: context,
                  controller: _openingCreditController,
                  focusNode: _openingCreditFocusNode,
                  label: isStock
                      ? 'Sell Amount Opening'
                      : 'Credit Opening Balance',
                  icon: Icons.arrow_upward_rounded,
                  accentColor: isStock ? AppColors.debit : AppColors.credit,
                  readOnly: readOnly,
                  compact: compactForDesktop,
                );

                Widget buildBuyBagsField() => _buildOpeningBalanceField(
                  context: context,
                  controller: _openingBuyBagsController,
                  focusNode: _openingBuyBagsFocusNode,
                  label: provider.useWeight ? 'Buy Wt Opening' : 'Buy Opening',
                  icon: Icons.shopping_bag_outlined,
                  accentColor: isStock ? AppColors.credit : AppColors.debit,
                  readOnly: readOnly,
                  compact: compactForDesktop,
                  isWeight: provider.useWeight,
                );

                Widget buildSellBagsField() => _buildOpeningBalanceField(
                  context: context,
                  controller: _openingSellBagsController,
                  focusNode: _openingSellBagsFocusNode,
                  label: provider.useWeight
                      ? 'Sell Wt Opening'
                      : 'Sell Opening',
                  icon: Icons.sell_outlined,
                  accentColor: isStock ? AppColors.debit : AppColors.credit,
                  readOnly: readOnly,
                  compact: compactForDesktop,
                  isWeight: provider.useWeight,
                );

                if (constraints.maxWidth < 600) {
                  return Column(
                    children: <Widget>[
                      if (isStock) ...[
                        buildBuyBagsField(),
                        const SizedBox(height: 10),
                        buildSellBagsField(),
                        const SizedBox(height: 10),
                      ],
                      buildDebitField(),
                      const SizedBox(height: 10),
                      buildCreditField(),
                    ],
                  );
                }

                return Column(
                  children: [
                    if (isStock) ...[
                      Row(
                        children: [
                          Expanded(child: buildBuyBagsField()),
                          SizedBox(width: compactForDesktop ? 8 : 10),
                          Expanded(child: buildSellBagsField()),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: <Widget>[
                        Expanded(child: buildDebitField()),
                        SizedBox(width: compactForDesktop ? 8 : 10),
                        Expanded(child: buildCreditField()),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpeningBalanceField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required Color accentColor,
    required bool readOnly,
    bool compact = false,
    bool isWeight = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: isWeight
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : const TextInputType.numberWithOptions(decimal: true),
      scrollPadding: const EdgeInsets.only(bottom: 180),
      readOnly: readOnly,
      inputFormatters: <TextInputFormatter>[
        if (isWeight)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))
        else
          DecimalTextInputFormatter(decimalRange: 2),
      ],
      onChanged: readOnly
          ? null
          : (_) {
              _debounceOpeningBalanceUpdate();
            },
      decoration: InputDecoration(
        isDense: compact,
        labelText: label,
        hintText: '0',
        filled: true,
        fillColor: colorScheme.surface.withValues(alpha: 0.88),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 10 : 14,
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.all(compact ? 6 : 7),
          child: Container(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: compact ? 42 : 48,
          minHeight: compact ? 42 : 48,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(color: accentColor, width: 1.3),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLedgerOverview(
    BuildContext context,
    LedgerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customer = provider.customer;
    final displayBalance = provider.isStockLedger
        ? -provider.finalBalance
        : provider.finalBalance;
    final balanceAccent = AppColors.balanceColor(displayBalance);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Total',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(spacing: 8, runSpacing: 8, children: <Widget>[]),
                  ],
                ),
              ),
              if (true)
                IconButton.filledTonal(
                  tooltip: 'Edit customer details',
                  onPressed: () => _showEditCustomerDialog(provider),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (provider.isStockLedger) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = (constraints.maxWidth - 20) / 3;
                return Column(
                  spacing: 10,
                  children: <Widget>[
                    Row(
                      spacing: 10,
                      children: <Widget>[
                        SizedBox(
                          width: itemWidth,
                          child: _buildMobileOverviewMetric(
                            context,
                            label: provider.useWeight ? 'Buy Wt' : 'Buy Qty',
                            value: provider.formatBags(provider.totalBuyBags),
                            accentColor: AppColors.credit,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildMobileOverviewMetric(
                            context,
                            label: provider.useWeight ? 'Sell Wt' : 'Sell Qty',
                            value: provider.formatBags(provider.totalSellBags),
                            accentColor: AppColors.debit,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildMobileOverviewMetric(
                            context,
                            label: provider.useWeight ? 'Rem. Wt' : 'Remaining',
                            value: provider.formatBags(
                              provider.finalRemainingBags,
                            ),
                            accentColor: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      spacing: 10,
                      children: <Widget>[
                        SizedBox(
                          width: itemWidth,
                          child: _buildMobileOverviewMetric(
                            context,
                            label: 'Buy Amt',
                            value: provider.formatAmount(provider.totalDebit),
                            accentColor: AppColors.credit,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildMobileOverviewMetric(
                            context,
                            label: 'Sell Amt',
                            value: provider.formatAmount(provider.totalCredit),
                            accentColor: AppColors.debit,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _buildMobileOverviewMetric(
                            context,
                            label: 'Balance',
                            value: provider.formatBalance(displayBalance),
                            accentColor: balanceAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: balanceAccent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: balanceAccent.withValues(alpha: 0.16),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: balanceAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Net Balance',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: balanceAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        provider.formatBalance(displayBalance),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _buildMobileOverviewMetric(
                    context,
                    label: 'Debit',
                    value: provider.formatAmount(provider.totalDebit),
                    accentColor: const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMobileOverviewMetric(
                    context,
                    label: 'Credit',
                    value: provider.formatAmount(provider.totalCredit),
                    accentColor: const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
          ],
          if (customer.displayAddress != '-' ||
              customer.displayPhone != '-') ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (customer.displayAddress != '-')
                  _buildMobileInfoPill(
                    context,
                    icon: Icons.location_on_outlined,
                    label: customer.displayAddress,
                  ),
                if (customer.displayPhone != '-')
                  _buildMobileInfoPill(
                    context,
                    icon: Icons.call_outlined,
                    label: customer.displayPhone,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileOverviewMetric(
    BuildContext context, {
    required String label,
    required String value,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileInfoPill(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfoCard(BuildContext context, LedgerProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customer = provider.customer;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surface,
            colorScheme.surfaceContainerLow,
            colorScheme.secondaryContainer.withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -70,
            right: -30,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -90,
            left: -50,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.secondary.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    const canEdit = true;
                    final editButton = canEdit
                        ? IconButton.filledTonal(
                            tooltip: 'Edit customer details',
                            onPressed: () => _showEditCustomerDialog(provider),
                            style: IconButton.styleFrom(
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.primary,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                          )
                        : null;

                    final titleBlock = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _buildHeroMetaChip(
                              context,
                              icon: Icons.receipt_long_outlined,
                              label: '${provider.entries.length} entries',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              flex: 2,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Total',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              color: colorScheme.onSurface,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 23,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _buildCustomerIdBadge(context, customer.id),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              flex: 3,
                              child: _buildCustomerIdentityBar(
                                context,
                                customer,
                                isCompact: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                    final displayBalance = provider.isStockLedger
                        ? -provider.finalBalance
                        : provider.finalBalance;
                    final balanceAccent = AppColors.balanceColor(
                      displayBalance,
                    );
                    final balanceCard = _buildHeroBalanceCard(
                      context,
                      value: provider.formatBalance(displayBalance),
                      accentColor: balanceAccent,
                      label: 'Balance',
                    );
                    final bagsCard = provider.isStockLedger
                        ? _buildHeroBalanceCard(
                            context,
                            value: provider.finalRemainingBags.toStringAsFixed(
                              0,
                            ),
                            accentColor: colorScheme.primary,
                            label: 'Remaining',
                            icon: Icons.inventory_2_outlined,
                          )
                        : null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleBlock),
                            if (editButton != null) const SizedBox(width: 16),
                            ?editButton,
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            if (bagsCard != null) ...[
                              Expanded(child: bagsCard),
                              const SizedBox(width: 12),
                            ],
                            Expanded(child: balanceCard),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                // Balance Section
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerIdBadge(BuildContext context, int? id) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.2)),
      ),
      child: Text(
        '#${id ?? '-'}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.secondary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCustomerIdentityBar(
    BuildContext context,
    Customer customer, {
    bool isCompact = false,
    bool isFooter = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: (isCompact || isFooter)
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isFooter
            ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.5)
            : isCompact
            ? Colors.transparent
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: isFooter
            ? Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              )
            : isCompact
            ? null
            : Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 500;

          final items = [
            _CustomerIdentityItem(
              icon: Icons.call_outlined,
              label: 'Phone',
              value: customer.displayPhone,
            ),
            _CustomerIdentityItem(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: customer.displayAddress,
              isLast: true,
            ),
          ];

          if (isWide || isCompact) {
            return Row(
              children: [
                Flexible(flex: 2, child: items[0]),
                _buildIdentityDivider(context),
                Flexible(flex: 3, child: items[1]),
              ],
            );
          } else {
            return Column(
              children: [
                items[0],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, thickness: 0.5),
                ),
                items[1],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, thickness: 0.5),
                ),
                items[2],
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildIdentityDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildDesktopLedgerHeader(
    BuildContext context,
    LedgerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customer = provider.customer;

    final metricItems = <({String label, String value})>[
      if (provider.isStockLedger) ...[
        (
          label: provider.useWeight ? 'Buy Wt' : 'Buy Qty',
          value: provider.formatBags(provider.totalBuyBags),
        ),
        (
          label: 'Buy Amount',
          value: provider.formatAmount(provider.totalDebit),
        ),
        (
          label: provider.useWeight ? 'Sell Wt' : 'Sell Qty',
          value: provider.formatBags(provider.totalSellBags),
        ),
        (
          label: 'Sell Amount',
          value: provider.formatAmount(provider.totalCredit),
        ),
        (
          label: provider.useWeight ? 'Rem. Wt' : 'Remaining',
          value: provider.formatBags(provider.finalRemainingBags),
        ),
        (
          label: 'Balance',
          value: provider.formatBalance(
            provider.isStockLedger
                ? -provider.finalBalance
                : provider.finalBalance,
          ),
        ),
      ] else ...[
        (
          label: 'Total Debit',
          value: provider.formatAmount(provider.totalDebit),
        ),
        (
          label: 'Total Credit',
          value: provider.formatAmount(provider.totalCredit),
        ),
        (
          label: 'Balance',
          value: provider.formatBalance(
            provider.isStockLedger
                ? -provider.finalBalance
                : provider.finalBalance,
          ),
        ),
      ],
    ];

    Widget buildTile(
      ({String label, String value}) item,
      bool isMetric, {
      double? maxWidth,
    }) {
      final isDebit =
          item.label == 'Total Debit' ||
          (provider.isStockLedger &&
              (item.label == 'Buy Amount' ||
                  item.label == 'Buy' ||
                  item.label == 'Buy Wt')) ||
          (!provider.isStockLedger &&
              (item.label == 'Sell Amount' ||
                  item.label == 'Sell' ||
                  item.label == 'Sell Wt'));
      final isCredit =
          item.label == 'Total Credit' ||
          (provider.isStockLedger &&
              (item.label == 'Sell Amount' ||
                  item.label == 'Sell' ||
                  item.label == 'Sell Wt')) ||
          (!provider.isStockLedger &&
              (item.label == 'Buy Amount' ||
                  item.label == 'Buy' ||
                  item.label == 'Buy Wt'));
      final isBalance = item.label == 'Balance';
      final isBags = item.label == 'Remaining';

      final displayBalance = provider.isStockLedger
          ? -provider.finalBalance
          : provider.finalBalance;
      final balanceColor = AppColors.balanceColor(displayBalance);

      final bgColor = isDebit
          ? (provider.isStockLedger ? AppColors.credit : AppColors.debit)
          : isCredit
          ? (provider.isStockLedger ? AppColors.debit : AppColors.credit)
          : isBags
          ? colorScheme.primary
          : isBalance
          ? (balanceColor == AppColors.debit
                ? AppColors.debit
                : (balanceColor == AppColors.credit
                      ? AppColors.credit
                      : Colors.grey.shade600))
          : colorScheme.surface;

      return _CustomerInfoTile(
        label: item.label,
        value: item.value,
        backgroundColor: bgColor,
        labelColor: isMetric ? Colors.white70 : colorScheme.onSurfaceVariant,
        valueColor: isMetric ? Colors.white : colorScheme.onSurface,
        borderColor: isMetric ? Colors.transparent : colorScheme.outlineVariant,
        isMetric: isMetric,
        maxWidth: maxWidth,
      );
    }

    final canEdit = true;
    final editButton = canEdit
        ? IconButton.filledTonal(
            tooltip: 'Edit customer details',
            onPressed: () => _showEditCustomerDialog(provider),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.primary,
            ),
            icon: const Icon(Icons.edit_outlined),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Row 1: Name, Info Cards, and Edit Icon
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    flex: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              provider.customerName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildCustomerIdBadge(context, customer.id),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 3,
                    child: _buildCustomerIdentityBar(
                      context,
                      customer,
                      isCompact: true,
                    ),
                  ),
                ],
              ),
            ),
            if (editButton != null) const SizedBox(width: 16),
            ?editButton,
          ],
        ),
        const SizedBox(height: 20),
        // Row 2: Metric Cards (Equal width/height)
        Row(
          children: [
            for (int i = 0; i < metricItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: buildTile(metricItems[i], true)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildHeroMetaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBalanceCard(
    BuildContext context, {
    required String value,
    required Color accentColor,
    String label = 'Total Balance',
    IconData icon = Icons.account_balance_wallet_outlined,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accentColor.withValues(alpha: 0.85),
            accentColor,
            accentColor.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accentColor.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(!isSelected),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      colorScheme.primary,
                      colorScheme.primary.withValues(alpha: 0.86),
                    ],
                  )
                : null,
            color: isSelected
                ? null
                : colorScheme.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.9),
            ),
            boxShadow: isSelected
                ? <BoxShadow>[
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: compact ? 15 : 17,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: compact ? 6 : 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: compact ? 13 : null,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomRange(LedgerProvider provider) async {
    final now = DateTime.now();
    final initialRange =
        provider.customRange ??
        DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);

    final pickedRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (!mounted || pickedRange == null) {
      return;
    }

    final normalizedRange = DateTimeRange(
      start: DateTime(
        pickedRange.start.year,
        pickedRange.start.month,
        pickedRange.start.day,
      ),
      end: DateTime(
        pickedRange.end.year,
        pickedRange.end.month,
        pickedRange.end.day,
        23,
        59,
        59,
        999,
      ),
    );

    await provider.applyFilter(
      LedgerDateFilter.customRange,
      customRange: normalizedRange,
    );
  }

  Widget _buildScreenBackground(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary.withValues(alpha: 0.05),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntriesSectionHeader(
    BuildContext context,
    LedgerProvider provider, {
    required bool isCompact,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: isCompact ? 6 : 8),
      child: Row(
        children: <Widget>[
          Text(
            '${provider.entries.length} ${provider.entries.length == 1 ? 'entry' : 'entries'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (provider.isLoading) ...[
            const SizedBox(width: 6),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerProvider>(
      builder: (BuildContext context, LedgerProvider provider, _) {
        _syncOpeningBalanceControllers(provider);

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final isDesktop = PlatformHelper.isDesktop;
            final isCompact = !isDesktop && constraints.maxWidth < 760;
            final useCardLayout = constraints.maxWidth < 1100;
            final hasFab = isCompact;
            const desktopHorizontalPadding = 20.0;
            final desktopPageWidth = constraints.maxWidth;
            final bottomPadding =
                24.0 +
                MediaQuery.viewInsetsOf(context).bottom +
                (hasFab ? 84.0 : 0.0);
            final pageContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isCompact)
                  _buildMobileLedgerOverview(context, provider)
                else if (isDesktop)
                  _buildDesktopLedgerHeader(context, provider)
                else
                  _buildCustomerInfoCard(context, provider),

                if (!isCompact && !isDesktop) ...<Widget>[
                  const SizedBox(height: 12),
                  _buildLedgerStats(context, provider),
                ],
                const SizedBox(height: 12),
                const SizedBox(height: 18),
                _buildEntriesSectionHeader(
                  context,
                  provider,
                  isCompact: isCompact,
                ),
                const SizedBox(height: 12),
                _buildLedgerBody(
                  context: context,
                  provider: provider,
                  compactLayout: useCardLayout,
                ),
              ],
            );

            return Scaffold(
              key: _scaffoldKey,
              endDrawer: Drawer(
                width: math.min(MediaQuery.sizeOf(context).width * 0.85, 420.0),
                child: SafeArea(
                  child: Column(
                    children: [
                      AppBar(
                        automaticallyImplyLeading: false,
                        title: const Text('Ledger Settings'),
                        actions: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFilterBar(
                                context: context,
                                provider: provider,
                              ),
                              const SizedBox(height: 16),
                              _buildOpeningBalanceSection(
                                context: context,
                                provider: provider,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'LEDGER TYPE',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                title: const Text('Stock Ledger Mode'),
                                subtitle: const Text(
                                  'Enable stock tracking for this customer.',
                                ),
                                secondary: Icon(
                                  Icons.inventory_2_outlined,
                                  color: provider.isStockLedger
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                                value: provider.isStockLedger,
                                onChanged:
                                    true
                                    ? (bool value) {
                                        provider.toggleStockLedger();
                                      }
                                    : null,
                                trackColor:
                                    WidgetStateProperty.resolveWith<Color?>(
                                      (states) =>
                                          states.contains(WidgetState.selected)
                                          ? null
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant
                                                .withValues(alpha: 0.4),
                                    ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (provider.isStockLedger) ...[
                                const Divider(height: 32),
                                Text(
                                  'STOCK SETTINGS',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  title: const Text('Use Weight (Mund-KG)'),
                                  subtitle: const Text(
                                    'Display stock quantities in Mund and KG format (1 Mund = 40 KG).',
                                  ),
                                  secondary: Icon(
                                    Icons.scale_outlined,
                                    color: provider.useWeight
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  value: provider.useWeight,
                                  onChanged:
                                      true
                                       ? (bool value) =>
                                             provider.toggleStockWeight()
                                       : null,
                                  trackColor:
                                      WidgetStateProperty.resolveWith<Color?>(
                                        (states) =>
                                            states.contains(
                                              WidgetState.selected,
                                            )
                                            ? null
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.4),
                                      ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              appBar: AppBar(
                toolbarHeight: isCompact ? 72 : 56,
                automaticallyImplyLeading: !isDesktop,
                leading: isDesktop && Navigator.of(context).canPop()
                    ? IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    : null,
                titleSpacing: isDesktop ? 0 : 16,
                title: isDesktop
                    ? Text(
                        '${provider.customerName} Ledger',
                        overflow: TextOverflow.ellipsis,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            provider.customerName,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Ledger',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                actions: _buildAppBarActions(
                  context: context,
                  provider: provider,
                  isCompact: isCompact,
                ),
              ),
              floatingActionButton:
                  hasFab && true
                  ? FloatingActionButton.extended(
                      onPressed: _showAddEntryDialog,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add Entry'),
                    )
                  : null,
              body: SafeArea(
                child: Shortcuts(
                  shortcuts: <LogicalKeySet, Intent>{
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyN,
                    ): const _LedgerIntent(
                      _LedgerShortcut.addEntry,
                    ),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyE,
                    ): const _LedgerIntent(
                      _LedgerShortcut.export,
                    ),
                    LogicalKeySet(
                      LogicalKeyboardKey.control,
                      LogicalKeyboardKey.keyP,
                    ): const _LedgerIntent(
                      _LedgerShortcut.print,
                    ),
                    // Feature 5: Esc key to go back to customer list
                    LogicalKeySet(LogicalKeyboardKey.escape):
                        const _LedgerIntent(_LedgerShortcut.goBack),
                    LogicalKeySet(LogicalKeyboardKey.arrowDown):
                        const _ScrollIntent(80),
                    LogicalKeySet(LogicalKeyboardKey.arrowUp):
                        const _ScrollIntent(-80),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _LedgerIntent: CallbackAction<_LedgerIntent>(
                        onInvoke: (_LedgerIntent intent) {
                          const canEdit = true;
                          if (intent.action == _LedgerShortcut.addEntry &&
                              canEdit) {
                            _showAddEntryDialog();
                          } else if (intent.action == _LedgerShortcut.export) {
                            _exportWithOptions();
                          } else if (intent.action == _LedgerShortcut.print) {
                            _printPdf();
                          } else if (intent.action == _LedgerShortcut.goBack) {
                            Navigator.of(context).maybePop();
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
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _buildScreenBackground(context),
                            ),
                          ),
                          if (isDesktop)
                            SingleChildScrollView(
                              controller: _tableVerticalController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                desktopHorizontalPadding,
                                12,
                                desktopHorizontalPadding,
                                0,
                              ).copyWith(bottom: bottomPadding),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: desktopPageWidth,
                                  child: pageContent,
                                ),
                              ),
                            )
                          else
                            SingleChildScrollView(
                              controller: _tableVerticalController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.fromLTRB(
                                isCompact ? 16 : 20,
                                12,
                                isCompact ? 16 : 20,
                                bottomPadding,
                              ),
                              child: pageContent,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLedgerBody({
    required BuildContext context,
    required LedgerProvider provider,
    required bool compactLayout,
  }) {
    if (provider.isLoading && provider.entries.isEmpty) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No ledger entries yet',
        message: 'Add the first debit or credit entry for this customer.',
        actionLabel: 'Add Entry',
        onAction: _showAddEntryDialog,
      );
    }

    if (compactLayout) {
      return _buildCompactLedgerEntries(context, provider);
    }

    final dataTextStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final horizontalMargin = PlatformHelper.isDesktop
            ? constraints.maxWidth >= 1700
                  ? 20.0
                  : constraints.maxWidth >= 1450
                  ? 14.0
                  : constraints.maxWidth >= 1100
                  ? 10.0
                  : 6.0
            : 12.0;
        final columnSpacing = PlatformHelper.isDesktop
            ? constraints.maxWidth >= 1700
                  ? 38.0
                  : constraints.maxWidth >= 1450
                  ? 24.0
                  : constraints.maxWidth >= 1100
                  ? 14.0
                  : constraints.maxWidth >= 950
                  ? 8.0
                  : 4.0
            : 18.0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                dataTextStyle: dataTextStyle,
                horizontalMargin: horizontalMargin,
                columnSpacing: columnSpacing,
                headingRowHeight: 54,
                dataRowMinHeight: 50,
                dataRowMaxHeight: 56,
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                columns: provider.isStockLedger
                    ? <DataColumn>[
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Entry Date'),
                          ),
                        ),
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Created Date'),
                          ),
                        ),
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Page No'),
                          ),
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              provider.useWeight ? 'Buy Weight' : 'Buy Qty',
                            ),
                          ),
                          numeric: true,
                        ),
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Buy Amount'),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              provider.useWeight ? 'Sell Weight' : 'Sell Qty',
                            ),
                          ),
                          numeric: true,
                        ),
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Sell Amount'),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              provider.useWeight ? 'Rem. Weight' : 'Remaining',
                            ),
                          ),
                          numeric: true,
                        ),
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Balance'),
                          ),
                        ),
                        const DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Actions'),
                          ),
                        ),
                      ]
                    : const <DataColumn>[
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Entry Date'),
                          ),
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Created Date'),
                          ),
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Page No'),
                          ),
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Description'),
                          ),
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Debit'),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Credit'),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Balance'),
                          ),
                        ),
                        DataColumn(
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Actions'),
                          ),
                        ),
                      ],
                rows: _buildLedgerRows(
                  provider,
                  compact: constraints.maxWidth < 1100,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactLedgerEntries(
    BuildContext context,
    LedgerProvider provider,
  ) {
    final entries = provider.entries.reversed.toList();
    final balances = <_EntryBalance>[];
    double? runningBalance;
    double? runningRemainingBags;

    for (final entry in entries) {
      final isOpeningBalanceEntry = _isOpeningBalanceEntry(provider, entry);
      final debit = entry.debit;
      final credit = entry.credit;
      final buyBags = entry.buyBags;
      final sellBags = entry.sellBags;
      final hasValue =
          debit != 0 ||
          credit != 0 ||
          buyBags.trim().isNotEmpty && buyBags.trim() != '0' ||
          sellBags.trim().isNotEmpty && sellBags.trim() != '0';
      var balanceLabel = '';
      var remainingBagsLabel = '';
      double currentBalance = 0;

      if (hasValue) {
        currentBalance = provider.isStockLedger
            ? (runningBalance ?? 0) + credit - debit
            : (runningBalance ?? 0) + debit - credit;
        runningBalance = currentBalance;
        balanceLabel = provider.formatBalance(currentBalance);

        if (provider.isStockLedger) {
          final currentRemainingBags =
              (runningRemainingBags ?? 0) +
              (double.tryParse(buyBags) ?? 0) -
              (double.tryParse(sellBags) ?? 0);
          runningRemainingBags = currentRemainingBags;
          remainingBagsLabel = provider.formatBags(currentRemainingBags);
        }
      }

      balances.add(
        _EntryBalance(
          isOpeningBalanceEntry: isOpeningBalanceEntry,
          balanceLabel: balanceLabel,
          balance: currentBalance,
          remainingBagsLabel: remainingBagsLabel,
        ),
      );
    }

    final reversedBalances = balances.reversed.toList();
    final chronEntries = entries.reversed.toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chronEntries.length,
      itemBuilder: (context, index) {
        final b = reversedBalances[index];
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
          child: _buildLedgerEntryCard(
            context,
            provider,
            entry: chronEntries[index],
            balanceLabel: b.balanceLabel,
            balance: b.balance,
            remainingBagsLabel: b.remainingBagsLabel,
            isOpeningBalanceEntry: b.isOpeningBalanceEntry,
          ),
        );
      },
    );
  }

  Widget _buildLedgerEntryCard(
    BuildContext context,
    LedgerProvider provider, {
    required Entry entry,
    required String balanceLabel,
    double balance = 0,
    String remainingBagsLabel = '',
    required bool isOpeningBalanceEntry,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = isOpeningBalanceEntry
        ? colorScheme.secondary
        : colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOpeningBalanceEntry
              ? colorScheme.secondary.withValues(alpha: 0.28)
              : colorScheme.outlineVariant.withValues(alpha: 0.92),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.032),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              spacing: 8,
              children: <Widget>[
                _buildEntryMetaChip(
                  context,
                  icon: Icons.event_outlined,
                  label: _formatStoredDate(entry.entryDate),
                  accentColor: accentColor,
                  highlight: isOpeningBalanceEntry,
                ),
                _buildEntryMetaChip(
                  context,
                  icon: Icons.schedule_outlined,
                  label: _formatStoredDate(entry.createdAt),
                  accentColor: accentColor,
                ),
                if (entry.pageNo.trim().isNotEmpty ||
                    entry.dailyLogPageNo.trim().isNotEmpty)
                  _buildEntryMetaChip(
                    context,
                    icon: Icons.menu_book_outlined,
                    label: () {
                      final parts = <String>[];
                      if (entry.pageNo.trim().isNotEmpty) {
                        parts.add('Pg ${entry.pageNo}');
                      }
                      if (entry.dailyLogPageNo.trim().isNotEmpty) {
                        parts.add('DL Pg ${entry.dailyLogPageNo}');
                      }
                      return parts.join(', ');
                    }(),
                    accentColor: colorScheme.tertiary,
                    highlight: true,
                  ),
                if (isOpeningBalanceEntry)
                  _buildEntryMetaChip(
                    context,
                    icon: Icons.flag_rounded,
                    label: 'Opening Balance',
                    accentColor: accentColor,
                    highlight: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              isOpeningBalanceEntry
                  ? 'Opening Balance'
                  : entry.displayDescription,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (provider.isStockLedger) {
                const spacing = 10.0;
                final hasBuy =
                    (entry.buyBags.trim().isNotEmpty &&
                        entry.buyBags.trim() != '0') ||
                    entry.debit != 0;
                final hasSell =
                    (entry.sellBags.trim().isNotEmpty &&
                        entry.sellBags.trim() != '0') ||
                    entry.credit != 0;
                final bothSides = hasBuy && hasSell;
                final columns = bothSides ? 3 : 2;
                final tileWidth =
                    (constraints.maxWidth - ((columns - 1) * spacing)) /
                    columns;

                if (bothSides) {
                  return Column(
                    spacing: spacing,
                    children: <Widget>[
                      Row(
                        spacing: spacing,
                        children: <Widget>[
                          SizedBox(
                            width: tileWidth,
                            child: _buildEntryMetricTile(
                              context,
                              label: provider.useWeight
                                  ? 'Buy Weight'
                                  : 'Buy Qty',
                              value: provider.formatBags(
                                double.tryParse(entry.buyBags) ?? 0,
                              ),
                              accentColor: AppColors.credit,
                            ),
                          ),
                          SizedBox(
                            width: tileWidth,
                            child: _buildEntryMetricTile(
                              context,
                              label: provider.useWeight
                                  ? 'Sell Weight'
                                  : 'Sell Qty',
                              value: provider.formatBags(
                                double.tryParse(entry.sellBags) ?? 0,
                              ),
                              accentColor: AppColors.debit,
                            ),
                          ),
                          SizedBox(
                            width: tileWidth,
                            child: _buildEntryMetricTile(
                              context,
                              label: provider.useWeight
                                  ? 'Rem. Weight'
                                  : 'Remaining',
                              value: remainingBagsLabel.isEmpty
                                  ? '-'
                                  : remainingBagsLabel,
                              accentColor: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        spacing: spacing,
                        children: <Widget>[
                          SizedBox(
                            width: tileWidth,
                            child: _buildEntryMetricTile(
                              context,
                              label: 'Buy Amount',
                              value: provider.formatAmount(entry.debit),
                              accentColor: AppColors.credit,
                            ),
                          ),
                          SizedBox(
                            width: tileWidth,
                            child: _buildEntryMetricTile(
                              context,
                              label: 'Sell Amount',
                              value: provider.formatAmount(entry.credit),
                              accentColor: AppColors.debit,
                            ),
                          ),
                          SizedBox(
                            width: tileWidth,
                            child: _buildEntryMetricTile(
                              context,
                              label: 'Balance',
                              value: balanceLabel.isEmpty
                                  ? 'No change'
                                  : balanceLabel,
                              accentColor: AppColors.balanceColor(balance),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Column(
                  spacing: spacing,
                  children: <Widget>[
                    Row(
                      spacing: spacing,
                      children: <Widget>[
                        SizedBox(
                          width: tileWidth,
                          child: _buildEntryMetricTile(
                            context,
                            label: hasBuy
                                ? (provider.useWeight
                                      ? 'Buy Weight'
                                      : 'Buy Qty')
                                : (provider.useWeight
                                      ? 'Sell Weight'
                                      : 'Sell Qty'),
                            value: hasBuy
                                ? provider.formatBags(
                                    double.tryParse(entry.buyBags) ?? 0,
                                  )
                                : provider.formatBags(
                                    double.tryParse(entry.sellBags) ?? 0,
                                  ),
                            accentColor: hasBuy
                                ? AppColors.credit
                                : AppColors.debit,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _buildEntryMetricTile(
                            context,
                            label: provider.useWeight
                                ? 'Rem. Weight'
                                : 'Remaining',
                            value: remainingBagsLabel.isEmpty
                                ? '-'
                                : remainingBagsLabel,
                            accentColor: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      spacing: spacing,
                      children: <Widget>[
                        SizedBox(
                          width: tileWidth,
                          child: _buildEntryMetricTile(
                            context,
                            label: hasBuy ? 'Buy Amount' : 'Sell Amount',
                            value: hasBuy
                                ? provider.formatAmount(entry.debit)
                                : provider.formatAmount(entry.credit),
                            accentColor: hasBuy
                                ? AppColors.credit
                                : AppColors.debit,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _buildEntryMetricTile(
                            context,
                            label: 'Balance',
                            value: balanceLabel.isEmpty
                                ? 'No change'
                                : balanceLabel,
                            accentColor: AppColors.balanceColor(balance),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              const spacing = 12.0;
              final tileWidth = (constraints.maxWidth - (2 * spacing)) / 3;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: <Widget>[
                  SizedBox(
                    width: tileWidth,
                    child: _buildEntryMetricTile(
                      context,
                      label: 'Debit',
                      value: provider.formatAmount(entry.debit),
                      accentColor: const Color(0xFF0F766E),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _buildEntryMetricTile(
                      context,
                      label: 'Credit',
                      value: provider.formatAmount(entry.credit),
                      accentColor: const Color(0xFFB45309),
                    ),
                  ),
                  SizedBox(
                    width: tileWidth,
                    child: _buildEntryMetricTile(
                      context,
                      label: 'Balance',
                      value: balanceLabel.isEmpty ? 'No change' : balanceLabel,
                      accentColor: AppColors.balanceColor(balance),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              if (isOpeningBalanceEntry &&
                  true)
                IconButton(
                  tooltip: 'Clear opening balance',
                  onPressed: () => _clearOpeningBalance(provider),
                  icon: const Icon(Icons.delete_outline, size: 18),
                )
              else ...<Widget>[
                IconButton.filledTonal(
                  tooltip: 'Entry Options',
                  onPressed: () => _showEntryMenu(context, provider, entry),
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntryMetaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accentColor,
    bool highlight = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? accentColor.withValues(alpha: 0.14)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlight
              ? accentColor.withValues(alpha: 0.32)
              : colorScheme.outlineVariant.withValues(alpha: 0.92),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: highlight ? accentColor : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: highlight ? accentColor : colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryMetricTile(
    BuildContext context, {
    required String label,
    required String value,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerStats(BuildContext context, LedgerProvider provider) {
    final items = provider.isStockLedger
        ? <({String label, String value, IconData icon, Color accentColor})>[
            (
              label: 'Total Buy',
              value: provider.formatAmount(provider.totalDebit),
              icon: Icons.shopping_cart_outlined,
              accentColor: AppColors.credit,
            ),
            (
              label: 'Total Sell',
              value: provider.formatAmount(provider.totalCredit),
              icon: Icons.sell_outlined,
              accentColor: AppColors.debit,
            ),
            (
              label: 'Net Balance',
              value: provider.formatBalance(
                provider.isStockLedger
                    ? -provider.finalBalance
                    : provider.finalBalance,
              ),
              icon: Icons.account_balance_wallet_outlined,
              accentColor: AppColors.balanceColor(
                provider.isStockLedger
                    ? -provider.finalBalance
                    : provider.finalBalance,
              ),
            ),
          ]
        : <({String label, String value, IconData icon, Color accentColor})>[
            (
              label: 'Total Debit',
              value: provider.formatAmount(provider.totalDebit),
              icon: Icons.south_west_rounded,
              accentColor: AppColors.debit,
            ),
            (
              label: 'Total Credit',
              value: provider.formatAmount(provider.totalCredit),
              icon: Icons.north_east_rounded,
              accentColor: AppColors.credit,
            ),
            (
              label: 'Net Balance',
              value: provider.formatBalance(
                provider.isStockLedger
                    ? -provider.finalBalance
                    : provider.finalBalance,
              ),
              icon: Icons.account_balance_wallet_outlined,
              accentColor: AppColors.balanceColor(
                provider.isStockLedger
                    ? -provider.finalBalance
                    : provider.finalBalance,
              ),
            ),
          ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const spacing = 12.0;
        final tileWidth = (constraints.maxWidth - (2 * spacing)) / 3;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: _buildLedgerStatTile(
                  context,
                  label: item.label,
                  value: item.value,
                  icon: item.icon,
                  accentColor: item.accentColor,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildLedgerStatTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, Object?>>? _cachedLedgerCustomers;

  Future<List<Map<String, Object?>>> _getOtherCustomers(
    int currentCustomerId,
  ) async {
    _cachedLedgerCustomers ??= await AppDatabase.instance.getCustomers();
    return _cachedLedgerCustomers!
        .where(
          (Map<String, Object?> c) => (c['id'] as int) != currentCustomerId,
        )
        .toList(growable: false);
  }

  Future<void> _showTransferDialog(LedgerProvider provider, Entry entry) async {
    if (entry.id == null) {
      return;
    }

    final currentCustomerId = provider.customer.id;
    if (currentCustomerId == null) {
      return;
    }

    final otherCustomers = await _getOtherCustomers(currentCustomerId);
    if (!mounted) {
      return;
    }

    if (otherCustomers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other customers available to transfer to.'),
        ),
      );
      return;
    }

    final selectedCustomer = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return _LedgerTransferCustomerDialog(
          customers: otherCustomers,
          currentCustomerName: provider.customerName,
          entry: entry,
          formatDate: _formatStoredDate,
          formatDateTime: _formatStoredDate,
          formatAmount: provider.formatAmount,
        );
      },
    );

    if (selectedCustomer == null || !mounted) {
      return;
    }

    final newCustomerId = selectedCustomer['id'] as int;
    final newCustomerName = selectedCustomer['name'] as String;

    final shouldTransfer = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirm Transfer'),
          content: Text(
            'Transfer entry #${entry.id}\n'
            'From: ${provider.customerName}\n'
            'To: $newCustomerName\n\n'
            'Date: ${_formatStoredDate(entry.entryDate)}\n'
            'Description: ${entry.displayDescription}\n'
            'Debit: ${provider.formatAmount(entry.debit)}\n'
            'Credit: ${provider.formatAmount(entry.credit)}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Transfer'),
            ),
          ],
        );
      },
    );

    if (shouldTransfer != true || !mounted) {
      return;
    }

    final isTransferred = await provider.transferEntry(
      entry: entry,
      newCustomerId: newCustomerId,
    );

    if (!mounted) {
      return;
    }

    if (isTransferred) {
      _cachedLedgerCustomers = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entry transferred to $newCustomerName.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Unable to transfer entry.'),
        ),
      );
    }
  }

  List<DataRow> _buildLedgerRows(
    LedgerProvider provider, {
    required bool compact,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final rows = <DataRow>[];
    double? runningBalance;
    double? runningRemainingBags;

    final entries = provider.entries.reversed.toList();
    for (final entry in entries) {
      final isOpeningBalanceEntry = _isOpeningBalanceEntry(provider, entry);
      final debit = entry.debit;
      final credit = entry.credit;
      final buyBags = entry.buyBags;
      final sellBags = entry.sellBags;
      final hasValue =
          debit != 0 ||
          credit != 0 ||
          buyBags.trim().isNotEmpty && buyBags.trim() != '0' ||
          sellBags.trim().isNotEmpty && sellBags.trim() != '0';
      String balanceLabel = '';
      String remainingBagsLabel = '';
      final rowStyle = isOpeningBalanceEntry
          ? Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
          : null;

      if (hasValue) {
        final currentBalance = provider.isStockLedger
            ? (runningBalance ?? 0) + credit - debit
            : (runningBalance ?? 0) + debit - credit;
        runningBalance = currentBalance;
        balanceLabel = provider.formatBalance(currentBalance);

        if (provider.isStockLedger) {
          final currentRemainingBags =
              (runningRemainingBags ?? 0) +
              (double.tryParse(buyBags) ?? 0) -
              (double.tryParse(sellBags) ?? 0);
          runningRemainingBags = currentRemainingBags;
          remainingBagsLabel = provider.formatBags(currentRemainingBags);
        }
      }

      final List<DataCell> cells = <DataCell>[
        DataCell(Text(_formatStoredDate(entry.entryDate), style: rowStyle)),
        DataCell(Text(_formatStoredDate(entry.createdAt), style: rowStyle)),
        DataCell(
          Text(
            isOpeningBalanceEntry
                ? (provider.isStockLedger ? 'Opening Balance' : '')
                : [
                    if (entry.pageNo.isNotEmpty) entry.pageNo,
                    if (entry.dailyLogPageNo.isNotEmpty)
                      'DL: ${entry.dailyLogPageNo}',
                  ].join(' | '),
            style: rowStyle?.copyWith(
              color: entry.dailyLogPageNo.isNotEmpty
                  ? colorScheme.tertiary
                  : null,
              fontWeight: entry.dailyLogPageNo.isNotEmpty
                  ? FontWeight.bold
                  : null,
            ),
          ),
        ),
      ];

      if (provider.isStockLedger) {
        cells.addAll(<DataCell>[
          DataCell(
            Text(
              provider.formatBags(double.tryParse(buyBags) ?? 0),
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: AppColors.credit,
              ),
            ),
          ),
          DataCell(
            Text(
              provider.formatAmount(debit),
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: AppColors.credit,
              ),
            ),
          ),
          DataCell(
            Text(
              provider.formatBags(double.tryParse(sellBags) ?? 0),
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: AppColors.debit,
              ),
            ),
          ),
          DataCell(
            Text(
              provider.formatAmount(credit),
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: AppColors.debit,
              ),
            ),
          ),
          DataCell(
            Text(
              remainingBagsLabel,
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: (runningRemainingBags ?? 0) >= 0
                    ? AppColors.credit
                    : AppColors.debit,
              ),
            ),
          ),
        ]);
      } else {
        cells.addAll(<DataCell>[
          DataCell(
            SizedBox(
              width: compact ? 120 : 260,
              child: Text(
                isOpeningBalanceEntry
                    ? 'Opening Balance'
                    : entry.displayDescription,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rowStyle,
              ),
            ),
          ),
          DataCell(
            Text(
              provider.formatAmount(debit),
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: AppColors.debit,
              ),
            ),
          ),
          DataCell(
            Text(
              provider.formatAmount(credit),
              style: (rowStyle ?? const TextStyle()).copyWith(
                color: AppColors.credit,
              ),
            ),
          ),
        ]);
      }

      cells.addAll(<DataCell>[
        DataCell(
          Text(
            balanceLabel,
            style: (rowStyle ?? const TextStyle()).copyWith(
              color: AppColors.balanceLabelColor(balanceLabel),
            ),
          ),
        ),
        DataCell(
          isOpeningBalanceEntry &&
                  true
              ? IconButton(
                  tooltip: 'Clear opening balance',
                  onPressed: () => _clearOpeningBalance(provider),
                  icon: const Icon(Icons.delete_outline),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Entry Options',
                      onPressed: () => _showEntryMenu(context, provider, entry),
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                ),
        ),
      ]);

      rows.add(
        DataRow(
          color: isOpeningBalanceEntry
              ? WidgetStatePropertyAll<Color?>(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                )
              : null,
          cells: cells,
        ),
      );
    }

    final resultRows = rows.reversed.toList();

    return resultRows;
  }
}

class _EntryDraft {
  const _EntryDraft({
    required this.entryDate,
    required this.pageNo,
    required this.description,
    required this.debit,
    required this.credit,
    this.buyBags = '',
    this.sellBags = '',
  });

  final DateTime entryDate;
  final String pageNo;
  final String description;
  final double debit;
  final double credit;
  final String buyBags;
  final String sellBags;
}

class _EntryBalance {
  const _EntryBalance({
    required this.isOpeningBalanceEntry,
    required this.balanceLabel,
    required this.balance,
    required this.remainingBagsLabel,
  });

  final bool isOpeningBalanceEntry;
  final String balanceLabel;
  final double balance;
  final String remainingBagsLabel;
}

class _CustomerProfileDraft {
  const _CustomerProfileDraft({
    required this.name,
    this.address = '',
    this.phone = '',
  });

  final String name;
  final String address;
  final String phone;
}

class _ResponsiveFormDialogShell extends StatelessWidget {
  const _ResponsiveFormDialogShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.actions,
    this.maxWidth = 460,
    this.compactMaxHeightFactor = 0.92,
    this.compactDense = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;
  final double compactMaxHeightFactor;
  final bool compactDense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 640;
    final useDenseCompactLayout = isCompact && compactDense;
    final headerPadding = useDenseCompactLayout
        ? const EdgeInsets.fromLTRB(16, 14, 16, 10)
        : const EdgeInsets.fromLTRB(18, 18, 18, 12);
    final bodyPadding = useDenseCompactLayout
        ? const EdgeInsets.fromLTRB(16, 0, 16, 0)
        : const EdgeInsets.fromLTRB(18, 0, 18, 0);
    final actionPadding = useDenseCompactLayout
        ? const EdgeInsets.fromLTRB(16, 10, 16, 16)
        : const EdgeInsets.fromLTRB(18, 12, 18, 18);
    final compactRadius = useDenseCompactLayout ? 24.0 : 28.0;
    final iconSize = useDenseCompactLayout ? 42.0 : 46.0;
    final iconRadius = useDenseCompactLayout ? 15.0 : 16.0;
    final iconDecoration = useDenseCompactLayout
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.primary.withValues(alpha: 0.24),
                colorScheme.primaryContainer.withValues(alpha: 0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(iconRadius),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
            ),
          )
        : BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(iconRadius),
          );
    final iconColor = useDenseCompactLayout
        ? colorScheme.onPrimaryContainer
        : colorScheme.primary;
    final handleTopSpacing = useDenseCompactLayout ? 8.0 : 10.0;
    final handleWidth = useDenseCompactLayout ? 42.0 : 46.0;
    final handleHeight = useDenseCompactLayout ? 4.0 : 5.0;
    final dialogGradient = useDenseCompactLayout
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
              colorScheme.surface,
            ],
          )
        : null;

    return Dialog(
      alignment: isCompact ? Alignment.bottomCenter : Alignment.center,
      insetPadding: EdgeInsets.fromLTRB(16, isCompact ? 12 : 24, 16, 16),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(maxWidth, size.width - 32),
          maxHeight: size.height * (isCompact ? compactMaxHeightFactor : 0.84),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: dialogGradient == null ? colorScheme.surface : null,
            gradient: dialogGradient,
            borderRadius: BorderRadius.circular(isCompact ? compactRadius : 30),
            border: Border.all(
              color: useDenseCompactLayout
                  ? colorScheme.outline
                  : colorScheme.outlineVariant,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: useDenseCompactLayout ? 0.18 : 0.12,
                ),
                blurRadius: useDenseCompactLayout ? 32 : 28,
                offset: Offset(0, useDenseCompactLayout ? 14 : 18),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (isCompact) ...<Widget>[
                  SizedBox(height: handleTopSpacing),
                  Container(
                    width: handleWidth,
                    height: handleHeight,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
                Padding(
                  padding: headerPadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: iconDecoration,
                        child: Icon(icon, color: iconColor),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: bodyPadding,
                    child: child,
                  ),
                ),
                Padding(
                  padding: actionPadding,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerEntryDateCard extends StatelessWidget {
  const _LedgerEntryDateCard({
    required this.selectedDateLabel,
    required this.supportingText,
    required this.actionLabel,
    required this.onTap,
  });

  final String selectedDateLabel;
  final String supportingText;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colorScheme.primaryContainer.withValues(alpha: 0.78),
                colorScheme.surfaceContainerLow.withValues(alpha: 0.96),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Entry Date',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.88,
                        ),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedDateLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        supportingText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.84),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      actionLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<DateTime?> _showAutoClosingDatePicker({
  required BuildContext context,
  required DateTime initialDate,
}) async {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  String formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dayOfWeek = [
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
    ][date.weekday % 7];
    return '$dayOfWeek, ${months[date.month - 1]} ${date.day}';
  }

  return showDialog<DateTime>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 328),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELECT DATE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onPrimary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      formatDate(initialDate),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: CalendarDatePicker(
                  initialDate: initialDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  onDateChanged: (DateTime date) {
                    Navigator.of(dialogContext).pop(date);
                  },
                ),
              ),
              // Footer
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('CANCEL'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AddEntryDialog extends StatefulWidget {
  const _AddEntryDialog({this.customerId, required this.isStockLedger});

  final int? customerId;
  final bool isStockLedger;

  @override
  State<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<_AddEntryDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pageNoController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _debitController = TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _buyBagsController = TextEditingController();
  final TextEditingController _sellBagsController = TextEditingController();

  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSelectedDate();
    // Feature 4: Load persistent page number for this customer
    _loadSavedPageNo();
  }

  Future<void> _loadSavedPageNo() async {
    final customerId = widget.customerId;
    if (customerId == null) return;
    final savedPageNo = await AppDatabase.instance.getAppSetting(
      'ledger.pageNo:$customerId',
    );
    if (!mounted || savedPageNo == null || savedPageNo.isEmpty) return;
    _pageNoController.text = savedPageNo;
  }

  @override
  void dispose() {
    _pageNoController.dispose();
    _descriptionController.dispose();
    _debitController.dispose();
    _creditController.dispose();
    _buyBagsController.dispose();
    _sellBagsController.dispose();
    super.dispose();
  }

  Future<void> _pickEntryDate() async {
    final pickedDate = await _showAutoClosingDatePicker(
      context: context,
      initialDate: _selectedDate,
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _selectedDate = pickedDate;
      });
      unawaited(_LedgerSelectedDatePreference.save(pickedDate));
    }
  }

  Future<void> _loadSelectedDate() async {
    final savedDate = await _LedgerSelectedDatePreference.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedDate = savedDate;
    });
  }

  void _submit() {
    final debit = _parseAmount(_debitController.text);
    final credit = _parseAmount(_creditController.text);
    final buyBagsStr = _buyBagsController.text.trim();
    final sellBagsStr = _sellBagsController.text.trim();

    final provider = context.read<LedgerProvider>();

    String buyBags = buyBagsStr;
    String sellBags = sellBagsStr;

    if (provider.useWeight) {
      final buyBagsParsed = number_format_utils.parseWeight(buyBagsStr);
      final sellBagsParsed = number_format_utils.parseWeight(sellBagsStr);
      buyBags = buyBagsParsed == 0 && buyBagsStr.isEmpty
          ? ''
          : buyBagsParsed.toString();
      sellBags = sellBagsParsed == 0 && sellBagsStr.isEmpty
          ? ''
          : sellBagsParsed.toString();
    } else {
      final buyBagsParsed = double.tryParse(buyBagsStr) ?? 0;
      final sellBagsParsed = double.tryParse(sellBagsStr) ?? 0;
      buyBags = buyBagsParsed == 0 && buyBagsStr.isEmpty
          ? ''
          : buyBagsParsed.toString();
      sellBags = sellBagsParsed == 0 && sellBagsStr.isEmpty
          ? ''
          : sellBagsParsed.toString();
    }

    final isStockLedger = widget.isStockLedger;

    if (isStockLedger) {
      if (buyBags.isEmpty && debit == 0 && sellBags.isEmpty && credit == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter bag quantities and amounts.')),
        );
        return;
      }
    } else if (debit == 0 && credit == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a debit or credit amount.')),
      );
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    unawaited(_LedgerSelectedDatePreference.save(_selectedDate));

    // Feature 4: Save page number for this customer
    final customerId = widget.customerId;
    final pageNoValue = _pageNoController.text.trim();
    if (customerId != null) {
      unawaited(
        AppDatabase.instance.setAppSetting(
          key: 'ledger.pageNo:$customerId',
          value: pageNoValue,
        ),
      );
    }

    Navigator.of(context).pop(
      _EntryDraft(
        entryDate: _selectedDate,
        pageNo: pageNoValue,
        description: _descriptionController.text.trim(),
        debit: debit,
        credit: credit,
        buyBags: buyBags,
        sellBags: sellBags,
      ),
    );
  }

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parsedValue = _parseAmount(value);
    if (parsedValue == 0 && value.trim().isNotEmpty && value.trim() != '0') {
      if (double.tryParse(value.replaceAll(',', '').trim()) == null) {
        return 'Enter a valid number';
      }
    }

    if (parsedValue < 0) {
      return 'Amount cannot be negative';
    }

    return null;
  }

  String? _validateBuyBags(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final amount = _parseAmount(_debitController.text);
    if (amount > 0 && (value == null || value.trim().isEmpty)) {
      return 'Required';
    }
    return null;
  }

  String? _validateBuyAmount(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final bags = _buyBagsController.text.trim();
    final amount = _parseAmount(value ?? '');
    if (bags.isNotEmpty && amount == 0) {
      return 'Amount required';
    }
    return _validateAmount(value);
  }

  String? _validateSellBags(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final amount = _parseAmount(_creditController.text);
    if (amount > 0 && (value == null || value.trim().isEmpty)) {
      return 'Required';
    }
    return null;
  }

  String? _validateSellAmount(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final bags = _sellBagsController.text.trim();
    final amount = _parseAmount(value ?? '');
    if (bags.isNotEmpty && amount == 0) {
      return 'Amount required';
    }
    return _validateAmount(value);
  }

  double _parseAmount(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 640;
    final fieldGap = isCompact ? 14.0 : 16.0;

    return _ResponsiveFormDialogShell(
      icon: Icons.add_chart_rounded,
      title: 'Add Entry',
      subtitle:
          'Capture a new debit or credit transaction with a mobile-safe form.',
      compactMaxHeightFactor: 0.86,
      compactDense: true,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save Entry')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (isCompact)
              _LedgerEntryDateCard(
                selectedDateLabel: _formatDate(_selectedDate),
                supportingText: 'Today: ${_formatDate(DateTime.now())}',
                actionLabel: 'Select',
                onTap: _pickEntryDate,
              )
            else ...<Widget>[
              Text('Entry Date', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickEntryDate,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_formatDate(_selectedDate)),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Text(
                  'Current Date: ${_formatDate(DateTime.now())}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            SizedBox(height: fieldGap),
            TextFormField(
              controller: _pageNoController,
              decoration: const InputDecoration(labelText: 'Page No'),
              textInputAction: TextInputAction.next,
              scrollPadding: const EdgeInsets.only(bottom: 180),
            ),
            if (!widget.isStockLedger) ...[
              SizedBox(height: fieldGap),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Leave empty to show -',
                ),
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: 3,
                scrollPadding: const EdgeInsets.only(bottom: 180),
              ),
            ],
            SizedBox(height: fieldGap),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final isStockLedger = widget.isStockLedger;

                if (isStockLedger) {
                  return Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              controller: _buyBagsController,
                              decoration: const InputDecoration(
                                labelText: 'Buy',
                              ),
                              validator: _validateBuyBags,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AmountInputField(
                              controller: _debitController,
                              label: 'Amount',
                              validator: _validateBuyAmount,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: fieldGap),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              controller: _sellBagsController,
                              decoration: const InputDecoration(
                                labelText: 'Sell',
                              ),
                              validator: _validateSellBags,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AmountInputField(
                              controller: _creditController,
                              label: 'Amount',
                              validator: _validateSellAmount,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                if (constraints.maxWidth < 420) {
                  return Column(
                    children: <Widget>[
                      AmountInputField(
                        controller: _debitController,
                        label: 'Debit',
                        validator: _validateAmount,
                      ),
                      SizedBox(height: fieldGap),
                      AmountInputField(
                        controller: _creditController,
                        label: 'Credit',
                        validator: _validateAmount,
                      ),
                    ],
                  );
                }

                return Row(
                  children: <Widget>[
                    Expanded(
                      child: AmountInputField(
                        controller: _debitController,
                        label: 'Debit',
                        validator: _validateAmount,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AmountInputField(
                        controller: _creditController,
                        label: 'Credit',
                        validator: _validateAmount,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.entry, required this.isStockLedger});

  final Entry entry;
  final bool isStockLedger;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pageNoController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _debitController = TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _buyBagsController = TextEditingController();
  final TextEditingController _sellBagsController = TextEditingController();

  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _pageNoController.text = widget.entry.pageNo;
    _descriptionController.text = widget.entry.description == '-'
        ? ''
        : widget.entry.description;
    // Feature 1: Use formatted numbers (with commas) for consistency
    _debitController.text = widget.entry.debit == 0
        ? ''
        : _formatInitialAmount(widget.entry.debit);
    _creditController.text = widget.entry.credit == 0
        ? ''
        : _formatInitialAmount(widget.entry.credit);
    final provider = Provider.of<LedgerProvider>(context, listen: false);
    if (provider.useWeight) {
      _buyBagsController.text =
          widget.entry.buyBags.trim().isEmpty ||
              widget.entry.buyBags.trim() == '0'
          ? ''
          : number_format_utils.formatWeight(
              double.tryParse(widget.entry.buyBags) ?? 0,
            );
      _sellBagsController.text =
          widget.entry.sellBags.trim().isEmpty ||
              widget.entry.sellBags.trim() == '0'
          ? ''
          : number_format_utils.formatWeight(
              double.tryParse(widget.entry.sellBags) ?? 0,
            );
    } else {
      _buyBagsController.text =
          widget.entry.buyBags.trim().isEmpty ||
              widget.entry.buyBags.trim() == '0'
          ? ''
          : widget.entry.buyBags.trim();
      _sellBagsController.text =
          widget.entry.sellBags.trim().isEmpty ||
              widget.entry.sellBags.trim() == '0'
          ? ''
          : widget.entry.sellBags.trim();
    }
    _selectedDate = DateTime.tryParse(widget.entry.entryDate) ?? DateTime.now();
  }

  @override
  void dispose() {
    _pageNoController.dispose();
    _descriptionController.dispose();
    _debitController.dispose();
    _creditController.dispose();
    _buyBagsController.dispose();
    _sellBagsController.dispose();
    super.dispose();
  }

  Future<void> _pickEntryDate() async {
    final pickedDate = await _showAutoClosingDatePicker(
      context: context,
      initialDate: _selectedDate,
    );

    if (pickedDate != null && mounted) {
      setState(() {
        _selectedDate = pickedDate;
      });
      unawaited(_LedgerSelectedDatePreference.save(pickedDate));
    }
  }

  void _submit() {
    final debit = _parseAmount(_debitController.text);
    final credit = _parseAmount(_creditController.text);
    final buyBagsStr = _buyBagsController.text.trim();
    final sellBagsStr = _sellBagsController.text.trim();

    final provider = context.read<LedgerProvider>();

    String buyBags = buyBagsStr;
    String sellBags = sellBagsStr;

    if (provider.useWeight) {
      final buyBagsParsed = number_format_utils.parseWeight(buyBagsStr);
      final sellBagsParsed = number_format_utils.parseWeight(sellBagsStr);
      buyBags = buyBagsParsed == 0 && buyBagsStr.isEmpty
          ? ''
          : buyBagsParsed.toString();
      sellBags = sellBagsParsed == 0 && sellBagsStr.isEmpty
          ? ''
          : sellBagsParsed.toString();
    } else {
      final buyBagsParsed = double.tryParse(buyBagsStr) ?? 0;
      final sellBagsParsed = double.tryParse(sellBagsStr) ?? 0;
      buyBags = buyBagsParsed == 0 && buyBagsStr.isEmpty
          ? ''
          : buyBagsParsed.toString();
      sellBags = sellBagsParsed == 0 && sellBagsStr.isEmpty
          ? ''
          : sellBagsParsed.toString();
    }

    final isStockLedger = widget.isStockLedger;

    if (isStockLedger) {
      if (buyBags.isEmpty && debit == 0 && sellBags.isEmpty && credit == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter bag quantities and amounts.')),
        );
        return;
      }
    } else if (debit == 0 && credit == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a debit or credit amount.')),
      );
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    unawaited(_LedgerSelectedDatePreference.save(_selectedDate));

    Navigator.of(context).pop(
      _EntryDraft(
        entryDate: _selectedDate,
        pageNo: _pageNoController.text.trim(),
        description: _descriptionController.text.trim(),
        debit: debit,
        credit: credit,
        buyBags: buyBags,
        sellBags: sellBags,
      ),
    );
  }

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parsedValue = _parseAmount(value);
    if (parsedValue == 0 && value.trim().isNotEmpty && value.trim() != '0') {
      if (double.tryParse(value.replaceAll(',', '').trim()) == null) {
        return 'Enter a valid number';
      }
    }

    if (parsedValue < 0) {
      return 'Amount cannot be negative';
    }

    return null;
  }

  String? _validateBuyBags(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final amount = _parseAmount(_debitController.text);
    if (amount > 0 && (value == null || value.trim().isEmpty)) {
      return 'Required';
    }
    return null;
  }

  String? _validateBuyAmount(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final bags = _buyBagsController.text.trim();
    final amount = _parseAmount(value ?? '');
    if (bags.isNotEmpty && amount == 0) {
      return 'Amount required';
    }
    return _validateAmount(value);
  }

  String? _validateSellBags(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final amount = _parseAmount(_creditController.text);
    if (amount > 0 && (value == null || value.trim().isEmpty)) {
      return 'Required';
    }
    return null;
  }

  String? _validateSellAmount(String? value) {
    if (!widget.isStockLedger) {
      return null;
    }
    final bags = _sellBagsController.text.trim();
    final amount = _parseAmount(value ?? '');
    if (bags.isNotEmpty && amount == 0) {
      return 'Amount required';
    }
    return _validateAmount(value);
  }

  double _parseAmount(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatInitialAmount(double amount) {
    return number_format_utils.formatAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 640;
    final fieldGap = isCompact ? 14.0 : 16.0;

    return _ResponsiveFormDialogShell(
      icon: Icons.edit_note_rounded,
      title: 'Edit Entry',
      subtitle:
          'Update the transaction details without leaving the ledger view.',
      compactMaxHeightFactor: 0.86,
      compactDense: true,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Update')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (isCompact)
              _LedgerEntryDateCard(
                selectedDateLabel: _formatDate(_selectedDate),
                supportingText: 'Tap to revise the posting date before saving.',
                actionLabel: 'Change',
                onTap: _pickEntryDate,
              )
            else ...<Widget>[
              Text('Entry Date', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickEntryDate,
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_formatDate(_selectedDate)),
                ),
              ),
            ],
            SizedBox(height: fieldGap),
            TextFormField(
              controller: _pageNoController,
              decoration: const InputDecoration(labelText: 'Page No'),
              textInputAction: TextInputAction.next,
              scrollPadding: const EdgeInsets.only(bottom: 180),
            ),
            if (!widget.isStockLedger) ...[
              SizedBox(height: fieldGap),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Leave empty to show -',
                ),
                textInputAction: TextInputAction.next,
                minLines: 1,
                maxLines: 3,
                scrollPadding: const EdgeInsets.only(bottom: 180),
              ),
            ],
            SizedBox(height: fieldGap),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final isStockLedger = widget.isStockLedger;

                if (isStockLedger) {
                  return Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              controller: _buyBagsController,
                              decoration: const InputDecoration(
                                labelText: 'Buy',
                              ),
                              validator: _validateBuyBags,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AmountInputField(
                              controller: _debitController,
                              label: 'Amount',
                              validator: _validateBuyAmount,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: fieldGap),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextFormField(
                              controller: _sellBagsController,
                              decoration: const InputDecoration(
                                labelText: 'Sell',
                              ),
                              validator: _validateSellBags,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AmountInputField(
                              controller: _creditController,
                              label: 'Amount',
                              validator: _validateSellAmount,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                if (constraints.maxWidth < 420) {
                  return Column(
                    children: <Widget>[
                      AmountInputField(
                        controller: _debitController,
                        label: 'Debit',
                        validator: _validateAmount,
                      ),
                      SizedBox(height: fieldGap),
                      AmountInputField(
                        controller: _creditController,
                        label: 'Credit',
                        validator: _validateAmount,
                      ),
                    ],
                  );
                }

                return Row(
                  children: <Widget>[
                    Expanded(
                      child: AmountInputField(
                        controller: _debitController,
                        label: 'Debit',
                        validator: _validateAmount,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AmountInputField(
                        controller: _creditController,
                        label: 'Credit',
                        validator: _validateAmount,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EditCustomerDialog extends StatefulWidget {
  const _EditCustomerDialog({
    required this.initialName,
    required this.initialAddress,
    required this.initialPhone,
  });

  final String initialName;
  final String initialAddress;
  final String initialPhone;

  @override
  State<_EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends State<_EditCustomerDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _addressController.text = widget.initialAddress;
    _phoneController.text = widget.initialPhone;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(
        _CustomerProfileDraft(
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          phone: _phoneController.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ResponsiveFormDialogShell(
      icon: Icons.person_outline_rounded,
      title: 'Edit Customer',
      subtitle: 'Keep customer details polished and easy to review on mobile.',
      maxWidth: 400,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Customer name'),
              scrollPadding: const EdgeInsets.only(bottom: 180),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Customer name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _addressController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Address (Optional)',
              ),
              minLines: 1,
              maxLines: 2,
              scrollPadding: const EdgeInsets.only(bottom: 180),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Phone Number (Optional)',
              ),
              scrollPadding: const EdgeInsets.only(bottom: 180),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerIdentityItem extends StatelessWidget {
  const _CustomerIdentityItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerInfoTile extends StatelessWidget {
  const _CustomerInfoTile({
    required this.label,
    required this.value,
    this.backgroundColor,
    this.labelColor,
    this.valueColor,
    this.borderColor,
    this.isMetric = false,
    this.maxWidth,
  });

  final String label;
  final String value;
  final Color? backgroundColor;
  final Color? labelColor;
  final Color? valueColor;
  final Color? borderColor;
  final bool isMetric;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(22);

    final resolvedBg = backgroundColor ?? colorScheme.surfaceContainerLowest;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 120,
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isMetric
                  ? resolvedBg.withValues(alpha: 0.15)
                  : resolvedBg.withValues(alpha: 0.1),
              gradient: isMetric
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        resolvedBg.withValues(alpha: 0.25),
                        resolvedBg.withValues(alpha: 0.15),
                        resolvedBg.withValues(alpha: 0.2),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        colorScheme.surface.withValues(alpha: 0.2),
                        colorScheme.surfaceContainerLow.withValues(alpha: 0.1),
                      ],
                    ),
              boxShadow: isMetric
                  ? <BoxShadow>[
                      BoxShadow(
                        color: resolvedBg.withValues(alpha: 0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
              borderRadius: borderRadius,
              border: Border.all(
                color: isMetric
                    ? resolvedBg.withValues(alpha: 0.3)
                    : borderColor ??
                          colorScheme.outlineVariant.withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isMetric
                              ? Colors.white.withValues(alpha: 0.7)
                              : labelColor ?? colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isMetric
                              ? Colors.white
                              : (valueColor ?? colorScheme.onSurface),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerSelectedDatePreference {
  const _LedgerSelectedDatePreference._();

  static const String _settingKey = 'ledger.lastSelectedDate';

  static Future<DateTime> load() async {
    final rawValue = await AppDatabase.instance.getAppSetting(_settingKey);
    return DateTime.tryParse(rawValue ?? '') ?? DateTime.now();
  }

  static Future<void> save(DateTime date) {
    return AppDatabase.instance.setAppSetting(
      key: _settingKey,
      value: date.toIso8601String(),
    );
  }
}

class _LedgerTransferCustomerDialog extends StatefulWidget {
  const _LedgerTransferCustomerDialog({
    required this.customers,
    required this.currentCustomerName,
    required this.entry,
    required this.formatDate,
    required this.formatDateTime,
    required this.formatAmount,
  });

  final List<Map<String, Object?>> customers;
  final String currentCustomerName;
  final Entry entry;
  final String Function(String) formatDate;
  final String Function(String) formatDateTime;
  final String Function(double) formatAmount;

  @override
  State<_LedgerTransferCustomerDialog> createState() =>
      _LedgerTransferCustomerDialogState();
}

class _LedgerTransferCustomerDialogState
    extends State<_LedgerTransferCustomerDialog> {
  String _searchQuery = '';

  List<Map<String, Object?>> get _filteredCustomers {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.customers;
    }

    return widget.customers
        .where(
          (Map<String, Object?> c) =>
              (c['name'] as String? ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Transfer Entry to...'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Current customer: ${widget.currentCustomerName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search customer...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (String value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filteredCustomers.isEmpty
                  ? Center(
                      child: Text(
                        'No customers found.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (BuildContext context, int index) {
                        final customer = _filteredCustomers[index];
                        final name = customer['name'] as String? ?? '-';
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(
                            'ID: ${customer['id']}',
                            style: theme.textTheme.bodySmall,
                          ),
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
