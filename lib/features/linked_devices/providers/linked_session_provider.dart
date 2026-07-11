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
  String? _adminDeviceId;
  bool _iAmAdmin = false;
  bool _isLinked = false;
  SessionPermission _permission = SessionPermission.read;
  WorkspaceMode _workspaceMode = WorkspaceMode.local;
  StreamSubscription<dynamic>? _sessionSub;
  Timer? _adminUploadTimer;
  Timer? _guestSyncTimer;
  Timer? _guestDownloadDebounce;
  String? _lastSnapshotAt;
  String? _lastGuestSnapshotAt;
  String? _lastAdminAppliedGuestSnapshotAt;
  String? _lastLinkedFingerprint;
  String? _lastLocalFingerprint;
  bool _isSyncing = false;
  bool _isDisposed = false;

  static String localBackupSnapshotId(String deviceId) =>
      'local_backup_$deviceId';

  String? get sessionId => _sessionId;
  bool get iAmAdmin => _iAmAdmin;
  bool get isLinked => _isLinked;
  SessionPermission get permission => _permission;
  WorkspaceMode get workspaceMode => _workspaceMode;
  bool get canEdit =>
      !_isLinked ||
      _iAmAdmin ||
      _workspaceMode == WorkspaceMode.local ||
      _permission == SessionPermission.write;
  bool get isUsingLinkedWorkspace => _workspaceMode == WorkspaceMode.linked;

  // ── Load session from local storage ──
  Future<void> loadSession() async {
    try {
      await LinkedDevicesService.ensureFirebase();
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
        final session = await LinkedDevicesService.instance.getSession(
          savedSessionId,
        );
        if (session == null) {
          await _clearStoredSession(prefs);
          _reset();
          _notify();
          return;
        }
        _sessionId = savedSessionId;
        _isLinked = true;
        _adminDeviceId = session.adminDeviceId;
        _permission = session.permission;

        final savedMode = prefs.getString(_workspaceModeKey);
        _workspaceMode = savedMode == 'local'
            ? WorkspaceMode.local
            : WorkspaceMode.linked;

        // Auto-download admin snapshot on first load in linked mode
        if (_workspaceMode == WorkspaceMode.linked) {
          await _downloadLinkedSnapshot(session.adminDeviceId);
        } else {
          _lastLocalFingerprint = await WorkspaceSyncService.instance
              .localFingerprint();
        }
        startSessionListener();
      } else {
        _sessionId = savedSessionId;
        _isLinked = true;
        _workspaceMode = WorkspaceMode.local;
      }

      if (_iAmAdmin) _startAdminAutoSync();
      _notify();
    } catch (e) {
      debugPrint('LinkedSessionProvider.loadSession error: $e');
      _reset();
      _notify();
    }
  }

  // ── Start real-time listener (guest only) ──
  void startSessionListener([VoidCallback? onDisconnected]) {
    if (_sessionId == null) return;
    _sessionSub?.cancel();
    _sessionSub = LinkedDevicesService.instance
        .sessionStream(_sessionId!)
        .listen(
          (snap) async {
            if (_isDisposed) return;

            // Handle both DocumentSnapshot (mobile) and Map (desktop)
            bool exists;
            Map<String, dynamic>? data;
            if (snap is Map) {
              exists = snap['exists'] == true;
              data = snap['data'] as Map<String, dynamic>?;
            } else {
              final doc = snap as DocumentSnapshot<Map<String, dynamic>>;
              exists = doc.exists;
              data = doc.data();
            }

            if (!exists || data == null) {
              await _handleAdminDisconnect(onDisconnected);
              return;
            }
            final status = data['status']?.toString() ?? 'active';
            if (status != 'active') {
              await _handleAdminDisconnect(onDisconnected);
              return;
            }
            // Track admin device ID
            _adminDeviceId = data['adminDeviceId']?.toString();

            // Update permission
            final permStr = data['permission']?.toString() ?? 'read';
            _permission = permStr == 'write'
                ? SessionPermission.write
                : SessionPermission.read;

            // Auto-sync: detect snapshot version change → download for guest
            final newSnapshotAt = data['lastSnapshotAt']?.toString();
            _lastGuestSnapshotAt = data['lastGuestSnapshotAt']?.toString();
            _lastAdminAppliedGuestSnapshotAt =
                data['lastAdminAppliedGuestSnapshotAt']?.toString();
            if (!_iAmAdmin &&
                _workspaceMode == WorkspaceMode.linked &&
                newSnapshotAt != null &&
                newSnapshotAt != _lastSnapshotAt) {
              if (await _shouldDeferAdminDownload()) {
                await _pushGuestSnapshotIfChanged();
                _notify();
                return;
              }

              _guestDownloadDebounce?.cancel();
              _guestDownloadDebounce = Timer(
                const Duration(milliseconds: 500),
                () async {
                  final adminId = _adminDeviceId;
                  if (adminId != null &&
                      !_isDisposed &&
                      !await _shouldDeferAdminDownload()) {
                    final downloaded = await _downloadLinkedSnapshot(adminId);
                    if (downloaded) _lastSnapshotAt = newSnapshotAt;
                  }
                },
              );
            }

            _notify();
          },
          onError: (e) {
            debugPrint('LinkedSessionProvider sessionStream error: $e');
          },
        );

    // Start guest polling timer for snapshot changes (only if guest)
    if (!_iAmAdmin) _startGuestSync();
  }

  // ── Admin auto-sync: push snapshot + notify guests + pull guest changes ──
  void _startAdminAutoSync() {
    if (!_iAmAdmin || !_isLinked) return;
    _adminUploadTimer?.cancel();
    _adminUploadTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_isDisposed || !_iAmAdmin || _isSyncing) return;

      final deviceId = await LinkedDevicesUtils.getPersistentDeviceId();

      _isSyncing = true;
      try {
        final sessions = await LinkedDevicesService.instance
            .getAllActiveSessions(deviceId);

        for (final session in sessions) {
          final guestSnapshotAt = session.lastGuestSnapshotAt;
          final alreadyApplied = session.lastAdminAppliedGuestSnapshotAt;
          if (session.permission != SessionPermission.write ||
              guestSnapshotAt == null ||
              guestSnapshotAt == alreadyApplied) {
            continue;
          }

          await WorkspaceSyncService.instance.mergeSnapshotFromDevice(
            session.linkedDeviceId,
          );
          await LinkedDevicesService.instance.updateSessionField(
            session.sessionId,
            {'lastAdminAppliedGuestSnapshotAt': guestSnapshotAt},
          );
          AppDatabase.instance.notifyDataChanged();
        }

        // Push the admin workspace after any editable guest changes have landed.
        final ts = await WorkspaceSyncService.instance.uploadFullSnapshot(
          deviceId,
        );
        for (final s in sessions) {
          if (ts != null) {
            await LinkedDevicesService.instance.updateSessionField(
              s.sessionId,
              {'lastSnapshotAt': ts},
            );
          }
        }
      } catch (e) {
        debugPrint('LinkedSessionProvider admin sync error: $e');
      } finally {
        _isSyncing = false;
      }
    });
  }

  void _stopAdminAutoSync() {
    _adminUploadTimer?.cancel();
    _adminUploadTimer = null;
  }

  // ── Guest sync: pull admin changes + push own changes when editable ──
  void _startGuestSync() {
    _guestSyncTimer?.cancel();
    _guestSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_isDisposed || _iAmAdmin || _adminDeviceId == null) return;

      if (_workspaceMode == WorkspaceMode.local) {
        await _backupLocalWorkspaceIfChanged();
        return;
      }

      if (await _pushGuestSnapshotIfChanged()) {
        return;
      }

      // Pull: download admin's latest snapshot
      if (_workspaceMode != WorkspaceMode.linked ||
          _isSyncing ||
          await _shouldDeferAdminDownload()) {
        return;
      }
      final ts = await WorkspaceSyncService.instance.getSnapshotTimestamp(
        _adminDeviceId!,
      );
      if (ts != null && ts != _lastSnapshotAt) {
        final downloaded = await _downloadLinkedSnapshot(_adminDeviceId!);
        if (downloaded) _lastSnapshotAt = ts;
      }
    });
  }

  void _stopGuestSync() {
    _guestSyncTimer?.cancel();
    _guestSyncTimer = null;
    _guestDownloadDebounce?.cancel();
    _guestDownloadDebounce = null;
  }

  Future<void> _handleAdminDisconnect(VoidCallback? onDisconnected) async {
    if (_workspaceMode == WorkspaceMode.local) {
      await _backupLocalWorkspaceIfChanged(force: true);
    }
    await _restoreLocalWorkspace();
    _reset();
    _notify();
    onDisconnected?.call();
  }

  // ── Switch workspace mode (local ↔ linked) ──
  Future<void> setWorkspaceMode(
    WorkspaceMode mode,
    BuildContext context,
  ) async {
    if (_iAmAdmin) return; // admins always local
    if (_workspaceMode == mode) return;
    final previousMode = _workspaceMode;
    final myId = await LinkedDevicesUtils.getPersistentDeviceId();

    if (previousMode == WorkspaceMode.local) {
      await _backupLocalWorkspaceIfChanged(deviceId: myId, force: true);
    } else if (_permission == SessionPermission.write && _sessionId != null) {
      await _pushGuestSnapshotIfChanged(deviceId: myId, force: true);
    }

    _workspaceMode = mode;
    _notify();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _workspaceModeKey,
      mode == WorkspaceMode.linked ? 'linked' : 'local',
    );

    if (mode == WorkspaceMode.linked) {
      // Download admin snapshot
      final session = await LinkedDevicesService.instance.getSession(
        _sessionId!,
      );
      if (session != null) {
        await _downloadLinkedSnapshot(session.adminDeviceId);
      }
    } else {
      // Restore local snapshot
      await _restoreLocalWorkspace(deviceId: myId);
    }
  }

  // ── Disconnect (guest) ──
  Future<void> disconnect(BuildContext context) async {
    if (!_iAmAdmin) {
      if (_workspaceMode == WorkspaceMode.local) {
        await _backupLocalWorkspaceIfChanged(force: true);
      } else if (_permission == SessionPermission.write) {
        await _pushGuestSnapshotIfChanged(force: true);
      }
    }

    // Notify admin by updating session status in Firestore
    if (_sessionId != null) {
      await LinkedDevicesService.instance.disconnectSession(_sessionId!);
    }

    _sessionSub?.cancel();
    _sessionSub = null;
    _stopAdminAutoSync();
    _stopGuestSync();

    // Restore own workspace
    await _restoreLocalWorkspace();

    final prefs = await SharedPreferences.getInstance();
    await _clearStoredSession(prefs);
    _reset();
    _notify();
  }

  Future<void> _restoreLocalWorkspace({String? deviceId}) async {
    try {
      final myId = deviceId ?? await LinkedDevicesUtils.getPersistentDeviceId();
      final restored = await _restoreSnapshot(localBackupSnapshotId(myId));
      if (!restored) {
        await _restoreSnapshot(myId);
      }
    } catch (e) {
      debugPrint('LinkedSessionProvider._restoreLocalWorkspace error: $e');
    }
  }

  Future<bool> _restoreSnapshot(String snapshotId) async {
    _isSyncing = true;
    try {
      final restored = await WorkspaceSyncService.instance.restoreLocalSnapshot(
        snapshotId,
      );
      if (restored) {
        AppDatabase.instance.notifyDataChanged();
        _lastLocalFingerprint = await WorkspaceSyncService.instance
            .localFingerprint();
      }
      return restored;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _downloadLinkedSnapshot(String deviceId) async {
    _isSyncing = true;
    try {
      final downloaded = await WorkspaceSyncService.instance
          .downloadAndImportSnapshot(deviceId);
      if (downloaded) {
        AppDatabase.instance.notifyDataChanged();
        _lastLinkedFingerprint = await WorkspaceSyncService.instance
            .localFingerprint();
      }
      return downloaded;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _backupLocalWorkspaceIfChanged({
    String? deviceId,
    bool force = false,
  }) async {
    final myId = deviceId ?? await LinkedDevicesUtils.getPersistentDeviceId();
    final fingerprint = await WorkspaceSyncService.instance.localFingerprint();
    if (!force && fingerprint != null && fingerprint == _lastLocalFingerprint) {
      return false;
    }

    final ts = await WorkspaceSyncService.instance.uploadFullSnapshot(
      localBackupSnapshotId(myId),
    );
    if (ts == null) return false;
    _lastLocalFingerprint = fingerprint;
    return true;
  }

  Future<bool> _pushGuestSnapshotIfChanged({
    String? deviceId,
    bool force = false,
  }) async {
    if (_iAmAdmin ||
        _workspaceMode != WorkspaceMode.linked ||
        _permission != SessionPermission.write ||
        _sessionId == null) {
      return false;
    }

    final fingerprint = await WorkspaceSyncService.instance.localFingerprint();
    if (!force &&
        fingerprint != null &&
        fingerprint == _lastLinkedFingerprint) {
      return false;
    }

    final myId = deviceId ?? await LinkedDevicesUtils.getPersistentDeviceId();
    final ts = await WorkspaceSyncService.instance.uploadFullSnapshot(myId);
    if (ts == null) return false;

    _lastLinkedFingerprint = fingerprint;
    _lastGuestSnapshotAt = ts;
    await LinkedDevicesService.instance.updateSessionField(_sessionId!, {
      'lastGuestSnapshotAt': ts,
    });
    return true;
  }

  Future<bool> _shouldDeferAdminDownload() async {
    if (_iAmAdmin ||
        _workspaceMode != WorkspaceMode.linked ||
        _permission != SessionPermission.write) {
      return false;
    }

    final fingerprint = await WorkspaceSyncService.instance.localFingerprint();
    if (fingerprint != null && fingerprint != _lastLinkedFingerprint) {
      return true;
    }

    return _lastGuestSnapshotAt != null &&
        _lastGuestSnapshotAt != _lastAdminAppliedGuestSnapshotAt;
  }

  // ── Save session after joining or admin registration ──
  Future<void> saveSession({
    required String sessionId,
    required bool iAmAdmin,
    String? adminDeviceId,
    SessionPermission permission = SessionPermission.read,
    WorkspaceMode? workspaceMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, sessionId);
    await prefs.setBool(_iAmAdminKey, iAmAdmin);
    final nextMode =
        workspaceMode ??
        (iAmAdmin ? WorkspaceMode.local : WorkspaceMode.linked);
    await prefs.setString(
      _workspaceModeKey,
      nextMode == WorkspaceMode.linked ? 'linked' : 'local',
    );
    _sessionId = sessionId;
    _iAmAdmin = iAmAdmin;
    _isLinked = true;
    _adminDeviceId = adminDeviceId ?? _adminDeviceId;
    _permission = permission;
    _workspaceMode = nextMode;
    if (_iAmAdmin) {
      _startAdminAutoSync();
      startSessionListener();
    } else {
      startSessionListener();
      if (_workspaceMode == WorkspaceMode.linked && _adminDeviceId != null) {
        // If the joining device's local workspace is empty, keep it empty
        // instead of pulling the admin's snapshot over it.
        final localEmpty = await WorkspaceSyncService.instance
            .isLocalWorkspaceEmpty();
        if (!localEmpty) {
          await _downloadLinkedSnapshot(_adminDeviceId!);
        }
      }
    }
    _notify();
  }

  void _reset() {
    _stopAdminAutoSync();
    _stopGuestSync();
    _sessionSub?.cancel();
    _sessionSub = null;
    _sessionId = null;
    _adminDeviceId = null;
    _iAmAdmin = false;
    _isLinked = false;
    _permission = SessionPermission.read;
    _workspaceMode = WorkspaceMode.local;
    _lastSnapshotAt = null;
    _lastGuestSnapshotAt = null;
    _lastAdminAppliedGuestSnapshotAt = null;
    _lastLinkedFingerprint = null;
    _lastLocalFingerprint = null;
    _isSyncing = false;
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
    _stopAdminAutoSync();
    _stopGuestSync();
    _sessionSub?.cancel();
    super.dispose();
  }
}
