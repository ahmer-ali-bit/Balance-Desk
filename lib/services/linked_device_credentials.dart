import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LinkedWorkspaceConfig {
  const LinkedWorkspaceConfig({
    required this.localWorkspaceId,
    required this.cloudWorkspaceId,
    required this.deviceId,
    required this.role,
    required this.permission,
    required this.cursor,
  });

  final String localWorkspaceId;
  final String cloudWorkspaceId;
  final String deviceId;
  final String role;
  final String permission;
  final int cursor;

  bool get isOwner => role == 'owner';
  bool get isReadOnly => permission == 'read_only';

  LinkedWorkspaceConfig copyWith({String? permission, String? role, int? cursor}) {
    return LinkedWorkspaceConfig(
      localWorkspaceId: localWorkspaceId,
      cloudWorkspaceId: cloudWorkspaceId,
      deviceId: deviceId,
      role: role ?? this.role,
      permission: permission ?? this.permission,
      cursor: cursor ?? this.cursor,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'localWorkspaceId': localWorkspaceId,
    'cloudWorkspaceId': cloudWorkspaceId,
    'deviceId': deviceId,
    'role': role,
    'permission': permission,
    'cursor': cursor,
  };

  factory LinkedWorkspaceConfig.fromJson(Map<String, dynamic> json) {
    return LinkedWorkspaceConfig(
      localWorkspaceId: json['localWorkspaceId'] as String,
      cloudWorkspaceId: json['cloudWorkspaceId'] as String,
      deviceId: json['deviceId'] as String,
      role: json['role'] as String? ?? 'linked',
      permission: json['permission'] as String? ?? 'edit',
      cursor: (json['cursor'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Device capabilities are kept in Keychain/Keystore/OS credential storage,
/// never in SharedPreferences or the SQLite ledger.
class LinkedDeviceCredentials {
  LinkedDeviceCredentials({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _prefix = 'balance_desk.linked_device.';
  final FlutterSecureStorage _storage;

  Future<String?> readToken(String localWorkspaceId) =>
      _storage.read(key: '${_prefix}token.$localWorkspaceId');

  Future<void> writeToken(String localWorkspaceId, String token) =>
      _storage.write(key: '${_prefix}token.$localWorkspaceId', value: token);

  Future<void> deleteToken(String localWorkspaceId) =>
      _storage.delete(key: '${_prefix}token.$localWorkspaceId');

  Future<String> getOrCreateDeviceId(String localWorkspaceId) async {
    final key = '${_prefix}device_id.$localWorkspaceId';
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = newUuid();
    await _storage.write(key: key, value: created);
    return created;
  }

  static String newSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((int value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class LinkedWorkspaceConfigStore {
  static const String _prefix = 'linked_workspace_config.';

  Future<LinkedWorkspaceConfig?> read(String localWorkspaceId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('$_prefix$localWorkspaceId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return LinkedWorkspaceConfig.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(LinkedWorkspaceConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '$_prefix${config.localWorkspaceId}',
      jsonEncode(config.toJson()),
    );
  }

  Future<void> delete(String localWorkspaceId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('$_prefix$localWorkspaceId');
  }
}
