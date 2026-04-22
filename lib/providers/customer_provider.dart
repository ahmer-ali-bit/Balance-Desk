import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/customer.dart';
import '../services/linked_devices_controller.dart';

class CustomerProvider extends ChangeNotifier {
  CustomerProvider({
    AppDatabase? database,
    LinkedDevicesController? linkedDevices,
  }) : _database = database ?? AppDatabase.instance,
       _linkedDevices = linkedDevices ?? LinkedDevicesController.instance {
    _linkedDevices.addListener(_handleLinkedDevicesChanged);
  }

  final AppDatabase _database;
  final LinkedDevicesController _linkedDevices;
  bool _isDisposed = false;
  int _lastSeenLinkedDataVersion = 0;

  List<Customer> _customers = <Customer>[];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  List<Customer> get customers => List<Customer>.unmodifiable(_customers);
  List<Customer> get filteredCustomers {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return customers;
    }

    return _customers
        .where((Customer customer) => _matchesStartingLetters(customer, query))
        .toList(growable: false);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;

  Future<void> loadCustomers() async {
    _setLoading(true);

    try {
      await _refreshCustomers();
      _errorMessage = null;
    } catch (error, stackTrace) {
      debugPrint('CustomerProvider.loadCustomers failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to load customers.';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addCustomer(
    String name, {
    String address = '',
    String phone = '',
  }) async {
    final customer = await addCustomerAndReturn(
      name,
      address: address,
      phone: phone,
    );
    return customer != null;
  }

  Future<Customer?> addCustomerAndReturn(
    String name, {
    String address = '',
    String phone = '',
  }) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return null;
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      _errorMessage = 'Customer name is required.';
      _notifyListeners();
      return null;
    }

    if (await _database.customerNameExists(trimmedName)) {
      _errorMessage = 'A customer named "$trimmedName" already exists.';
      _notifyListeners();
      return null;
    }

    try {
      final id = await _database.insertCustomer(
        trimmedName,
        address: address,
        phone: phone,
      );
      await _refreshCustomers();
      _errorMessage = null;
      await _linkedDevices.syncAfterLocalChange(reason: 'customer_add');
      _notifyListeners();
      return _customers.firstWhere(
        (Customer customer) => customer.id == id,
        orElse: () => Customer(
          id: id,
          name: trimmedName,
          address: address.trim(),
          phone: phone.trim(),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('CustomerProvider.addCustomer failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to add customer.';
      _notifyListeners();
      return null;
    }
  }

  Future<Customer?> addCustomerAndReturnWithDetails(
    String name,
    String address,
    String phone,
  ) {
    return addCustomerAndReturn(name, address: address, phone: phone);
  }

  Future<void> deleteCustomer(Customer customer) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return;
    }

    if (customer.id == null) {
      return;
    }

    try {
      await _database.deleteCustomer(customer.id!);
      await _refreshCustomers();
      await _database.resetCustomerIdSequence();
      _errorMessage = null;
      await _linkedDevices.syncAfterLocalChange(reason: 'customer_delete');
      _notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('CustomerProvider.deleteCustomer failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to delete customer.';
      _notifyListeners();
    }
  }

  Future<bool> updateCustomerName({
    required int customerId,
    required String name,
  }) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
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
      excludingCustomerId: customerId,
    )) {
      _errorMessage = 'A customer named "$trimmedName" already exists.';
      _notifyListeners();
      return false;
    }

    try {
      await _database.updateCustomer(id: customerId, name: trimmedName);
      await _refreshCustomers();
      _errorMessage = null;
      await _linkedDevices.syncAfterLocalChange(reason: 'customer_rename');
      _notifyListeners();
      return true;
    } catch (error, stackTrace) {
      debugPrint('CustomerProvider.updateCustomerName failed: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'Unable to update customer name.';
      _notifyListeners();
      return false;
    }
  }

  void updateSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }

    _searchQuery = value;
    _notifyListeners();
  }

  bool _matchesStartingLetters(Customer customer, String query) {
    final normalizedName = customer.name.trim().toLowerCase();
    final parts = normalizedName.split(RegExp(r'\s+'));

    return normalizedName.startsWith(query) ||
        parts.any((String part) => part.startsWith(query));
  }

  Future<void> _refreshCustomers() async {
    final rows = await _database.getCustomers();
    final customers = rows
        .map<Customer>((Map<String, Object?> row) => Customer.fromMap(row))
        .toList(growable: false);
    final sortedCustomers = customers.toList(growable: false)
      ..sort((Customer a, Customer b) {
        final leftName = a.name.trim().toLowerCase();
        final rightName = b.name.trim().toLowerCase();
        final nameCompare = leftName.compareTo(rightName);
        if (nameCompare != 0) {
          return nameCompare;
        }
        final leftId = a.id ?? 0;
        final rightId = b.id ?? 0;
        return leftId.compareTo(rightId);
      });
    _customers = List<Customer>.unmodifiable(sortedCustomers);
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
    loadCustomers();
  }

  @override
  void dispose() {
    _linkedDevices.removeListener(_handleLinkedDevicesChanged);
    _isDisposed = true;
    super.dispose();
  }
}
