import 'dart:async';
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/customer.dart';
import '../models/entry.dart';
import '../models/snapshot_opening_balance.dart';
import '../utils/number_format_utils.dart' as number_format_utils;

enum LedgerDateFilter { all, today, thisWeek, thisMonth, customRange }

class LedgerProvider extends ChangeNotifier {
  static const String _openingBalanceDescription = 'Opening Balance';

  final AppDatabase _database;
  bool _isDisposed = false;
  StreamSubscription<void>? _dbSub;
  final Customer _customer;
  String _customerName;
  String _customerAddress;
  String _customerPhone;
  bool _isStockLedger;
  bool _useWeight;

  LedgerProvider({
    required Customer customer,
    AppDatabase? database,
  }) : _customer = customer,
       _customerName = customer.name,
       _customerAddress = customer.address,
       _customerPhone = customer.phone,
       _isStockLedger = customer.isStockLedger,
       _useWeight = customer.useWeight,
       _database = database ?? AppDatabase.instance {
    _dbSub = _database.onDataChanged.listen((_) {
      if (!_isDisposed) loadEntries();
    });
  }

  List<Entry> _entries = <Entry>[];
  List<Entry> _visibleEntries = <Entry>[];
  SnapshotOpeningBalance _openingBalance = SnapshotOpeningBalance(
    debit: 0,
    credit: 0,
  );
  bool _isLoading = false;
  String? _errorMessage;
  LedgerDateFilter _activeFilter = LedgerDateFilter.all;
  DateTimeRange? _customRange;

  Customer get customer => Customer(
    id: _customer.id,
    name: _customerName,
    address: _customerAddress,
    phone: _customerPhone,
    isStockLedger: _isStockLedger,
    useWeight: _useWeight,
  );
  String get customerName => _customerName;
  String get customerAddress => _customerAddress;
  String get customerPhone => _customerPhone;
  LedgerDateFilter get activeFilter => _activeFilter;
  DateTimeRange? get customRange => _customRange;
  List<Entry> get entries => List<Entry>.unmodifiable(_visibleEntries);
  SnapshotOpeningBalance get openingBalance => _openingBalance;
  bool get hasOpeningBalance => _openingBalance.hasValue;
  bool get isStockLedger => _isStockLedger;
  bool get useWeight => _useWeight;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get totalDebit => _visibleEntries.fold<double>(
    0,
    (double sum, Entry entry) => sum + entry.debit,
  );

  double get totalCredit => _visibleEntries.fold<double>(
    0,
    (double sum, Entry entry) => sum + entry.credit,
  );

  double get finalBalance => totalDebit - totalCredit;

  double get totalBuyBags => _visibleEntries.fold<double>(
    0,
    (double sum, Entry entry) => sum + (double.tryParse(entry.buyBags) ?? 0),
  );

  double get totalSellBags => _visibleEntries.fold<double>(
    0,
    (double sum, Entry entry) => sum + (double.tryParse(entry.sellBags) ?? 0),
  );

  double get finalRemainingBags => totalBuyBags - totalSellBags;

  String get activeFilterLabel {
    final range = _resolveActiveRange();
    final label = switch (_activeFilter) {
      LedgerDateFilter.all => 'All Entries',
      LedgerDateFilter.today => 'Today',
      LedgerDateFilter.thisWeek => 'This Week',
      LedgerDateFilter.thisMonth => 'This Month',
      LedgerDateFilter.customRange => 'Custom Range',
    };

    if (range == null) {
      return label;
    }

    return '$label (${_formatDate(range.start)} - ${_formatDate(range.end)})';
  }

