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
import '../providers/customer_provider.dart';
import '../providers/ledger_provider.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../utils/app_colors.dart';
import '../utils/number_format_utils.dart';
import '../utils/platform_helper.dart';
import '../widgets/amount_input_field.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/decimal_text_input_formatter.dart';
import '../widgets/scale_down_width.dart';
import '../features/linked_devices/providers/linked_session_provider.dart';

enum _ExportChoice { pdf, excel }

enum _LedgerShortcut { addEntry, export, print }

enum _LedgerAppBarAction { export, print, editCustomer }

class _LedgerIntent extends Intent {
  const _LedgerIntent(this.action);

  final _LedgerShortcut action;
}

class _ScrollIntent extends Intent {
  const _ScrollIntent(this.delta);

  final double delta;
}

class LedgerScreen extends StatelessWidget {
  const LedgerScreen({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LedgerProvider>(
      create: (_) => LedgerProvider(
        customer: customer,
      )..loadEntries(),
      child: _LedgerView(customer: customer),
    );
  }
}

class _LedgerView extends StatefulWidget {
  const _LedgerView({required this.customer});

  final Customer customer;

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
  final FocusNode _openingDebitFocusNode = FocusNode();
  final FocusNode _openingCreditFocusNode = FocusNode();
  String _lastOpeningBalanceSignature = '';
  bool _showOpeningBalancePanel = false;
  bool _showDateFilterPanel = false;

  @override
  void dispose() {
    _tableVerticalController.dispose();
    _openingDebitController.dispose();
    _openingCreditController.dispose();
    _openingDebitFocusNode.dispose();
    _openingCreditFocusNode.dispose();
    super.dispose();
  }

