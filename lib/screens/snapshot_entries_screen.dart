import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../features/linked_devices/providers/linked_session_provider.dart';
import '../models/customer.dart';
import '../models/entry.dart';
import '../models/snapshot_opening_balance.dart';
import '../models/summary_snapshot.dart';
import '../providers/customer_provider.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../utils/app_colors.dart';
import '../utils/number_format_utils.dart';
import '../utils/platform_helper.dart';
import 'ledger_screen.dart';

class SnapshotEntriesScreen extends StatefulWidget {
  const SnapshotEntriesScreen({super.key});

  @override
  State<SnapshotEntriesScreen> createState() => _SnapshotEntriesScreenState();
}

enum _SnapshotExportChoice { pdf, excel }

enum _EntryDeletionOption { dailyLogOnly, both }

class _ScrollIntent extends Intent {
  const _ScrollIntent(this.delta);

  final double delta;
}

class _SnapshotEntriesScreenState extends State<SnapshotEntriesScreen> {
  final AppDatabase _database = AppDatabase.instance;
  final PdfService _pdfService = const PdfService();
  final ExportService _exportService = const ExportService();
  final ScrollController _entryTableVerticalController = ScrollController();
  final TextEditingController _debitOpeningBalanceController =
      TextEditingController();
  final TextEditingController _creditOpeningBalanceController =
      TextEditingController();

  List<SummarySnapshot> _snapshots = <SummarySnapshot>[];
  List<_SnapshotEntry> _entries = <_SnapshotEntry>[];
  SnapshotOpeningBalance? _savedOpeningBalance;
  bool _isLoading = true;
  bool _isSavingSnapshot = false;
  String? _errorMessage;
  bool _showDailyLogActions = false;
  bool _showDailyLatestSnapshot = false;
  bool _showDailyOpeningBalance = false;
  static const int _snapshotPageSize = 800;
  final Set<String> _expandedSnapshots = <String>{};
  String _searchQuery = '';

  SummarySnapshot? get _latestSnapshot =>
      _snapshots.isEmpty ? null : _snapshots.last;
  double get _openingDebitBalance =>
      double.tryParse(
        _debitOpeningBalanceController.text.trim().replaceAll(',', ''),
      ) ??
      0;
  double get _openingCreditBalance =>
      double.tryParse(
        _creditOpeningBalanceController.text.trim().replaceAll(',', ''),
      ) ??
      0;
  SnapshotOpeningBalance get _effectiveOpeningBalance => SnapshotOpeningBalance(
    debit: _openingDebitBalance,
    credit: _openingCreditBalance,
  );
  bool get _hasSavedOpeningBalance => _savedOpeningBalance?.hasValue ?? false;
  bool get _hasOpeningBalance => _effectiveOpeningBalance.hasValue;

  SnapshotOpeningBalance get _currentPeriodStartingBalance {
    final latestSnapshot = _latestSnapshot;
    if (latestSnapshot == null) {
      return _effectiveOpeningBalance;
    }

    return _balanceToOpening(latestSnapshot.finalBalance);
  }

