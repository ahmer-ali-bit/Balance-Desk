import 'package:cloud_firestore/cloud_firestore.dart';

import 'linked_device.dart';

/// A pairing capability: knowing the [token] is what lets a device join.
///
/// Tokens are 128-bit random (32 hex chars), expire, and can only be redeemed
/// a bounded number of times. They carry **no ledger data** — only the
/// workspace id and the role the joiner will receive.
class LinkInvite {
  const LinkInvite({
    required this.token,
    required this.workspaceId,
    required this.role,
    required this.createdByUid,
    required this.createdAt,
    required this.expiresAt,
    required this.maxUses,
    required this.uses,
    this.joinedDeviceIds = const <String>[],
    this.revoked = false,
  });

  final String token;
  final String workspaceId;
  final DeviceRole role;
  final String createdByUid;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int maxUses;
  final int uses;
  final List<String> joinedDeviceIds;
  final bool revoked;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsable => !revoked && !isExpired && uses < maxUses;
  int get remainingUses => (maxUses - uses).clamp(0, maxUses);

  /// `balancedesk://link-device?w=<workspaceId>&t=<token>`
  ///
  /// Matches the Android intent filter, the iOS/macOS URL scheme and the
  /// Windows registry entry installed by `tool/installer/balance-desk.iss`.
  String get inviteLink => 'balancedesk://link-device?w=$workspaceId&t=$token';

  Map<String, Object?> toDocument() => <String, Object?>{
        'token': token,
        'createdByUid': createdByUid,
        'role': role.wire,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'maxUses': maxUses,
        'uses': 0,
        'joinedDeviceIds': <String>[],
        'revoked': false,
      };

  factory LinkInvite.fromDocument(String token, Map<String, Object?> data) {
    return LinkInvite(
      token: (data['token'] ?? token) as String,
      workspaceId: (data['workspaceId'] ?? '') as String,
      role: DeviceRole.fromWire(data['role']),
      createdByUid: (data['createdByUid'] ?? '') as String,
      createdAt: _readDate(data['createdAt']),
      expiresAt: _readDate(data['expiresAt']),
      maxUses: (data['maxUses'] ?? 1) as int,
      uses: (data['uses'] ?? 0) as int,
      // Stored as `joinedUids` — one redemption per account.
      joinedDeviceIds: ((data['joinedUids'] ?? <String>[]) as List<Object?>)
          .map((Object? id) => '$id')
          .toList(),
      revoked: (data['revoked'] ?? false) as bool,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