  Future<void> _showAddEntryDialog() async {
    final draft = await showDialog<_EntryDraft>(
      context: context,
      builder: (BuildContext context) => const _AddEntryDialog(),
    );

    if (!mounted || draft == null) {
      return;
    }

    final provider = context.read<LedgerProvider>();
    final isSaved = await provider.addEntry(
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
    final draft = await showDialog<_EntryDraft>(
      context: context,
      builder: (BuildContext context) => _EditEntryDialog(entry: entry),
    );

    if (!mounted || draft == null) {
      return;
    }

    final provider = context.read<LedgerProvider>();
    final isUpdated = await provider.updateEntry(
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
      await AppDatabase.instance.updateEntryDailyLogVisibility(
        entryId: entry.id!,
        show: true,
      );
      await provider.loadEntries();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry added to Daily Logs')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add entry to Daily Logs: $e')),
      );
    }
  }

  void _showEntryMenu(BuildContext context, LedgerProvider provider, Entry entry) {

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
                  padding: const EdgeInsets.only(bottom: 16, left: 24, right: 24),
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
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.edit_outlined, color: colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('Edit Entry', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: context.read<LinkedSessionProvider>().canEdit ? () {
                    Navigator.pop(context);
                    _showEditEntryDialog(entry);
                  } : null,
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.swap_horiz_rounded, color: colorScheme.onSecondaryContainer),
                  ),
                  title: const Text('Transfer to another customer', style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: context.read<LinkedSessionProvider>().canEdit ? () {
                    Navigator.pop(context);
                    _showTransferDialog(provider, entry);
                  } : null,
                ),
                if (!entry.showInDailyLog)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.playlist_add_rounded, color: colorScheme.onTertiaryContainer),
                    ),
                    title: const Text('Add to Daily Log', style: TextStyle(fontWeight: FontWeight.w600)),
                    onTap: context.read<LinkedSessionProvider>().canEdit ? () {
                      Navigator.pop(context);
                      _addEntryToDailyLog(provider, entry);
                    } : null,
                    enabled: context.read<LinkedSessionProvider>().canEdit,
                  ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.delete_outline, color: colorScheme.onErrorContainer),
                  ),
                  title: Text('Delete Entry', style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600)),
                  onTap: context.read<LinkedSessionProvider>().canEdit ? () {
                    Navigator.pop(context);
                    _confirmDeleteEntry(entry);
                  } : null,
                  enabled: context.read<LinkedSessionProvider>().canEdit,
                ),
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

  double? _parseOpeningBalanceValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 0;
    }

    return double.tryParse(trimmed);
  }

  bool _amountEquals(double first, double second) {
    return (first - second).abs() < 0.0001;
  }

  String _openingBalanceSignature(double debit, double credit) {
    return '${debit.toStringAsFixed(2)}|${credit.toStringAsFixed(2)}';
  }

  SnapshotOpeningBalance _readOpeningBalance(LedgerProvider provider) {
    final dynamic dynamicProvider = provider;

    try {
      final value = dynamicProvider.openingBalance;
      if (value is SnapshotOpeningBalance) {
        return value;
      }
    } catch (_) {}

    return const SnapshotOpeningBalance(debit: 0, credit: 0);
  }

  Future<bool> _saveProviderOpeningBalance(
    LedgerProvider provider, {
    required double debit,
    required double credit,
  }) async {
    final dynamic dynamicProvider = provider;

    try {
      final result = await dynamicProvider.setOpeningBalance(
        debit: debit,
        credit: credit,
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
    _openingDebitController.text = debitText;
    _openingCreditController.text = creditText;
    _lastOpeningBalanceSignature = _openingBalanceSignature(
      openingBalance.debit,
      openingBalance.credit,
    );
  }

  void _syncOpeningBalanceControllers(LedgerProvider provider) {
    final openingBalance = _readOpeningBalance(provider);
    final signature = _openingBalanceSignature(
      openingBalance.debit,
      openingBalance.credit,
    );
    final isEditing =
        _openingDebitFocusNode.hasFocus || _openingCreditFocusNode.hasFocus;
    final debitText = openingBalance.debit == 0
        ? ''
        : provider.formatAmount(openingBalance.debit);
    final creditText = openingBalance.credit == 0
        ? ''
        : provider.formatAmount(openingBalance.credit);
    final matchesController =
        _openingDebitController.text == debitText &&
        _openingCreditController.text == creditText;

    if (isEditing ||
        (_lastOpeningBalanceSignature == signature && matchesController)) {
      return;
    }

    _openingDebitController.text = debitText;
    _openingCreditController.text = creditText;
    _lastOpeningBalanceSignature = signature;
  }

  bool _hasOpeningBalanceDraftChanged(LedgerProvider provider) {
    final debit = _parseOpeningBalanceValue(_openingDebitController.text);
    final credit = _parseOpeningBalanceValue(_openingCreditController.text);
    final openingBalance = _readOpeningBalance(provider);

    if (debit == null || credit == null) {
      return false;
    }

    return !_amountEquals(debit, openingBalance.debit) ||
        !_amountEquals(credit, openingBalance.credit);
  }

  Future<void> _saveOpeningBalance() async {
    FocusScope.of(context).unfocus();

    final debit = _parseOpeningBalanceValue(_openingDebitController.text);
    final credit = _parseOpeningBalanceValue(_openingCreditController.text);

    if (debit == null || credit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid opening balance amount.')),
      );
      return;
    }

    final provider = context.read<LedgerProvider>();
    final isSaved = await _saveProviderOpeningBalance(
      provider,
      debit: debit,
      credit: credit,
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
      _lastOpeningBalanceSignature = _openingBalanceSignature(0, 0);
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
        if (context.read<LinkedSessionProvider>().canEdit) {
          await _showEditCustomerDialog(provider);
        }
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
            unawaited(
              _handleAppBarAction(
                action,
                provider: provider,
              ),
            );
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
                  PopupMenuItem<_LedgerAppBarAction>(
                    value: _LedgerAppBarAction.editCustomer,
                    enabled: context.read<LinkedSessionProvider>().canEdit,
                    child: _buildAppBarMenuItem(
                      context,
                      icon: Icons.edit_outlined,
                      label: 'Edit Customer',
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
                FilledButton.icon(
                  onPressed: context.watch<LinkedSessionProvider>().canEdit ? _showAddEntryDialog : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Entry'),
                ),
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
                  child: Text(
                    'Date Filters',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
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
    final readOnly = false;
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
                      child: Text(
                        'Opening Balance',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
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
                      IconButton(
                        tooltip: 'Clear opening balance',
                        onPressed:
                            !provider.hasOpeningBalance || !context.read<LinkedSessionProvider>().canEdit
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
                        onPressed:
                            hasInvalidAmount || !hasChanges || !context.read<LinkedSessionProvider>().canEdit
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
                            !context.read<LinkedSessionProvider>().canEdit
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
                            !context.read<LinkedSessionProvider>().canEdit
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
                if (constraints.maxWidth < 520) {
                  return Column(
                    children: <Widget>[
                      _buildOpeningBalanceField(
                        context: context,
                        controller: _openingDebitController,
                        focusNode: _openingDebitFocusNode,
                        label: 'Debit Opening Balance',
                        icon: Icons.arrow_downward_rounded,
                        accentColor: AppColors.debit,
                        readOnly: readOnly,
                        compact: compactForDesktop,
                      ),
                      const SizedBox(height: 10),
                      _buildOpeningBalanceField(
                        context: context,
                        controller: _openingCreditController,
                        focusNode: _openingCreditFocusNode,
                        label: 'Credit Opening Balance',
                        icon: Icons.arrow_upward_rounded,
                        accentColor: AppColors.credit,
                        readOnly: readOnly,
                        compact: compactForDesktop,
                      ),
                    ],
                  );
                }

                return Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildOpeningBalanceField(
                        context: context,
                        controller: _openingDebitController,
                        focusNode: _openingDebitFocusNode,
                        label: 'Debit Opening Balance',
                        icon: Icons.arrow_downward_rounded,
                        accentColor: const Color(0xFF0F766E),
                        readOnly: readOnly,
                        compact: compactForDesktop,
                      ),
                    ),
                    SizedBox(width: compactForDesktop ? 8 : 10),
                    Expanded(
                      child: _buildOpeningBalanceField(
                        context: context,
                        controller: _openingCreditController,
                        focusNode: _openingCreditFocusNode,
                        label: 'Credit Opening Balance',
                        icon: Icons.arrow_upward_rounded,
                        accentColor: const Color(0xFFB45309),
                        readOnly: readOnly,
                        compact: compactForDesktop,
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

  Widget _buildOpeningBalanceField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required Color accentColor,
    required bool readOnly,
    bool compact = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      scrollPadding: const EdgeInsets.only(bottom: 180),
      readOnly: readOnly,
      inputFormatters: <TextInputFormatter>[
        DecimalTextInputFormatter(decimalRange: 2),
      ],
      onChanged: readOnly
          ? null
          : (_) {
              setState(() {});
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
    final balanceAccent = AppColors.balanceColor(provider.finalBalance);

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
                    Text(
                      provider.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _buildMobileInfoPill(
                          context,
                          icon: Icons.filter_alt_outlined,
                          label: _shortActiveFilterLabel(provider),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
                IconButton.filledTonal(
                  tooltip: 'Edit customer details',
                  onPressed: () => _showEditCustomerDialog(provider),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: balanceAccent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: balanceAccent.withValues(alpha: 0.16)),
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
                  child: Text(
                    provider.formatBalance(provider.finalBalance),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
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
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
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
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLedgerControls({
    required BuildContext context,
    required LedgerProvider provider,
  }) {
    final openingBalance = _readOpeningBalance(provider);
    final openingLabel = openingBalance.hasValue
        ? provider.formatBalance(openingBalance.finalBalance)
        : '0';

    return Column(
      children: <Widget>[
        _buildMobileToggleHeader(
          context,
          icon: Icons.account_balance_wallet_rounded,
          title: 'Opening Balance',
          value: openingLabel,
          expanded: _showOpeningBalancePanel,
          onTap: () {
            setState(() {
              _showOpeningBalancePanel = !_showOpeningBalancePanel;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showOpeningBalancePanel
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                    child: _buildOpeningBalanceSection(
                      context: context,
                      provider: provider,
                    ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 10),
        _buildMobileToggleHeader(
          context,
          icon: Icons.tune_rounded,
          title: 'Date Filter',
          value: _shortActiveFilterLabel(provider),
          expanded: _showDateFilterPanel,
          onTap: () {
            setState(() {
              _showDateFilterPanel = !_showDateFilterPanel;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showDateFilterPanel
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildFilterBar(context: context, provider: provider),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildMobileToggleHeader(
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

  Widget _buildCustomerInfoCard(
    BuildContext context,
    LedgerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customer = provider.customer;
    final balanceAccent = AppColors.balanceColor(provider.finalBalance);

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
                    final titleBlock = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _buildHeroMetaChip(
                              context,
                              icon: Icons.filter_alt_outlined,
                              label: _shortActiveFilterLabel(provider),
                            ),
                            _buildHeroMetaChip(
                              context,
                              icon: Icons.receipt_long_outlined,
                              label: '${provider.entries.length} entries',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          provider.customerName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 23,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Local Workspace',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    );
                    final balanceCard = _buildHeroBalanceCard(
                      context,
                      value: provider.formatBalance(provider.finalBalance),
                      accentColor: balanceAccent,
                    );
                    final editButton = IconButton.filledTonal(
                            tooltip: 'Edit customer details',
                            onPressed: () => _showEditCustomerDialog(provider),
                            style: IconButton.styleFrom(
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.primary,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                          );

                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(child: titleBlock),
                              ...<Widget>[
                              const SizedBox(width: 12),
                              editButton,
                            ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          balanceCard,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(child: titleBlock),
                              ...<Widget>[
                              const SizedBox(width: 12),
                              editButton,
                            ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(width: 188, child: balanceCard),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final tileWidth = constraints.maxWidth >= 840
                        ? (constraints.maxWidth - 24) / 3
                        : constraints.maxWidth >= 520
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        SizedBox(
                          width: tileWidth,
                          child: _CustomerInfoTile(
                            label: 'Customer ID',
                            value: '${customer.id ?? '-'}',
                            icon: Icons.badge_outlined,
                            backgroundColor: colorScheme.surface,
                            labelColor: colorScheme.onSurfaceVariant,
                            valueColor: colorScheme.onSurface,
                            borderColor: colorScheme.outlineVariant,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _CustomerInfoTile(
                            label: 'Address',
                            value: customer.displayAddress,
                            icon: Icons.location_on_outlined,
                            backgroundColor: colorScheme.surface,
                            labelColor: colorScheme.onSurfaceVariant,
                            valueColor: colorScheme.onSurface,
                            borderColor: colorScheme.outlineVariant,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _CustomerInfoTile(
                            label: 'Phone Number',
                            value: customer.displayPhone,
                            icon: Icons.call_outlined,
                            backgroundColor: colorScheme.surface,
                            labelColor: colorScheme.onSurfaceVariant,
                            valueColor: colorScheme.onSurface,
                            borderColor: colorScheme.outlineVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLedgerHeader(
    BuildContext context,
    LedgerProvider provider,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customer = provider.customer;
    final items = <({String label, String value})>[
      (label: 'Customer ID', value: '${customer.id ?? '-'}'),
      (label: 'Address', value: customer.displayAddress),
      (label: 'Phone Number', value: customer.displayPhone),
      (label: 'Total Debit', value: provider.formatAmount(provider.totalDebit)),
      (
        label: 'Total Credit',
        value: provider.formatAmount(provider.totalCredit),
      ),
      (label: 'Balance', value: provider.formatBalance(provider.finalBalance)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                provider.customerName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
              IconButton(
                tooltip: 'Edit customer details',
                onPressed: () => _showEditCustomerDialog(provider),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= 1400
                ? 6
                : constraints.maxWidth >= 1080
                ? 4
                : constraints.maxWidth >= 760
                ? 3
                : 2;
            const spacing = 12.0;
            final tileWidth =
                (constraints.maxWidth - ((columns - 1) * spacing)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: <Widget>[
                for (final item in items) ...[
                  () {
                    final isDebit = item.label == 'Total Debit';
                    final isCredit = item.label == 'Total Credit';
                    final isBalance = item.label == 'Balance';
                    final isMetric = isDebit || isCredit || isBalance;
                    
                    final bgColor = isDebit 
                      ? AppColors.debit 
                      : isCredit 
                        ? AppColors.credit 
                        : isBalance 
                          ? (AppColors.balanceColor(provider.finalBalance) == AppColors.debit 
                              ? AppColors.debit 
                              : (AppColors.balanceColor(provider.finalBalance) == AppColors.credit ? AppColors.credit : Colors.grey.shade600))
                          : colorScheme.surface;

                    return SizedBox(
                      width: tileWidth,
                      child: _CustomerInfoTile(
                        label: item.label,
                        value: item.value,
                        backgroundColor: bgColor,
                        labelColor: isMetric ? Colors.white70 : colorScheme.onSurfaceVariant,
                        valueColor: isMetric ? Colors.white : colorScheme.onSurface,
                        borderColor: isMetric ? Colors.transparent : colorScheme.outlineVariant,
                        isMetric: isMetric,
                      ),
                    );
                  }(),
                ],
              ],
            );
          },
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
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Current Balance',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
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
    if (PlatformHelper.isDesktop && !isCompact) {
      return Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Ledger Entries',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (provider.isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
        ],
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final countLabel =
        '${provider.entries.length} ${provider.entries.length == 1 ? 'entry' : 'entries'}';
    final trailing = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            countLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (provider.isLoading)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 18,
        vertical: isCompact ? 12 : 16,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(isCompact ? 18 : 26),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.92),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Ledger Entries',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                trailing,
              ],
            );
          }

          return Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Ledger Entries',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          );
        },
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
            final useWideTopLayout = constraints.maxWidth >= 980;
            final useCardLayout = constraints.maxWidth < 760;
            final hasFab = isCompact;
            const desktopHorizontalPadding = 20.0;
            final desktopPageWidth = constraints.maxWidth;
            const desktopTopCardHeight = 112.0;
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
                if (isCompact) ...<Widget>[
                  _buildMobileLedgerControls(
                    context: context,
                    provider: provider,
                  ),
                ] else if (useWideTopLayout) ...<Widget>[
                  SizedBox(
                    height: desktopTopCardHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: _buildOpeningBalanceSection(
                            context: context,
                            provider: provider,
                            compactForDesktop: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFilterBar(
                            context: context,
                            provider: provider,
                            compactForDesktop: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...<Widget>[
                  _buildOpeningBalanceSection(
                    context: context,
                    provider: provider,
                  ),
                  const SizedBox(height: 12),
                  _buildFilterBar(context: context, provider: provider),
                ],
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
              floatingActionButton: hasFab && context.watch<LinkedSessionProvider>().canEdit
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
                    LogicalKeySet(LogicalKeyboardKey.arrowDown):
                        const _ScrollIntent(80),
                    LogicalKeySet(LogicalKeyboardKey.arrowUp):
                        const _ScrollIntent(-80),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      _LedgerIntent: CallbackAction<_LedgerIntent>(
                        onInvoke: (_LedgerIntent intent) {
                          final canEdit = context.read<LinkedSessionProvider>().canEdit;
                          if (intent.action == _LedgerShortcut.addEntry && canEdit) {
                              _showAddEntryDialog();
                          } else if (intent.action == _LedgerShortcut.export) {
                            _exportWithOptions();
                          } else if (intent.action == _LedgerShortcut.print) {
                            _printPdf();
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
      return _buildCompactLedgerEntries(
        context,
        provider,
      );
    }

    final dataTextStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final horizontalMargin = PlatformHelper.isDesktop
            ? constraints.maxWidth >= 1700
                ? 22.0
                : constraints.maxWidth >= 1450
                    ? 16.0
                    : 12.0
            : 12.0;
        final columnSpacing = PlatformHelper.isDesktop
            ? constraints.maxWidth >= 1700
                ? 42.0
                : constraints.maxWidth >= 1450
                    ? 28.0
                    : 18.0
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
                columns: const <DataColumn>[
                  DataColumn(label: Text('Entry Date')),
                  DataColumn(label: Text('Created Date')),
                  DataColumn(label: Text('Page No')),
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                  DataColumn(label: Text('Balance')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: _buildLedgerRows(
                  provider,
                  compact: false,
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
    final children = <Widget>[];
    double? runningBalance;

    for (var index = 0; index < provider.entries.length; index++) {
      final entry = provider.entries[index];
      final isOpeningBalanceEntry = _isOpeningBalanceEntry(provider, entry);
      final debit = entry.debit;
      final credit = entry.credit;
      final hasValue = debit != 0 || credit != 0;
      var balanceLabel = '';

      if (hasValue) {
        final currentBalance = (runningBalance ?? 0) + debit - credit;
        runningBalance = currentBalance;
        balanceLabel = provider.formatBalance(currentBalance);
      }

      if (index != 0) {
        children.add(const SizedBox(height: 12));
      }

      children.add(
        _buildLedgerEntryCard(
          context,
          provider,
          entry: entry,
          balanceLabel: balanceLabel,
          isOpeningBalanceEntry: isOpeningBalanceEntry,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildLedgerEntryCard(
    BuildContext context,
    LedgerProvider provider, {
    required Entry entry,
    required String balanceLabel,
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
              if (entry.pageNo.trim().isNotEmpty)
                _buildEntryMetaChip(
                  context,
                  icon: Icons.bookmark_border_rounded,
                  label: 'Page ${entry.pageNo}',
                  accentColor: accentColor,
                ),
              if (entry.dailyLogPageNo.trim().isNotEmpty)
                _buildEntryMetaChip(
                  context,
                  icon: Icons.menu_book_outlined,
                  label: 'DL Pg ${entry.dailyLogPageNo}',
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
          const SizedBox(height: 10),
          Text(
            entry.displayDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              if (constraints.maxWidth < 520) {
                return _buildEntryAmountStrip(
                  context,
                  provider,
                  entry: entry,
                  balanceLabel: balanceLabel,
                  accentColor: accentColor,
                );
              }

              final columnCount = constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 420
                  ? 2
                  : 1;
              const spacing = 12.0;
              final tileWidth =
                  (constraints.maxWidth - ((columnCount - 1) * spacing)) /
                  columnCount;

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
                      accentColor: accentColor,
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
              if (isOpeningBalanceEntry)
                IconButton(
                  tooltip: 'Clear opening balance',
                  onPressed: context.watch<LinkedSessionProvider>().canEdit ? () => _clearOpeningBalance(provider) : null,
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
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: highlight ? accentColor : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryAmountStrip(
    BuildContext context,
    LedgerProvider provider, {
    required Entry entry,
    required String balanceLabel,
    required Color accentColor,
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
            child: _buildEntryAmountStripItem(
              context,
              label: 'Debit',
              value: provider.formatAmount(entry.debit),
              accentColor: const Color(0xFF0F766E),
            ),
          ),
          _buildEntryAmountDivider(context),
          Expanded(
            child: _buildEntryAmountStripItem(
              context,
              label: 'Credit',
              value: provider.formatAmount(entry.credit),
              accentColor: const Color(0xFFB45309),
            ),
          ),
          _buildEntryAmountDivider(context),
          Expanded(
            child: _buildEntryAmountStripItem(
              context,
              label: 'Balance',
              value: balanceLabel.isEmpty ? '0' : balanceLabel,
              accentColor: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryAmountDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildEntryAmountStripItem(
    BuildContext context, {
    required String label,
    required String value,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
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
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
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
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerStats(BuildContext context, LedgerProvider provider) {
    final items =
        <({String label, String value, IconData icon, Color accentColor})>[
          (
            label: 'Total Debit',
            value: provider.formatAmount(provider.totalDebit),
            icon: Icons.south_west_rounded,
            accentColor: const Color(0xFF0F766E),
          ),
          (
            label: 'Total Credit',
            value: provider.formatAmount(provider.totalCredit),
            icon: Icons.north_east_rounded,
            accentColor: const Color(0xFFB45309),
          ),
          (
            label: 'Net Balance',
            value: provider.formatBalance(provider.finalBalance),
            icon: Icons.account_balance_wallet_outlined,
            accentColor: Theme.of(context).colorScheme.primary,
          ),
        ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final columnCount = constraints.maxWidth >= 920
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const spacing = 12.0;
        final tileWidth =
            (constraints.maxWidth - ((columnCount - 1) * spacing)) /
            columnCount;

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
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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

  Future<void> _showTransferDialog(
    LedgerProvider provider,
    Entry entry,
  ) async {


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

    for (final entry in provider.entries) {
      final isOpeningBalanceEntry = _isOpeningBalanceEntry(provider, entry);
      final debit = entry.debit;
      final credit = entry.credit;
      final hasValue = debit != 0 || credit != 0;
      String balanceLabel = '';
      final rowStyle = isOpeningBalanceEntry
          ? Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
          : null;

      if (hasValue) {
        final currentBalance = (runningBalance ?? 0) + debit - credit;
        runningBalance = currentBalance;
        balanceLabel = provider.formatBalance(currentBalance);
      }

      rows.add(
        DataRow(
          color: isOpeningBalanceEntry
              ? WidgetStatePropertyAll<Color?>(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                )
              : null,
          cells: <DataCell>[
            DataCell(Text(_formatStoredDate(entry.entryDate), style: rowStyle)),
            DataCell(Text(_formatStoredDate(entry.createdAt), style: rowStyle)),
            DataCell(
              Text(
                [
                  if (entry.pageNo.isNotEmpty) entry.pageNo,
                  if (entry.dailyLogPageNo.isNotEmpty) 'DL: ${entry.dailyLogPageNo}'
                ].join(' | ').isEmpty ? '-' : [
                  if (entry.pageNo.isNotEmpty) entry.pageNo,
                  if (entry.dailyLogPageNo.isNotEmpty) 'DL: ${entry.dailyLogPageNo}'
                ].join(' | '),
                style: rowStyle?.copyWith(
                  color: entry.dailyLogPageNo.isNotEmpty ? colorScheme.tertiary : null,
                  fontWeight: entry.dailyLogPageNo.isNotEmpty ? FontWeight.bold : null,
                ),
              ),
            ),
            DataCell(
              SizedBox(
                width: compact ? 220 : 260,
                child: Text(
                  entry.displayDescription,
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
            DataCell(
              Text(
                balanceLabel,
                style: (rowStyle ?? const TextStyle()).copyWith(
                  color: AppColors.balanceLabelColor(balanceLabel),
                ),
              ),
            ),
            DataCell(
              isOpeningBalanceEntry
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
          ],
        ),
      );
    }

    return rows;
  }
}

class _EntryDraft {
  const _EntryDraft({
    required this.entryDate,
    required this.pageNo,
    required this.description,
    required this.debit,
    required this.credit,
  });

  final DateTime entryDate;
  final String pageNo;
  final String description;
  final double debit;
  final double credit;
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
                    Text(
                      supportingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.2,
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dayOfWeek = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][date.weekday % 7];
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
  const _AddEntryDialog();

  @override
  State<_AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<_AddEntryDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pageNoController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _debitController = TextEditingController();
  final TextEditingController _creditController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _loadSelectedDate();
  }

  @override
  void dispose() {
    _pageNoController.dispose();
    _descriptionController.dispose();
    _debitController.dispose();
    _creditController.dispose();
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
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final debit = double.tryParse(_debitController.text.trim()) ?? 0;
    final credit = double.tryParse(_creditController.text.trim()) ?? 0;

    if (debit == 0 && credit == 0) {
      setState(() {
        _amountError = 'Enter a debit or credit amount.';
      });
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
      ),
    );
  }

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parsedValue = double.tryParse(value.trim());
    if (parsedValue == null) {
      return 'Enter a valid number';
    }

    if (parsedValue < 0) {
      return 'Amount cannot be negative';
    }

    return null;
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
            SizedBox(height: fieldGap),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
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
            if (_amountError != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _amountError!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.entry});

  final Entry entry;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pageNoController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _debitController = TextEditingController();
  final TextEditingController _creditController = TextEditingController();

  late DateTime _selectedDate;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _pageNoController.text = widget.entry.pageNo;
    _descriptionController.text = widget.entry.description == '-'
        ? ''
        : widget.entry.description;
    _debitController.text = _formatAmount(widget.entry.debit);
    _creditController.text = _formatAmount(widget.entry.credit);
    _selectedDate = DateTime.tryParse(widget.entry.entryDate) ?? DateTime.now();
  }

  @override
  void dispose() {
    _pageNoController.dispose();
    _descriptionController.dispose();
    _debitController.dispose();
    _creditController.dispose();
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
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final debit = double.tryParse(_debitController.text.trim()) ?? 0;
    final credit = double.tryParse(_creditController.text.trim()) ?? 0;

    if (debit == 0 && credit == 0) {
      setState(() {
        _amountError = 'Enter a debit or credit amount.';
      });
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
      ),
    );
  }

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final parsedValue = double.tryParse(value.trim());
    if (parsedValue == null) {
      return 'Enter a valid number';
    }

    if (parsedValue < 0) {
      return 'Amount cannot be negative';
    }

    return null;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatAmount(double amount) => formatAmount(amount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
            SizedBox(height: fieldGap),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
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
            if (_amountError != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _amountError!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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

class _CustomerInfoTile extends StatelessWidget {
  const _CustomerInfoTile({
    required this.label,
    required this.value,
    this.icon,
    this.backgroundColor,
    this.labelColor,
    this.valueColor,
    this.borderColor,
    this.isMetric = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? labelColor;
  final Color? valueColor;
  final Color? borderColor;
  final bool isMetric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(22);

    final resolvedBg = backgroundColor ?? colorScheme.surfaceContainerLowest;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 240),
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
                    : borderColor ?? colorScheme.outlineVariant.withValues(alpha: 0.2),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (valueColor ?? colorScheme.primary).withValues(
                        alpha: 0.1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon, 
                      size: 18, 
                      color: isMetric ? Colors.white : (valueColor ?? colorScheme.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
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
                          color: isMetric ? Colors.white : (valueColor ?? colorScheme.onSurface),
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
