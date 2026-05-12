import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/linked_device_models.dart';
import '../services/linked_devices_service.dart';
import '../services/workspace_sync_service.dart';
import '../utils/linked_devices_utils.dart';
import '../../../database/app_database.dart';

class LinkedSessionProvider extends ChangeNotifier {
  static const String _sessionIdKey = 'linked_session_id';
  static const String _iAmAdminKey = 'linked_i_am_admin';
  static const String _workspaceModeKey = 'linked_workspace_mode';

  String? _sessionId;
  bool _iAmAdmin = false;
  bool _isLinked = false;
  SessionPermission _permission = SessionPermission.read;
  WorkspaceMode _workspaceMode = WorkspaceMode.local;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  bool _isDisposed = false;

  String? get sessionId => _sessionId;
  bool get iAmAdmin => _iAmAdmin;
  bool get isLinked => _isLinked;
  SessionPermission get permission => _permission;
  WorkspaceMode get workspaceMode => _workspaceMode;
  bool get canEdit => !_isLinked || _iAmAdmin || _permission == SessionPermission.write;

  // ── Load session from local storage ──
  Future<void> loadSession() async {
    // Feature temporarily disabled. To re-enable, restore the original logic.
    _reset();
    _notify();
    return;
    /*
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSessionId = prefs.getString(_sessionIdKey);
      final savedIsAdmin = prefs.getBool(_iAmAdminKey) ?? false;

      if (savedSessionId == null || savedSessionId.isEmpty) {
        _reset();
        _notify();
        return;
      }

      _iAmAdmin = savedIsAdmin;

      if (!savedIsAdmin) {
        // Verify session still active on Firestore
        final session = await LinkedDevicesService.instance.getSession(savedSessionId);
        if (session == null) {
          await _clearStoredSession(prefs);
          _reset();
          _notify();
          return;
        }
        _sessionId = savedSessionId;
        _isLinked = true;
        _permission = session.permission;

        final savedMode = prefs.getString(_workspaceModeKey);
        _workspaceMode = savedMode == 'linked'
            ? WorkspaceMode.linked
            : WorkspaceMode.local;
      } else {
        _sessionId = savedSessionId;
        _isLinked = true;
        _workspaceMode = WorkspaceMode.local;
      }

      _notify();
    } catch (e) {
      debugPrint('LinkedSessionProvider.loadSession error: $e');
      _reset();
      _notify();
    }
    */
  }

  // ── Start real-time listener (guest only) ──
  void startSessionListener(VoidCallback onDisconnected) {
    if (_sessionId == null) return;
    _sessionSub?.cancel();
    _sessionSub = LinkedDevicesService.instance
        .sessionStream(_sessionId!)
        .listen((snap) async {
      if (_isDisposed) return;
      if (!snap.exists) {
        await _handleAdminDisconnect(onDisconnected);
        return;
      }
      final data = snap.data()!;
      final status = data['status'] as String? ?? 'active';
      if (status != 'active') {
        await _handleAdminDisconnect(onDisconnected);
        return;
      }
      // Update permission
      final permStr = data['permission'] as String? ?? 'read';
      _permission = permStr == 'write'
          ? SessionPermission.write
          : SessionPermission.read;
      _notify();
    }, onError: (e) {
      debugPrint('LinkedSessionProvider sessionStream error: $e');
    });
  }

  Future<void> _handleAdminDisconnect(VoidCallback onDisconnected) async {
    await _restoreLocalWorkspace();
    _reset();
    _notify();
    onDisconnected();
  }

  // ── Switch workspace mode (local ↔ linked) ──
  Future<void> setWorkspaceMode(WorkspaceMode mode, BuildContext context) async {
    if (_iAmAdmin) return; // admins always local
    _workspaceMode = mode;
    _notify();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workspaceModeKey, mode == WorkspaceMode.linked ? 'linked' : 'local');

    if (mode == WorkspaceMode.linked) {
      // Download admin snapshot
      final session = await LinkedDevicesService.instance.getSession(_sessionId!);
      if (session != null) {
        await WorkspaceSyncService.instance.downloadAndImportSnapshot(session.adminDeviceId);
        AppDatabase.instance.notifyDataChanged();
      }
    } else {
      // Restore local snapshot
      final myId = await LinkedDevicesUtils.getPersistentDeviceId();
      await WorkspaceSyncService.instance.restoreLocalSnapshot(myId);
      AppDatabase.instance.notifyDataChanged();
    }
  }

  // ── Disconnect (guest) ──
  Future<void> disconnect(BuildContext context) async {
    _sessionSub?.cancel();
    _sessionSub = null;

    // Restore own workspace
    await _restoreLocalWorkspace();

    final prefs = await SharedPreferences.getInstance();
    await _clearStoredSession(prefs);
    _reset();
    _notify();
  }

  Future<void> _restoreLocalWorkspace() async {
    try {
      final myId = await LinkedDevicesUtils.getPersistentDeviceId();
      await WorkspaceSyncService.instance.restoreLocalSnapshot(myId);
      AppDatabase.instance.notifyDataChanged();
    } catch (e) {
      debugPrint('LinkedSessionProvider._restoreLocalWorkspace error: $e');
    }
  }

  // ── Save session after joining ──
  Future<void> saveSession({
    required String sessionId,
    required bool iAmAdmin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, sessionId);
    await prefs.setBool(_iAmAdminKey, iAmAdmin);
    _sessionId = sessionId;
    _iAmAdmin = iAmAdmin;
    _isLinked = true;
    _notify();
  }

  void _reset() {
    _sessionId = null;
    _iAmAdmin = false;
    _isLinked = false;
    _permission = SessionPermission.read;
    _workspaceMode = WorkspaceMode.local;
  }

  Future<void> _clearStoredSession(SharedPreferences prefs) async {
    await prefs.remove(_sessionIdKey);
    await prefs.remove(_iAmAdminKey);
    await prefs.remove(_workspaceModeKey);
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _sessionSub?.cancel();
    super.dispose();
  }
}
