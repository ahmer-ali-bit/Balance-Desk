import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/link_invite.dart';
import '../../models/linked_device.dart';
import 'device_identity_service.dart';

/// Thrown when a pairing or membership operation cannot complete.
class LinkServiceException implements Exception {
  const LinkServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// All Firestore traffic for Linked Devices.
///
/// Firestore layout (kept in sync with `firestore.rules`):
/// ```
/// workspaces/{workspaceId}                  {name, ownerUid, revision, …}
/// workspaces/{workspaceId}/members/{uid}    {uid, deviceId, role, …}
/// workspaces/{workspaceId}/invites/{token}  {token, role, uses, maxUses, …}
/// workspaces/{workspaceId}/ops/{opId}       {table, rowId, action, payload}
/// ```
class LinkService {
  LinkService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestoreOverride = firestore,
        _authOverride = auth;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  static const String workspacesCollection = 'workspaces';
  static const String membersCollection = 'members';
  static const String invitesCollection = 'invites';
  static const String opsCollection = 'ops';

  static const int _inviteTokenBytes = 16; // 128 bits → 32 hex chars

  FirebaseFirestore get firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  FirebaseAuth get auth => _authOverride ?? FirebaseAuth.instance;

  DeviceIdentityService get identity => DeviceIdentityService.instance;

  // ------------------------------------------------------------- documents

  DocumentReference<Map<String, dynamic>> workspaceDoc(String workspaceId) =>
      firestore.collection(workspacesCollection).doc(workspaceId);

  CollectionReference<Map<String, dynamic>> membersRef(String workspaceId) =>
      workspaceDoc(workspaceId).collection(membersCollection);

  CollectionReference<Map<String, dynamic>> invitesRef(String workspaceId) =>
      workspaceDoc(workspaceId).collection(invitesCollection);

  CollectionReference<Map<String, dynamic>> opsRef(String workspaceId) =>
      workspaceDoc(workspaceId).collection(opsCollection);

  // ------------------------------------------------------------------ auth

  /// Anonymous sign-in. The uid is what ties this device to its membership
  /// document; nothing about the ledger is attached to the account.
  Future<String> ensureUid() async {
    final User? current = auth.currentUser;
    if (current != null) {
      return current.uid;
    }
    final UserCredential credential = await auth.signInAnonymously();
    final User? user = credential.user;
    if (user == null) {
      throw const LinkServiceException('Sign-in failed. Try again.');
    }
    return user.uid;
  }

  // -------------------------------------------------------------- workspaces

  /// Creates a new workspace and seats this device as its owner.
  Future<void> createWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    final String uid = await ensureUid();

    final WriteBatch batch = firestore.batch();
    batch.set(
      workspaceDoc(workspaceId),
      <String, Object?>{
        'name': name,
        'ownerUid': uid,
        'revision': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      membersRef(workspaceId).doc(uid),
      <String, Object?>{
        'uid': uid,
        'deviceId': identity.deviceId,
        'displayName': identity.displayName,
        'platform': identity.platformLabel,
        'role': DeviceRole.owner.wire,
        'inviteToken': '',
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      },
    );

    await batch.commit();
  }

