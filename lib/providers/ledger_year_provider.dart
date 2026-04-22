import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../services/linked_devices_controller.dart';

class LedgerYearProvider extends ChangeNotifier {
  LedgerYearProvider({
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

  List<int> _years = <int>[];
  int _activeYear = DateTime.now().year;
  bool _isLoading = false;
  String? _errorMessage;

  List<int> get years => List<int>.unmodifiable(_years);
  int get activeYear => _activeYear;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadYears() async {
    _setLoading(true);

    try {
      final years = await _database.getLedgerYears();
      _activeYear = _database.activeYear;
      _years = years.contains(_activeYear)
          ? List<int>.unmodifiable(years)
          : List<int>.unmodifiable(
              <int>[_activeYear, ...years]
                ..sort((int a, int b) => b.compareTo(a)),
            );
      _errorMessage = null;
    } catch (_) {
      _errorMessage = 'Unable to load years.';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addAndSelectYear(int year) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

    if (!_isValidYear(year)) {
      _errorMessage = 'Enter a valid year.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.addLedgerYear(year);
      await _database.setActiveYear(year);
      await loadYears();
      await _linkedDevices.syncAfterLocalChange(reason: 'year_add');
      return true;
    } catch (_) {
      _errorMessage = 'Unable to add year.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> selectYear(int year) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

    if (!_isValidYear(year)) {
      _errorMessage = 'Enter a valid year.';
      _notifyListeners();
      return false;
    }

    if (year == _activeYear) {
      return true;
    }

    _setLoading(true);

    try {
      await _database.setActiveYear(year);
      await loadYears();
      await _linkedDevices.syncAfterLocalChange(reason: 'year_select');
      return true;
    } catch (_) {
      _errorMessage = 'Unable to open year.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> deleteYear(int year) async {
    if (!_linkedDevices.canEditWorkspace) {
      _errorMessage = _linkedDevices.readOnlyMessage;
      _notifyListeners();
      return false;
    }

    if (!_isValidYear(year)) {
      _errorMessage = 'Enter a valid year.';
      _notifyListeners();
      return false;
    }

    if (_years.length <= 1) {
      _errorMessage = 'Cannot delete the only active year.';
      _notifyListeners();
      return false;
    }

    _setLoading(true);

    try {
      await _database.deleteLedgerYear(year);
      await loadYears();
      await _linkedDevices.syncAfterLocalChange(reason: 'year_delete');
      return true;
    } catch (_) {
      _errorMessage = 'Unable to delete year.';
      _setLoading(false);
      return false;
    }
  }

  bool _isValidYear(int year) {
    return year >= 1900 && year <= 9999;
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
    loadYears();
  }

  @override
  void dispose() {
    _linkedDevices.removeListener(_handleLinkedDevicesChanged);
    _isDisposed = true;
    super.dispose();
  }
}
