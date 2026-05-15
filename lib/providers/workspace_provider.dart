import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../services/workspace_service.dart';
import '../database/app_database.dart';

class WorkspaceProvider extends ChangeNotifier {
  final WorkspaceService _service;
  bool _isDisposed = false;

  WorkspaceProvider({
    WorkspaceService? service,
  }) : _service = service ?? WorkspaceService.instance;

  List<Workspace> get workspaces => _service.workspaces;
  Workspace get activeWorkspace => _service.activeWorkspace;
  String get activeWorkspaceId => _service.activeWorkspaceId;
  bool _isSwitching = false;
  bool get isSwitching => _isSwitching;

  /// Callback that will be set by the app to handle full database switch.
  Future<void> Function(String workspaceId)? onWorkspaceSwitch;

  Future<Workspace> addWorkspace(String name) async {
    final workspace = await _service.addWorkspace(name);
    _notifyListeners();
    return workspace;
  }

  Future<void> renameWorkspace(String workspaceId, String newName) async {
    await _service.renameWorkspace(workspaceId, newName);
    _notifyListeners();
  }

  Future<bool> deleteWorkspace(String workspaceId) async {
    // 1. Delete the physical database file
    try {
      await DatabaseHelper.instance.deleteWorkspaceDatabase(workspaceId);
    } catch (e) {
      debugPrint('Error deleting workspace database file: $e');
    }

    // 2. Remove from metadata
    final deleted = await _service.deleteWorkspace(workspaceId);
    if (deleted) {
      _notifyListeners();
    }
    return deleted;
  }

  Future<bool> switchWorkspace(String workspaceId) async {
    if (workspaceId == _service.activeWorkspaceId) return true;
    if (_isSwitching) return false;

    _isSwitching = true;
    _notifyListeners();

    try {
      await _service.setActiveWorkspace(workspaceId);
      if (onWorkspaceSwitch != null) {
        await onWorkspaceSwitch!(workspaceId);
      }
      _isSwitching = false;
      _notifyListeners();
      return true;
    } catch (e) {
      debugPrint('WorkspaceProvider.switchWorkspace failed: $e');
      _isSwitching = false;
      _notifyListeners();
      return false;
    }
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
