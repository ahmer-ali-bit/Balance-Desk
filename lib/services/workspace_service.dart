import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/workspace.dart';

/// Manages workspace metadata (list of workspaces + active workspace)
/// using shared_preferences, since this data lives above any individual
/// database file.
class WorkspaceService {
  WorkspaceService._();

  static final WorkspaceService instance = WorkspaceService._();

  static const String _workspacesKey = 'app_workspaces';
  static const String _activeWorkspaceIdKey = 'app_active_workspace_id';
  static const String _defaultWorkspaceId = 'default';
  static const String _defaultWorkspaceName = 'Main Workspace';

  List<Workspace> _workspaces = [];
  String _activeWorkspaceId = _defaultWorkspaceId;

  List<Workspace> get workspaces => List<Workspace>.unmodifiable(_workspaces);
  String get activeWorkspaceId => _activeWorkspaceId;

  Workspace get activeWorkspace {
    return _workspaces.firstWhere(
      (Workspace w) => w.id == _activeWorkspaceId,
      orElse: () => const Workspace(
        id: _defaultWorkspaceId,
        name: _defaultWorkspaceName,
      ),
    );
  }

  /// Returns the database filename for a given workspace.
  /// Default workspace uses the original 'shop_desktop.db' for backward
  /// compatibility.
  String databaseNameForWorkspace(String workspaceId) {
    if (workspaceId == _defaultWorkspaceId) {
      return 'shop_desktop.db';
    }
    // Sanitize workspace id for safe filename
    final sanitized = workspaceId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return 'shop_desktop_$sanitized.db';
  }

  String get activeDatabaseName =>
      databaseNameForWorkspace(_activeWorkspaceId);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Load workspaces
    final workspacesJson = prefs.getString(_workspacesKey);
    if (workspacesJson != null && workspacesJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(workspacesJson) as List<dynamic>;
        _workspaces = decoded
            .map((dynamic item) =>
                Workspace.fromMap(Map<String, String>.from(item as Map)))
            .toList();
      } catch (_) {
        _workspaces = [];
      }
    }

    // Ensure default workspace exists
    if (!_workspaces.any((Workspace w) => w.id == _defaultWorkspaceId)) {
      _workspaces.insert(
        0,
        const Workspace(
          id: _defaultWorkspaceId,
          name: _defaultWorkspaceName,
        ),
      );
      await _saveWorkspaces(prefs);
    }

    // Load active workspace
    _activeWorkspaceId =
        prefs.getString(_activeWorkspaceIdKey) ?? _defaultWorkspaceId;

    // Validate that active workspace exists
    if (!_workspaces.any((Workspace w) => w.id == _activeWorkspaceId)) {
      _activeWorkspaceId = _defaultWorkspaceId;
      await prefs.setString(_activeWorkspaceIdKey, _activeWorkspaceId);
    }
  }

  Future<Workspace> addWorkspace(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final workspace = Workspace(id: id, name: name.trim());
    _workspaces.add(workspace);
    await _saveWorkspaces(prefs);
    return workspace;
  }

  Future<void> renameWorkspace(String workspaceId, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final index = _workspaces.indexWhere((Workspace w) => w.id == workspaceId);
    if (index < 0) return;

    _workspaces[index] = _workspaces[index].copyWith(name: newName.trim());
    await _saveWorkspaces(prefs);
  }

  Future<bool> deleteWorkspace(String workspaceId) async {
    // Cannot delete default workspace or the only workspace
    if (workspaceId == _defaultWorkspaceId) return false;
    if (_workspaces.length <= 1) return false;

    final prefs = await SharedPreferences.getInstance();
    _workspaces.removeWhere((Workspace w) => w.id == workspaceId);

    // If active workspace was deleted, switch to default
    if (_activeWorkspaceId == workspaceId) {
      _activeWorkspaceId = _defaultWorkspaceId;
      await prefs.setString(_activeWorkspaceIdKey, _activeWorkspaceId);
    }

    await _saveWorkspaces(prefs);
    return true;
  }

  Future<void> setActiveWorkspace(String workspaceId) async {
    if (!_workspaces.any((Workspace w) => w.id == workspaceId)) return;

    final prefs = await SharedPreferences.getInstance();
    _activeWorkspaceId = workspaceId;
    await prefs.setString(_activeWorkspaceIdKey, _activeWorkspaceId);
  }

  Future<void> _saveWorkspaces(SharedPreferences prefs) async {
    final encoded = jsonEncode(
      _workspaces.map((Workspace w) => w.toMap()).toList(),
    );
    await prefs.setString(_workspacesKey, encoded);
  }
}
