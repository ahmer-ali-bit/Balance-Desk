import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../database/app_database.dart';
import '../models/workspace.dart';
import '../services/linked_device_api.dart';
import '../services/linked_device_credentials.dart';
import '../services/linked_devices_service.dart';
import '../services/linked_workspace_sync_service.dart';
import '../services/workspace_service.dart';
import 'workspace_provider.dart';

class LinkedDevicesProvider extends ChangeNotifier with WidgetsBindingObserver {
  LinkedDevicesProvider({
    LinkedDevicesService? service,
    LinkedWorkspaceSyncService? syncService,
  }) : _service = service ?? LinkedDevicesService.instance,
       _syncService = syncService ?? LinkedWorkspaceSyncService();

  final LinkedDevicesService _service;
  final LinkedWorkspaceSyncService _syncService;
  WorkspaceProvider? _workspaceProvider;
  StreamSubscription<void>? _databaseSubscription;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  bool _isDisposed = false;
  bool _initialized = false;
  bool _isSyncing = false;
  bool _isBusy = false;
  bool _isConfigLoading = true;
  bool _syncRequestedWhileBusy = false;
  bool _lastSyncFailed = false;
  int _consecutiveSyncFailures = 0;
  String _activeLocalWorkspaceId = 'default';
  LinkedWorkspaceConfig? _config;
  String? _error;
  DateTime? _lastSyncAt;
  int _lastChangeCount = 0;
  int _conflictCount = 0;
  List<Map<String, Object?>> _devices = const <Map<String, Object?>>[];
  LinkedInvite? _invite;

  bool get isLoading => !_initialized;
  bool get isBusy => _isBusy;
  bool get isSyncing => _isSyncing;
  bool get isLinked => _config != null;
  bool get isOwner => _config?.isOwner ?? false;
  bool get isReadOnly => _config?.isReadOnly ?? false;
  String? get error => _error;
  DateTime? get lastSyncAt => _lastSyncAt;
  int get lastChangeCount => _lastChangeCount;
  int get conflictCount => _conflictCount;
  LinkedWorkspaceConfig? get config => _config;
  List<Map<String, Object?>> get devices => List.unmodifiable(_devices);
  LinkedInvite? get invite => _invite;

  String get syncLabel {
    if (_isSyncing) return 'Syncing changes…';
    if (_error != null) {
      if (_conflictCount > 0) return 'Conflict needs review';
      return _config == null ? 'Sync stopped' : 'Retrying automatically';
    }
    if (_config?.isReadOnly ?? false) return 'Read-only device';
    if (_config != null) return 'Auto-sync on · local-first';
    return 'This workspace is only on this device';
  }

  Future<void> initialize() async {
    if (_initialized) return;
    WidgetsBinding.instance.addObserver(this);
    _databaseSubscription = AppDatabase.instance.onDataChanged.listen((_) {
      if (_config == null) return;
      if (_isSyncing) {
        _syncRequestedWhileBusy = true;
      } else {
        _scheduleSync();
      }
    });
    await _refreshConfig();
    _initialized = true;
    if (_config != null) {
      _scheduleNextSync(const Duration(seconds: 1));
    }
    _notify();
  }

  void bindWorkspaceProvider(WorkspaceProvider provider) {
    _workspaceProvider = provider;
    final id = provider.activeWorkspaceId;
    if (!_initialized) {
      _activeLocalWorkspaceId = id;
      unawaited(initialize());
      return;
    }
    if (id != _activeLocalWorkspaceId) unawaited(setActiveWorkspace(id));
  }

  Future<void> setActiveWorkspace(String workspaceId) async {
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    if (_activeLocalWorkspaceId == workspaceId && _initialized) {
      // A device may rejoin a workspace whose local database is still active.
      // Refresh config instead of assuming the previous link is still valid.
      await _refreshConfig();
      _notify();
      if (_config != null) {
        unawaited(syncNow(silent: true));
      }
      return;
    }
    _activeLocalWorkspaceId = workspaceId;
    _error = null;
    _lastSyncAt = null;
    _lastChangeCount = 0;
    _lastSyncFailed = false;
    _consecutiveSyncFailures = 0;
    _syncRequestedWhileBusy = false;
    _devices = const <Map<String, Object?>>[];
    _invite = null;
    await _refreshConfig();
    _notify();
    if (_config != null) unawaited(syncNow(silent: true));
  }