  bool get _hasCurrentPeriodEntries {
    if (_currentPeriodStartingBalance.hasValue) {
      return true;
    }

    final latestSnapshot = _latestSnapshot;
    if (latestSnapshot == null) {
      return _entries.isNotEmpty;
    }

    return _entries.any(
      (_SnapshotEntry entry) =>
          _compareMoments(entry.entry.createdAt, latestSnapshot.savedAt) > 0,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadTimeline();
  }

  @override
  void dispose() {
    _entryTableVerticalController.dispose();
    _debitOpeningBalanceController.dispose();
    _creditOpeningBalanceController.dispose();
    super.dispose();
  }

  Future<void> _loadTimeline() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshotRows = await _database.getSummarySnapshots();
      final openingBalance = await _database.getSnapshotOpeningBalance();
      final snapshots =
          snapshotRows
              .map<SummarySnapshot>(
                (Map<String, Object?> row) => SummarySnapshot.fromMap(row),
              )
              .toList()
            ..sort(
              (SummarySnapshot a, SummarySnapshot b) =>
                  _compareMoments(a.savedAt, b.savedAt),
            );

      final entries = await _loadEntriesPaged(
        startDate: null,
        endDate: DateTime.now().toIso8601String(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _snapshots = snapshots;
        _entries = entries;
        _savedOpeningBalance = openingBalance;
        _errorMessage = null;
        _isLoading = false;
      });

      _debitOpeningBalanceController.text =
          openingBalance != null && openingBalance.debit != 0
          ? _formatAmount(openingBalance.debit)
          : '';
      _creditOpeningBalanceController.text =
          openingBalance != null && openingBalance.credit != 0
          ? _formatAmount(openingBalance.credit)
          : '';
    } catch (error) {
      debugPrint('SnapshotEntriesScreen._loadTimeline failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load snapshot entries.';
        _isLoading = false;
      });
    }
  }

  Future<void> _recalculateSnapshots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshotRows = await _database.getSummarySnapshots();
      final snapshots = snapshotRows
          .map((Map<String, Object?> row) => SummarySnapshot.fromMap(row))
          .toList()
          .reversed
          .toList();

      String? previousSavedAt;
      SnapshotOpeningBalance currentStartingBalance = _effectiveOpeningBalance;

      for (final snapshot in snapshots) {
        if (snapshot.id == null) continue;

        final entries = await _loadEntriesPaged(
          startDate: previousSavedAt,
          endDate: snapshot.savedAt,
        );

        final totals = _buildSnapshotTotals(
          entries: entries,
          startingBalance: currentStartingBalance,
        );

        await _database.updateSummarySnapshotTotals(
          id: snapshot.id!,
          overallDebit: totals.debit,
          overallCredit: totals.credit,
        );

        final finalBalance = totals.debit - totals.credit;
        currentStartingBalance = _balanceToOpening(finalBalance);
        previousSavedAt = snapshot.savedAt;
      }

      await _loadTimeline();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All snapshots recalculated successfully.'),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('SnapshotEntriesScreen._recalculateSnapshots failed: $e');
      debugPrint('$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to recalculate snapshots: $e')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSnapshot() async {
    if (_isLoading || _isSavingSnapshot) {
      return;
    }

    final savedAt = DateTime.now().toIso8601String();

    try {
      final entries = await _loadEntriesPaged(
        startDate: _latestSnapshot?.savedAt,
        endDate: savedAt,
      );
      final startingBalance = _currentPeriodStartingBalance;
      final snapshotTotals = _buildSnapshotTotals(
        entries: entries,
        startingBalance: startingBalance,
      );

      if (entries.isEmpty && !startingBalance.hasValue) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new entries to snapshot.')),
        );
        return;
      }

      final pageNoController = TextEditingController();
      if (!mounted) return;
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Save Snapshot'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter Daily Log Page Number (Optional):'),
                const SizedBox(height: 12),
                TextField(
                  controller: pageNoController,
                  decoration: const InputDecoration(
                    labelText: 'Page No',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      if (shouldSave != true) {
        return;
      }
      final dailyLogPageNo = pageNoController.text.trim();

      setState(() {
        _isSavingSnapshot = true;
        _errorMessage = null;
      });

      final customerIds = entries
          .map<int>((_SnapshotEntry entry) => entry.entry.customerId)
          .toSet();

      if (_latestSnapshot == null) {
        if (_effectiveOpeningBalance.hasValue) {
          await _database.setSnapshotOpeningBalance(
            debit: _effectiveOpeningBalance.debit,
            credit: _effectiveOpeningBalance.credit,
          );
          _savedOpeningBalance = _effectiveOpeningBalance;
        } else {
          await _database.clearSnapshotOpeningBalance();
          _savedOpeningBalance = null;
        }
      }

      await _database.addSummarySnapshot(
        savedAt: savedAt,
        overallDebit: snapshotTotals.debit,
        overallCredit: snapshotTotals.credit,
        customerCount: customerIds.length,
        dailyLogPageNo: dailyLogPageNo,
      );

      if (dailyLogPageNo.isNotEmpty) {
        final entryIds = entries
            .map((e) => e.entry.id)
            .where((id) => id != null)
            .cast<int>()
            .toList();
        if (entryIds.isNotEmpty) {
          await _database.batchUpdateDailyLogPageNo(
            entryIds: entryIds,
            dailyLogPageNo: dailyLogPageNo,
          );
        }
      }
      if (!_hasSavedOpeningBalance) {
        _debitOpeningBalanceController.clear();
        _creditOpeningBalanceController.clear();
      }
      await _loadTimeline();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Snapshot row saved.')));
    } catch (error, stackTrace) {
      debugPrint('SnapshotEntriesScreen._saveSnapshot failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unable to save snapshot.';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to save snapshot.')));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSnapshot = false;
        });
      }
    }
  }

  Future<void> _removeEntryFromDailyLog(Entry entry) async {
    if (entry.id == null) return;

    final option = await showDialog<_EntryDeletionOption>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Entry'),
          content: const Text(
            'Do you want to remove this entry only from Daily Logs, or delete it permanently from the Customer Ledger as well?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_EntryDeletionOption.dailyLogOnly),
              child: const Text('Daily Logs Only'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_EntryDeletionOption.both),
              child: const Text('Delete Permanently'),
            ),
          ],
        );
      },
    );

    if (option == null || !mounted) return;

    try {
      if (option == _EntryDeletionOption.dailyLogOnly) {
        await _database.updateEntryDailyLogVisibility(
          entryId: entry.id!,
          show: false,
        );
      } else {
        await _database.deleteEntry(entry.id!);
      }

      await _loadTimeline();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            option == _EntryDeletionOption.dailyLogOnly
                ? 'Entry removed from Daily Logs.'
                : 'Entry deleted permanently.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete entry: $e')));
    }
  }

  // Feature 7: Edit daily log page number on a saved snapshot
  Future<void> _editSnapshotPageNo(SummarySnapshot snapshot) async {
    final controller = TextEditingController(text: snapshot.dailyLogPageNo);
    final newPageNo = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit DL Page Number'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Page No',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.menu_book_outlined),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || newPageNo == null) return;
    final snapshotId = snapshot.id;
    if (snapshotId == null) return;

    try {
      await _database.updateSnapshotDailyLogPageNo(
        id: snapshotId,
        dailyLogPageNo: newPageNo,
      );

      // Also batch-update entries in that snapshot period with the new page no
      if (newPageNo.isNotEmpty) {
        final snapshotIndex = _snapshots.indexOf(snapshot);
        final previousSnapshot = snapshotIndex > 0
            ? _snapshots[snapshotIndex - 1]
            : null;
        final periodEntries = await _loadEntriesPaged(
          startDate: previousSnapshot?.savedAt,
          endDate: snapshot.savedAt,
        );
        final entryIds = periodEntries
            .map((e) => e.entry.id)
            .where((id) => id != null)
            .cast<int>()
            .toList();
        if (entryIds.isNotEmpty) {
          await _database.batchUpdateDailyLogPageNo(
            entryIds: entryIds,
            dailyLogPageNo: newPageNo,
          );
        }
      }

      await _loadTimeline();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newPageNo.isEmpty
              ? 'DL page number cleared.'
              : 'DL page number updated to "$newPageNo".'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update page number: $e')),
      );
    }
  }

  // Feature 8: Navigate to customer ledger on long-press
  Future<void> _navigateToCustomerLedger(_SnapshotEntry item) async {
    final customerId = item.entry.customerId;
    final customerRows = await _database.getCustomers();
    final customers = customerRows
        .map<Customer>((Map<String, Object?> row) => Customer.fromMap(row))
        .toList(growable: false);
    final customer = customers.cast<Customer?>().firstWhere(
      (Customer? c) => c?.id == customerId,
      orElse: () => null,
    );
    if (!mounted || customer == null) return;

    final customerProvider = context.read<CustomerProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiProvider(
          providers: [
            ChangeNotifierProvider<CustomerProvider>.value(
              value: customerProvider,
            ),
          ],
          child: LedgerScreen(
            customer: customer,
            autoOpenAddEntry: false,
          ),
        ),
      ),
    );
  }

  Future<List<_SnapshotEntry>> _loadEntriesPaged({
    required String? startDate,
    required String endDate,
  }) async {
    final entries = <_SnapshotEntry>[];
    var offset = 0;

    while (true) {
      final rows = await _database.getEntriesWithCustomerRangePaged(
        startDate: startDate,
        endDate: endDate,
        limit: _snapshotPageSize,
        offset: offset,
      );
      if (rows.isEmpty) {
        break;
      }

      entries.addAll(
        rows.map<_SnapshotEntry>(
          (Map<String, Object?> row) => _SnapshotEntry.fromMap(row),
        ),
      );

      if (rows.length < _snapshotPageSize) {
        break;
      }
      offset += _snapshotPageSize;
      await Future<void>.delayed(Duration.zero);
    }

    entries.sort(_compareEntries);
    return entries;
  }

  int _compareEntries(_SnapshotEntry a, _SnapshotEntry b) {
    final createdCompare = _compareMoments(
      a.entry.createdAt,
      b.entry.createdAt,
    );
    if (createdCompare != 0) {
      return createdCompare;
    }

    final entryDateCompare = _compareMoments(
      a.entry.entryDate,
      b.entry.entryDate,
    );
    if (entryDateCompare != 0) {
      return entryDateCompare;
    }

    return (a.entry.id ?? 0).compareTo(b.entry.id ?? 0);
  }

  int _compareMoments(String left, String right) {
    final leftDate = DateTime.tryParse(left);
    final rightDate = DateTime.tryParse(right);

    if (leftDate != null && rightDate != null) {
      return leftDate.compareTo(rightDate);
    }

    return left.compareTo(right);
  }

  String _formatAmount(double amount) => formatAmount(amount);

  String _formatBalance(double balance) => formatBalance(balance);

  String _formatDate(String value) {
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate == null) {
      return value;
    }

    final month = parsedDate.month.toString().padLeft(2, '0');
    final day = parsedDate.day.toString().padLeft(2, '0');
    return '${parsedDate.year}-$month-$day';
  }

  String _formatDateTime(String value) {
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate == null) {
      return value;
    }

    final month = parsedDate.month.toString().padLeft(2, '0');
    final day = parsedDate.day.toString().padLeft(2, '0');
    final hour = parsedDate.hour.toString().padLeft(2, '0');
    final minute = parsedDate.minute.toString().padLeft(2, '0');
    return '${parsedDate.year}-$month-$day $hour:$minute';
  }

  String _buildExportFileName(String suffix, String ext) {
    return 'snapshot_$suffix.$ext';
  }

  List<List<String>> _buildSnapshotExportRows({
    bool includeOpeningBalance = true,
  }) {
    final rows = <List<String>>[];
    var entryIndex = 0;
    // The snapshot export currently shows individual entry amounts and snapshot totals.
    // We are keeping track of indices but don't need running totals across individual rows here.

    if (includeOpeningBalance && _snapshots.isEmpty && _hasOpeningBalance) {
      final openingBalance = _effectiveOpeningBalance;
      rows.add(<String>[
        'Opening Balance',
        '-',
        'Starting amount',
        _formatAmount(openingBalance.debit),
        _formatAmount(openingBalance.credit),
        _formatBalance(openingBalance.debit - openingBalance.credit),
        '-',
      ]);
    }

    for (final snapshot in _snapshots) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          snapshot.dailyLogPageNo.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );
      final snapshotEntries = <List<String>>[];

      while (entryIndex < _entries.length &&
          _compareMoments(
                _entries[entryIndex].entry.createdAt,
                snapshot.savedAt,
              ) <=
              0) {
        final entry = _entries[entryIndex];
        
        // Individual entries in this export view don't currently show running balance/bags in the row list
    // to maintain a clean snapshot total focus.

        snapshotEntries.add(<String>[
          entry.customerName,
          _formatDate(entry.entry.entryDate),
          _formatDescription(entry),
          _formatAmount(entry.entry.debit),
          _formatAmount(entry.entry.credit),
          '',
          entry.entry.pageNo.isEmpty ? '-' : entry.entry.pageNo,
        ]);
        entryIndex++;
      }

      if (matchesSearch) {
        rows.addAll(snapshotEntries);
        rows.add(<String>[
          'Snapshot Total',
          _formatDateTime(snapshot.savedAt),
          'Total',
          _formatAmount(snapshot.overallDebit),
          _formatAmount(snapshot.overallCredit),
          _formatBalance(snapshot.finalBalance),
          snapshot.dailyLogPageNo.isNotEmpty ? 'DL Pg ${snapshot.dailyLogPageNo}' : '-',
        ]);

        // Next snapshot starts fresh with its own total calculation
        
        final carryForward = _balanceToOpening(snapshot.finalBalance);
        if (carryForward.hasValue) {
          rows.add(<String>[
            'Balance B/F',
            '-',
            'From previous snapshot',
            _formatAmount(carryForward.debit),
            _formatAmount(carryForward.credit),
            _formatBalance(carryForward.debit - carryForward.credit),
            '-',
          ]);
        }
      }
    }

    while (entryIndex < _entries.length) {
      final entry = _entries[entryIndex];
      rows.add(<String>[
        entry.customerName,
        _formatDate(entry.entry.entryDate),
        _formatDescription(entry),
        _formatAmount(entry.entry.debit),
        _formatAmount(entry.entry.credit),
        '',
        entry.entry.pageNo.isEmpty ? '-' : entry.entry.pageNo,
      ]);
      entryIndex++;
    }

    return rows;
  }

  List<({String label, String value})> _buildSnapshotPdfSummaryItems() {
    final items = <({String label, String value})>[];

    var totalBuyAmt = 0.0;
    var totalSellAmt = 0.0;

    for (final entry in _entries) {
      totalBuyAmt += entry.entry.debit;
      totalSellAmt += entry.entry.credit;
    }

    final latestSnapshot = _latestSnapshot;
    final finalBalance = latestSnapshot?.finalBalance ??
        ((totalBuyAmt + _openingDebitBalance) - (totalSellAmt + _openingCreditBalance));
    
    items.add((label: 'Total Entries', value: _entries.length.toString()));
    items.add((label: 'Total Debit', value: _formatAmount(totalBuyAmt)));
    items.add((label: 'Total Credit', value: _formatAmount(totalSellAmt)));
    items.add((label: 'Net Balance', value: _formatBalance(finalBalance)));

    return items;
  }

  Future<void> _exportSnapshotPdf() async {
    final rows = _buildSnapshotExportRows(includeOpeningBalance: false);
    if (rows.isEmpty && !_hasOpeningBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No snapshot rows to export.')),
      );
      return;
    }

    try {
      await _pdfService.exportSnapshotPdf(
        title: 'Snapshot Export',
        headers: const <String>[
          'Customer',
          'Entry Date',
          'Description',
          'Debit',
          'Credit',
          'Balance',
          'Page No',
        ],
        rows: rows,
        fileName: _buildExportFileName('export', 'pdf'),
        summaryItems: _buildSnapshotPdfSummaryItems(),
        openingBalanceRow: _hasOpeningBalance
            ? <String>[
                'Opening Balance',
                '-',
                'Starting amount',
                _formatAmount(_effectiveOpeningBalance.debit),
                _formatAmount(_effectiveOpeningBalance.credit),
                _formatBalance(_effectiveOpeningBalance.debit - _effectiveOpeningBalance.credit),
                '-',
              ]
            : null,
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

  Future<void> _exportSnapshotExcel() async {
    final rows = _buildSnapshotExportRows();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No snapshot rows to export.')),
      );
      return;
    }

    try {
      await _exportService.saveCsv(
        dialogTitle: 'Export Snapshot (Excel)',
        fileName: _buildExportFileName('export', 'csv'),
        headers: const <String>[
          'Customer',
          'Entry Date',
          'Description',
          'Debit',
          'Credit',
          'Balance',
          'Page No',
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

  Future<void> _exportSnapshot() async {
    final choice = await showDialog<_SnapshotExportChoice>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Export Snapshot'),
          content: const Text('Choose an export format.'),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SnapshotExportChoice.excel),
              child: const Text('Excel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_SnapshotExportChoice.pdf),
              child: const Text('PDF'),
            ),
          ],
        );
      },
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == _SnapshotExportChoice.pdf) {
      await _exportSnapshotPdf();
    } else {
      await _exportSnapshotExcel();
    }
  }

  SnapshotOpeningBalance _balanceToOpening(double balance) {
    if (balance > 0) {
      return SnapshotOpeningBalance(debit: balance, credit: 0);
    }
    if (balance < 0) {
      return SnapshotOpeningBalance(debit: 0, credit: balance.abs());
    }
    return const SnapshotOpeningBalance(debit: 0, credit: 0);
  }

  _SnapshotTotals _buildSnapshotTotals({
    required Iterable<_SnapshotEntry> entries,
    required SnapshotOpeningBalance startingBalance,
  }) {
    return _SnapshotTotals(
      debit:
          startingBalance.debit +
          entries.fold<double>(
            0,
            (double sum, _SnapshotEntry entry) => sum + entry.entry.debit,
          ),
      credit:
          startingBalance.credit +
          entries.fold<double>(
            0,
            (double sum, _SnapshotEntry entry) => sum + entry.entry.credit,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const _ScrollIntent(80),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const _ScrollIntent(-80),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (_) {
              final canEdit = context.read<LinkedSessionProvider>().canEdit;
              if (!_isLoading &&
                  !_isSavingSnapshot &&
                  _hasCurrentPeriodEntries &&
                  canEdit) {
                _saveSnapshot();
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
              final canEdit = context.watch<LinkedSessionProvider>().canEdit;
              final isCompact =
                  !PlatformHelper.isDesktop && constraints.maxWidth < 760;
              final isDesktop = PlatformHelper.isDesktop;
              final latestSnapshot = _latestSnapshot;
              final headerActions = _buildHeaderActions(isCompact: isCompact, canEdit: canEdit);
              final bottomPadding =
                  12.0 + MediaQuery.viewInsetsOf(context).bottom;

              final page = SingleChildScrollView(
                controller: _entryTableVerticalController,
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
                    if (!isDesktop) ...<Widget>[
                      _buildSnapshotHero(context, compact: isCompact),
                      SizedBox(height: isCompact ? 10 : 12),
                      if (isCompact)
                        _buildCompactDailyLogControls(
                          context,
                          headerActions: headerActions,
                        )
                      else
                        headerActions,
                    ] else
                      headerActions,

                    if (isCompact) ...<Widget>[
                      const SizedBox(height: 10),
                    ] else ...<Widget>[
                      const SizedBox(height: 12),
                      if (isDesktop && latestSnapshot != null) ...<Widget>[
                        _buildDesktopSnapshotSummarySection(
                          context,
                          latestSnapshot,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildOpeningBalanceSection(context),
                      const SizedBox(height: 12),
                    ],
                    if (_snapshots.isNotEmpty) ...<Widget>[
                      _buildSearchBar(compact: isCompact),
                      const SizedBox(height: 16),
                    ],
                    _buildTimelineContent(context),
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

  void _scrollTable(double delta) {
    if (!_entryTableVerticalController.hasClients) {
      return;
    }
    final position = _entryTableVerticalController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _entryTableVerticalController.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  Widget _buildSearchBar({required bool compact}) {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search by DL Page No...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      onChanged: (String value) {
        setState(() {
          _searchQuery = value.trim();
        });
      },
    );
  }

  Widget _buildSnapshotHero(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 6 : 8,
        ),
        leading: CircleAvatar(
          backgroundColor: colorScheme.tertiaryContainer,
          foregroundColor: colorScheme.tertiary,
          child: const Icon(Icons.timeline_rounded),
        ),
        title: Text(
          'Daily Logs',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${_entries.length} entries, ${_snapshots.length} snapshots',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: _isLoading || _isSavingSnapshot
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : null,
      ),
    );
  }

  Widget _buildHeaderActions({required bool isCompact, required bool canEdit}) {
    final isDesktop = PlatformHelper.isDesktop;
    final actions = Wrap(
      alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: _isLoading || _isSavingSnapshot ? null : _loadTimeline,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
        if (_snapshots.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _isLoading || _isSavingSnapshot || !canEdit ? null : _recalculateSnapshots,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Recalculate'),
          ),
        OutlinedButton.icon(
          onPressed: _isLoading || _isSavingSnapshot ? null : _exportSnapshot,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export'),
        ),
        if (_snapshots.isNotEmpty)
          TextButton.icon(
            onPressed: _isLoading || _isSavingSnapshot || !canEdit ? null : _clearAllSnapshots,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(isDesktop ? 'Clear Snapshots' : 'Clear'),
          ),
        FilledButton.icon(
          onPressed:
              _isLoading || _isSavingSnapshot || !_hasCurrentPeriodEntries || !canEdit
              ? null
              : _saveSnapshot,
          icon: _isSavingSnapshot
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.bookmark_add_outlined),
          label: Text(_isSavingSnapshot ? 'Saving...' : 'Save Snapshot'),
        ),
      ],
    );

    return Align(
      alignment: isCompact ? Alignment.centerLeft : Alignment.centerRight,
      child: actions,
    );
  }

  Widget _buildCompactDailyLogControls(
    BuildContext context, {
    required Widget headerActions,
  }) {
    final latestSnapshot = _latestSnapshot;
    final openingLabel = _hasOpeningBalance
        ? _formatBalance(_effectiveOpeningBalance.finalBalance)
        : '0';

    return Column(
      children: <Widget>[
        _buildDailyToggleHeader(
          context,
          icon: Icons.bolt_outlined,
          title: 'Actions',
          value: _hasCurrentPeriodEntries ? 'Ready' : 'No new entries',
          expanded: _showDailyLogActions,
          onTap: () {
            setState(() {
              _showDailyLogActions = !_showDailyLogActions;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showDailyLogActions
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: headerActions,
                )
              : const SizedBox.shrink(),
        ),
        if (latestSnapshot != null) ...<Widget>[
          const SizedBox(height: 10),
          _buildDailyToggleHeader(
            context,
            icon: Icons.bookmark_added_outlined,
            title: 'Last Saved Snapshot',
            value:
                '${_formatDateTime(latestSnapshot.savedAt)} - ${_formatBalance(latestSnapshot.finalBalance)}',
            expanded: _showDailyLatestSnapshot,
            onTap: () {
              setState(() {
                _showDailyLatestSnapshot = !_showDailyLatestSnapshot;
              });
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _showDailyLatestSnapshot
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildCompactSnapshotSummaryCard(
                      context,
                      latestSnapshot,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        const SizedBox(height: 10),
        _buildDailyToggleHeader(
          context,
          icon: Icons.account_balance_wallet_outlined,
          title: 'Opening Balance',
          value: openingLabel,
          expanded: _showDailyOpeningBalance,
          onTap: () {
            setState(() {
              _showDailyOpeningBalance = !_showDailyOpeningBalance;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _showDailyOpeningBalance
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _buildOpeningBalanceSection(context),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildCompactSnapshotSummaryCard(
    BuildContext context,
    SummarySnapshot snapshot,
  ) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _formatDateTime(snapshot.savedAt),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _CompactAmountChip(
                  label: 'Debit',
                  value: _formatEntryAmount(snapshot.overallDebit),
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.debit,
                ),
                _CompactAmountChip(
                  label: 'Credit',
                  value: _formatEntryAmount(snapshot.overallCredit),
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.credit,
                ),
                _CompactAmountChip(
                  label: 'Balance',
                  value: _formatBalance(snapshot.finalBalance),
                  icon: snapshot.finalBalance > 0
                      ? Icons.arrow_downward_rounded
                      : (snapshot.finalBalance < 0
                          ? Icons.arrow_upward_rounded
                          : Icons.account_balance_wallet_outlined),
                  color: AppColors.balanceColor(snapshot.finalBalance),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSnapshotSummarySection(
    BuildContext context,
    SummarySnapshot snapshot,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          height: 56,
          child: Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: _buildDesktopSnapshotMetric(
                  context,
                  label: 'Last Saved Snapshot',
                  value: _formatDateTime(snapshot.savedAt),
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopSnapshotMetric(
                  context,
                  label: 'Debit',
                  value: _formatEntryAmount(snapshot.overallDebit),
                  icon: Icons.arrow_downward_rounded,
                  accentColor: AppColors.debit,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopSnapshotMetric(
                  context,
                  label: 'Credit',
                  value: _formatEntryAmount(snapshot.overallCredit),
                  icon: Icons.arrow_upward_rounded,
                  accentColor: AppColors.credit,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopSnapshotMetric(
                  context,
                  label: 'Balance',
                  value: _formatBalance(snapshot.finalBalance),
                  icon: snapshot.finalBalance > 0
                      ? Icons.arrow_downward_rounded
                      : (snapshot.finalBalance < 0
                          ? Icons.arrow_upward_rounded
                          : Icons.account_balance_wallet_outlined),
                  accentColor:
                      AppColors.balanceColor(snapshot.finalBalance) ==
                              AppColors.debit
                          ? AppColors.debit
                          : (AppColors.balanceColor(snapshot.finalBalance) ==
                                    AppColors.credit
                                ? AppColors.credit
                                : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSnapshotMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    Color? accentColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMetric = accentColor != null;
    final borderRadius = BorderRadius.circular(14);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isMetric
                ? accentColor.withValues(alpha: 0.15)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
            gradient: isMetric
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      accentColor.withValues(alpha: 0.25),
                      accentColor.withValues(alpha: 0.15),
                      accentColor.withValues(alpha: 0.2),
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
                      color: accentColor.withValues(alpha: 0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
            borderRadius: borderRadius,
            border: Border.all(
              color: isMetric 
                  ? accentColor.withValues(alpha: 0.3) 
                  : colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 1.2,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (isMetric ? Colors.white : colorScheme.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: isMetric ? Colors.white : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: isMetric
                            ? Colors.white.withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant,
                        fontSize: 9,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: isMetric ? Colors.white : colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

  Widget _buildDailyToggleHeader(
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
                  color: colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colorScheme.tertiary, size: 18),
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

  Widget _buildOpeningBalanceSection(BuildContext context) {

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final debitField = _buildOpeningBalanceField(
              controller: _debitOpeningBalanceController,
              label: 'Debit Opening Balance',
              icon: Icons.arrow_downward_rounded,
              readOnly: false,
            );
            final creditField = _buildOpeningBalanceField(
              controller: _creditOpeningBalanceController,
              label: 'Credit Opening Balance',
              icon: Icons.arrow_upward_rounded,
              readOnly: false,
            );

            if (constraints.maxWidth < 560) {
              return Column(
                children: <Widget>[
                  debitField,
                  const SizedBox(height: 12),
                  creditField,
                ],
              );
            }

            return Row(
              children: <Widget>[
                Expanded(child: debitField),
                const SizedBox(width: 12),
                Expanded(child: creditField),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOpeningBalanceField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool readOnly,
  }) {
    final canEdit = context.watch<LinkedSessionProvider>().canEdit;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      scrollPadding: const EdgeInsets.only(bottom: 180),
      readOnly: readOnly || !canEdit,
      onChanged: (readOnly || !canEdit)
          ? null
          : (_) {
              setState(() {});
            },
      decoration: InputDecoration(
        labelText: label,
        hintText: '0',
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _buildTimelineContent(BuildContext context) {
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
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadTimeline,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_entries.isEmpty && _snapshots.isEmpty) {
      if (_hasOpeningBalance) {
        return _buildEntryTable(context);
      }

      return const SizedBox(
        height: 240,
        child: Card(child: Center(child: Text('No customer entries yet.'))),
      );
    }

    return _buildEntryTable(context);
  }

  // ignore: unused_element
  Widget _buildCompactEntryCard(BuildContext context, _SnapshotEntry item) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.customerName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (item.entry.pageNo.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Page ${item.entry.pageNo}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatDate(item.entry.entryDate)} • ${_formatDescription(item)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _CompactAmountChip(
                  label: 'Debit',
                  value: _formatEntryAmount(item.entry.debit),
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.debit,
                ),
                _CompactAmountChip(
                  label: 'Credit',
                  value: _formatEntryAmount(item.entry.credit),
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.credit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactSnapshotCard(
    BuildContext context,
    SummarySnapshot snapshot, {
    required bool isExpanded,
  }) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedSnapshots.remove(snapshot.savedAt);
            } else {
              _expandedSnapshots.add(snapshot.savedAt);
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Snapshot Total',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (snapshot.dailyLogPageNo.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DL Pg ${snapshot.dailyLogPageNo}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Feature 7: Edit DL page number icon
                  if (context.watch<LinkedSessionProvider>().canEdit) ...[
                    IconButton(
                      tooltip: snapshot.dailyLogPageNo.isEmpty
                          ? 'Add DL Page No'
                          : 'Edit DL Page No',
                      onPressed: _isLoading || _isSavingSnapshot
                          ? null
                          : () => _editSnapshotPageNo(snapshot),
                      icon: Icon(
                        snapshot.dailyLogPageNo.isEmpty
                            ? Icons.post_add_rounded
                            : Icons.edit_note_rounded,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Delete snapshot',
                      onPressed: _isLoading || _isSavingSnapshot
                          ? null
                          : () => _deleteSnapshot(snapshot),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
              Text(
                _formatDateTime(snapshot.savedAt),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _CompactAmountChip(
                    label: 'Debit',
                    value: _formatEntryAmount(snapshot.overallDebit),
                    icon: Icons.arrow_downward_rounded,
                    color: AppColors.debit,
                  ),
                  _CompactAmountChip(
                    label: 'Credit',
                    value: _formatEntryAmount(snapshot.overallCredit),
                    icon: Icons.arrow_upward_rounded,
                    color: AppColors.credit,
                  ),
                  _CompactAmountChip(
                    label: 'Balance',
                    value: _formatBalance(snapshot.finalBalance),
                    icon: snapshot.finalBalance > 0
                        ? Icons.arrow_downward_rounded
                        : (snapshot.finalBalance < 0
                            ? Icons.arrow_upward_rounded
                            : Icons.account_balance_wallet_outlined),
                    color: AppColors.balanceColor(snapshot.finalBalance),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactBalanceCard(
    BuildContext context,
    SnapshotOpeningBalance balance, {
    String title = 'Opening Balance',
    String subtitle = 'Starting amount',
  }) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _CompactAmountChip(
                  label: 'Debit',
                  value: _formatEntryAmount(balance.debit),
                  icon: Icons.arrow_downward_rounded,
                  color: AppColors.debit,
                ),
                _CompactAmountChip(
                  label: 'Credit',
                  value: _formatEntryAmount(balance.credit),
                  icon: Icons.arrow_upward_rounded,
                  color: AppColors.credit,
                ),
                _CompactAmountChip(
                  label: 'Balance',
                  value: _formatBalance(balance.finalBalance),
                  icon: balance.finalBalance > 0
                      ? Icons.arrow_downward_rounded
                      : (balance.finalBalance < 0
                          ? Icons.arrow_upward_rounded
                          : Icons.account_balance_wallet_outlined),
                  color: AppColors.balanceColor(balance.finalBalance),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTimeline(BuildContext context) {
    final items = <Widget>[];
    var entryIndex = _entries.length - 1;

    final currentEntries = <Widget>[];
    while (entryIndex >= 0 &&
        (_snapshots.isEmpty ||
            _compareMoments(
                  _entries[entryIndex].entry.createdAt,
                  _snapshots.last.savedAt,
                ) >
                0)) {
      currentEntries.add(
        _buildTimelineEntryCard(context, _entries[entryIndex]),
      );
      entryIndex--;
    }
    final showCurrentEntries = _searchQuery.isEmpty;
    if (showCurrentEntries) {
      items.addAll(currentEntries);
    }

    for (var i = _snapshots.length - 1; i >= 0; i--) {
      final snapshot = _snapshots[i];
      final previousSnapshot = i > 0 ? _snapshots[i - 1] : null;

      final isExpanded = _expandedSnapshots.contains(snapshot.savedAt);
      final snapshotEntries = <Widget>[];

      while (entryIndex >= 0 &&
          (previousSnapshot == null ||
              _compareMoments(
                    _entries[entryIndex].entry.createdAt,
                    previousSnapshot.savedAt,
                  ) >
                  0)) {
        if (isExpanded) {
          snapshotEntries.add(
            _buildTimelineEntryCard(context, _entries[entryIndex]),
          );
        }
        entryIndex--;
      }

      final matchesSearch =
          _searchQuery.isEmpty ||
          snapshot.dailyLogPageNo.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );

      if (matchesSearch) {
        items.add(
          _buildCompactSnapshotCard(context, snapshot, isExpanded: isExpanded),
        );
        if (isExpanded) {
          items.addAll(snapshotEntries);
        }

        if (previousSnapshot != null) {
          final carryForward = _balanceToOpening(previousSnapshot.finalBalance);
          if (carryForward.hasValue) {
            items.add(
              _buildCompactBalanceCard(
                context,
                carryForward,
                title: 'Balance B/F',
                subtitle: 'From previous snapshot',
              ),
            );
          }
        } else if (_hasOpeningBalance) {
          items.add(
            _buildCompactBalanceCard(context, _effectiveOpeningBalance),
          );
        }
      }
    }

    if (_snapshots.isEmpty && _hasOpeningBalance && _searchQuery.isEmpty) {
      items.add(_buildCompactBalanceCard(context, _effectiveOpeningBalance));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < items.length; index++) ...<Widget>[
          if (index != 0) const SizedBox(height: 10),
          items[index],
        ],
      ],
    );
  }

  Widget _buildTimelineEntryCard(BuildContext context, _SnapshotEntry item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Feature 8: Long-press to navigate to customer ledger
    return GestureDetector(
      onLongPress: () => _navigateToCustomerLedger(item),
      child: Container(
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
                  item.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (item.entry.pageNo.isNotEmpty) ...[
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
                    'Page ${item.entry.pageNo}',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (context.watch<LinkedSessionProvider>().canEdit)
                IconButton(
                  tooltip: 'Delete or Remove Entry',
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _removeEntryFromDailyLog(item.entry),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDate(item.entry.entryDate)} - ${_formatDescription(item)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _buildDailyAmountStrip(
            context,
            debit: _formatEntryAmount(item.entry.debit),
            credit: _formatEntryAmount(item.entry.credit),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildDailyAmountStrip(
    BuildContext context, {
    required String debit,
    required String credit,
    String? balance,
    Color? balanceColor,
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
            child: _buildDailyStripItem(
              context,
              label: 'Debit',
              value: debit,
              icon: Icons.arrow_downward_rounded,
              color: AppColors.debit,
            ),
          ),
          _dailyStripDivider(context),
          Expanded(
            child: _buildDailyStripItem(
              context,
              label: 'Credit',
              value: credit,
              icon: Icons.arrow_upward_rounded,
              color: AppColors.credit,
            ),
          ),
          if (balance != null) ...<Widget>[
            _dailyStripDivider(context),
            Expanded(
              child: _buildDailyStripItem(
                context,
                label: 'Balance',
                value: balance,
                icon: balance.startsWith('-')
                    ? Icons.arrow_upward_rounded
                    : (balance == '-' || balance == '0'
                        ? Icons.account_balance_wallet_outlined
                        : Icons.arrow_downward_rounded),
                color: balanceColor ?? colorScheme.tertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dailyStripDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _buildDailyStripItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
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
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntryTable(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompactTable = constraints.maxWidth < 760;
        if (isCompactTable) {
          return _buildCompactTimeline(context);
        }

        final dataTextStyle = Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontSize: 14);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                dataTextStyle: dataTextStyle,
                horizontalMargin: 12,
                columnSpacing: 16,
                headingRowHeight: 56,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 64,
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                columns: const <DataColumn>[
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Entry Date')),
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Debit'), numeric: true),
                  DataColumn(label: Text('Credit'), numeric: true),
                  DataColumn(label: Text('Balance')),
                  DataColumn(label: Text('Page No')),
                  DataColumn(label: Text('Action')),
                ],
                rows: _buildTimelineRows(context, compact: false),
              ),
            ),
          ),
        );
      },
    );
  }

  List<DataRow> _buildTimelineRows(
    BuildContext context, {
    required bool compact,
  }) {
    final rows = <DataRow>[];
    var entryIndex = _entries.length - 1;

    final currentEntries = <DataRow>[];
    while (entryIndex >= 0 &&
        (_snapshots.isEmpty ||
            _compareMoments(
                  _entries[entryIndex].entry.createdAt,
                  _snapshots.last.savedAt,
                ) >
                0)) {
      currentEntries.add(
        _buildEntryRow(_entries[entryIndex], compact: compact),
      );
      entryIndex--;
    }
    final showCurrentEntries = _searchQuery.isEmpty;
    if (showCurrentEntries) {
      rows.addAll(currentEntries);
    }

    for (var i = _snapshots.length - 1; i >= 0; i--) {
      final snapshot = _snapshots[i];
      final previousSnapshot = i > 0 ? _snapshots[i - 1] : null;

      final isExpanded = _expandedSnapshots.contains(snapshot.savedAt);
      final snapshotEntries = <DataRow>[];

      while (entryIndex >= 0 &&
          (previousSnapshot == null ||
              _compareMoments(
                    _entries[entryIndex].entry.createdAt,
                    previousSnapshot.savedAt,
                  ) >
                  0)) {
        if (isExpanded) {
          snapshotEntries.add(
            _buildEntryRow(_entries[entryIndex], compact: compact),
          );
        }
        entryIndex--;
      }

      final matchesSearch =
          _searchQuery.isEmpty ||
          snapshot.dailyLogPageNo.toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );

      if (matchesSearch) {
        rows.add(
          _buildSnapshotTotalRow(
            context,
            snapshot,
            compact: compact,
            isExpanded: isExpanded,
          ),
        );
        if (isExpanded) {
          rows.addAll(snapshotEntries);
        }

        if (previousSnapshot != null) {
          final carryForward = _balanceToOpening(previousSnapshot.finalBalance);
          if (carryForward.hasValue) {
            rows.add(
              _buildCarryForwardRow(context, carryForward, compact: compact),
            );
          }
        } else if (_hasOpeningBalance) {
          rows.add(_buildOpeningBalanceRow(context, compact: compact));
        }
      }
    }

    if (_snapshots.isEmpty && _hasOpeningBalance && _searchQuery.isEmpty) {
      rows.add(_buildOpeningBalanceRow(context, compact: compact));
    }

    return rows;
  }

  DataRow _buildEntryRow(_SnapshotEntry item, {required bool compact}) {
    return DataRow(
      cells: <DataCell>[
        DataCell(
          GestureDetector(
            onLongPress: () => _navigateToCustomerLedger(item),
            child: SizedBox(
              width: compact ? 160 : 200,
              child: Text(
                item.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        DataCell(Text(_formatDate(item.entry.entryDate))),
        DataCell(
          SizedBox(
            width: compact ? 220 : 280,
            child: Text(
              _formatDescription(item),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Text(
            _formatEntryAmount(item.entry.debit),
            style: const TextStyle(
              color: AppColors.debit,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          Text(
            _formatEntryAmount(item.entry.credit),
            style: const TextStyle(
              color: AppColors.credit,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const DataCell(Text('')),
        DataCell(Text(item.entry.pageNo.isEmpty ? '-' : item.entry.pageNo)),
        DataCell(
          context.watch<LinkedSessionProvider>().canEdit
              ? IconButton(
                  tooltip: 'Delete or Remove Entry',
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _removeEntryFromDailyLog(item.entry),
                  visualDensity: VisualDensity.compact,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  DataRow _buildSnapshotTotalRow(
    BuildContext context,
    SummarySnapshot snapshot, {
    required bool compact,
    required bool isExpanded,
  }) {
    final totalStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: compact ? 14 : null,
      fontWeight: FontWeight.w700,
    );

    return DataRow(
      color: WidgetStatePropertyAll<Color?>(
        Theme.of(context).colorScheme.primaryContainer,
      ),
      cells: <DataCell>[
        DataCell(
          SizedBox(
            width: compact ? 150 : 180,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedSnapshots.remove(snapshot.savedAt);
                  } else {
                    _expandedSnapshots.add(snapshot.savedAt);
                  }
                });
              },
              child: Row(
                children: <Widget>[
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Snapshot Total',
                      style: totalStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        DataCell(Text(_formatDateTime(snapshot.savedAt), style: totalStyle)),
        DataCell(Text('Total incl. balance B/F', style: totalStyle)),
        DataCell(
          Text(
            _formatEntryAmount(snapshot.overallDebit),
            style: totalStyle?.copyWith(color: AppColors.debit),
          ),
        ),
        DataCell(
          Text(
            _formatEntryAmount(snapshot.overallCredit),
            style: totalStyle?.copyWith(color: AppColors.credit),
          ),
        ),
        DataCell(
          Text(
            _formatBalance(snapshot.finalBalance),
            style: totalStyle?.copyWith(
              color: AppColors.balanceColor(snapshot.finalBalance),
            ),
          ),
        ),
        DataCell(
          snapshot.dailyLogPageNo.isNotEmpty
              ? Text(
                  'DL Pg ${snapshot.dailyLogPageNo}',
                  style: totalStyle?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                )
              : const Text('-'),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (context.watch<LinkedSessionProvider>().canEdit)
                IconButton(
                  tooltip: snapshot.dailyLogPageNo.isEmpty
                      ? 'Add DL Page No'
                      : 'Edit DL Page No',
                  onPressed: _isLoading || _isSavingSnapshot
                      ? null
                      : () => _editSnapshotPageNo(snapshot),
                  icon: Icon(
                    snapshot.dailyLogPageNo.isEmpty
                        ? Icons.post_add_rounded
                        : Icons.edit_note_rounded,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              if (context.watch<LinkedSessionProvider>().canEdit)
                IconButton(
                  tooltip: 'Delete snapshot',
                  onPressed: _isLoading || _isSavingSnapshot
                      ? null
                      : () => _deleteSnapshot(snapshot),
                  icon: const Icon(Icons.delete_outline),
                  visualDensity: VisualDensity.compact,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _buildOpeningBalanceRow(
    BuildContext context, {
    required bool compact,
  }) {
    final rowStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: compact ? 14 : null,
      fontWeight: FontWeight.w600,
    );
    final openingBalance = _effectiveOpeningBalance;

    return DataRow(
      color: WidgetStatePropertyAll<Color?>(
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      cells: <DataCell>[
        DataCell(Text('Opening Balance', style: rowStyle)),
        const DataCell(Text('-')),
        DataCell(Text('Starting amount', style: rowStyle)),
        DataCell(
          Text(
            _formatEntryAmount(openingBalance.credit), // Sell Amount in Debit column
            style: rowStyle?.copyWith(color: AppColors.debit),
          ),
        ),
        DataCell(
          Text(
            _formatEntryAmount(openingBalance.debit), // Buy Amount in Credit column
            style: rowStyle?.copyWith(color: AppColors.credit),
          ),
        ),
        DataCell(
          Text(
            _formatBalance(openingBalance.finalBalance),
            style: rowStyle?.copyWith(
              color: AppColors.balanceColor(openingBalance.finalBalance),
            ),
          ),
        ),
        const DataCell(Text('')), // Page No
        const DataCell(Text('')), // Action
      ],
    );
  }

  DataRow _buildCarryForwardRow(
    BuildContext context,
    SnapshotOpeningBalance carryForward, {
    required bool compact,
  }) {
    final rowStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontSize: compact ? 14 : null,
      fontWeight: FontWeight.w600,
    );

    return DataRow(
      color: WidgetStatePropertyAll<Color?>(
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      cells: <DataCell>[
        DataCell(Text('Balance B/F', style: rowStyle)),
        const DataCell(Text('-')),
        DataCell(Text('From previous snapshot', style: rowStyle)),
        DataCell(
          Text(
            _formatEntryAmount(carryForward.credit), // Sell Amount in Debit column
            style: rowStyle?.copyWith(color: AppColors.debit),
          ),
        ),
        DataCell(
          Text(
            _formatEntryAmount(carryForward.debit), // Buy Amount in Credit column
            style: rowStyle?.copyWith(color: AppColors.credit),
          ),
        ),
        DataCell(
          Text(
            _formatBalance(carryForward.finalBalance),
            style: rowStyle?.copyWith(
              color: AppColors.balanceColor(carryForward.finalBalance),
            ),
          ),
        ),
        const DataCell(Text('')), // Page No
        const DataCell(Text('')), // Action
      ],
    );
  }

  Future<void> _deleteSnapshot(SummarySnapshot snapshot) async {
    if (!context.read<LinkedSessionProvider>().canEdit) return;

    final snapshotId = snapshot.id;
    if (snapshotId == null) {
      return;
    }

    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Delete Snapshot'),
              content: Text(
                'Delete snapshot from ${_formatDateTime(snapshot.savedAt)}?',
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

    await _database.deleteSummarySnapshot(snapshotId);
    await _loadTimeline();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Snapshot deleted.')));
  }

  Future<void> _clearAllSnapshots() async {
    if (!context.read<LinkedSessionProvider>().canEdit) return;

    if (_snapshots.isEmpty) {
      return;
    }

    final shouldClear =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Clear All Snapshots'),
              content: const Text(
                'This will permanently delete all saved snapshot history.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Clear All'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldClear || !mounted) {
      return;
    }

    await _database.clearSummarySnapshots();
    await _loadTimeline();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('All snapshots cleared.')));
  }

  String _formatEntryAmount(double amount) {
    if (amount == 0) {
      return '-';
    }

    return _formatAmount(amount);
  }

  String _formatDescription(dynamic item) {
    final Entry entry = item is _SnapshotEntry ? item.entry : (item as Entry);
    final desc = entry.description.trim();
    final parts = <String>[];
    if (entry.buyBags.trim().isNotEmpty && entry.buyBags.trim() != '0') {
      parts.add("Buy: ${entry.buyBags.trim()}");
    }
    final parsedSellBags = double.tryParse(entry.sellBags) ?? 0;
    if (parsedSellBags > 0 || (entry.sellBags.trim().isNotEmpty && entry.sellBags.trim() != '0')) {
      parts.add("Sell: ${entry.sellBags.trim()}");
    }

    final bagsPart = parts.join(" | ");
    if (desc.isEmpty) {
      return bagsPart.isEmpty ? "-" : bagsPart;
    } else {
      return bagsPart.isEmpty ? desc : "$desc ($bagsPart)";
    }
  }
}

class _SnapshotEntry {
  const _SnapshotEntry({required this.entry, required this.customerName});

  final Entry entry;
  final String customerName;

  factory _SnapshotEntry.fromMap(Map<String, Object?> map) {
    return _SnapshotEntry(
      entry: Entry.fromMap(map),
      customerName: map['customerName'] as String? ?? '-',
    );
  }
}

class _SnapshotTotals {
  const _SnapshotTotals({required this.debit, required this.credit});

  final double debit;
  final double credit;
}

class _CompactAmountChip extends StatelessWidget {
  const _CompactAmountChip({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = color ?? colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 80),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 14, color: primaryColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
