import 'dart:convert';

enum DeviceRole { admin, editor, viewer }

enum DeviceStatus { active, inactive, revoked }

class LinkedDevice {
  const LinkedDevice({
    required this.deviceId,
    required this.name,
    required this.role,
    required this.status,
    required this.platform,
    required this.appVersion,
    required this.lastSeenAt,
    this.firstLinkedAt,
  });

  final String deviceId;
  final String name;
  final DeviceRole role;
  final DeviceStatus status;
  final String platform;
  final String appVersion;
  final String lastSeenAt;
  final String? firstLinkedAt;

  bool get isAdmin => role == DeviceRole.admin;
  bool get isEditable => role == DeviceRole.editor || role == DeviceRole.admin;
  bool get canRead => status == DeviceStatus.active;

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'name': name,
        'role': role.name,
        'status': status.name,
        'platform': platform,
        'appVersion': appVersion,
        'lastSeenAt': lastSeenAt,
        'firstLinkedAt': firstLinkedAt,
      };

  factory LinkedDevice.fromMap(Map<String, dynamic> map) {
    return LinkedDevice(
      deviceId: map['deviceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: DeviceRole.values.byName(map['role'] as String? ?? 'viewer'),
      status: DeviceStatus.values.byName(map['status'] as String? ?? 'active'),
      platform: map['platform'] as String? ?? '',
      appVersion: map['appVersion'] as String? ?? '',
      lastSeenAt: map['lastSeenAt'] as String? ?? '',
      firstLinkedAt: map['firstLinkedAt'] as String?,
    );
  }

  LinkedDevice copyWith({
    String? deviceId,
    String? name,
    DeviceRole? role,
    DeviceStatus? status,
    String? platform,
    String? appVersion,
    String? lastSeenAt,
    String? firstLinkedAt,
  }) {
    return LinkedDevice(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      role: role ?? this.role,
      status: status ?? this.status,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      firstLinkedAt: firstLinkedAt ?? this.firstLinkedAt,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory LinkedDevice.fromJson(String source) =>
      LinkedDevice.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class LinkedWorkspace {
  const LinkedWorkspace({
    required this.workspaceId,
    required this.name,
    required this.adminDeviceId,
    required this.devices,
    required this.createdAt,
    required this.updatedAt,
    this.activeInviteToken,
    this.inviteExpiresAt,
  });

  final String workspaceId;
  final String name;
  final String adminDeviceId;
  final List<LinkedDevice> devices;
  final String createdAt;
  final String updatedAt;
  final String? activeInviteToken;
  final String? inviteExpiresAt;

  LinkedDevice? get adminDevice {
    try {
      return devices.firstWhere((d) => d.deviceId == adminDeviceId);
    } catch (_) {
      return null;
    }
  }

  List<LinkedDevice> get activeDevices =>
      devices.where((d) => d.status == DeviceStatus.active).toList();

  List<LinkedDevice> get editableDevices =>
      devices
          .where((d) => d.status == DeviceStatus.active && d.isEditable)
          .toList();

  Map<String, dynamic> toMap() => {
        'workspaceId': workspaceId,
        'name': name,
        'adminDeviceId': adminDeviceId,
        'devices': devices.map((d) => d.toMap()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'activeInviteToken': activeInviteToken,
        'inviteExpiresAt': inviteExpiresAt,
      };

  factory LinkedWorkspace.fromMap(Map<String, dynamic> map) {
    return LinkedWorkspace(
      workspaceId: map['workspaceId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      adminDeviceId: map['adminDeviceId'] as String? ?? '',
      devices: (map['devices'] as List<dynamic>? ?? [])
          .map((d) => LinkedDevice.fromMap(d as Map<String, dynamic>))
          .toList(),
      createdAt: map['createdAt'] as String? ?? '',
      updatedAt: map['updatedAt'] as String? ?? '',
      activeInviteToken: map['activeInviteToken'] as String?,
      inviteExpiresAt: map['inviteExpiresAt'] as String?,
    );
  }

  LinkedWorkspace copyWith({
    String? workspaceId,
    String? name,
    String? adminDeviceId,
    List<LinkedDevice>? devices,
    String? createdAt,
    String? updatedAt,
    String? activeInviteToken,
    String? inviteExpiresAt,
  }) {
    return LinkedWorkspace(
      workspaceId: workspaceId ?? this.workspaceId,
      name: name ?? this.name,
      adminDeviceId: adminDeviceId ?? this.adminDeviceId,
      devices: devices ?? this.devices,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activeInviteToken: activeInviteToken ?? this.activeInviteToken,
      inviteExpiresAt: inviteExpiresAt ?? this.inviteExpiresAt,
    );
  }
}

class LinkedInvite {
  const LinkedInvite({
    required this.token,
    required this.workspaceId,
    required this.workspaceName,
    required this.createdAt,
    required this.expiresAt,
    this.maxUses = 1,
    this.usedCount = 0,
  });

  final String token;
  final String workspaceId;
  final String workspaceName;
  final String createdAt;
  final String expiresAt;
  final int maxUses;
  final int usedCount;

  bool get isValid =>
      DateTime.now().isBefore(DateTime.parse(expiresAt)) &&
      usedCount < maxUses;

  Map<String, dynamic> toMap() => {
        'token': token,
        'workspaceId': workspaceId,
        'workspaceName': workspaceName,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'maxUses': maxUses,
        'usedCount': usedCount,
      };

  factory LinkedInvite.fromMap(Map<String, dynamic> map) {
    return LinkedInvite(
      token: map['token'] as String? ?? '',
      workspaceId: map['workspaceId'] as String? ?? '',
      workspaceName: map['workspaceName'] as String? ?? '',
      createdAt: map['createdAt'] as String? ?? '',
      expiresAt: map['expiresAt'] as String? ?? '',
      maxUses: map['maxUses'] as int? ?? 1,
      usedCount: map['usedCount'] as int? ?? 0,
    );
  }
}