  Future<void> _refreshConfig() async {
    _isConfigLoading = true;
    DatabaseHelper.instance.writeGuard = () {
      if (_isConfigLoading ||
          WorkspaceService.instance.activeWorkspaceId !=
              _activeLocalWorkspaceId) {
        return false;
      }
      final config = _config;
      if (config == null) return true;
      if (config.localWorkspaceId != _activeLocalWorkspaceId) return false;
      return !config.isReadOnly;
    };
    _config = null;
    try {
      _config = await _service.configFor(_activeLocalWorkspaceId);
      if (_config == null) {
        _conflictCount = 0;
        _lastSyncAt = null;
        return;
      }
      final db = await AppDatabase.instance.database;
      _conflictCount = (await db.query('sync_conflicts')).length;
    } finally {
      _isConfigLoading = false;
    }
  }

  Future<void> shareCurrentWorkspace(String name) async {
    if (_isBusy) return;
    _setBusy(true);
    try {
      final identity = await LinkedDevicesService.currentDevice();
      final config = await _service.shareWorkspace(
        localWorkspaceId: _activeLocalWorkspaceId,
        workspaceName: name,
        deviceName: identity.$1,
        platform: identity.$2,
      );
      _config = config;
      _error = null;
      await syncNow(silent: true);
    } catch (error) {
      _error = _friendlyError(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<Workspace> joinWorkspace(String inviteCode) async {
    if (_isBusy) throw StateError('Another linked-device action is running.');
    _setBusy(true);
    try {
      final identity = await LinkedDevicesService.currentDevice();
      final workspace = await _service.joinWorkspace(
        inviteToken: inviteCode,
        deviceName: identity.$1,
        platform: identity.$2,
      );
      final workspaceProvider = _workspaceProvider;
      if (workspaceProvider != null) {
        final switched = await workspaceProvider.switchWorkspace(workspace.id);
        if (!switched) {
          throw const LinkedDeviceException(
            'The device was linked, but the workspace could not be opened. Select it from the workspace switcher to sync.',
          );
        }
        await setActiveWorkspace(workspace.id);
        await syncNow(silent: true);
      }
      return workspace;
    } catch (error) {
      _error = _friendlyError(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> createInvite() async {
    final config = _config;
    if (config == null || !config.isOwner) {
      throw const LinkedDeviceException('Only the workspace owner can link a device.');
    }
    _setBusy(true);
    try {
      _invite = await _service.createInvite(config);
      _error = null;
      await refreshDevices();
    } catch (error) {
      _error = _friendlyError(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshDevices() async {
    final config = _config;
    if (config == null || !config.isOwner) return;
    try {
      _devices = await _service.listDevices(config);
      _error = null;
    } catch (error) {
      _error = _friendlyError(error);
      rethrow;
    } finally {
      _notify();
    }
  }

  Future<void> setDevicePermission(String deviceId, String permission) async {
    final config = _config;
    if (config == null) return;
    await _service.setPermission(config, deviceId, permission);
    await refreshDevices();
  }

  Future<void> transferOwnership(String deviceId) async {
    final config = _config;
    if (config == null || !config.isOwner) return;
    await _service.transferOwnership(config, deviceId);
    final updated = config.copyWith(role: 'linked');
    _config = updated;
    await LinkedWorkspaceConfigStore().write(updated);
    _devices = const <Map<String, Object?>>[];
    _notify();
  }

  Future<void> revokeDevice(String deviceId) async {
    final config = _config;
    if (config == null) return;
    await _service.revokeDevice(config, deviceId);
    await refreshDevices();
  }

  Future<void> stopSharing() async {
    final config = _config;
    if (config == null || !config.isOwner) return;
    _setBusy(true);
    try {
      await _service.stopSharing(config);
      _periodicTimer?.cancel();
      _periodicTimer = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _config = null;
      _devices = const <Map<String, Object?>>[];
      _invite = null;
      _error = null;
      DatabaseHelper.instance.writeGuard = null;
    } catch (error) {
      _error = _friendlyError(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disconnect() async {
    final config = _config;
    if (config == null || config.isOwner) return;
    _setBusy(true);
    try {
      await _service.disconnect(config);
      _periodicTimer?.cancel();
      _periodicTimer = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _config = null;
      _devices = const <Map<String, Object?>>[];
      _error = null;
      DatabaseHelper.instance.writeGuard = null;
    } catch (error) {
      _error = _friendlyError(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> syncNow({bool silent = false}) async {
    final config = _config;
    if (config == null || _isSyncing) return;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _syncRequestedWhileBusy = false;
    _isSyncing = true;
    _lastSyncFailed = false;
    _error = null;
    _notify();
    try {
      var current = config;
      LinkedSyncResult result = LinkedSyncResult(
        cursor: current.cursor,
        changedRecords: 0,
        pendingRecords: 0,
        conflictCount: _conflictCount,
        permission: current.permission,
        role: current.role,
      );
      for (var pass = 0; pass < 20; pass++) {
        result = await _syncService.sync(current);
        current = current.copyWith(
          cursor: result.cursor,
          permission: result.permission,
          role: result.role,
        );
        await LinkedWorkspaceConfigStore().write(current);
        if (result.pendingRecords == 0) break;
      }
      final previousRole = _config?.role;
      final roleChanged = previousRole != null && previousRole != current.role;
      final becameOwner = roleChanged && current.isOwner;
      _config = current;
      if (roleChanged && !current.isOwner) {
        _devices = const <Map<String, Object?>>[];
      }
      if (becameOwner) await refreshDevices();
      _lastSyncAt = DateTime.now();
      _lastChangeCount = result.changedRecords;
      _conflictCount = result.conflictCount;
      _consecutiveSyncFailures = 0;
      if (_conflictCount > 0) {
        _error = 'Some records changed on two devices. Review the conflicts below.';
      }
    } catch (error) {
      _lastSyncFailed = true;
      _consecutiveSyncFailures++;
      _error = _friendlyError(error);
      final message = error.toString();
      if (message.contains('device_revoked_or_invalid') ||
          message.contains('workspace_unavailable')) {
        await _service.forgetRevokedLink(config.localWorkspaceId);
        _config = null;
        _devices = const <Map<String, Object?>>[];
        DatabaseHelper.instance.writeGuard = null;
        _error = 'Cloud access was removed. This device still has its local copy.';
      }
      if (!silent) rethrow;
    } finally {
      _isSyncing = false;
      _notify();
      if (_config == null) {
        _periodicTimer?.cancel();
        _periodicTimer = null;
      } else if (_syncRequestedWhileBusy) {
        _syncRequestedWhileBusy = false;
        _scheduleSync();
      } else {
        _scheduleNextSync(_nextSyncDelay);
      }
    }
  }

  Future<void> resolveConflict({
    required String entity,
    required String recordId,
    required bool keepThisDevice,
  }) async {
    await _syncService.resolveConflict(
      localWorkspaceId: _activeLocalWorkspaceId,
      entity: entity,
      recordId: recordId,
      keepThisDevice: keepThisDevice,
    );
    final db = await AppDatabase.instance.database;
    _conflictCount = (await db.query('sync_conflicts')).length;
    _notify();
    if (_conflictCount == 0) await syncNow(silent: true);
  }

  Future<List<Map<String, Object?>>> getConflicts() async {
    final db = await AppDatabase.instance.database;
    return db.query('sync_conflicts', orderBy: 'detectedAt');
  }

  Duration get _nextSyncDelay {
    if (!_lastSyncFailed) return const Duration(seconds: 15);
    final retrySeconds = switch (_consecutiveSyncFailures) {
      <= 1 => 8,
      2 => 16,
      3 => 32,
      _ => 60,
    };
    return Duration(seconds: retrySeconds);
  }

  void _scheduleNextSync([Duration? delay]) {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    if (_config == null || _isDisposed) return;
    _periodicTimer = Timer(delay ?? _nextSyncDelay, () {
      _periodicTimer = null;
      unawaited(syncNow(silent: true));
    });
  }

  void _scheduleSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 900), () {
      _debounceTimer = null;
      unawaited(syncNow(silent: true));
    });
  }

  void _setBusy(bool value) {
    _isBusy = value;
    _notify();
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('device_revoked_or_invalid')) {
      return 'This device was unlinked. Its local copy is still available; ask the owner to link it again.';
    }
    if (message.contains('device_read_only')) {
      return 'This device is read-only. Changes are blocked until the owner restores edit access.';
    }
    if (message.contains('invite_invalid_expired_or_used')) {
      return 'This invite has expired or was already used. Ask the owner for a fresh code.';
    }
    return message;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _config != null) {
      unawaited(syncNow(silent: true));
    }
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _databaseSubscription?.cancel();
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
