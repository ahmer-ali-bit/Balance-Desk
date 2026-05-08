import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../models/entry.dart';
import '../models/snapshot_opening_balance.dart';
import '../models/summary_snapshot.dart';
import '../services/export_service.dart';
import '../services/linked_devices_controller.dart';
import '../services/pdf_service.dart';
import '../utils/number_format_utils.dart';
import '../utils/platform_helper.dart';
import '../widgets/linked_read_only_banner.dart';

class SnapshotEntriesScreen extends StatefulWidget {
  const SnapshotEntriesScreen({super.key});

  @override
  State<SnapshotEntriesScreen> createState() => _SnapshotEntriesScreenState();
}

enum _SnapshotExportChoice { pdf, excel }

class _ScrollIntent extends Intent {
  const _ScrollIntent(this.delta);

  final double delta;
}

class _SnapshotEntriesScreenState extends State<SnapshotEntriesScreen> {
  final AppDatabase _database = AppDatabase.instance;
  final PdfService _pdfService = const PdfService();
  final ExportService _exportService = const ExportService();
  final LinkedDevicesController _linkedDevices =
      LinkedDevicesController.instance;
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
  int _lastSeenLinkedDataVersion = 0;
  bool _showDailyLogActions = false;
  bool _showDailyLatestSnapshot = false;
  bool _showDailyOpeningBalance = false;
  static const int _snapshotPageSize = 800;
  final Set<String> _expandedSnapshots = <String>{};

