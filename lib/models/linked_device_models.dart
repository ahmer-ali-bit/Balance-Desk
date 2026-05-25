import 'package:flutter/foundation.dart';

enum SessionPermission { read, write }

enum WorkspaceMode { local, linked }

class LinkedSession {
  final String sessionId;
  final String adminDeviceId;
  final String? adminDeviceName;
  final String linkedDeviceId;
  final String? linkedDeviceName;
  final SessionPermission permission;
  final String? editableCode;
  final DateTime? editableCodeExpiresAt;
  final DateTime? joinedAt;
  final String? lastSnapshotAt;
  final String? lastGuestSnapshotAt;
  final String? lastAdminAppliedGuestSnapshotAt;

  const LinkedSession({
    required this.sessionId,
    required this.adminDeviceId,
    this.adminDeviceName,
    required this.linkedDeviceId,
    this.linkedDeviceName,
    required this.permission,
    this.editableCode,
    this.editableCodeExpiresAt,
    this.joinedAt,
    this.lastSnapshotAt,
    this.lastGuestSnapshotAt,
    this.lastAdminAppliedGuestSnapshotAt,
  });

  bool get hasActiveEditCode {
    if (editableCode == null || editableCode!.isEmpty) return false;
    final expiry = editableCodeExpiresAt;
    return expiry == null || DateTime.now().isBefore(expiry);
  }

  factory LinkedSession.fromMap(Map<String, dynamic> map) {
    try {
      final permStr = map['permission'] as String? ?? 'read';
      final rawEditCode = map['editableCode']?.toString();
      final editCode = rawEditCode == null || rawEditCode == 'null'
          ? null
          : rawEditCode;
      return LinkedSession(
        sessionId: map['sessionId']?.toString() ?? map['id']?.toString() ?? '',
        adminDeviceId: map['adminDeviceId']?.toString() ?? '',
        adminDeviceName: map['adminDeviceName']?.toString(),
        linkedDeviceId: map['linkedDeviceId']?.toString() ?? '',
        linkedDeviceName: map['linkedDeviceName']?.toString(),
        permission: permStr.toLowerCase() == 'write'
            ? SessionPermission.write
            : SessionPermission.read,
        editableCode: editCode,
        editableCodeExpiresAt: DateTime.tryParse(
          map['editableCodeExpiresAt']?.toString() ?? '',
        ),
        joinedAt: DateTime.tryParse(map['joinedAt']?.toString() ?? ''),
        lastSnapshotAt: map['lastSnapshotAt']?.toString(),
        lastGuestSnapshotAt: map['lastGuestSnapshotAt']?.toString(),
        lastAdminAppliedGuestSnapshotAt: map['lastAdminAppliedGuestSnapshotAt']
            ?.toString(),
      );
    } catch (e) {
      debugPrint('LinkedSession.fromMap error: $e');
      return const LinkedSession(
        sessionId: '',
        adminDeviceId: '',
        linkedDeviceId: '',
        permission: SessionPermission.read,
      );
    }
  }

  Map<String, dynamic> toMap() => {
    'sessionId': sessionId,
    'adminDeviceId': adminDeviceId,
    'adminDeviceName': adminDeviceName,
    'linkedDeviceId': linkedDeviceId,
    'linkedDeviceName': linkedDeviceName,
    'permission': permission == SessionPermission.write ? 'write' : 'read',
    'editableCode': editableCode,
    'editableCodeExpiresAt': editableCodeExpiresAt?.toIso8601String(),
    'joinedAt': joinedAt?.toIso8601String(),
    'lastSnapshotAt': lastSnapshotAt,
    'lastGuestSnapshotAt': lastGuestSnapshotAt,
    'lastAdminAppliedGuestSnapshotAt': lastAdminAppliedGuestSnapshotAt,
  };

  LinkedSession copyWith({
    String? sessionId,
    String? adminDeviceId,
    String? adminDeviceName,
    String? linkedDeviceId,
    String? linkedDeviceName,
    SessionPermission? permission,
    String? editableCode,
    DateTime? editableCodeExpiresAt,
    DateTime? joinedAt,
    String? lastSnapshotAt,
    String? lastGuestSnapshotAt,
    String? lastAdminAppliedGuestSnapshotAt,
    bool clearEditableCode = false,
  }) {
    return LinkedSession(
      sessionId: sessionId ?? this.sessionId,
      adminDeviceId: adminDeviceId ?? this.adminDeviceId,
      adminDeviceName: adminDeviceName ?? this.adminDeviceName,
      linkedDeviceId: linkedDeviceId ?? this.linkedDeviceId,
      linkedDeviceName: linkedDeviceName ?? this.linkedDeviceName,
      permission: permission ?? this.permission,
      editableCode: clearEditableCode
          ? null
          : (editableCode ?? this.editableCode),
      editableCodeExpiresAt: clearEditableCode
          ? null
          : (editableCodeExpiresAt ?? this.editableCodeExpiresAt),
      joinedAt: joinedAt ?? this.joinedAt,
      lastSnapshotAt: lastSnapshotAt ?? this.lastSnapshotAt,
      lastGuestSnapshotAt: lastGuestSnapshotAt ?? this.lastGuestSnapshotAt,
      lastAdminAppliedGuestSnapshotAt:
          lastAdminAppliedGuestSnapshotAt ??
          this.lastAdminAppliedGuestSnapshotAt,
    );
  }
}