  Future<void> loadEntries() async {
    if (_customer.id == null) {
      _errorMessage = 'Customer record is invalid.';
      _notifyListeners();
      return;
    }

    _setLoading(true);

    try {
      final range = _resolveActiveRange();
      final rows = range == null
          ? await _database.getEntriesByCustomer(_customer.id!)
          : await _database.getEntriesByDateRange(
              customerId: _customer.id!,
              startDate: range.start.toIso8601String(),
              endDate: range.end.toIso8601String(),
            );
      final openingBalance = await _database.getCustomerLedgerOpeningBalance(
        _customer.id!,
      );
      _entries = rows
          .map<Entry>((Map<String, Object?> row) => Entry.fromMap(row))
          .toList(growable: false);
      _openingBalance =
          openingBalance ?? SnapshotOpeningBalance(debit: 0, credit: 0);
      _rebuildVisibleEntries();
      _errorMessage = null;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.loadEntries failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to load ledger entries.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> applyFilter(
    LedgerDateFilter filter, {
    DateTimeRange? customRange,
  }) async {
    _activeFilter = filter;
    if (filter == LedgerDateFilter.customRange) {
      _customRange = customRange;
    }
    await loadEntries();
  }

  Future<void> toggleStockLedger() async {
    if (_customer.id == null) return;
    
    _isStockLedger = !_isStockLedger;
    _notifyListeners();
    
    try {
      await _database.updateCustomerStockMode(_customer.id!, _isStockLedger);
    } catch (e) {
      debugPrint('Failed to persist stock ledger mode: $e');
    }
  }

  Future<void> toggleStockWeight() async {
    if (_customer.id == null) return;
    
    _useWeight = !_useWeight;
    _notifyListeners();
    
    try {
      await _database.updateCustomerWeightMode(_customer.id!, _useWeight);
    } catch (e) {
      debugPrint('Failed to persist weight mode: $e');
    }
  }

  Future<bool> setOpeningBalance({
    required double debit,
    required double credit,
    double buyBags = 0,
    double sellBags = 0,
  }) async {

    if (_customer.id == null) {
      _errorMessage = 'Customer record is invalid.';
      _notifyListeners();
      return false;
    }

    if (debit < 0 || credit < 0 || buyBags < 0 || sellBags < 0) {
      _errorMessage = 'Amounts cannot be negative.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      if (debit == 0 && credit == 0 && buyBags == 0 && sellBags == 0) {
        await _database.clearCustomerLedgerOpeningBalance(_customer.id!);
      } else {
        await _database.setCustomerLedgerOpeningBalance(
          customerId: _customer.id!,
          debit: debit,
          credit: credit,
          buyBags: buyBags,
          sellBags: sellBags,
        );
      }

      _openingBalance = SnapshotOpeningBalance(
        debit: debit,
        credit: credit,
        buyBags: buyBags,
        sellBags: sellBags,
      );
      _rebuildVisibleEntries();
      _errorMessage = null;
      _setLoading(false);
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.setOpeningBalance failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to save opening balance.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> addEntry({
    required DateTime entryDate,
    required String pageNo,
    required String description,
    required double debit,
    required double credit,
  }) async {

    if (_customer.id == null) {
      _errorMessage = 'Customer record is invalid.';
      _notifyListeners();
      return false;
    }

    if (debit < 0 || credit < 0) {
      _errorMessage = 'Amounts cannot be negative.';
      _notifyListeners();
      return false;
    }

    if (debit == 0 && credit == 0) {
      _errorMessage = 'Enter a debit or credit amount.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.addEntry(
        customerId: _customer.id!,
        entryDate: entryDate.toIso8601String(),
        createdAt: DateTime.now().toIso8601String(),
        pageNo: pageNo,
        description: description.trim(),
        debit: debit,
        credit: credit,
      );
      await loadEntries();
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.addEntry failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to save ledger entry.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> addStockEntry({
    required DateTime entryDate,
    required String pageNo,
    required String description,
    required String buyBags,
    required double buyAmount,
    required String sellBags,
    required double sellAmount,
  }) async {
    if (_customer.id == null) {
      _errorMessage = 'Customer record is invalid.';
      _notifyListeners();
      return false;
    }

    if (buyAmount < 0 || sellAmount < 0) {
      _errorMessage = 'Values cannot be negative.';
      _notifyListeners();
      return false;
    }

    if (buyBags.trim().isEmpty && buyAmount == 0 && sellBags.trim().isEmpty && sellAmount == 0) {
      _errorMessage = 'Enter at least one value.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.addStockEntry(
        customerId: _customer.id!,
        entryDate: entryDate.toIso8601String(),
        createdAt: DateTime.now().toIso8601String(),
        pageNo: pageNo,
        description: description.trim(),
        buyBags: buyBags,
        buyAmount: buyAmount,
        sellBags: sellBags,
        sellAmount: sellAmount,
      );
      await loadEntries();
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.addStockEntry failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to save ledger entry.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateEntry({
    required Entry entry,
    required DateTime entryDate,
    required String pageNo,
    required String description,
    required double debit,
    required double credit,
  }) async {

    if (entry.id == null) {
      _errorMessage = 'Entry record is invalid.';
      _notifyListeners();
      return false;
    }

    if (debit < 0 || credit < 0) {
      _errorMessage = 'Amounts cannot be negative.';
      _notifyListeners();
      return false;
    }

    if (debit == 0 && credit == 0) {
      _errorMessage = 'Enter a debit or credit amount.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.updateEntry(
        id: entry.id!,
        entryDate: entryDate.toIso8601String(),
        pageNo: pageNo,
        description: description.trim(),
        debit: debit,
        credit: credit,
      );
      await loadEntries();
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.updateEntry failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to update ledger entry.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateStockEntry({
    required Entry entry,
    required DateTime entryDate,
    required String pageNo,
    required String description,
    required String buyBags,
    required double buyAmount,
    required String sellBags,
    required double sellAmount,
  }) async {
    if (entry.id == null) {
      _errorMessage = 'Entry record is invalid.';
      _notifyListeners();
      return false;
    }

    if (buyAmount < 0 || sellAmount < 0) {
      _errorMessage = 'Values cannot be negative.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.updateStockEntry(
        id: entry.id!,
        entryDate: entryDate.toIso8601String(),
        pageNo: pageNo,
        description: description.trim(),
        buyBags: buyBags,
        buyAmount: buyAmount,
        sellBags: sellBags,
        sellAmount: sellAmount,
      );
      await loadEntries();
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.updateStockEntry failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to update ledger entry.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> transferEntry({
    required Entry entry,
    required int newCustomerId,
  }) async {

    if (entry.id == null) {
      _errorMessage = 'Entry record is invalid.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.transferEntry(
        entryId: entry.id!,
        newCustomerId: newCustomerId,
      );
      await loadEntries();
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.transferEntry failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to transfer entry.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteEntry(Entry entry) async {

    if (entry.id == null) {
      _errorMessage = 'Entry record is invalid.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.deleteEntry(entry.id!);
      await loadEntries();
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.deleteEntry failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to delete ledger entry.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateCustomerProfile({
    required String name,
    String address = '',
    String phone = '',
  }) async {

    if (_customer.id == null) {
      _errorMessage = 'Customer record is invalid.';
      _notifyListeners();
      return false;
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _errorMessage = 'Customer name is required.';
      _notifyListeners();
      return false;
    }

    if (await _database.customerNameExists(
      trimmedName,
      excludingCustomerId: _customer.id,
    )) {
      _errorMessage = 'A customer named "$trimmedName" already exists.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.updateCustomer(
        id: _customer.id!,
        name: trimmedName,
        address: address,
        phone: phone,
      );
      _customerName = trimmedName;
      _customerAddress = address.trim();
      _customerPhone = phone.trim();
      _errorMessage = null;
      _setLoading(false);
      return true;
    } catch (_) {
      _errorMessage = 'Unable to update customer details.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> updateCustomerName(
    String name, {
    String address = '',
    String phone = '',
  }) {
    return updateCustomerProfile(name: name, address: address, phone: phone);
  }

  Future<bool> updateCustomerNameWithDetails(
    String name,
    String address,
    String phone,
  ) {
    return updateCustomerProfile(name: name, address: address, phone: phone);
  }

  bool isOpeningBalanceEntry(Entry entry) {
    return entry.id == null &&
        entry.description == _openingBalanceDescription &&
        entry.entryDate == '-' &&
        entry.createdAt == '-';
  }

  double calculateBalance(Entry entry) => entry.debit - entry.credit;

  String formatAmount(double amount) =>
      number_format_utils.formatAmount(amount);

  String formatBalance(double balance) =>
      number_format_utils.formatBalance(balance);

  String formatBags(double bags) {
    if (_isStockLedger && _useWeight) {
      return number_format_utils.formatWeight(bags);
    }
    return number_format_utils.formatBags(bags);
  }

  DateTimeRange? _resolveActiveRange() {
    final now = DateTime.now();

    switch (_activeFilter) {
      case LedgerDateFilter.all:
        return null;
      case LedgerDateFilter.today:
        final start = DateTime(now.year, now.month, now.day);
        final end = start
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case LedgerDateFilter.thisWeek:
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        final end = start
            .add(const Duration(days: 7))
            .subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case LedgerDateFilter.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        final end = nextMonth.subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case LedgerDateFilter.customRange:
        return _customRange;
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  void _rebuildVisibleEntries() {
    if (!_openingBalance.hasValue) {
      _visibleEntries = List<Entry>.from(_entries, growable: false);
      return;
    }

    _visibleEntries = <Entry>[
      ..._entries,
      Entry(
        customerId: _customer.id ?? 0,
        entryDate: '-',
        createdAt: '-',
        pageNo: '',
        description: _openingBalanceDescription,
        debit: _openingBalance.debit,
        credit: _openingBalance.credit,
        buyBags: _openingBalance.buyBags == 0 ? '' : _openingBalance.buyBags.toString(),
        sellBags: _openingBalance.sellBags == 0 ? '' : _openingBalance.sellBags.toString(),
      ),
    ];
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
    _dbSub?.cancel();
    super.dispose();
  }
}
