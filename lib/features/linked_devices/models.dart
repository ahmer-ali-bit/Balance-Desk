import 'dart:convert';

enum LinkRole { none, host, guest }

extension LinkRoleX on LinkRole {
  String get wireValue {
    switch (this) {
      case LinkRole.host:
        return 'host';
      case LinkRole.guest:
        return 'guest';
      case LinkRole.none:
        return 'none';
    }
  }

  static LinkRole parse(String? value) {
    switch (value) {
      case 'host':
        return LinkRole.host;
      case 'guest':
        return LinkRole.guest;
      default:
        return LinkRole.none;
    }
  }
}

enum DevicePermission { read, write }

extension DevicePermissionX on DevicePermission {
  String get wireValue => this == DevicePermission.write ? 'write' : 'read';
  bool get canEdit => this == DevicePermission.write;
  String get badge => this == DevicePermission.write ? 'EDITABLE' : 'READ ONLY';

  static DevicePermission parse(String? value) {
    return value == 'write' ? DevicePermission.write : DevicePermission.read;
  }
}

enum DeviceStatus { active, removed }

extension DeviceStatusX on DeviceStatus {
  String get wireValue => this == DeviceStatus.removed ? 'removed' : 'active';

  static DeviceStatus parse(String? value) {
    return value == 'removed' ? DeviceStatus.removed : DeviceStatus.active;
  }
}

class LinkedDevice {
  const LinkedDevice({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.permission,
    required this.status,
    required this.role,
    required this.joinedAt,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String name;
  final String platform;
  final DevicePermission permission;
  final DeviceStatus status;
  final LinkRole role;
  final String joinedAt;
  final String lastSeenAt;

  bool get isActive => status == DeviceStatus.active;

  bool get isOnline {
    final DateTime? last = DateTime.tryParse(lastSeenAt);
    if (last == null) return false;
    return DateTime.now().toUtc().difference(last.toUtc()) < const Duration(hours: 26);
  }

  LinkedDevice copyWith({
    String? name,
    DevicePermission? permission,
    DeviceStatus? status,
    String? lastSeenAt,
  }) {
    return LinkedDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      platform: platform,
      permission: permission ?? this.permission,
      status: status ?? this.status,
      role: role,
      joinedAt: joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'deviceId': deviceId,
      'name': name,
      'platform': platform,
      'permission': permission.wireValue,
      'status': status.wireValue,
      'role': role.wireValue,
      'joinedAt': joinedAt,
      'lastSeenAt': lastSeenAt,
    };
  }

  static LinkedDevice? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final String? id = raw['deviceId'] as String?;
    if (id == null || id.isEmpty) return null;
    return LinkedDevice(
      deviceId: id,
      name: (raw['name'] as String?) ?? 'Device',
      platform: (raw['platform'] as String?) ?? '',
      permission: DevicePermissionX.parse(raw['permission'] as String?),
      status: DeviceStatusX.parse(raw['status'] as String?),
      role: LinkRoleX.parse(raw['role'] as String?),
      joinedAt: (raw['joinedAt'] as String?) ?? '',
      lastSeenAt: (raw['lastSeenAt'] as String?) ?? '',
    );
  }
}

class LinkedInvite {
  const LinkedInvite({
    required this.token,
    required this.workspaceId,
    required this.workspaceName,
    required this.hostDeviceName,
    required this.expiresAt,
    required this.consumed,
  });

  final String token;
  final String workspaceId;
  final String workspaceName;
  final String hostDeviceName;
  final String expiresAt;
  final bool consumed;

  static const Duration validity = Duration(minutes: 10);

  DateTime? get expiryTime => DateTime.tryParse(expiresAt);

  bool get isExpired {
    final DateTime? expiry = expiryTime;
    if (expiry == null) return true;
    return DateTime.now().toUtc().isAfter(expiry.toUtc());
  }

  bool get isUsable => !consumed && !isExpired;

