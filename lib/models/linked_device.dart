import 'package:cloud_firestore/cloud_firestore.dart';

/// Role a linked device holds inside a workspace.
enum DeviceRole {
  owner,
  editor,
  viewer;

  /// Wire format stored in Firestore.
  String get wire => name;

  bool get canEditLedger => this != DeviceRole.viewer;

  String get label {
    switch (this) {
      case DeviceRole.owner:
        return 'Owner';
      case DeviceRole.editor:
        return 'Can edit';
      case DeviceRole.viewer:
        return 'View only';
    }
  }

  static DeviceRole fromWire(Object? value) {
    switch (value) {
      case 'owner':
        return DeviceRole.owner;
      case 'editor':
        return DeviceRole.editor;
      default:
        return DeviceRole.viewer;
    }
  }
}

/// A device that is linked to the active workspace.
class LinkedDevice {
  const LinkedDevice({
    required this.deviceId,
    required this.uid,
    required this.displayName,
    required this.platform,
    required this.role,
    required this.joinedAt,
    required this.lastSeenAt,
    this.inviteToken = '',
    this.isCurrentDevice = false,
  });

  final String deviceId;
  final String uid;
  final String displayName;
  final String platform;
  final DeviceRole role;
  final DateTime joinedAt;
  final DateTime lastSeenAt;
  final String inviteToken;

  /// True when this document describes the device the app is running on.
  final bool isCurrentDevice;

  LinkedDevice copyWith({
    DeviceRole? role,
    String? displayName,
    DateTime? lastSeenAt,
    bool? isCurrentDevice,
  }) {
    return LinkedDevice(
      deviceId: deviceId,
      uid: uid,
      displayName: displayName ?? this.displayName,
      platform: platform,
      role: role ?? this.role,
      joinedAt: joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      inviteToken: inviteToken,
      isCurrentDevice: isCurrentDevice ?? this.isCurrentDevice,
    );
  }

  Map<String, Object?> toDocument() => <String, Object?>{
        'deviceId': deviceId,
        'uid': uid,
        'displayName': displayName,
        'platform': platform,
        'role': role.wire,
        'inviteToken': inviteToken,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      };

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory LinkedDevice.fromDocument(
    Map<String, Object?> data, {
    required String currentDeviceId,
  }) {
    final String deviceId = (data['deviceId'] ?? '') as String;
    return LinkedDevice(
      deviceId: deviceId,
      uid: (data['uid'] ?? '') as String,
      displayName: (data['displayName'] ?? 'Unknown device') as String,
      platform: (data['platform'] ?? 'unknown') as String,
      role: DeviceRole.fromWire(data['role']),
      joinedAt: _readDate(data['joinedAt']),
      lastSeenAt: _readDate(data['lastSeenAt']),
      inviteToken: (data['inviteToken'] ?? '') as String,
      isCurrentDevice: deviceId == currentDeviceId,
    );
  }
}
