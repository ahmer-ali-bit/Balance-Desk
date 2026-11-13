import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../database/app_database.dart';
import '../models/workspace.dart';
import 'linked_device_api.dart';
import 'linked_device_credentials.dart';
import 'workspace_service.dart';

class LinkedInvite {
  const LinkedInvite({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
}

/// Coordinates device capability registration and workspace pairing. The
/// provider/UI layer never handles database credentials or raw SQL.
class LinkedDevicesService {
  LinkedDevicesService({
    LinkedDeviceApi? api,
    LinkedDeviceCredentials? credentials,
    LinkedWorkspaceConfigStore? configs,
  }) : _api = api ?? LinkedDeviceApi(),
       _credentials = credentials ?? LinkedDeviceCredentials(),
       _configs = configs ?? LinkedWorkspaceConfigStore();

  static final LinkedDevicesService instance = LinkedDevicesService();

  final LinkedDeviceApi _api;
  final LinkedDeviceCredentials _credentials;
  final LinkedWorkspaceConfigStore _configs;

  Future<LinkedWorkspaceConfig?> configFor(String localWorkspaceId) =>
      _configs.read(localWorkspaceId);

  Future<LinkedWorkspaceConfig?> activeConfig() async {
    return _configs.read(WorkspaceService.instance.activeWorkspaceId);
  }

  Future<LinkedWorkspaceConfig> shareWorkspace({
    required String localWorkspaceId,
    required String workspaceName,
    required String deviceName,
    required String platform,
  }) async {
    final existing = await _configs.read(localWorkspaceId);
    if (existing != null) {
      throw const LinkedDeviceException('This workspace is already linked.');
    }
    final deviceId = await _credentials.getOrCreateDeviceId(localWorkspaceId);
    // This is a newly created cloud workspace, so old revisions/cursors from a
    // previous link must not be sent as optimistic bases to the new workspace.
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('sync_shadow');
      await txn.delete('sync_conflicts');
      await txn.delete('sync_state');
    });
    final deviceToken = LinkedDeviceCredentials.newSecret();
    // Persist the capability before registering it remotely so a transient
    // secure-storage failure cannot strand an already-created owner device.
    await _credentials.writeToken(localWorkspaceId, deviceToken);
    final response = await _api.rpc('bd_create_workspace', <String, Object?>{
      'p_name': workspaceName.trim(),
      'p_device_id': deviceId,
      'p_device_token': deviceToken,
      'p_device_name': deviceName,
      'p_platform': platform,
    });
    final body = _asMap(response);
    final cloudId = body['workspace_id']?.toString();
    if (cloudId == null || cloudId.isEmpty) {
      throw const LinkedDeviceException('The cloud did not create the workspace.');
    }
    final config = LinkedWorkspaceConfig(
      localWorkspaceId: localWorkspaceId,
      cloudWorkspaceId: cloudId,
      deviceId: deviceId,
      role: 'owner',
      permission: 'edit',
      cursor: 0,
    );
    await _configs.write(config);
    return config;
  }