  SummarySnapshot? get _latestSnapshot =>
      _snapshots.isEmpty ? null : _snapshots.last;
  double get _openingDebitBalance =>
      double.tryParse(_debitOpeningBalanceController.text.trim()) ?? 0;
  double get _openingCreditBalance =>
      double.tryParse(_creditOpeningBalanceController.text.trim()) ?? 0;
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
    _linkedDevices.addListener(_handleLinkedDevicesChanged);
    _loadTimeline();
  }

  @override
  void dispose() {
    _linkedDevices.removeListener(_handleLinkedDevicesChanged);
    _entryTableVerticalController.dispose();
    _debitOpeningBalanceController.dispose();
    _creditOpeningBalanceController.dispose();
    super.dispose();
  }

  void _handleLinkedDevicesChanged() {
    if (_lastSeenLinkedDataVersion == _linkedDevices.dataVersion) {
      return;
    }

    _lastSeenLinkedDataVersion = _linkedDevices.dataVersion;
    _loadTimeline();
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
    } catch (error, stackTrace) {
      debugPrint('SnapshotEntriesScreen._loadTimeline failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load snapshot entries.';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSnapshot() async {
    if (!_linkedDevices.canEditWorkspace) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_linkedDevices.readOnlyMessage)));
      return;
    }

    if (_isLoading || _isSavingSnapshot) {
      return;
    }

    setState(() {
      _isSavingSnapshot = true;
      _errorMessage = null;
    });

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
      );
      await _linkedDevices.syncAfterLocalChange(reason: 'snapshot_save');
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

  List<List<String>> _buildSnapshotExportRows() {
    final rows = <List<String>>[];
    var entryIndex = 0;

    for (final snapshot in _snapshots) {
      while (entryIndex < _entries.length &&
          _compareMoments(
                _entries[entryIndex].entry.createdAt,
                snapshot.savedAt,
              ) <=
              0) {
        final entry = _entries[entryIndex];
        rows.add(<String>[
          entry.customerName,
          _formatDate(entry.entry.entryDate),
          entry.entry.displayDescription,
          _formatAmount(entry.entry.debit),
          _formatAmount(entry.entry.credit),
          '',
          entry.entry.pageNo,
        ]);
        entryIndex++;
      }

      rows.add(<String>[
        'Snapshot Total',
        _formatDateTime(snapshot.savedAt),
        'Total incl. balance B/F',
        _formatAmount(snapshot.overallDebit),
        _formatAmount(snapshot.overallCredit),
        _formatBalance(snapshot.finalBalance),
        '',
      ]);

      final carryForward = _balanceToOpening(snapshot.finalBalance);
      if (carryForward.hasValue) {
        rows.add(<String>[
          'Balance B/F',
          '-',
          'From previous snapshot',
          _formatAmount(carryForward.debit),
          _formatAmount(carryForward.credit),
          _formatBalance(carryForward.finalBalance),
          '',
        ]);
      }
    }

    if (_snapshots.isEmpty && _hasOpeningBalance) {
      final openingBalance = _effectiveOpeningBalance;
      rows.add(<String>[
        'Opening Balance',
        '-',
        'Starting amount',
        _formatAmount(openingBalance.debit),
        _formatAmount(openingBalance.credit),
        _formatBalance(openingBalance.finalBalance),
        '',
      ]);
    }

    while (entryIndex < _entries.length) {
      final entry = _entries[entryIndex];
      rows.add(<String>[
        entry.customerName,
        _formatDate(entry.entry.entryDate),
        entry.entry.displayDescription,
        _formatAmount(entry.entry.debit),
        _formatAmount(entry.entry.credit),
        '',
        entry.entry.pageNo,
      ]);
      entryIndex++;
    }

    return rows;
  }

  List<({String label, String value})> _buildSnapshotPdfSummaryItems() {
    final items = <({String label, String value})>[];

    items.add((
      label: 'Total Entries',
      value: '${_entries.length}',
    ));

    final latestSnapshot = _latestSnapshot;
    items.add((
      label: 'Last Saved Snapshot Balance',
      value: latestSnapshot != null ? _formatBalance(latestSnapshot.finalBalance) : '-',
    ));

    return items;
  }

  Future<void> _exportSnapshotPdf() async {
    final rows = _buildSnapshotExportRows();
    if (rows.isEmpty) {
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
              if (!_isLoading &&
                  !_isSavingSnapshot &&
                  _hasCurrentPeriodEntries) {
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
              final isCompact =
                  !PlatformHelper.isDesktop && constraints.maxWidth < 760;
              final isDesktop = PlatformHelper.isDesktop;
              final latestSnapshot = _latestSnapshot;
              final headerActions = _buildHeaderActions(isCompact: isCompact);
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
                    if (_linkedDevices.isReadOnlyLinkedDevice) ...<Widget>[
                      const SizedBox(height: 12),
                      const LinkedReadOnlyBanner(),
                    ],
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

  Widget _buildHeaderActions({required bool isCompact}) {
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
        OutlinedButton.icon(
          onPressed: _isLoading || _isSavingSnapshot ? null : _exportSnapshot,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Export'),
        ),
        if (_snapshots.isNotEmpty)
          TextButton.icon(
            onPressed:
                _isLoading ||
                    _isSavingSnapshot ||
                    !_linkedDevices.canEditWorkspace
                ? null
                : _clearAllSnapshots,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(isDesktop ? 'Clear Snapshots' : 'Clear'),
          ),
        FilledButton.icon(
          onPressed:
              _isLoading ||
                  _isSavingSnapshot ||
                  !_hasCurrentPeriodEntries ||
                  !_linkedDevices.canEditWorkspace
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
                ),
                _CompactAmountChip(
                  label: 'Credit',
                  value: _formatEntryAmount(snapshot.overallCredit),
                ),
                _CompactAmountChip(
                  label: 'Balance',
                  value: _formatBalance(snapshot.finalBalance),
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopSnapshotMetric(
                  context,
                  label: 'Credit',
                  value: _formatEntryAmount(snapshot.overallCredit),
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDesktopSnapshotMetric(
                  context,
                  label: 'Balance',
                  value: _formatBalance(snapshot.finalBalance),
                  icon: Icons.account_balance_wallet_outlined,
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
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
    final openingLocked = !_linkedDevices.canEditWorkspace;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final debitField = _buildOpeningBalanceField(
              controller: _debitOpeningBalanceController,
              label: 'Debit Opening Balance',
              icon: Icons.arrow_downward_rounded,
              readOnly: openingLocked,
            );
            final creditField = _buildOpeningBalanceField(
              controller: _creditOpeningBalanceController,
              label: 'Credit Opening Balance',
              icon: Icons.arrow_upward_rounded,
              readOnly: openingLocked,
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
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      scrollPadding: const EdgeInsets.only(bottom: 180),
      readOnly: readOnly,
      onChanged: readOnly
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
              '${_formatDate(item.entry.entryDate)} • ${item.entry.displayDescription}',
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
                ),
                _CompactAmountChip(
                  label: 'Credit',
                  value: _formatEntryAmount(item.entry.credit),
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
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Snapshot Total',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_linkedDevices.canEditWorkspace)
                    IconButton(
                      tooltip: 'Delete snapshot',
                      onPressed: _isLoading || _isSavingSnapshot
                          ? null
                          : () => _deleteSnapshot(snapshot),
                      icon: const Icon(Icons.delete_outline),
                    ),
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
                  ),
                  _CompactAmountChip(
                    label: 'Credit',
                    value: _formatEntryAmount(snapshot.overallCredit),
                  ),
                  _CompactAmountChip(
                    label: 'Balance',
                    value: _formatBalance(snapshot.finalBalance),
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
                ),
                _CompactAmountChip(
                  label: 'Credit',
                  value: _formatEntryAmount(balance.credit),
                ),
                _CompactAmountChip(
                  label: 'Balance',
                  value: _formatBalance(balance.finalBalance),
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
    items.addAll(currentEntries);

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

      items.add(
        _buildCompactSnapshotCard(
          context,
          snapshot,
          isExpanded: isExpanded,
        ),
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
        items.add(_buildCompactBalanceCard(context, _effectiveOpeningBalance));
      }
    }

    if (_snapshots.isEmpty && _hasOpeningBalance) {
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
                  item.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (item.entry.pageNo.isNotEmpty)
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
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDate(item.entry.entryDate)} - ${item.entry.displayDescription}',
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
    );
  }

  Widget _buildDailyAmountStrip(
    BuildContext context, {
    required String debit,
    required String credit,
    String? balance,
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
              color: colorScheme.primary,
            ),
          ),
          _dailyStripDivider(context),
          Expanded(
            child: _buildDailyStripItem(
              context,
              label: 'Credit',
              value: credit,
              color: colorScheme.secondary,
            ),
          ),
          if (balance != null) ...<Widget>[
            _dailyStripDivider(context),
            Expanded(
              child: _buildDailyStripItem(
                context,
                label: 'Balance',
                value: balance,
                color: colorScheme.tertiary,
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
    required Color color,
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

  Widget _buildEntryTable(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompactTable = constraints.maxWidth < 760;
        if (isCompactTable) {
          return _buildCompactTimeline(context);
        }
        final tableMinWidth = PlatformHelper.isDesktop
            ? math.max(1060.0, constraints.maxWidth - 16)
            : 1060.0;

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
                    DataColumn(label: Text('Page/Action')),
                  ],
                  rows: _buildTimelineRows(context, compact: false),
                ),
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
    rows.addAll(currentEntries);

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

    if (_snapshots.isEmpty && _hasOpeningBalance) {
      rows.add(_buildOpeningBalanceRow(context, compact: compact));
    }

    return rows;
  }

  DataRow _buildEntryRow(_SnapshotEntry item, {required bool compact}) {
    return DataRow(
      cells: <DataCell>[
        DataCell(
          SizedBox(
            width: compact ? 160 : 200,
            child: Text(
              item.customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(_formatDate(item.entry.entryDate))),
        DataCell(
          SizedBox(
            width: compact ? 220 : 280,
            child: Text(
              item.entry.displayDescription,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(Text(_formatEntryAmount(item.entry.debit))),
        DataCell(Text(_formatEntryAmount(item.entry.credit))),
        const DataCell(Text('')),
        DataCell(Text(item.entry.pageNo.isEmpty ? '-' : item.entry.pageNo)),
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
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18),
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
          Text(_formatEntryAmount(snapshot.overallDebit), style: totalStyle),
        ),
        DataCell(
          Text(_formatEntryAmount(snapshot.overallCredit), style: totalStyle),
        ),
        DataCell(
          Text(_formatBalance(snapshot.finalBalance), style: totalStyle),
        ),
        DataCell(
          IconButton(
            tooltip: 'Delete snapshot',
            onPressed:
                _isLoading ||
                    _isSavingSnapshot ||
                    !_linkedDevices.canEditWorkspace
                ? null
                : () => _deleteSnapshot(snapshot),
            icon: const Icon(Icons.delete_outline),
            visualDensity: VisualDensity.compact,
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
          Text(_formatEntryAmount(openingBalance.debit), style: rowStyle),
        ),
        DataCell(
          Text(_formatEntryAmount(openingBalance.credit), style: rowStyle),
        ),
        DataCell(
          Text(_formatBalance(openingBalance.finalBalance), style: rowStyle),
        ),
        const DataCell(Text('')),
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
        DataCell(Text(_formatEntryAmount(carryForward.debit), style: rowStyle)),
        DataCell(
          Text(_formatEntryAmount(carryForward.credit), style: rowStyle),
        ),
        DataCell(
          Text(_formatBalance(carryForward.finalBalance), style: rowStyle),
        ),
        const DataCell(Text('')),
      ],
    );
  }

  Future<void> _deleteSnapshot(SummarySnapshot snapshot) async {
    if (!_linkedDevices.canEditWorkspace) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_linkedDevices.readOnlyMessage)));
      return;
    }

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
    await _linkedDevices.syncAfterLocalChange(reason: 'snapshot_delete');
    await _loadTimeline();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Snapshot deleted.')));
  }

  Future<void> _clearAllSnapshots() async {
    if (!_linkedDevices.canEditWorkspace) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_linkedDevices.readOnlyMessage)));
      return;
    }

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
    await _linkedDevices.syncAfterLocalChange(reason: 'snapshot_clear_all');
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
  const _CompactAmountChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 80),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
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
}
