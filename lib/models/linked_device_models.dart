import 'package:flutter/foundation.dart';

enum SessionPermission { read, write }

enum WorkspaceMode { local, linked }

class LinkedSession {
  final String sessionId;
  final String adminDeviceId;
  final String linkedDeviceId;
  final SessionPermission permission;
  final String? editableCode;

  const LinkedSession({
    required this.sessionId,
    required this.adminDeviceId,
    required this.linkedDeviceId,
    required this.permission,
    this.editableCode,
  });

  factory LinkedSession.fromMap(Map<String, dynamic> map) {
    try {
      final permStr = map['permission'] as String? ?? 'read';
      return LinkedSession(
        sessionId: map['sessionId']?.toString() ?? map['id']?.toString() ?? '',
        adminDeviceId: map['adminDeviceId']?.toString() ?? '',
        linkedDeviceId: map['linkedDeviceId']?.toString() ?? '',
        permission: permStr.toLowerCase() == 'write'
            ? SessionPermission.write
            : SessionPermission.read,
        editableCode: map['editableCode']?.toString(),
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
        'linkedDeviceId': linkedDeviceId,
        'permission': permission == SessionPermission.write ? 'write' : 'read',
        'editableCode': editableCode,
      };

  LinkedSession copyWith({
    String? sessionId,
    String? adminDeviceId,
    String? linkedDeviceId,
    SessionPermission? permission,
    String? editableCode,
    bool clearEditableCode = false,
  }) {
    return LinkedSession(
      sessionId: sessionId ?? this.sessionId,
      adminDeviceId: adminDeviceId ?? this.adminDeviceId,
      linkedDeviceId: linkedDeviceId ?? this.linkedDeviceId,
      permission: permission ?? this.permission,
      editableCode:
          clearEditableCode ? null : (editableCode ?? this.editableCode),
    );
  }
}
