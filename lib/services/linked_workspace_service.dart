import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/firebase_config.dart';
import '../database/app_database.dart';
import '../models/linked_device.dart';
import '../models/workspace.dart';
import '../providers/workspace_provider.dart';
import '../services/workspace_service.dart';
import '../utils/platform_helper.dart';

/// Service for managing linked workspaces and device authorization.
/// Persists linked workspace state using SharedPreferences (mimics cloud sync).
/// Firebase integration would replace the SharedPreferences operations below.
class LinkedWorkspaceService {
  LinkedWorkspaceService._();

  static final LinkedWorkspaceService instance = LinkedWorkspaceService._();

  /// Local device ID persisted across app launches.
  static const String _deviceIdKey = 'linked_device_id';

  String? _cachedDeviceId;
  String? _cachedAuthToken;
  DateTime? _authTokenExpiry;
  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _cachedIsAdmin = false;
  bool _cachedIsLinked = false;
  LinkedWorkspace? _cachedWorkspace;

  String get deviceId {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    // Generate deterministic ID if not cached
    return _generateDeviceId();
  }

  Future<void> initialize() async {
    _cachedDeviceId = await _getOrCreateDeviceId();
    await _ensureWorkspaceLinkConfig();
  }

  /// Gets the current device's linked workspace info.
  Future<LinkedWorkspace?> getCurrentWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final linkedWorkspaceId = prefs.getString('linked_workspace_id');
    if (linkedWorkspaceId == null || linkedWorkspaceId.isEmpty) {
      _cachedWorkspace = null;
      _cachedIsAdmin = false;
      _cachedIsLinked = false;
      return null;
    }