  Future<LinkedInvite> createInvite(LinkedWorkspaceConfig config) async {
    final token = await _requireToken(config.localWorkspaceId);
    final inviteCode = LinkedDeviceCredentials.newSecret();
    final response = await _api.rpc('bd_issue_invite', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
      'p_invite_token': inviteCode,
    });
    final result = _asMap(response);
    final expiry = DateTime.tryParse(result['expires_at']?.toString() ?? '');
    if (expiry == null) {
      throw const LinkedDeviceException('The invite expiry was not returned.');
    }
    return LinkedInvite(token: inviteCode, expiresAt: expiry.toLocal());
  }

  Future<Workspace> joinWorkspace({
    required String inviteToken,
    required String deviceName,
    required String platform,
  }) async {
    final normalizedToken = inviteToken.trim();
    if (normalizedToken.length < 28) {
      throw const LinkedDeviceException('Enter a valid invite code.');
    }
    // Generate identity before claim. If the RPC succeeds, the token is
    // immediately written to OS secure storage before any workspace switching.
    final deviceToken = LinkedDeviceCredentials.newSecret();
    final deviceId = _ephemeralDeviceId();
    final response = await _api.rpc('bd_claim_invite', <String, Object?>{
      'p_invite_token': normalizedToken,
      'p_device_id': deviceId,
      'p_device_token': deviceToken,
      'p_device_name': deviceName,
      'p_platform': platform,
    });
    final body = _asMap(response);
    final cloudId = body['workspace_id']?.toString();
    final name = body['workspace_name']?.toString();
    if (cloudId == null || cloudId.isEmpty || name == null || name.isEmpty) {
      throw const LinkedDeviceException('The invite did not return a workspace.');
    }
    final localId = 'linked_$cloudId';
    await _credentials.writeToken(localId, deviceToken);
    final workspace = await WorkspaceService.instance.addWorkspaceWithId(
      localId,
      name,
    );
    await _configs.write(
      LinkedWorkspaceConfig(
        localWorkspaceId: workspace.id,
        cloudWorkspaceId: cloudId,
        deviceId: deviceId,
        role: 'linked',
        permission: 'edit',
        cursor: 0,
      ),
    );
    return workspace;
  }

  Future<List<Map<String, Object?>>> listDevices(
    LinkedWorkspaceConfig config,
  ) async {
    final token = await _requireToken(config.localWorkspaceId);
    final response = await _api.rpc('bd_list_devices', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
    });
    if (response is! List) return const <Map<String, Object?>>[];
    return response
        .whereType<Map>()
        .map((Map item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  Future<void> setPermission(
    LinkedWorkspaceConfig config,
    String targetDeviceId,
    String permission,
  ) async {
    final token = await _requireToken(config.localWorkspaceId);
    await _api.rpc('bd_set_device_permission', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
      'p_target_device_id': targetDeviceId,
      'p_permission': permission,
    });
  }

  Future<void> transferOwnership(
    LinkedWorkspaceConfig config,
    String targetDeviceId,
  ) async {
    final token = await _requireToken(config.localWorkspaceId);
    await _api.rpc('bd_transfer_owner', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
      'p_target_device_id': targetDeviceId,
    });
  }

  Future<void> revokeDevice(
    LinkedWorkspaceConfig config,
    String targetDeviceId,
  ) async {
    final token = await _requireToken(config.localWorkspaceId);
    await _api.rpc('bd_revoke_device', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
      'p_target_device_id': targetDeviceId,
    });
  }

  Future<void> stopSharing(LinkedWorkspaceConfig config) async {
    final token = await _requireToken(config.localWorkspaceId);
    await _api.rpc('bd_stop_sharing', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
    });
    await _forgetLocalLink(config.localWorkspaceId);
  }

  Future<void> disconnect(LinkedWorkspaceConfig config) async {
    final token = await _requireToken(config.localWorkspaceId);
    await _api.rpc('bd_leave_workspace', <String, Object?>{
      'p_workspace_id': config.cloudWorkspaceId,
      'p_device_id': config.deviceId,
      'p_device_token': token,
    });
    // The shared local ledger is intentionally kept as a normal workspace.
    await _forgetLocalLink(config.localWorkspaceId);
  }

  Future<void> forgetRevokedLink(String localWorkspaceId) =>
      _forgetLocalLink(localWorkspaceId);

  Future<void> _forgetLocalLink(String localWorkspaceId) async {
    await _configs.delete(localWorkspaceId);
    await _credentials.deleteToken(localWorkspaceId);
  }

  Future<String> _requireToken(String localWorkspaceId) async {
    final token = await _credentials.readToken(localWorkspaceId);
    if (token == null || token.length < 40) {
      throw const LinkedDeviceException(
        'This device credential is missing. Relink this device from the owner device.',
      );
    }
    return token;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const LinkedDeviceException('Unexpected response from the cloud.');
  }

  static String _ephemeralDeviceId() => LinkedDeviceCredentials.newUuid();

  static Future<(String name, String platform)> currentDevice() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      return ('${info.manufacturer} ${info.model}'.trim(), 'android');
    }
    if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      return (info.name.trim().isEmpty ? info.model : info.name, 'ios');
    }
    if (Platform.isMacOS) {
      final info = await plugin.macOsInfo;
      return (info.computerName, 'macos');
    }
    if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      return (info.computerName, 'windows');
    }
    if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      return (info.prettyName, 'linux');
    }
    return ('Balance Desk device', 'unknown');
  }

}
