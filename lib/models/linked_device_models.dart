import 'package:cloud_firestore/cloud_firestore.dart';

enum LinkedWorkspaceRole { none, owner, viewer, editor }

extension LinkedWorkspaceRoleX on LinkedWorkspaceRole {
  bool get canEdit =>
      this == LinkedWorkspaceRole.owner || this == LinkedWorkspaceRole.editor;

  String get label {
    switch (this) {
      case LinkedWorkspaceRole.none:
        return 'Local';
      case LinkedWorkspaceRole.owner:
        return 'Owner';
      case LinkedWorkspaceRole.viewer:
        return 'Read Only';
      case LinkedWorkspaceRole.editor:
        return 'Editor';
    }
  }

  static LinkedWorkspaceRole parse(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'owner':
        return LinkedWorkspaceRole.owner;
      case 'viewer':
        return LinkedWorkspaceRole.viewer;
      case 'editor':
        return LinkedWorkspaceRole.editor;
      default:
        return LinkedWorkspaceRole.none;
    }
  }

  String get storageValue {
    switch (this) {
      case LinkedWorkspaceRole.none:
        return 'none';
      case LinkedWorkspaceRole.owner:
        return 'owner';
      case LinkedWorkspaceRole.viewer:
        return 'viewer';
      case LinkedWorkspaceRole.editor:
        return 'editor';
    }
  }
}

enum LinkedWorkspaceMembershipStatus { unlinked, active, revoked }

extension LinkedWorkspaceMembershipStatusX on LinkedWorkspaceMembershipStatus {
  bool get isActive => this == LinkedWorkspaceMembershipStatus.active;

  String get storageValue {
    switch (this) {
      case LinkedWorkspaceMembershipStatus.unlinked:
        return 'unlinked';
      case LinkedWorkspaceMembershipStatus.active:
        return 'active';
      case LinkedWorkspaceMembershipStatus.revoked:
        return 'revoked';
    }
  }

  static LinkedWorkspaceMembershipStatus parse(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'active':
        return LinkedWorkspaceMembershipStatus.active;
      case 'revoked':
        return LinkedWorkspaceMembershipStatus.revoked;
      default:
        return LinkedWorkspaceMembershipStatus.unlinked;
    }
  }
}

class LinkedDeviceMember {
  const LinkedDeviceMember({
    required this.uid,
    required this.deviceName,
    required this.platform,
    required this.role,
    required this.status,
    this.linkedAt,
    this.lastSeenAt,
  });

  final String uid;
  final String deviceName;
  final String platform;
  final LinkedWorkspaceRole role;
  final LinkedWorkspaceMembershipStatus status;
  final DateTime? linkedAt;
  final DateTime? lastSeenAt;

  bool get isActive => status == LinkedWorkspaceMembershipStatus.active;
  bool get canEdit => isActive && role.canEdit;

  factory LinkedDeviceMember.fromMap(String uid, Map<String, Object?> map) {
    return LinkedDeviceMember(
      uid: uid,
      deviceName: map['deviceName'] as String? ?? 'Unknown Device',
      platform: map['platform'] as String? ?? 'Unknown',
      role: LinkedWorkspaceRoleX.parse(map['role'] as String?),
      status: LinkedWorkspaceMembershipStatusX.parse(map['status'] as String?),
      linkedAt: _parseDate(map['linkedAt']),
      lastSeenAt: _parseDate(map['lastSeenAt']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class LinkedActionResult {
  const LinkedActionResult({required this.isSuccess, required this.message});

  final bool isSuccess;
  final String message;

  const LinkedActionResult.success(String message)
    : this(isSuccess: true, message: message);

  const LinkedActionResult.failure(String message)
    : this(isSuccess: false, message: message);
}

class LinkedInviteData {
  const LinkedInviteData({required this.inviteLink, required this.expiresAt});

  final String inviteLink;
  final DateTime expiresAt;
}

class LinkedEditCodeData {
  const LinkedEditCodeData({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}