    final workspace = LinkedWorkspace.fromMap(
        jsonDecode(prefs.getString('linked_workspace_cache') ?? '{}') as Map<String, dynamic>);
    _cachedWorkspace = workspace;
    _cachedIsAdmin = workspace.adminDeviceId == deviceId;
    _cachedIsLinked = true;
    return workspace;
  }

  /// Synchronous check for linked status using cached value.
  bool get isCachedLinked => _cachedIsLinked;

  /// Synchronous check for admin status using cached value.
  bool get isCachedAdmin => _cachedIsAdmin;

  /// Gets the cached workspace (synchronous).
  LinkedWorkspace? get cachedWorkspace => _cachedWorkspace;

  /// Checks if current device is admin of the linked workspace.
  Future<bool> isAdmin() async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) return false;
    final result = workspace.adminDeviceId == deviceId;
    _cachedIsAdmin = result;
    return result;
  }

  /// Gets the role of current device in linked workspace.
  Future<DeviceRole?> getCurrentDeviceRole() async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) return null;

    for (final d in workspace.devices) {
      if (d.deviceId == deviceId) return d.role;
    }
    return null;
  }

  /// Creates a new linked workspace (promotes current workspace to admin).
  Future<LinkedWorkspace> createLinkedWorkspace({
    required String workspaceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWorkspaceId = WorkspaceService.instance.activeWorkspaceId;
    final currentWorkspaceName =
        WorkspaceService.instance.activeWorkspace.name;

    final workspaceId = _generateWorkspaceId();
    final now = DateTime.now().toIso8601String();

    final adminDevice = await _buildCurrentDeviceInfo(role: DeviceRole.admin);
    final updatedAdminDevice = adminDevice.copyWith(firstLinkedAt: now);

    final workspace = LinkedWorkspace(
      workspaceId: workspaceId,
      name: workspaceName.isNotEmpty ? workspaceName : currentWorkspaceName,
      adminDeviceId: deviceId,
      devices: [adminDevice],
      createdAt: now,
      updatedAt: now,
    );

    // "Write" to cloud (SharedPreferences mock)
    await prefs.setString('linked_workspace_id', workspaceId);
    await prefs.setString('linked_workspace_cache', jsonEncode(workspace.toMap()));

    // Link locally
    await _linkLocalWorkspace(currentWorkspaceId, workspaceId);

    _cachedIsLinked = true;
    _cachedIsAdmin = true;
    _cachedWorkspace = workspace;

    return workspace;
  }

  /// Generates an invite link for joining the workspace.
  Future<LinkedInvite> generateInvite({
    Duration validity = const Duration(minutes: 10),
    int maxUses = 1,
  }) async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) {
      throw StateError('No linked workspace to invite to');
    }

    if (!(await isAdmin())) {
      throw StateError('Only admin can generate invites');
    }

    final token = _generateInviteToken();
    final now = DateTime.now();
    final expiresAt = now.add(validity).toIso8601String();

    final invite = LinkedInvite(
      token: token,
      workspaceId: workspace.workspaceId,
      workspaceName: workspace.name,
      createdAt: now.toIso8601String(),
      expiresAt: expiresAt,
      maxUses: maxUses,
    );

    // "Write" to cloud
    await LinkedWorkspaceService.prefsSetStringMap('linked_invites', token, invite.toMap());

    // Update workspace with active invite
    final updatedWorkspace = workspace.copyWith(
      activeInviteToken: token,
      inviteExpiresAt: expiresAt,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeWorkspace(updatedWorkspace);

    return invite;
  }

  /// Revokes the current active invite.
  Future<void> revokeInvite() async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null || workspace.activeInviteToken == null) return;

    // "Delete" from cloud
    await LinkedWorkspaceService.prefsDeleteString('linked_invites', workspace.activeInviteToken!);

    final updatedWorkspace = workspace.copyWith(
      activeInviteToken: null,
      inviteExpiresAt: null,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeWorkspace(updatedWorkspace);
  }

  /// Joins a workspace using an invite token.
  Future<LinkedWorkspace> joinWorkspace(String inviteToken) async {
    // Read invite from cloud (SharedPreferences mock)
    final inviteMap =
        await LinkedWorkspaceService.prefsGetMap('linked_invites', inviteToken);
    if (inviteMap == null) {
      throw StateError('Invalid or expired invite');
    }
    final invite = LinkedInvite.fromMap(inviteMap);
    if (!invite.isValid) {
      throw StateError('Invalid or expired invite');
    }

    final prefs = await SharedPreferences.getInstance();
    final workspaceJson = prefs.getString('linked_workspace_cache');
    if (workspaceJson == null || workspaceJson.isEmpty) {
      throw StateError('Workspace not found');
    }
    final workspace = LinkedWorkspace.fromMap(
        jsonDecode(workspaceJson) as Map<String, dynamic>);

    // Check if already linked
    if (workspace.devices.any((d) => d.deviceId == deviceId)) {
      // Already linked - just link locally
      await _linkLocalWorkspace(
        WorkspaceService.instance.activeWorkspaceId,
        workspace.workspaceId,
      );
      return workspace;
    }

    final newDevice = await _buildCurrentDeviceInfo(role: DeviceRole.viewer);
    final updatedDevices = [...workspace.devices, newDevice];

    final updatedWorkspace = workspace.copyWith(
      devices: updatedDevices,
      updatedAt: DateTime.now().toIso8601String(),
    );

    // "Write" updated workspace to cloud
    await _writeWorkspace(updatedWorkspace);

    // Update invite used count
    final usedInvite = LinkedInvite(
      token: invite.token,
      workspaceId: invite.workspaceId,
      workspaceName: invite.workspaceName,
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
      maxUses: invite.maxUses,
      usedCount: invite.usedCount + 1,
    );
    await LinkedWorkspaceService.prefsSetStringMap('linked_invites', usedInvite.token, usedInvite.toMap());

    // Link local workspace
    await _linkLocalWorkspace(
      WorkspaceService.instance.activeWorkspaceId,
      workspace.workspaceId,
    );

    await _markDataForSync();

    return updatedWorkspace;
  }

  /// Removes current device from the linked workspace.
  Future<void> leaveWorkspace() async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) return;

    final prefs = await SharedPreferences.getInstance();

    // If admin and only device, delete workspace
    if (workspace.adminDeviceId == deviceId && workspace.devices.length == 1) {
      await _deleteWorkspace(workspace.workspaceId);
    } else {
      // Remove device from roster
      final updatedDevices =
          workspace.devices.where((d) => d.deviceId != deviceId).toList();
      final updatedWorkspace = workspace.copyWith(
        devices: updatedDevices,
        updatedAt: DateTime.now().toIso8601String(),
      );
      await _writeWorkspace(updatedWorkspace);
    }

    // Unlink locally
    await prefs.remove('linked_workspace_id');
    await prefs.remove('linked_workspace_cache');

    // Restore guest backup if exists
    await _restoreGuestBackup();

    _cachedIsLinked = false;
    _cachedIsAdmin = false;
    _cachedWorkspace = null;
  }

  /// Removes another device from the workspace (admin only).
  Future<void> removeDevice(String targetDeviceId) async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) throw StateError('Not linked to a workspace');
    if (!(await isAdmin())) throw StateError('Only admin can remove devices');
    if (targetDeviceId == workspace.adminDeviceId) {
      throw StateError('Cannot remove admin device');
    }

    final updatedDevices =
        workspace.devices.where((d) => d.deviceId != targetDeviceId).toList();
    final updatedWorkspace = workspace.copyWith(
      devices: updatedDevices,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeWorkspace(updatedWorkspace);
    await _markDataForSync();
  }

  /// Updates a device's role (admin only).
  Future<void> updateDeviceRole(String targetDeviceId, DeviceRole newRole) async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) throw StateError('Not linked to a workspace');
    if (!(await isAdmin())) throw StateError('Only admin can change roles');
    if (targetDeviceId == workspace.adminDeviceId) {
      throw StateError('Cannot change admin role');
    }

    final updatedDevices = workspace.devices.map((d) {
      if (d.deviceId == targetDeviceId) {
        return d.copyWith(role: newRole);
      }
      return d;
    }).toList();

    final updatedWorkspace = workspace.copyWith(
      devices: updatedDevices,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeWorkspace(updatedWorkspace);
    await _markDataForSync();
  }

  /// Revokes a device's access (sets status to revoked, admin only).
  Future<void> revokeDevice(String targetDeviceId) async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) throw StateError('Not linked to a workspace');
    if (!(await isAdmin())) throw StateError('Only admin can revoke access');
    if (targetDeviceId == workspace.adminDeviceId) {
      throw StateError('Cannot revoke admin');
    }

    final updatedDevices = workspace.devices.map((d) {
      if (d.deviceId == targetDeviceId) {
        return d.copyWith(status: DeviceStatus.revoked);
      }
      return d;
    }).toList();

    final updatedWorkspace = workspace.copyWith(
      devices: updatedDevices,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeWorkspace(updatedWorkspace);
    await _markDataForSync();
  }

  /// Updates the current device's last seen timestamp.
  Future<void> updateLastSeen() async {
    final workspace = await getCurrentWorkspace();
    if (workspace == null) return;

    final updatedDevices = workspace.devices.map((d) {
      if (d.deviceId == deviceId) {
        return d.copyWith(lastSeenAt: DateTime.now().toIso8601String());
      }
      return d;
    }).toList();

    final updatedWorkspace = workspace.copyWith(
      devices: updatedDevices,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _writeWorkspace(updatedWorkspace);
  }

  /// Starts periodic sync for the linked workspace.
  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) => _syncWorkspace());
  }

  /// Stops periodic sync.
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Forces an immediate sync.
  Future<void> syncNow() => _syncWorkspace();

  /// Gets the deep link URL for an invite.
  String getInviteDeepLink(String token) =>
      'balancedesk://join?token=$token';

  // Private methods ---------------------------------------------------------

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = _generateDeviceId();
      await prefs.setString(_deviceIdKey, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  String _generateDeviceId() {
    final bytes = List<int>.generate(16, (_) => math.Random().nextInt(256));
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  String _generateWorkspaceId() {
    final bytes = List<int>.generate(16, (_) => math.Random().nextInt(256));
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 24);
  }

  String _generateInviteToken() {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final random = math.Random.secure();
    return List<String>.generate(12, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  Future<LinkedDevice> _buildCurrentDeviceInfo({DeviceRole role = DeviceRole.viewer}) async {
    final deviceInfo = await _getDeviceInfo();
    final packageInfo = await PackageInfo.fromPlatform();
    return LinkedDevice(
      deviceId: deviceId,
      name: deviceInfo['name'] ?? 'Unknown Device',
      role: role,
      status: DeviceStatus.active,
      platform: deviceInfo['platform'] ?? (PlatformHelper.isAndroid ? 'Android' : 'iOS'),
      appVersion: packageInfo.version,
      lastSeenAt: DateTime.now().toIso8601String(),
    );
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (PlatformHelper.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return {
        'name': '${info.manufacturer} ${info.model}',
        'platform': 'Android',
      };
    } else if (PlatformHelper.isIOS) {
      final info = await deviceInfo.iosInfo;
      return {
        'name': '${info.name} (${info.model})',
        'platform': 'iOS',
      };
    }
    return {'name': PlatformHelper.platformLabel, 'platform': PlatformHelper.platformLabel};
  }

  Future<void> _ensureWorkspaceLinkConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final linkedWorkspaceId = prefs.getString('linked_workspace_id');
    if (linkedWorkspaceId != null) {
      // Verify workspace still exists and device is still authorized
      final workspace = await getCurrentWorkspace();
      if (workspace == null ||
          !workspace.devices.any((d) => d.deviceId == deviceId && d.status == DeviceStatus.active)) {
        // Workspace deleted or device revoked - restore guest backup
        await _restoreGuestBackup();
        await prefs.remove('linked_workspace_id');
        await prefs.remove('linked_workspace_cache');
        _cachedIsLinked = false;
        _cachedIsAdmin = false;
        _cachedWorkspace = null;
      } else {
        _cachedIsLinked = true;
        _cachedIsAdmin = workspace.adminDeviceId == deviceId;
        _cachedWorkspace = workspace;
      }
    }
  }

  Future<void> _linkLocalWorkspace(String localWorkspaceId, String cloudWorkspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('linked_workspace_id', cloudWorkspaceId);
    await prefs.setString('linked_local_workspace_id', localWorkspaceId);

    // Create guest backup before switching
    await AppDatabase.instance.createGuestBackup();

    // Switch to the cloud workspace's local database
    await WorkspaceService.instance.addWorkspaceWithId(cloudWorkspaceId, 'Linked Workspace');
    await WorkspaceService.instance.setActiveWorkspace(cloudWorkspaceId);
    await WorkspaceProvider.instance.switchWorkspace(cloudWorkspaceId);
  }

  Future<void> _restoreGuestBackup() async {
    if (await AppDatabase.instance.hasGuestBackup()) {
      await AppDatabase.instance.restoreGuestBackup();
      // Switch back to the local workspace
      final prefs = await SharedPreferences.getInstance();
      final localId = prefs.getString('linked_local_workspace_id');
      if (localId != null) {
        await WorkspaceService.instance.setActiveWorkspace(localId);
        await WorkspaceProvider.instance.switchWorkspace(localId);
      }
    }
  }

  /// Mock SharedPreferences "cloud" operations helper.
  static Future<void> prefsSetStringMap(String collection, String key, Map<String, dynamic> map) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('$collection:$key', jsonEncode(map));
  }

  static Future<Map<String, dynamic>?> prefsGetMap(String collection, String key) async {
    final sp = await SharedPreferences.getInstance();
    final json = sp.getString('$collection:$key');
    if (json == null) return null;
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<void> prefsDeleteString(String collection, String key) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('$collection:$key');
  }

  Future<void> _writeWorkspace(LinkedWorkspace workspace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('linked_workspace_cache', jsonEncode(workspace.toMap()));
  }

  Future<void> _deleteWorkspace(String workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('linked_workspace_id');
    await prefs.remove('linked_workspace_cache');
    _cachedIsLinked = false;
    _cachedIsAdmin = false;
    _cachedWorkspace = null;
  }

  Future<void> _syncWorkspace() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await updateLastSeen();
    } finally {
      _isSyncing = false;
    }
  }

  /// Marks data as dirty and triggers an immediate sync.
  Future<void> _markDataForSync() async {
    if (_cachedIsLinked && !_isSyncing) {
      await _syncWorkspace();
    }
  }
}