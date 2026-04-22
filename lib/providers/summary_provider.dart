import '../database/app_database.dart';
import '../models/customer.dart';
import '../models/customer_summary.dart';
import '../models/snapshot_opening_balance.dart';
import '../models/summary_snapshot.dart';
import 'package:flutter/foundation.dart';

class SummaryProvider extends ChangeNotifier {
  SummaryProvider({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  bool _isDisposed = false;

  List<CustomerSummary> _customerSummaries = <CustomerSummary>[];
  List<SummarySnapshot> _snapshots = <SummarySnapshot>[];
  bool _isLoading = false;
  String? _errorMessage;

  List<CustomerSummary> get customerSummaries =>
      List<CustomerSummary>.unmodifiable(_customerSummaries);
  List<SummarySnapshot> get snapshots =>
      List<SummarySnapshot>.unmodifiable(_snapshots);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get overallDebit => _customerSummaries.fold<double>(
    0,
    (double sum, CustomerSummary item) => sum + item.totalDebit,
  );

  double get overallCredit => _customerSummaries.fold<double>(
    0,
    (double sum, CustomerSummary item) => sum + item.totalCredit,
  );

  double get finalBalance => overallDebit - overallCredit;

  Future<void> loadSummary() async {
    _setLoading(true);

    try {
      final snapshotRows = await _database.getSummarySnapshots();
      final snapshots = snapshotRows
          .map<SummarySnapshot>(
            (Map<String, Object?> row) => SummarySnapshot.fromMap(row),
          )
          .toList(growable: false);
      final latestSnapshotAt = snapshots.isEmpty
          ? null
          : DateTime.tryParse(snapshots.first.savedAt);

      final customerRows = await _database.getCustomers();
      final customers = customerRows
          .map<Customer>((Map<String, Object?> row) => Customer.fromMap(row))
          .toList(growable: false);

      final totalsRows = await _database.getCustomerEntryTotalsSince(
        startCreatedAt: latestSnapshotAt?.toIso8601String(),
      );
      final totalsByCustomer = <int, _EntryTotals>{};
      for (final row in totalsRows) {
        final idValue = row['customerId'];
        final customerId = idValue is int
            ? idValue
            : int.tryParse('$idValue') ?? 0;
        if (customerId <= 0) {
          continue;
        }
        final entryCountValue = row['entryCount'];
        final entryCount = entryCountValue is int
            ? entryCountValue
            : int.tryParse('$entryCountValue') ?? 0;
        final totalDebitValue = row['totalDebit'];
        final totalCreditValue = row['totalCredit'];
        totalsByCustomer[customerId] = _EntryTotals(
          debit: totalDebitValue is num
              ? totalDebitValue.toDouble()
              : double.tryParse('$totalDebitValue') ?? 0,
          credit: totalCreditValue is num
              ? totalCreditValue.toDouble()
              : double.tryParse('$totalCreditValue') ?? 0,
          count: entryCount,
        );
      }

      final summaries = <CustomerSummary>[];
      for (final customer in customers) {
        final customerId = customer.id;
        if (customerId == null) {
          continue;
        }
        final totals = totalsByCustomer[customerId];
        if (totals == null || totals.count == 0) {
          continue;
        }

        summaries.add(
          CustomerSummary(
            customer: customer,
            totalDebit: totals.debit,
            totalCredit: totals.credit,
          ),
        );
      }

      _customerSummaries = summaries;
      _snapshots = snapshots;
      _errorMessage = null;
    } catch (error, stackTrace) {
      debugPrint('SummaryProvider.loadSummary failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to load summary data.';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> saveSnapshot() async {
    if (_customerSummaries.isEmpty) {
      _errorMessage = 'No summary data available to save.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      final latestSnapshot = _snapshots.isEmpty ? null : _snapshots.first;
      SnapshotOpeningBalance startingBalance;
      if (latestSnapshot != null) {
        startingBalance = _balanceToOpening(latestSnapshot.finalBalance);
      } else {
        startingBalance =
            await _database.getSnapshotOpeningBalance() ??
            const SnapshotOpeningBalance(debit: 0, credit: 0);
      }

      await _database.addSummarySnapshot(
        savedAt: DateTime.now().toIso8601String(),
        overallDebit: overallDebit + startingBalance.debit,
        overallCredit: overallCredit + startingBalance.credit,
        customerCount: _customerSummaries.length,
      );
      await loadSummary();
      return true;
    } catch (error, stackTrace) {
      debugPrint('SummaryProvider.saveSnapshot failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to save summary snapshot.';
      _setLoading(false);
      return false;
    }
  }

  String formatAmount(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String formatBalance(double balance) {
    if (balance > 0) {
      return '${formatAmount(balance)} Debit';
    }
    if (balance < 0) {
      return '${formatAmount(balance.abs())} Credit';
    }
    return '0';
  }

  String formatSavedAt(String value) {
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

  SnapshotOpeningBalance _balanceToOpening(double balance) {
    if (balance > 0) {
      return SnapshotOpeningBalance(debit: balance, credit: 0);
    }
    if (balance < 0) {
      return SnapshotOpeningBalance(debit: 0, credit: balance.abs());
    }
    return const SnapshotOpeningBalance(debit: 0, credit: 0);
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class _EntryTotals {
  const _EntryTotals({
    required this.debit,
    required this.credit,
    required this.count,
  });

  final double debit;
  final double credit;
  final int count;
}
