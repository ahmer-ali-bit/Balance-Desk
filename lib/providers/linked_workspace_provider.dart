import 'package:flutter/foundation.dart';

import '../models/linked_device.dart';
import '../services/linked_workspace_service.dart';

class LinkedWorkspaceProvider extends ChangeNotifier {
  final LinkedWorkspaceService _service;
  bool _isDisposed = false;

  LinkedWorkspaceProvider({LinkedWorkspaceService? service})
      : _service = service ?? LinkedWorkspaceService.instance;

  LinkedWorkspaceService get service => _service;

  LinkedWorkspace? get currentWorkspace => _service.cachedWorkspace;

  bool get isAdmin => _service.isCachedAdmin;

  bool get isLinked => _service.isCachedLinked;

  Future<void> initialize() async {
    await _service.initialize();
    _service.startPeriodicSync();
    _notifyListeners();
  }

  Future<LinkedWorkspace?> refreshWorkspace() async {
    final workspace = await _service.getCurrentWorkspace();
    _notifyListeners();
    return workspace;
  }

  void setError(String error) {
    // Error handling for linked workspace operations
    debugPrint('LinkedWorkspace error: $error');
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
    _service.stopPeriodicSync();
    super.dispose();
  }
}