  Duration get timeLeft {
    final DateTime? expiry = expiryTime;
    if (expiry == null) return Duration.zero;
    final Duration diff = expiry.toUtc().difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get deepLink => 'balancedesk://join?token=$token';

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'token': token,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'hostDeviceName': hostDeviceName,
      'expiresAt': expiresAt,
      'consumed': consumed,
    };
  }

  static LinkedInvite? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final String? token = raw['token'] as String?;
    if (token == null || token.isEmpty) return null;
    return LinkedInvite(
      token: token,
      workspaceId: (raw['workspaceId'] as String?) ?? '',
      workspaceName: (raw['workspaceName'] as String?) ?? '',
      hostDeviceName: (raw['hostDeviceName'] as String?) ?? '',
      expiresAt: (raw['expiresAt'] as String?) ?? '',
      consumed: raw['consumed'] == true,
    );
  }
}

class LinkedWorkspaceDoc {
  const LinkedWorkspaceDoc({
    required this.workspaceId,
    required this.workspaceName,
    required this.hostDeviceId,
    required this.hostDeviceName,
    required this.createdAt,
    required this.dataChangedAt,
    required this.devices,
    required this.invite,
  });

  final String workspaceId;
  final String workspaceName;
  final String hostDeviceId;
  final String hostDeviceName;
  final String createdAt;
  final String dataChangedAt;
  final Map<String, LinkedDevice> devices;
  final LinkedInvite? invite;

  LinkedDevice? deviceById(String id) => devices[id];

  List<LinkedDevice> get activeGuests {
    return devices.values
        .where(
          (LinkedDevice d) =>
              d.isActive &&
              d.deviceId != hostDeviceId &&
              d.role != LinkRole.host,
        )
        .toList()
      ..sort((LinkedDevice a, LinkedDevice b) => a.name.compareTo(b.name));
  }

  static LinkedWorkspaceDoc? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final String? id = raw['workspaceId'] as String?;
    if (id == null || id.isEmpty) return null;

    final Map<String, LinkedDevice> devices = <String, LinkedDevice>{};
    final Object? devicesRaw = raw['devices'];
    if (devicesRaw is Map) {
      devicesRaw.forEach((Object? key, Object? value) {
        final LinkedDevice? device = LinkedDevice.fromMap(value);
        if (device != null) {
          devices[device.deviceId] = device;
        }
      });
    }

    return LinkedWorkspaceDoc(
      workspaceId: id,
      workspaceName: (raw['workspaceName'] as String?) ?? '',
      hostDeviceId: (raw['hostDeviceId'] as String?) ?? '',
      hostDeviceName: (raw['hostDeviceName'] as String?) ?? '',
      createdAt: (raw['createdAt'] as String?) ?? '',
      dataChangedAt: (raw['dataChangedAt'] as String?) ?? '',
      devices: devices,
      invite: LinkedInvite.fromMap(raw['invite']),
    );
  }

  String toJson() {
    return json.encode(<String, Object?>{
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'hostDeviceId': hostDeviceId,
      'hostDeviceName': hostDeviceName,
      'createdAt': createdAt,
      'dataChangedAt': dataChangedAt,
      'devices': <String, Object?>{
        for (final MapEntry<String, LinkedDevice> e in devices.entries)
          e.key: e.value.toMap(),
      },
      'invite': invite?.toMap(),
    });
  }
}

enum SyncStage { idle, syncing, synced, offline, blocked, error }

class SyncStatus {
  const SyncStatus({
    this.stage = SyncStage.idle,
    this.message,
    this.lastSyncedAt,
    this.pendingUploads = 0,
  });

  final SyncStage stage;
  final String? message;
  final DateTime? lastSyncedAt;
  final int pendingUploads;

  bool get isBusy => stage == SyncStage.syncing;
  bool get hasProblem =>
      stage == SyncStage.offline ||
      stage == SyncStage.blocked ||
      stage == SyncStage.error;

  SyncStatus copyWith({
    SyncStage? stage,
    String? message,
    DateTime? lastSyncedAt,
    int? pendingUploads,
    bool clearMessage = false,
  }) {
    return SyncStatus(
      stage: stage ?? this.stage,
      message: clearMessage ? null : (message ?? this.message),
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingUploads: pendingUploads ?? this.pendingUploads,
    );
  }
}