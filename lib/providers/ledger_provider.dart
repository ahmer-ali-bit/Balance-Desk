import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/customer.dart';
import '../models/entry.dart';
import '../models/snapshot_opening_balance.dart';
import '../services/linked_devices_controller.dart';
import '../utils/number_format_utils.dart' as number_format_utils;

enum LedgerDateFilter { all, today, thisWeek, thisMonth, customRange }

class LedgerProvider extends ChangeNotifier {
  static const String _openingBalanceDescription = 'Opening Balance';

  LedgerProvider({
    required Customer customer,
    AppDatabase? database,
    LinkedDevicesController? linkedDevices,
  }) : _customer = customer,
       _customerName = customer.name,
       _customerAddress = customer.address,
       _customerPhone = customer.phone,
       _database = database ?? AppDatabase.instance,
       _linkedDevices = linkedDevices ?? LinkedDevicesController.instance {
    _linkedDevices.addListener(_handleLinkedDevicesChanged);
  }

  final Customer _customer;
  String _customerName;
  String _customerAddress;
  String _customerPhone;
  final AppDatabase _database;
  final LinkedDevicesController _linkedDevices;
  bool _isDisposed = false;
  int _lastSeenLinkedDataVersion = 0;

  List<Entry> _entries = <Entry>[];
  List<Entry> _visibleEntries = <Entry>[];
  SnapshotOpeningBalance _openingBalance = const SnapshotOpeningBalance(
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
  );
  String get customerName => _customerName;
  String get customerAddress => _customerAddress;
  String get customerPhone => _customerPhone;
  LedgerDateFilter get activeFilter => _activeFilter;
  DateTimeRange? get customRange => _customRange;
  List<Entry> get entries => List<Entry>.unmodifiable(_visibleEntries);
  SnapshotOpeningBalance get openingBalance => _openingBalance;
  bool get hasOpeningBalance => _openingBalance.hasValue;
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
          openingBalance ?? const SnapshotOpeningBalance(debit: 0, credit: 0);
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

  Future<bool> setOpeningBalance({
    required double debit,
    required double credit,
  }) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

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

    _setLoading(true);

    try {
      if (debit == 0 && credit == 0) {
        await _database.clearCustomerLedgerOpeningBalance(_customer.id!);
      } else {
        await _database.setCustomerLedgerOpeningBalance(
          customerId: _customer.id!,
          debit: debit,
          credit: credit,
        );
      }

      _openingBalance = SnapshotOpeningBalance(debit: debit, credit: credit);
      _rebuildVisibleEntries();
      _errorMessage = null;
      _setLoading(false);
      await _linkedDevices.syncAfterLocalChange(
        reason: 'ledger_opening_balance',
      );
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
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

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
      await _linkedDevices.syncAfterLocalChange(reason: 'entry_add');
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.addEntry failed: $error');
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
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

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
      await _linkedDevices.syncAfterLocalChange(reason: 'entry_update');
      return true;
    } catch (error, stackTrace) {
      debugPrint('LedgerProvider.updateEntry failed: $error');
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
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

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
      await _linkedDevices.syncAfterLocalChange(reason: 'entry_transfer');
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
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

    if (entry.id == null) {
      _errorMessage = 'Entry record is invalid.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.deleteEntry(entry.id!);
      await loadEntries();
      await _linkedDevices.syncAfterLocalChange(reason: 'entry_delete');
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
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

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
      await _linkedDevices.syncAfterLocalChange(
        reason: 'ledger_customer_update',
      );
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
      Entry(
        customerId: _customer.id ?? 0,
        entryDate: '-',
        createdAt: '-',
        pageNo: '',
        description: _openingBalanceDescription,
        debit: _openingBalance.debit,
        credit: _openingBalance.credit,
      ),
      ..._entries,
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

  void _handleLinkedDevicesChanged() {
    if (_lastSeenLinkedDataVersion == _linkedDevices.dataVersion) {
      return;
    }

    _lastSeenLinkedDataVersion = _linkedDevices.dataVersion;
    loadEntries();
  }

  @override
  void dispose() {
    _linkedDevices.removeListener(_handleLinkedDevicesChanged);
    _isDisposed = true;
    super.dispose();
  }
}