  Future<String?> readWorkspaceName(String workspaceId) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await workspaceDoc(workspaceId).get();
    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      return null;
    }
    return data['name'] as String?;
  }

  // ---------------------------------------------------------------- invites

  /// Generates a pairing token and publishes the invite document.
  Future<LinkInvite> createInvite({
    required String workspaceId,
    required DeviceRole role,
    Duration ttl = const Duration(minutes: 15),
    int maxUses = 5,
  }) async {
    if (role == DeviceRole.owner) {
      throw const LinkServiceException(
        'Ownership cannot be shared through an invite link.',
      );
    }

    final String uid = await ensureUid();
    final String token = _randomToken();
    final DateTime expiresAt = DateTime.now().add(ttl);

    final LinkInvite invite = LinkInvite(
      token: token,
      workspaceId: workspaceId,
      role: role,
      createdByUid: uid,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      maxUses: maxUses,
      uses: 0,
    );

    await invitesRef(workspaceId).doc(token).set(invite.toDocument());
    return invite;
  }

  Future<LinkInvite> readInvite({
    required String workspaceId,
    required String token,
  }) async {
    await ensureUid();

    final DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await invitesRef(workspaceId).doc(token).get();
    } on FirebaseException catch (error) {
      throw LinkServiceException(_describe(error, 'Could not read that invite.'));
    }

    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      throw const LinkServiceException(
        'That invite link is invalid or has expired.',
      );
    }
    return LinkInvite.fromDocument(token, data);
  }

  Future<void> revokeInvite({
    required String workspaceId,
    required String token,
  }) async {
    await invitesRef(workspaceId).doc(token).update(<String, Object?>{
      'revoked': true,
    });
  }

  // ------------------------------------------------------------------ join

  /// Redeems an invite: consumes one use and creates this device's membership
  /// document. Both writes happen in a single transaction so a token can never
  /// be over-redeemed.
  Future<DeviceRole> joinWorkspace({
    required String workspaceId,
    required String token,
  }) async {
    final String uid = await ensureUid();
    final DocumentReference<Map<String, dynamic>> inviteRef =
        invitesRef(workspaceId).doc(token);
    final DocumentReference<Map<String, dynamic>> memberRef =
        membersRef(workspaceId).doc(uid);

    try {
      return await firestore.runTransaction<DeviceRole>(
        (Transaction transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> inviteSnapshot =
              await transaction.get(inviteRef);
          final Map<String, dynamic>? inviteData = inviteSnapshot.data();
          if (!inviteSnapshot.exists || inviteData == null) {
            throw const LinkServiceException(
              'That invite link is invalid or has expired.',
            );
          }

          final LinkInvite invite = LinkInvite.fromDocument(token, inviteData);
          if (!invite.isUsable) {
            throw const LinkServiceException(
              'That invite has expired or already been used up.',
            );
          }

          final List<String> joinedUids = <String>[
            ...invite.joinedDeviceIds,
            uid,
          ];

          transaction.update(inviteRef, <String, Object?>{
            'uses': invite.uses + 1,
            'joinedUids': joinedUids,
          });

          transaction.set(memberRef, <String, Object?>{
            'uid': uid,
            'deviceId': identity.deviceId,
            'displayName': identity.displayName,
            'platform': identity.platformLabel,
            'role': invite.role.wire,
            'inviteToken': token,
            'joinedAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          });

          return invite.role;
        },
      );
    } on FirebaseException catch (error) {
      throw LinkServiceException(_describe(error, 'Could not join that workspace.'));
    }
  }

  // --------------------------------------------------------------- roster

  Stream<List<LinkedDevice>> watchMembers(String workspaceId) {
    return membersRef(workspaceId)
        .orderBy('joinedAt')
        .snapshots()
        .map(
      (QuerySnapshot<Map<String, dynamic>> snapshot) {
        return snapshot.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  LinkedDevice.fromDocument(
                doc.data(),
                currentDeviceId: identity.deviceId,
              ),
            )
            .toList();
      },
    );
  }

  Future<DeviceRole?> readMyRole(String workspaceId) async {
    final User? user = auth.currentUser;
    if (user == null) {
      return null;
    }
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await membersRef(workspaceId).doc(user.uid).get();
    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      return null;
    }
    return DeviceRole.fromWire(data['role']);
  }

  /// Owner-only role change (viewer ⇄ editor).
  Future<void> setMemberRole({
    required String workspaceId,
    required String memberUid,
    required DeviceRole role,
  }) async {
    await membersRef(workspaceId).doc(memberUid).update(<String, Object?>{
      'role': role.wire,
    });
  }

  /// Owner kicks a device.
  Future<void> removeMember({
    required String workspaceId,
    required String memberUid,
  }) async {
    await membersRef(workspaceId).doc(memberUid).delete();
  }

  /// This device leaves the workspace (deletes its own membership).
  Future<void> leaveWorkspace(String workspaceId) async {
    final User? user = auth.currentUser;
    if (user == null) {
      return;
    }
    await membersRef(workspaceId).doc(user.uid).delete();
  }

  /// Refreshes this device's heartbeat and display name.
  Future<void> heartbeat(String workspaceId) async {
    final User? user = auth.currentUser;
    if (user == null) {
      return;
    }
    final DocumentReference<Map<String, dynamic>> memberRef =
        membersRef(workspaceId).doc(user.uid);
    try {
      await memberRef.update(<String, Object?>{
        'lastSeenAt': FieldValue.serverTimestamp(),
        'displayName': identity.displayName,
        'platform': identity.platformLabel,
      });
    } on FirebaseException {
      // A failed heartbeat is not worth surfacing to the user.
    }
  }

  // --------------------------------------------------------------- helpers

  static String _randomToken() {
    final Random random = Random.secure();
    final List<int> bytes =
        List<int>.generate(_inviteTokenBytes, (_) => random.nextInt(256));
    return sha256.convert(bytes).toString().substring(0, _inviteTokenBytes * 2);
  }

  static String _describe(FirebaseException error, String fallback) {
    switch (error.code) {
      case 'permission-denied':
        return 'Access denied. Check that the invite is still valid and that '
            'the Firestore rules are deployed.';
      case 'unavailable':
        return 'No connection to Firebase. Check your internet and try again.';
      case 'not-found':
        return 'That workspace no longer exists.';
      default:
        return error.message?.isNotEmpty == true ? error.message! : fallback;
    }
  }
}
