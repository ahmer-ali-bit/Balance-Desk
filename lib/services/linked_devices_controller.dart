import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/linked_device_models.dart';
import '../models/workspace_snapshot_payload.dart';
import '../utils/platform_helper.dart';
import 'company_profile_service.dart';
import 'firebase_bootstrap_service.dart';

class LinkedDevicesController extends ChangeNotifier {
  LinkedDevicesController._({
    AppDatabase? database,
    CompanyProfileService? companyProfileService,
    FirebaseBootstrapService? bootstrapService,
  }) : _database = database ?? AppDatabase.instance,
       _companyProfileService =
           companyProfileService ?? CompanyProfileService(),
       _bootstrapService =
           bootstrapService ?? FirebaseBootstrapService.instance;

  static final LinkedDevicesController instance = LinkedDevicesController._();

  static const String _workspaceIdKey = 'linked.workspaceId';
  static const String _roleKey = 'linked.role';
  static const String _ownerUidKey = 'linked.ownerUid';
  static const String _memberUidKey = 'linked.memberUid';
  static const String _membershipStatusKey = 'linked.membershipStatus';
  static const String _lastAppliedRevisionKey = 'linked.lastAppliedRevision';
  static const String _deviceNameKey = 'linked.deviceName';
  static const String _localWorkspaceBackupKey = 'linked.localWorkspaceBackup';
  static const String _sharedWorkspaceBackupKey =
      'linked.sharedWorkspaceBackup';
  static const String _workspaceViewKey = 'linked.workspaceView';
  static const String _workspaceViewShared = 'shared';
  static const String _workspaceViewLocal = 'local';

  static const int _snapshotSchemaVersion = 1;
  static const int _chunkSize = 700000;
  static const Duration _authRestoreTimeout = Duration(seconds: 3);
  static const Duration _presenceHeartbeatInterval = Duration(seconds: 8);
  static const Duration _presenceVisibleWindow = Duration(seconds: 18);

  static const Set<String> _localOnlySettingKeys = <String>{
    'appPin',
    'appPinHash',
    'appPinSalt',
    'appPinSetupDismissed',
    'autoBackupPath',
    'companyLogoPath',
    _workspaceIdKey,
    _roleKey,
    _ownerUidKey,
    _memberUidKey,
    _membershipStatusKey,
    _lastAppliedRevisionKey,
    _deviceNameKey,
    _localWorkspaceBackupKey,
    _sharedWorkspaceBackupKey,
    _workspaceViewKey,
  };

  final AppDatabase _database;
  final CompanyProfileService _companyProfileService;
  final FirebaseBootstrapService _bootstrapService;

  FirebaseFirestore? _firestore;
  FirebaseAuth? _auth;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _workspaceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _selfMemberSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membersSub;
  Timer? _presenceTimer;

  bool _isInitializing = false;
  bool _isInitialized = false;
  bool _isBusy = false;
  bool _isSyncing = false;
  bool _isApplyingRemoteSnapshot = false;
  bool _featureAvailable = false;
  String? _availabilityMessage;
  String? _lastError;
  String? _workspaceId;
  String? _ownerUid;
  String? _memberUid;
  String? _deviceName;
  LinkedWorkspaceRole _role = LinkedWorkspaceRole.none;
  LinkedWorkspaceMembershipStatus _membershipStatus =
      LinkedWorkspaceMembershipStatus.unlinked;
  int _latestRemoteRevision = 0;
  int _lastAppliedRevision = 0;
  int _dataVersion = 0;
  List<LinkedDeviceMember> _members = const <LinkedDeviceMember>[];
  bool _isRecoveringFromAccessFailure = false;
  bool _isSendingPresenceHeartbeat = false;
  int _lastGeneratedRevisionId = 0;
  bool _isUsingLocalWorkspace = false;
  bool _hasLocalWorkspaceBackup = false;
  bool _hasSharedWorkspaceBackup = false;
  bool _isTransitioningLinkedState = false;

  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  bool get isSyncing => _isSyncing;
  bool get featureAvailable => _featureAvailable;
  String? get availabilityMessage => _availabilityMessage;
  String? get lastError => _lastError;
  String? get workspaceId => _workspaceId;
  String? get ownerUid => _ownerUid;
  String? get deviceName => _deviceName;
  LinkedWorkspaceRole get role => _role;
  LinkedWorkspaceMembershipStatus get membershipStatus => _membershipStatus;
  int get latestRemoteRevision => _latestRemoteRevision;
  int get lastAppliedRevision => _lastAppliedRevision;
  int get dataVersion => _dataVersion;
  bool get isUsingLocalWorkspace =>
      hasLinkedWorkspace && _isUsingLocalWorkspace;
  bool get hasLocalWorkspaceBackup => _hasLocalWorkspaceBackup;
  bool get canSwitchWorkspaceView =>
      hasLinkedWorkspace && !isOwner && _hasLocalWorkspaceBackup;
  List<LinkedDeviceMember> get members {
    return List<LinkedDeviceMember>.unmodifiable(
      _members.where(
        (LinkedDeviceMember member) =>
            member.role == LinkedWorkspaceRole.owner || member.isActive,
      ),
    );
  }

  List<LinkedDeviceMember> get connectedMembers {
    final now = DateTime.now();
    return List<LinkedDeviceMember>.unmodifiable(
      _members.where(
        (LinkedDeviceMember member) =>
            member.role == LinkedWorkspaceRole.owner ||
            (member.isActive && _isMemberRecentlySeen(member, now: now)),
      ),
    );
  }

  bool get hasLinkedWorkspace => (_workspaceId ?? '').trim().isNotEmpty;
  bool get isLinked =>
      hasLinkedWorkspace &&
      _membershipStatus.isActive &&
      _role != LinkedWorkspaceRole.none;
  bool get isOwner => isLinked && _role == LinkedWorkspaceRole.owner;
  bool get isViewer => isLinked && _role == LinkedWorkspaceRole.viewer;
  bool get isEditor => isLinked && _role == LinkedWorkspaceRole.editor;
  bool get canManageLinkedDevices => isOwner;
  bool get canEditWorkspace =>
      !hasLinkedWorkspace ||
      isUsingLocalWorkspace ||
      (isLinked && _role.canEdit);
  bool get isReadOnlyLinkedDevice =>
      hasLinkedWorkspace && !isUsingLocalWorkspace && !canEditWorkspace;

  String get workspaceBadgeLabel {
    if (_membershipStatus == LinkedWorkspaceMembershipStatus.revoked) {
      return 'Revoked';
    }
    if (isUsingLocalWorkspace) {
      return 'Local View';
    }
    if (isOwner) {
      return 'Owner';
    }
    if (isEditor) {
      return 'Editor';
    }
    if (isViewer) {
      return 'Read Only';
    }
    return 'Local';
  }

  String get workspaceSubtitle {
    if (_membershipStatus == LinkedWorkspaceMembershipStatus.revoked) {
      return 'Linked access removed';
    }
    if (isUsingLocalWorkspace) {
      return 'Using your own local workspace';
    }
    if (isOwner) {
      return 'Using your own shared workspace';
    }
    if (isEditor) {
      return 'Linked editor device';
    }
    if (isViewer) {
      return 'Linked read-only device';
    }
    return 'Local offline workspace';
  }

  String get readOnlyMessage =>
      'This linked device is read-only. Ask the owner for an edit code to enable changes.';

  @override
  void dispose() {
    _stopPresenceTracking();
    unawaited(disposeSubscriptions());
    super.dispose();
  }

  void clearLastError() {
    if ((_lastError ?? '').isEmpty) {
      return;
    }
    _lastError = null;
    notifyListeners();
  }

  bool looksLikeInviteLink(String rawLink) {
    return _parseInviteLink(rawLink) != null;
  }

  Future<void> initialize() async {
    if (_isInitializing || _isInitialized) {
      return;
    }

    _isInitializing = true;
    notifyListeners();

    try {
      final bootstrapResult = await _bootstrapService.initialize();
      _featureAvailable = bootstrapResult.isAvailable;
      _availabilityMessage = bootstrapResult.message;

      _deviceName = await _loadOrCreateDeviceName();
      _workspaceId = await _database.getAppSetting(_workspaceIdKey);
      _ownerUid = await _database.getAppSetting(_ownerUidKey);
      _memberUid = await _database.getAppSetting(_memberUidKey);
      _role = LinkedWorkspaceRoleX.parse(
        await _database.getAppSetting(_roleKey),
      );
      _membershipStatus = LinkedWorkspaceMembershipStatusX.parse(
        await _database.getAppSetting(_membershipStatusKey),
      );
      _lastAppliedRevision =
          int.tryParse(
            await _database.getAppSetting(_lastAppliedRevisionKey) ?? '',
          ) ??
          0;
      _isUsingLocalWorkspace =
          (await _database.getAppSetting(_workspaceViewKey)) ==
          _workspaceViewLocal;
      _hasLocalWorkspaceBackup =
          ((await _database.getAppSetting(_localWorkspaceBackupKey)) ?? '')
              .trim()
              .isNotEmpty;
      _hasSharedWorkspaceBackup =
          ((await _database.getAppSetting(_sharedWorkspaceBackupKey)) ?? '')
              .trim()
              .isNotEmpty;
      if (!hasLinkedWorkspace) {
        _isUsingLocalWorkspace = false;
      }

      if (_featureAvailable) {
        _firestore = FirebaseFirestore.instance;
        _auth = FirebaseAuth.instance;
        await _ensureSignedIn();

        if (hasLinkedWorkspace) {
          await _startWorkspaceSubscriptions();
        } else {
          await disposeSubscriptions();
          _lastError = null;
        }
      }
      _refreshPresenceTracking();
    } finally {
      _isInitializing = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<LinkedActionResult> createOwnerWorkspace({
    bool replaceCurrentLink = false,
  }) async {
    await initialize();

    if (!_featureAvailable) {
      return LinkedActionResult.failure(
        _availabilityMessage ?? 'Linked devices are not configured yet.',
      );
    }
    if (hasLinkedWorkspace && !replaceCurrentLink) {
      return const LinkedActionResult.failure(
        'This device is already connected to a linked workspace.',
      );
    }

    return _runBusyAction(() async {
      final previousWorkspaceId = hasLinkedWorkspace ? _workspaceId : null;
      final previousMemberUid = (_memberUid ?? _auth?.currentUser?.uid)?.trim();

      await _prepareForWorkspaceSwitch();

      final currentUser = await _ensureSignedIn();
      if (currentUser == null) {
        return const LinkedActionResult.failure(
          'Unable to authenticate this device for linked access.',
        );
      }

      final workspaceId = _randomToken(24);
      final companyProfile = await _companyProfileService.loadProfile();
      final workspaceName = companyProfile.name.trim().isEmpty
          ? 'Balance Desk Workspace'
          : companyProfile.name.trim();

      final workspaceDoc = _workspaceDoc(workspaceId);
      await workspaceDoc.set(<String, Object?>{
        'workspaceName': workspaceName,
        'ownerUid': currentUser.uid,
        'latestRevision': 0,
        'revisionCounter': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'schemaVersion': _snapshotSchemaVersion,
      });

      await workspaceDoc
          .collection('members')
          .doc(currentUser.uid)
          .set(<String, Object?>{
            'uid': currentUser.uid,
            'deviceName': _deviceName ?? await _loadOrCreateDeviceName(),
            'platform': PlatformHelper.platformLabel,
            'role': LinkedWorkspaceRole.owner.storageValue,
            'status': LinkedWorkspaceMembershipStatus.active.storageValue,
            'linkedAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          });

      await _saveLocalLinkState(
        workspaceId: workspaceId,
        memberUid: currentUser.uid,
        ownerUid: currentUser.uid,
        role: LinkedWorkspaceRole.owner,
        membershipStatus: LinkedWorkspaceMembershipStatus.active,
      );

      final syncResult = await _pushLocalSnapshot(reason: 'initial_publish');
      if (!syncResult.isSuccess) {
        await _rollbackWorkspaceCreation(
          workspaceId: workspaceId,
          currentUserUid: currentUser.uid,
        );
        await _resetInaccessibleLocalLinkState();
        return syncResult;
      }

      await _startWorkspaceSubscriptions();
      if ((previousWorkspaceId ?? '').isNotEmpty &&
          previousWorkspaceId != workspaceId &&
          (previousMemberUid ?? '').isNotEmpty) {
        await _runDuringLinkedStateTransition(() async {
          await _detachRemoteMembershipBestEffort(
            workspaceId: previousWorkspaceId!,
            memberUid: previousMemberUid!,
          );
        });
      }

      return const LinkedActionResult.success(
        'Linked devices are enabled for this workspace.',
      );
    });
  }

  Future<LinkedInviteData?> createInvite() async {
    await initialize();
    if (!isOwner || _firestore == null || _auth?.currentUser == null) {
      return null;
    }

    final inviteId = _randomToken(6).toUpperCase();
    final token = _randomToken(28);
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));
    final invitesCollection = _workspaceDoc(
      _workspaceId!,
    ).collection('invites');
    final activeInvites = await invitesCollection
        .where('status', isEqualTo: 'active')
        .get();
    final batch = _firestore!.batch();

    for (final inviteDoc in activeInvites.docs) {
      batch.delete(inviteDoc.reference);
    }

    batch.set(invitesCollection.doc(inviteId), <String, Object?>{
      'inviteId': inviteId,
      'token': token,
      'status': 'active',
      'createdByUid': _auth!.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
    await batch.commit();

    final inviteLink = Uri(
      scheme: 'balancedesk',
      host: 'link-device',
      queryParameters: <String, String>{
        'workspace': _workspaceId!,
        'invite': inviteId,
        'token': token,
      },
    ).toString();

    return LinkedInviteData(inviteLink: inviteLink, expiresAt: expiresAt);
  }

  Future<LinkedActionResult> joinWorkspaceFromLink(String rawLink) async {
    await initialize();
    if (!_featureAvailable) {
      return LinkedActionResult.failure(
        _availabilityMessage ?? 'Linked devices are not configured yet.',
      );
    }

    final invite = _parseInviteLink(rawLink);
    if (invite == null) {
      return const LinkedActionResult.failure(
        'This invite link is invalid. Check the link and try again.',
      );
    }

    final sameWorkspaceInvite =
        hasLinkedWorkspace && _workspaceId == invite.workspaceId;
    final hasVisibleAccessError = (_lastError ?? '').trim().isNotEmpty;

    if (sameWorkspaceInvite && isLinked && !hasVisibleAccessError) {
      return _runBusyAction(() async {
        if (canSwitchWorkspaceView && isUsingLocalWorkspace) {
          return _switchToLinkedWorkspace();
        }

        await _startWorkspaceSubscriptions();
        await _pullLatestSnapshot(force: true);
        return const LinkedActionResult.success(
          'This device is already linked to this workspace.',
        );
      });
    }

    return _runBusyAction(() async {
      final previousWorkspaceId = hasLinkedWorkspace ? _workspaceId : null;
      final previousMemberUid = (_memberUid ?? _auth?.currentUser?.uid)?.trim();
      User? currentUser = await _ensureSignedIn();
      if (currentUser == null) {
        return const LinkedActionResult.failure(
          'Unable to authenticate this device for linked access.',
        );
      }

      if (_firestore == null) {
        return const LinkedActionResult.failure(
          'Linked devices are not available right now.',
        );
      }

      final workspaceDoc = _workspaceDoc(invite.workspaceId);
      final currentDeviceName = _deviceName ?? await _loadOrCreateDeviceName();
      final joiningFromLocalOnlyState = !hasLinkedWorkspace;
      final canRetryWithFreshAuth =
          joiningFromLocalOnlyState ||
          sameWorkspaceInvite ||
          _membershipStatus != LinkedWorkspaceMembershipStatus.active;
      await _cacheCurrentWorkspaceAsLocalBackupIfNeeded();
      await _prepareForWorkspaceSwitch();

      try {
        await workspaceDoc
            .collection('members')
            .doc(currentUser.uid)
            .set(
              _joinMembershipData(
                uid: currentUser.uid,
                deviceName: currentDeviceName,
                invite: invite,
              ),
            );
      } on FirebaseException catch (error) {
        if (_isPermissionDeniedError(error) && canRetryWithFreshAuth) {
          await _detachRemoteMembershipBestEffort(
            workspaceId: invite.workspaceId,
            memberUid: currentUser.uid,
          );
          final retryUser = await _resetAnonymousAuthForFreshJoin();
          if (retryUser != null) {
            try {
              await workspaceDoc
                  .collection('members')
                  .doc(retryUser.uid)
                  .set(
                    _joinMembershipData(
                      uid: retryUser.uid,
                      deviceName: currentDeviceName,
                      invite: invite,
                    ),
                  );
              currentUser = retryUser;
            } on FirebaseException catch (retryError) {
              await _resumeWorkspaceAfterInterruptedSwitch();
              return LinkedActionResult.failure(
                _describeJoinWorkspaceError(retryError),
              );
            } catch (_) {
              await _resumeWorkspaceAfterInterruptedSwitch();
              rethrow;
            }
          } else {
            await _resumeWorkspaceAfterInterruptedSwitch();
            return LinkedActionResult.failure(
              _describeJoinWorkspaceError(error),
            );
          }
        } else {
          await _resumeWorkspaceAfterInterruptedSwitch();
          return LinkedActionResult.failure(_describeJoinWorkspaceError(error));
        }
      } catch (_) {
        await _resumeWorkspaceAfterInterruptedSwitch();
        rethrow;
      }

      String? ownerUid;
      try {
        final workspaceSnapshot = await workspaceDoc.get();
        ownerUid = workspaceSnapshot.data()?['ownerUid'] as String?;
      } catch (_) {
        // Membership was created successfully, so subscriptions can finish
        // populating workspace metadata even if this eager read is delayed.
      }

      await _saveLocalLinkState(
        workspaceId: invite.workspaceId,
        memberUid: currentUser.uid,
        ownerUid: ownerUid,
        role: LinkedWorkspaceRole.viewer,
        membershipStatus: LinkedWorkspaceMembershipStatus.active,
      );
      await _startWorkspaceSubscriptions();
      await _pullLatestSnapshot(force: true);
      if ((previousWorkspaceId ?? '').isNotEmpty &&
          previousWorkspaceId != invite.workspaceId &&
          (previousMemberUid ?? '').isNotEmpty) {
        await _runDuringLinkedStateTransition(() async {
          await _detachRemoteMembershipBestEffort(
            workspaceId: previousWorkspaceId!,
            memberUid: previousMemberUid!,
          );
        });
      }

      return const LinkedActionResult.success(
        'This device is now linked in read-only mode.',
      );
    });
  }

  Future<LinkedEditCodeData?> createEditCode(String memberUid) async {
    await initialize();
    if (!isOwner || _firestore == null) {
      return null;
    }

    final grantId = _randomToken(4).toUpperCase();
    final token = _randomDigits(6);
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));

    await _workspaceDoc(
      _workspaceId!,
    ).collection('edit_grants').doc(grantId).set(<String, Object?>{
      'grantId': grantId,
      'targetUid': memberUid,
      'token': token,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    return LinkedEditCodeData(code: '$grantId-$token', expiresAt: expiresAt);
  }

  Future<LinkedActionResult> redeemEditCode(String rawCode) async {
    await initialize();
    if (!_featureAvailable || !hasLinkedWorkspace || _firestore == null) {
      return const LinkedActionResult.failure(
        'This device is not connected to a linked workspace.',
      );
    }

    final pieces = rawCode
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .split('-')
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    if (pieces.length != 2) {
      return const LinkedActionResult.failure(
        'Enter the full edit code in the format ABCD-123456.',
      );
    }

    return _runBusyAction(() async {
      final currentUser = await _ensureSignedIn();
      if (currentUser == null) {
        return const LinkedActionResult.failure(
          'Unable to authenticate this device for edit access.',
        );
      }

      await _workspaceDoc(
        _workspaceId!,
      ).collection('members').doc(currentUser.uid).set(<String, Object?>{
        'role': LinkedWorkspaceRole.editor.storageValue,
        'grantId': pieces[0],
        'grantToken': pieces[1],
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _role = LinkedWorkspaceRole.editor;
      await _database.setAppSetting(
        key: _roleKey,
        value: LinkedWorkspaceRole.editor.storageValue,
      );
      notifyListeners();

      return const LinkedActionResult.success(
        'Edit access has been enabled on this device.',
      );
    });
  }

  Future<LinkedActionResult> revokeMember(String memberUid) async {
    await initialize();
    if (!isOwner || _firestore == null || !hasLinkedWorkspace) {
      return const LinkedActionResult.failure(
        'Only the owner can revoke linked devices.',
      );
    }
    if (memberUid.trim().isEmpty || memberUid == _auth?.currentUser?.uid) {
      return const LinkedActionResult.failure(
        'The owner device cannot remove itself from the shared workspace.',
      );
    }

    return _runBusyAction(() async {
      await _workspaceDoc(
        _workspaceId!,
      ).collection('members').doc(memberUid).set(<String, Object?>{
        'status': LinkedWorkspaceMembershipStatus.revoked.storageValue,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedByUid': _auth?.currentUser?.uid,
      }, SetOptions(merge: true));

      return const LinkedActionResult.success('Linked device access removed.');
    });
  }

  Future<LinkedActionResult> makeMemberReadOnly(String memberUid) async {
    await initialize();
    if (!isOwner || _firestore == null || !hasLinkedWorkspace) {
      return const LinkedActionResult.failure(
        'Only the owner can change linked device access.',
      );
    }

    return _runBusyAction(() async {
      await _workspaceDoc(
        _workspaceId!,
      ).collection('members').doc(memberUid).set(<String, Object?>{
        'role': LinkedWorkspaceRole.viewer.storageValue,
      }, SetOptions(merge: true));

      return const LinkedActionResult.success(
        'This linked device is now read-only.',
      );
    });
  }

  Future<LinkedActionResult> disconnectCurrentDevice() async {
    await initialize();
    if (!hasLinkedWorkspace || _firestore == null) {
      return const LinkedActionResult.failure(
        'This device is not connected to a linked workspace.',
      );
    }
    if (isOwner) {
      return const LinkedActionResult.failure(
        'The owner device cannot disconnect itself from the shared workspace.',
      );
    }

    final currentUser = await _ensureSignedIn();
    if (currentUser == null) {
      return const LinkedActionResult.failure(
        'Unable to verify this linked device.',
      );
    }

    return _runBusyAction(() async {
      final workspaceId = _workspaceId!;
      final currentRole = _role;
      final deviceName = _deviceName ?? await _loadOrCreateDeviceName();
      final memberUidsToClean = <String>{
        currentUser.uid,
        if ((_memberUid ?? '').trim().isNotEmpty) _memberUid!.trim(),
      };
      await _runDuringLinkedStateTransition(() async {
        await disposeSubscriptions();
        final cleanupResults = <String, bool>{};
        for (final memberUid in memberUidsToClean) {
          cleanupResults[memberUid] = await _detachRemoteMembershipBestEffort(
            workspaceId: workspaceId,
            memberUid: memberUid,
          );
        }
        for (final memberUid in memberUidsToClean.where(
          (String memberUid) => cleanupResults[memberUid] != true,
        )) {
          await _markRemoteMembershipRevokedBestEffort(
            workspaceId: workspaceId,
            memberUid: memberUid,
            role: currentRole,
            deviceName: deviceName,
          );
        }
        await _handleRevokedAccess(clearRemoteMembership: false);
      });

      return const LinkedActionResult.success(
        'This device is now disconnected and back in local mode. You can enter your own data here.',
      );
    });
  }

  Future<LinkedActionResult> switchWorkspaceView() async {
    await initialize();
    if (!hasLinkedWorkspace || isOwner) {
      return const LinkedActionResult.failure(
        'Only linked devices can switch between local and shared workspaces.',
      );
    }

    if (isUsingLocalWorkspace) {
      return _switchToLinkedWorkspace();
    }

    return _switchToLocalWorkspace();
  }

  Future<LinkedActionResult> syncAfterLocalChange({
    required String reason,
  }) async {
    await initialize();

    if (_isApplyingRemoteSnapshot || !hasLinkedWorkspace) {
      return const LinkedActionResult.success('No linked sync required.');
    }
    if (isUsingLocalWorkspace) {
      await _cacheCurrentWorkspaceAsLocalBackup();
      return const LinkedActionResult.success(
        'Local workspace changes were saved on this device.',
      );
    }
    if (!_featureAvailable) {
      return LinkedActionResult.failure(
        _availabilityMessage ?? 'Linked devices are not configured yet.',
      );
    }
    if (!canEditWorkspace) {
      return LinkedActionResult.failure(readOnlyMessage);
    }

    return _pushLocalSnapshot(reason: reason);
  }

  Future<LinkedActionResult> syncNow() async {
    await initialize();
    if (!hasLinkedWorkspace) {
      return const LinkedActionResult.failure(
        'Linked devices are not enabled on this device yet.',
      );
    }
    if (isUsingLocalWorkspace) {
      await _cacheCurrentWorkspaceAsLocalBackup();
      return const LinkedActionResult.success(
        'Your own local workspace is active right now. Switch back to the linked workspace whenever you want to sync again.',
      );
    }
    if (!_featureAvailable) {
      return LinkedActionResult.failure(
        _availabilityMessage ?? 'Linked devices are not configured yet.',
      );
    }

    if (canEditWorkspace) {
      return _pushLocalSnapshot(reason: 'manual_sync');
    }

    await _pullLatestSnapshot(force: true);
    return const LinkedActionResult.success('Linked data refreshed.');
  }

  Future<void> _prepareForWorkspaceSwitch() async {
    _stopPresenceTracking();
    await disposeSubscriptions();
    _members = const <LinkedDeviceMember>[];
    _latestRemoteRevision = 0;
    _lastAppliedRevision = 0;
    _lastError = null;
    notifyListeners();
  }

  Future<LinkedActionResult> _switchToLocalWorkspace() async {
    if (!_hasLocalWorkspaceBackup) {
      return const LinkedActionResult.failure(
        'No saved local workspace was found on this device yet.',
      );
    }

    return _runBusyAction(() async {
      await _cacheCurrentWorkspaceAsSharedBackup();
      final backup = await _loadWorkspaceBackup(_localWorkspaceBackupKey);
      if (backup == null) {
        return const LinkedActionResult.failure(
          'Your local workspace could not be opened on this device.',
        );
      }

      await _restoreWorkspacePayload(backup);
      _isUsingLocalWorkspace = true;
      await _database.setAppSetting(
        key: _workspaceViewKey,
        value: _workspaceViewLocal,
      );
      _lastError = null;
      _refreshPresenceTracking();
      notifyListeners();

      return const LinkedActionResult.success(
        'Your own workspace is now active on this device.',
      );
    });
  }

  Future<LinkedActionResult> _switchToLinkedWorkspace() async {
    return _runBusyAction(() async {
      final backup = _hasSharedWorkspaceBackup
          ? await _loadWorkspaceBackup(_sharedWorkspaceBackupKey)
          : null;
      if (backup != null) {
        await _restoreWorkspacePayload(backup);
      }

      _isUsingLocalWorkspace = false;
      await _database.setAppSetting(
        key: _workspaceViewKey,
        value: _workspaceViewShared,
      );
      _lastError = null;
      _refreshPresenceTracking();
      notifyListeners();
      await _pullLatestSnapshot(
        force: true,
        allowWhileUsingLocalWorkspace: true,
      );

      return const LinkedActionResult.success(
        'The linked workspace is active on this device again.',
      );
    });
  }

  Future<void> _resumeWorkspaceAfterInterruptedSwitch() async {
    if (_firestore == null || !hasLinkedWorkspace) {
      return;
    }

    try {
      await _startWorkspaceSubscriptions();
    } catch (_) {
      // Keep the original join error as the visible failure reason.
    }
  }

  Future<void> disposeSubscriptions() async {
    await _workspaceSub?.cancel();
    await _selfMemberSub?.cancel();
    await _membersSub?.cancel();
    _workspaceSub = null;
    _selfMemberSub = null;
    _membersSub = null;
  }

  bool _isMemberRecentlySeen(LinkedDeviceMember member, {DateTime? now}) {
    final lastSeenAt = member.lastSeenAt;
    if (lastSeenAt == null) {
      return false;
    }

    final referenceTime = now ?? DateTime.now();
    return referenceTime.difference(lastSeenAt) <= _presenceVisibleWindow;
  }

  bool get _shouldSendPresenceHeartbeat =>
      _featureAvailable &&
      hasLinkedWorkspace &&
      isLinked &&
      !isUsingLocalWorkspace &&
      _firestore != null &&
      _auth != null;

  void _refreshPresenceTracking() {
    if (!hasLinkedWorkspace || !_featureAvailable) {
      _stopPresenceTracking();
      return;
    }

    _presenceTimer ??= Timer.periodic(
      _presenceHeartbeatInterval,
      (_) => unawaited(_handlePresenceTick()),
    );
    unawaited(_handlePresenceTick());
  }

  void _stopPresenceTracking() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  Future<void> _handlePresenceTick() async {
    if (!hasLinkedWorkspace || !_featureAvailable) {
      _stopPresenceTracking();
      return;
    }

    if (_shouldSendPresenceHeartbeat) {
      await _sendPresenceHeartbeatBestEffort();
    }

    if (isOwner && _members.isNotEmpty) {
      notifyListeners();
    }
  }

  Future<void> _sendPresenceHeartbeatBestEffort() async {
    if (_isSendingPresenceHeartbeat || !_shouldSendPresenceHeartbeat) {
      return;
    }

    final workspaceId = _workspaceId;
    if ((workspaceId ?? '').trim().isEmpty) {
      return;
    }

    final expectedMemberUid = (_memberUid ?? '').trim();
    if (expectedMemberUid.isEmpty) {
      return;
    }

    _isSendingPresenceHeartbeat = true;
    try {
      final currentUser = await _ensureSignedIn();
      if (currentUser == null || currentUser.uid != expectedMemberUid) {
        return;
      }

      await _workspaceDoc(
        workspaceId!,
      ).collection('members').doc(expectedMemberUid).set(<String, Object?>{
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Presence updates are best-effort only.
    } finally {
      _isSendingPresenceHeartbeat = false;
    }
  }

  Future<LinkedActionResult> _pushLocalSnapshot({
    required String reason,
  }) async {
    if (_firestore == null || !hasLinkedWorkspace) {
      return const LinkedActionResult.failure(
        'Linked devices are not available right now.',
      );
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final currentUser = await _ensureSignedIn();
      if (currentUser == null) {
        return const LinkedActionResult.failure(
          'Unable to authenticate this device for syncing.',
        );
      }

      final payload = await _buildSnapshotPayload();
      final encodedPayload = payload.encode();
      final chunks = _splitIntoChunks(encodedPayload);

      final workspaceDoc = _workspaceDoc(_workspaceId!);
      final nextRevision = _nextRevisionId();
      final revisionDoc = workspaceDoc
          .collection('revisions')
          .doc('$nextRevision');

      await revisionDoc.set(<String, Object?>{
        'revision': nextRevision,
        'chunkCount': chunks.length,
        'reason': reason,
        'schemaVersion': _snapshotSchemaVersion,
        'syncedByUid': currentUser.uid,
        'syncedAt': FieldValue.serverTimestamp(),
        'isComplete': false,
      });

      var currentBatch = _firestore!.batch();
      var operationCount = 0;

      for (var index = 0; index < chunks.length; index++) {
        currentBatch.set(
          revisionDoc
              .collection('chunks')
              .doc(index.toString().padLeft(4, '0')),
          <String, Object?>{'index': index, 'data': chunks[index]},
        );
        operationCount++;
        if (operationCount >= 350) {
          await currentBatch.commit();
          currentBatch = _firestore!.batch();
          operationCount = 0;
        }
      }
      if (operationCount > 0) {
        await currentBatch.commit();
      }

      await revisionDoc.set(<String, Object?>{
        'isComplete': true,
      }, SetOptions(merge: true));
      await workspaceDoc.set(<String, Object?>{
        'latestRevision': nextRevision,
        'latestSyncedByUid': currentUser.uid,
        'workspaceName': payload.workspaceName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _latestRemoteRevision = nextRevision;
      _lastAppliedRevision = nextRevision;
      await _database.setAppSetting(
        key: _lastAppliedRevisionKey,
        value: '$nextRevision',
      );
      await _saveWorkspaceBackup(
        settingKey: _sharedWorkspaceBackupKey,
        payload: payload,
      );

      return const LinkedActionResult.success('Linked devices synced.');
    } catch (error) {
      _lastError = _describeGenericLinkedError(
        error,
        defaultMessage: 'Linked devices could not sync right now.',
      );
      return LinkedActionResult.failure(_lastError!);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _pullLatestSnapshot({
    bool force = false,
    bool allowWhileUsingLocalWorkspace = false,
  }) async {
    if (_firestore == null || !hasLinkedWorkspace) {
      return;
    }
    if (isUsingLocalWorkspace && !allowWhileUsingLocalWorkspace) {
      return;
    }

    final latestRevision = _latestRemoteRevision;
    if (latestRevision <= 0) {
      return;
    }
    if (!force && latestRevision <= _lastAppliedRevision) {
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      final revisionDoc = _workspaceDoc(
        _workspaceId!,
      ).collection('revisions').doc('$latestRevision');
      final revisionSnapshot = await revisionDoc.get();
      final revisionData = revisionSnapshot.data();
      final isComplete = revisionData?['isComplete'] == true;
      if (!isComplete) {
        return;
      }

      final chunkSnapshots = await revisionDoc
          .collection('chunks')
          .orderBy('index')
          .get();
      final payloadBuffer = StringBuffer();
      for (final doc in chunkSnapshots.docs) {
        payloadBuffer.write(doc.data()['data'] as String? ?? '');
      }
      final payload = WorkspaceSnapshotPayload.fromEncoded(
        payloadBuffer.toString(),
      );
      await _applyRemoteSnapshot(payload, latestRevision);
      _lastError = null;
    } catch (error) {
      _lastError = _describeGenericLinkedError(
        error,
        defaultMessage: 'Unable to refresh linked data right now.',
      );
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _applyRemoteSnapshot(
    WorkspaceSnapshotPayload payload,
    int revision,
  ) async {
    _isApplyingRemoteSnapshot = true;
    try {
      await _restoreWorkspacePayload(
        payload,
        revision: revision,
        backupSettingKey: _sharedWorkspaceBackupKey,
      );
    } finally {
      _isApplyingRemoteSnapshot = false;
      notifyListeners();
    }
  }

  Future<void> _handleRevokedAccess({
    required bool clearRemoteMembership,
  }) async {
    if (!hasLinkedWorkspace) {
      return;
    }

    final localBackup = isUsingLocalWorkspace
        ? null
        : await _loadWorkspaceBackup(_localWorkspaceBackupKey);
    if (localBackup != null) {
      await _restoreWorkspacePayload(localBackup);
    } else if (!isUsingLocalWorkspace) {
      final preservedSettings = await _loadLocalOnlySettings(
        includeLogoPath: false,
      );
      await _database.restoreFromCsv(
        customers: const <List<String>>[
          <String>['id', 'name', 'ledgerYear'],
        ],
        entries: const <List<String>>[
          <String>[
            'id',
            'customerId',
            'entryDate',
            'createdAt',
            'pageNo',
            'description',
            'debit',
            'credit',
          ],
        ],
        snapshots: const <List<String>>[
          <String>[
            'id',
            'ledgerYear',
            'savedAt',
            'overallDebit',
            'overallCredit',
            'customerCount',
          ],
        ],
        years: const <List<String>>[
          <String>['year'],
        ],
        settings: _settingsCsv(preservedSettings),
      );
      await _companyProfileService.clearLogo();
    }

    if (clearRemoteMembership &&
        _firestore != null &&
        _auth?.currentUser != null) {
      await _detachRemoteMembershipBestEffort(
        workspaceId: _workspaceId!,
        memberUid: _auth!.currentUser!.uid,
      );
    }

    await _clearLocalLinkState();
    _members = const <LinkedDeviceMember>[];
    _dataVersion++;
    notifyListeners();
  }

  Future<void> _startWorkspaceSubscriptions() async {
    await disposeSubscriptions();

    if (_firestore == null || !hasLinkedWorkspace) {
      return;
    }

    final expectedMemberUid = (_memberUid ?? '').trim();
    final currentUser = await _ensureSignedIn(
      expectedUid: expectedMemberUid.isEmpty ? null : expectedMemberUid,
    );
    if (currentUser == null) {
      if (expectedMemberUid.isNotEmpty) {
        _lastError =
            'Unable to restore the saved linked-device sign-in yet. '
            'Your workspace data is still saved on this device.';
        notifyListeners();
      }
      return;
    }
    _lastError = null;

    _workspaceSub = _workspaceDoc(_workspaceId!).snapshots().listen(
      (DocumentSnapshot<Map<String, dynamic>> snapshot) async {
        try {
          if (!snapshot.exists) {
            _lastError = 'The linked workspace is no longer available.';
            notifyListeners();
            return;
          }

          final data = snapshot.data() ?? const <String, dynamic>{};
          _ownerUid = data['ownerUid'] as String?;
          _latestRemoteRevision =
              (data['latestRevision'] as num?)?.toInt() ?? 0;
          if (_ownerUid != null) {
            await _database.setAppSetting(key: _ownerUidKey, value: _ownerUid!);
          }
          notifyListeners();
          await _pullLatestSnapshot();
        } catch (error) {
          _handleSubscriptionError('workspace updates', error);
        }
      },
      onError: (Object error) {
        _handleSubscriptionError('workspace updates', error);
      },
    );

    _selfMemberSub = _workspaceDoc(_workspaceId!)
        .collection('members')
        .doc(currentUser.uid)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>> snapshot) async {
            try {
              if (!snapshot.exists) {
                await _handleRevokedAccess(clearRemoteMembership: false);
                return;
              }

              final data = snapshot.data() ?? const <String, dynamic>{};
              _role = LinkedWorkspaceRoleX.parse(data['role'] as String?);
              _membershipStatus = LinkedWorkspaceMembershipStatusX.parse(
                data['status'] as String?,
              );
              if (_memberUid != currentUser.uid) {
                _memberUid = currentUser.uid;
                await _database.setAppSetting(
                  key: _memberUidKey,
                  value: currentUser.uid,
                );
              }
              await _database.setAppSetting(
                key: _roleKey,
                value: _role.storageValue,
              );
              await _database.setAppSetting(
                key: _membershipStatusKey,
                value: _membershipStatus.storageValue,
              );

              if (_membershipStatus ==
                  LinkedWorkspaceMembershipStatus.revoked) {
                await _handleRevokedAccess(clearRemoteMembership: false);
                return;
              }

              if (_role == LinkedWorkspaceRole.owner) {
                _membersSub ??= _workspaceDoc(_workspaceId!)
                    .collection('members')
                    .snapshots()
                    .listen(
                      (QuerySnapshot<Map<String, dynamic>> snapshot) {
                        try {
                          final nextMembers =
                              snapshot.docs
                                  .map<LinkedDeviceMember>(
                                    (
                                      QueryDocumentSnapshot<
                                        Map<String, dynamic>
                                      >
                                      doc,
                                    ) => LinkedDeviceMember.fromMap(
                                      doc.id,
                                      doc.data(),
                                    ),
                                  )
                                  .where(
                                    (LinkedDeviceMember member) =>
                                        member.isActive ||
                                        member.role ==
                                            LinkedWorkspaceRole.owner,
                                  )
                                  .toList(growable: false)
                                ..sort((
                                  LinkedDeviceMember left,
                                  LinkedDeviceMember right,
                                ) {
                                  final leftOwner =
                                      left.role == LinkedWorkspaceRole.owner
                                      ? 0
                                      : 1;
                                  final rightOwner =
                                      right.role == LinkedWorkspaceRole.owner
                                      ? 0
                                      : 1;
                                  if (leftOwner != rightOwner) {
                                    return leftOwner.compareTo(rightOwner);
                                  }
                                  return left.deviceName.compareTo(
                                    right.deviceName,
                                  );
                                });
                          _members = nextMembers;
                          notifyListeners();
                        } catch (error) {
                          _handleSubscriptionError(
                            'member list updates',
                            error,
                          );
                        }
                      },
                      onError: (Object error) {
                        _handleSubscriptionError('member list updates', error);
                      },
                    );
              } else {
                await _membersSub?.cancel();
                _membersSub = null;
                _members = const <LinkedDeviceMember>[];
              }

              notifyListeners();
            } catch (error) {
              _handleSubscriptionError('device membership updates', error);
            }
          },
          onError: (Object error) {
            _handleSubscriptionError('device membership updates', error);
          },
        );
  }

  void _handleSubscriptionError(String source, Object error) {
    if (_isTransitioningLinkedState && _isPermissionDeniedError(error)) {
      return;
    }

    if (_isPermissionDeniedError(error)) {
      _lastError =
          'This linked device no longer has access to the saved workspace. Resetting local link state now.';
      notifyListeners();
      unawaited(_recoverFromAccessFailure());
      return;
    }

    _lastError = _describeGenericLinkedError(
      error,
      defaultMessage: 'Linked devices could not refresh $source right now.',
    );
    notifyListeners();
  }

  Future<void> _recoverFromAccessFailure() async {
    if (_isRecoveringFromAccessFailure) {
      return;
    }

    _isRecoveringFromAccessFailure = true;
    try {
      await _runDuringLinkedStateTransition(() async {
        if (hasLinkedWorkspace) {
          await _handleRevokedAccess(clearRemoteMembership: false);
          return;
        }
        await _resetInaccessibleLocalLinkState();
      });
      _lastError =
          'Linked device access was reset because the saved workspace could not be opened. '
          'You can enable linked devices again.';
      notifyListeners();
    } finally {
      _isRecoveringFromAccessFailure = false;
    }
  }

  Future<void> _resetInaccessibleLocalLinkState() async {
    _stopPresenceTracking();
    await disposeSubscriptions();
    _workspaceId = null;
    _ownerUid = null;
    _memberUid = null;
    _role = LinkedWorkspaceRole.none;
    _membershipStatus = LinkedWorkspaceMembershipStatus.unlinked;
    _latestRemoteRevision = 0;
    _lastAppliedRevision = 0;
    _members = const <LinkedDeviceMember>[];
    _lastError = null;
    _isUsingLocalWorkspace = false;
    _hasLocalWorkspaceBackup = false;
    _hasSharedWorkspaceBackup = false;

    await _database.setAppSetting(key: _workspaceIdKey, value: '');
    await _database.setAppSetting(key: _ownerUidKey, value: '');
    await _database.setAppSetting(key: _memberUidKey, value: '');
    await _database.setAppSetting(
      key: _roleKey,
      value: LinkedWorkspaceRole.none.storageValue,
    );
    await _database.setAppSetting(
      key: _membershipStatusKey,
      value: LinkedWorkspaceMembershipStatus.unlinked.storageValue,
    );
    await _database.setAppSetting(key: _lastAppliedRevisionKey, value: '0');
    await _database.setAppSetting(key: _localWorkspaceBackupKey, value: '');
    await _database.setAppSetting(key: _sharedWorkspaceBackupKey, value: '');
    await _database.setAppSetting(key: _workspaceViewKey, value: '');
  }

  Future<void> _runDuringLinkedStateTransition(
    Future<void> Function() action,
  ) async {
    final wasTransitioning = _isTransitioningLinkedState;
    _isTransitioningLinkedState = true;
    try {
      await action();
    } finally {
      _isTransitioningLinkedState = wasTransitioning;
    }
  }

  Future<bool> _detachRemoteMembershipBestEffort({
    required String workspaceId,
    required String memberUid,
  }) async {
    if ((_firestore == null) ||
        workspaceId.trim().isEmpty ||
        memberUid.trim().isEmpty) {
      return false;
    }

    try {
      await _workspaceDoc(
        workspaceId,
      ).collection('members').doc(memberUid).delete();
      return true;
    } on FirebaseException catch (_) {
      // Best-effort cleanup only. Local device state still needs to recover.
      return false;
    } catch (_) {
      // Best-effort cleanup only. Local device state still needs to recover.
      return false;
    }
  }

  Future<void> _markRemoteMembershipRevokedBestEffort({
    required String workspaceId,
    required String memberUid,
    required LinkedWorkspaceRole role,
    required String deviceName,
  }) async {
    if ((_firestore == null) ||
        workspaceId.trim().isEmpty ||
        memberUid.trim().isEmpty ||
        role == LinkedWorkspaceRole.none) {
      return;
    }

    try {
      await _workspaceDoc(
        workspaceId,
      ).collection('members').doc(memberUid).set(<String, Object?>{
        'uid': memberUid,
        'deviceName': deviceName,
        'platform': PlatformHelper.platformLabel,
        'role': role.storageValue,
        'status': LinkedWorkspaceMembershipStatus.revoked.storageValue,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedByUid': memberUid,
      }, SetOptions(merge: true));
    } on FirebaseException catch (_) {
      // Best-effort fallback only.
    } catch (_) {
      // Best-effort fallback only.
    }
  }

  Future<void> _rollbackWorkspaceCreation({
    required String workspaceId,
    required String currentUserUid,
  }) async {
    if (_firestore == null) {
      return;
    }

    try {
      await _firestore!
          .collection('workspaces')
          .doc(workspaceId)
          .collection('members')
          .doc(currentUserUid)
          .delete();
    } catch (_) {
      // Best-effort cleanup only.
    }

    try {
      await _firestore!.collection('workspaces').doc(workspaceId).delete();
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  Future<User?> _ensureSignedIn({String? expectedUid}) async {
    final auth = _auth;
    if (auth == null) {
      return null;
    }

    final requiredUid =
        (expectedUid ?? (hasLinkedWorkspace ? _memberUid : null) ?? '').trim();

    if (auth.currentUser != null) {
      if (requiredUid.isEmpty || auth.currentUser!.uid == requiredUid) {
        return auth.currentUser;
      }
    }

    final restoredUser = await _waitForRestoredAuthUser(
      auth,
      expectedUid: requiredUid.isEmpty ? null : requiredUid,
    );
    if (restoredUser != null) {
      return restoredUser;
    }

    // Never mint a brand-new anonymous account for an already-linked workspace.
    // A mismatched uid would immediately lose Firestore access and could trigger
    // destructive recovery paths on app restart.
    if (requiredUid.isNotEmpty) {
      return null;
    }

    final credential = await auth.signInAnonymously();
    return credential.user;
  }

  Future<User?> _waitForRestoredAuthUser(
    FirebaseAuth auth, {
    String? expectedUid,
  }) async {
    try {
      if ((expectedUid ?? '').trim().isNotEmpty) {
        return await auth
            .authStateChanges()
            .where(
              (User? user) => user != null && user.uid == expectedUid!.trim(),
            )
            .cast<User>()
            .first
            .timeout(_authRestoreTimeout);
      }

      return await auth
          .authStateChanges()
          .where((User? user) => user != null)
          .cast<User>()
          .first
          .timeout(_authRestoreTimeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<WorkspaceSnapshotPayload> _buildSnapshotPayload() async {
    final customers = await _database.getAllCustomersWithYear();
    final entries = await _database.getAllEntries();
    final snapshots = await _database.getAllSummarySnapshots();
    final years = await _database.getLedgerYears();
    final settingsRows = await _database.getAllAppSettings();
    final settings = <String, String>{};
    for (final row in settingsRows) {
      final key = '${row['settingKey'] ?? ''}';
      if (_isLocalOnlySetting(key)) {
        continue;
      }
      settings[key] = '${row['settingValue'] ?? ''}';
    }

    final companyName = settings['companyName']?.trim();
    final workspaceName = (companyName ?? '').isEmpty
        ? 'Balance Desk Workspace'
        : companyName!;
    final logoAsset = await _companyProfileService.exportLogoAsset();

    return WorkspaceSnapshotPayload(
      schemaVersion: _snapshotSchemaVersion,
      exportedAt: DateTime.now().toIso8601String(),
      workspaceName: workspaceName,
      customers: customers
          .map<Map<String, Object?>>(
            (Map<String, Object?> row) => <String, Object?>{
              'id': row['id'],
              'name': row['name'],
              'address': row['address'],
              'phone': row['phone'],
              'ledgerYear': row['ledgerYear'],
            },
          )
          .toList(growable: false),
      entries: entries
          .map<Map<String, Object?>>(
            (Map<String, Object?> row) => <String, Object?>{
              'id': row['id'],
              'customerId': row['customerId'],
              'entryDate': row['entryDate'],
              'createdAt': row['createdAt'],
              'pageNo': row['pageNo'],
              'description': row['description'],
              'debit': row['debit'],
              'credit': row['credit'],
            },
          )
          .toList(growable: false),
      snapshots: snapshots
          .map<Map<String, Object?>>(
            (Map<String, Object?> row) => <String, Object?>{
              'id': row['id'],
              'ledgerYear': row['ledgerYear'],
              'savedAt': row['savedAt'],
              'overallDebit': row['overallDebit'],
              'overallCredit': row['overallCredit'],
              'customerCount': row['customerCount'],
            },
          )
          .toList(growable: false),
      years: years,
      settings: settings,
      logoBase64: logoAsset == null ? null : base64Encode(logoAsset.bytes),
      logoExtension: logoAsset?.extension,
    );
  }

  Future<Map<String, String>> _loadLocalOnlySettings({
    bool includeLogoPath = true,
  }) async {
    final rows = await _database.getAllAppSettings();
    final preserved = <String, String>{};
    for (final row in rows) {
      final key = '${row['settingKey'] ?? ''}';
      if (!_isLocalOnlySetting(key)) {
        continue;
      }
      if (!includeLogoPath && key == 'companyLogoPath') {
        continue;
      }
      preserved[key] = '${row['settingValue'] ?? ''}';
    }
    return preserved;
  }

  bool _isLocalOnlySetting(String key) {
    return _localOnlySettingKeys.contains(key);
  }

  String _describeJoinWorkspaceError(Object error) {
    if (_isPermissionDeniedError(error)) {
      return 'This invite could not be accepted. Ask the owner device for a fresh QR or invite link, then try again.';
    }

    if (error is FirebaseException && error.code == 'not-found') {
      return 'This invite points to a workspace that no longer exists.';
    }

    return 'Unable to join this workspace right now. Please try again.';
  }

  Map<String, Object?> _joinMembershipData({
    required String uid,
    required String deviceName,
    required _ParsedInviteLink invite,
  }) {
    return <String, Object?>{
      'uid': uid,
      'deviceName': deviceName,
      'platform': PlatformHelper.platformLabel,
      'role': LinkedWorkspaceRole.viewer.storageValue,
      'status': LinkedWorkspaceMembershipStatus.active.storageValue,
      'inviteId': invite.inviteId,
      'inviteToken': invite.token,
      'linkedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    };
  }

  bool _isPermissionDeniedError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code == 'permission-denied' || code == 'permission denied') {
        return true;
      }
    }

    final normalizedError = '$error'.toLowerCase();
    return normalizedError.contains('permission-denied') ||
        normalizedError.contains('permission denied') ||
        normalizedError.contains('missing or insufficient permissions');
  }

  String _describeGenericLinkedError(
    Object error, {
    required String defaultMessage,
  }) {
    if (_isPermissionDeniedError(error)) {
      return 'This linked-device action needs a fresh invite, edit code, or access reset before it can continue.';
    }

    final normalizedError = '$error'.toLowerCase();
    if (normalizedError.contains('firebase') ||
        normalizedError.contains('channel-error') ||
        normalizedError.contains('failed to initialize')) {
      return 'Linked devices are unavailable on this platform until Firebase setup is complete.';
    }

    return defaultMessage;
  }

  Future<String> _loadOrCreateDeviceName() async {
    final existing = await _database.getAppSetting(_deviceNameKey);
    if ((existing ?? '').trim().isNotEmpty) {
      return existing!.trim();
    }

    final generatedName = '${PlatformHelper.platformLabel} ${_randomDigits(4)}';
    await _database.setAppSetting(key: _deviceNameKey, value: generatedName);
    return generatedName;
  }

  Future<User?> _resetAnonymousAuthForFreshJoin() async {
    final auth = _auth;
    if (auth == null) {
      return null;
    }

    try {
      await auth.signOut();
    } catch (_) {
      return null;
    }

    try {
      final credential = await auth.signInAnonymously();
      return credential.user;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveLocalLinkState({
    required String workspaceId,
    required String memberUid,
    required LinkedWorkspaceRole role,
    required LinkedWorkspaceMembershipStatus membershipStatus,
    String? ownerUid,
  }) async {
    _workspaceId = workspaceId;
    _memberUid = memberUid;
    _role = role;
    _membershipStatus = membershipStatus;
    _ownerUid = ownerUid;
    _isUsingLocalWorkspace = false;

    await _database.setAppSetting(key: _workspaceIdKey, value: workspaceId);
    await _database.setAppSetting(key: _memberUidKey, value: memberUid);
    await _database.setAppSetting(key: _roleKey, value: role.storageValue);
    await _database.setAppSetting(
      key: _membershipStatusKey,
      value: membershipStatus.storageValue,
    );
    await _database.setAppSetting(key: _ownerUidKey, value: ownerUid ?? '');
    await _database.setAppSetting(
      key: _workspaceViewKey,
      value: _workspaceViewShared,
    );
    _refreshPresenceTracking();
  }

  Future<void> _clearLocalLinkState() async {
    _stopPresenceTracking();
    _workspaceId = null;
    _ownerUid = null;
    _memberUid = null;
    _role = LinkedWorkspaceRole.none;
    _membershipStatus = LinkedWorkspaceMembershipStatus.unlinked;
    _latestRemoteRevision = 0;
    _lastAppliedRevision = 0;
    _isUsingLocalWorkspace = false;
    _hasLocalWorkspaceBackup = false;
    _hasSharedWorkspaceBackup = false;

    await _database.setAppSetting(key: _workspaceIdKey, value: '');
    await _database.setAppSetting(key: _ownerUidKey, value: '');
    await _database.setAppSetting(key: _memberUidKey, value: '');
    await _database.setAppSetting(
      key: _roleKey,
      value: LinkedWorkspaceRole.none.storageValue,
    );
    await _database.setAppSetting(
      key: _membershipStatusKey,
      value: LinkedWorkspaceMembershipStatus.unlinked.storageValue,
    );
    await _database.setAppSetting(key: _lastAppliedRevisionKey, value: '0');
    await _database.setAppSetting(key: _localWorkspaceBackupKey, value: '');
    await _database.setAppSetting(key: _sharedWorkspaceBackupKey, value: '');
    await _database.setAppSetting(key: _workspaceViewKey, value: '');
    await disposeSubscriptions();
  }

  Future<void> _cacheCurrentWorkspaceAsLocalBackupIfNeeded() async {
    if (hasLinkedWorkspace && !isUsingLocalWorkspace) {
      return;
    }
    await _cacheCurrentWorkspaceAsLocalBackup();
  }

  Future<void> _cacheCurrentWorkspaceAsLocalBackup() async {
    final payload = await _buildSnapshotPayload();
    await _saveWorkspaceBackup(
      settingKey: _localWorkspaceBackupKey,
      payload: payload,
    );
  }

  Future<void> _cacheCurrentWorkspaceAsSharedBackup() async {
    final payload = await _buildSnapshotPayload();
    await _saveWorkspaceBackup(
      settingKey: _sharedWorkspaceBackupKey,
      payload: payload,
    );
  }

  Future<void> _saveWorkspaceBackup({
    required String settingKey,
    required WorkspaceSnapshotPayload payload,
  }) async {
    await _database.setAppSetting(key: settingKey, value: payload.encode());
    if (settingKey == _localWorkspaceBackupKey) {
      _hasLocalWorkspaceBackup = true;
      return;
    }
    if (settingKey == _sharedWorkspaceBackupKey) {
      _hasSharedWorkspaceBackup = true;
    }
  }

  Future<WorkspaceSnapshotPayload?> _loadWorkspaceBackup(
    String settingKey,
  ) async {
    final encoded = (await _database.getAppSetting(settingKey))?.trim() ?? '';
    if (encoded.isEmpty) {
      return null;
    }

    try {
      return WorkspaceSnapshotPayload.fromEncoded(encoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreWorkspacePayload(
    WorkspaceSnapshotPayload payload, {
    int? revision,
    String? backupSettingKey,
  }) async {
    final preservedSettings = await _loadLocalOnlySettings();

    await _database.restoreFromCsv(
      customers: _customersCsv(payload.customers),
      entries: _entriesCsv(payload.entries),
      snapshots: _snapshotsCsv(payload.snapshots),
      years: _yearsCsv(payload.years),
      settings: _settingsCsv(<String, String>{
        ...payload.settings,
        ...preservedSettings,
      }),
    );

    if ((payload.logoBase64 ?? '').isNotEmpty) {
      final bytes = base64Decode(payload.logoBase64!);
      final logoPath = await _companyProfileService.saveLogoBytes(
        bytes: Uint8List.fromList(bytes),
        extension: payload.logoExtension ?? '.png',
      );
      if (logoPath != null && logoPath.isNotEmpty) {
        await _database.setAppSetting(key: 'companyLogoPath', value: logoPath);
      }
    } else {
      await _companyProfileService.clearLogo();
    }

    if (revision != null) {
      _lastAppliedRevision = revision;
      await _database.setAppSetting(
        key: _lastAppliedRevisionKey,
        value: '$revision',
      );
    }

    if (backupSettingKey != null) {
      await _saveWorkspaceBackup(
        settingKey: backupSettingKey,
        payload: payload,
      );
    }

    _dataVersion++;
  }

  DocumentReference<Map<String, dynamic>> _workspaceDoc(String workspaceId) {
    return _firestore!.collection('workspaces').doc(workspaceId);
  }

  List<String> _splitIntoChunks(String input) {
    if (input.isEmpty) {
      return <String>[''];
    }

    final chunks = <String>[];
    for (var start = 0; start < input.length; start += _chunkSize) {
      final end = min(start + _chunkSize, input.length);
      chunks.add(input.substring(start, end));
    }
    return chunks;
  }

  Future<LinkedActionResult> _runBusyAction(
    Future<LinkedActionResult> Function() action,
  ) async {
    if (_isBusy) {
      return const LinkedActionResult.failure(
        'Please wait for the current linked-device action to finish.',
      );
    }

    _isBusy = true;
    _lastError = null;
    notifyListeners();

    try {
      final result = await action();
      if (!result.isSuccess) {
        _lastError = result.message;
      }
      return result;
    } catch (error) {
      _lastError = _describeGenericLinkedError(
        error,
        defaultMessage: 'Linked devices action could not finish right now.',
      );
      return LinkedActionResult.failure(_lastError!);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  _ParsedInviteLink? _parseInviteLink(String rawLink) {
    final trimmed = rawLink.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return null;
    }

    final workspaceId = uri.queryParameters['workspace']?.trim() ?? '';
    final inviteId = uri.queryParameters['invite']?.trim() ?? '';
    final token = uri.queryParameters['token']?.trim() ?? '';

    if (workspaceId.isEmpty || inviteId.isEmpty || token.isEmpty) {
      return null;
    }

    return _ParsedInviteLink(
      workspaceId: workspaceId,
      inviteId: inviteId,
      token: token,
    );
  }

  String _randomToken(int length) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789abcdefghijkmnpqrstuvwxyz';
    final random = Random.secure();
    final codeUnits = List<int>.generate(
      length,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    );
    return String.fromCharCodes(codeUnits);
  }

  String _randomDigits(int length) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }

  int _nextRevisionId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final nextRevision = now > _lastGeneratedRevisionId
        ? now
        : _lastGeneratedRevisionId + 1;
    _lastGeneratedRevisionId = nextRevision;
    return nextRevision;
  }

  List<List<String>> _customersCsv(List<Map<String, Object?>> customers) {
    return <List<String>>[
      <String>['id', 'name', 'ledgerYear', 'address', 'phone'],
      ...customers.map<List<String>>((Map<String, Object?> row) {
        return <String>[
          '${row['id'] ?? ''}',
          '${row['name'] ?? ''}',
          '${row['ledgerYear'] ?? ''}',
          '${row['address'] ?? ''}',
          '${row['phone'] ?? ''}',
        ];
      }),
    ];
  }

  List<List<String>> _entriesCsv(List<Map<String, Object?>> entries) {
    return <List<String>>[
      <String>[
        'id',
        'customerId',
        'entryDate',
        'createdAt',
        'pageNo',
        'description',
        'debit',
        'credit',
      ],
      ...entries.map<List<String>>((Map<String, Object?> row) {
        return <String>[
          '${row['id'] ?? ''}',
          '${row['customerId'] ?? ''}',
          '${row['entryDate'] ?? ''}',
          '${row['createdAt'] ?? ''}',
          '${row['pageNo'] ?? ''}',
          '${row['description'] ?? ''}',
          '${row['debit'] ?? ''}',
          '${row['credit'] ?? ''}',
        ];
      }),
    ];
  }

  List<List<String>> _snapshotsCsv(List<Map<String, Object?>> snapshots) {
    return <List<String>>[
      <String>[
        'id',
        'ledgerYear',
        'savedAt',
        'overallDebit',
        'overallCredit',
        'customerCount',
      ],
      ...snapshots.map<List<String>>((Map<String, Object?> row) {
        return <String>[
          '${row['id'] ?? ''}',
          '${row['ledgerYear'] ?? ''}',
          '${row['savedAt'] ?? ''}',
          '${row['overallDebit'] ?? ''}',
          '${row['overallCredit'] ?? ''}',
          '${row['customerCount'] ?? ''}',
        ];
      }),
    ];
  }

  List<List<String>> _yearsCsv(List<int> years) {
    return <List<String>>[
      <String>['year'],
      ...years.map<List<String>>((int year) => <String>['$year']),
    ];
  }

  List<List<String>> _settingsCsv(Map<String, String> settings) {
    final sortedKeys = settings.keys.toList(growable: false)..sort();
    return <List<String>>[
      <String>['settingKey', 'settingValue'],
      ...sortedKeys.map<List<String>>((String key) {
        return <String>[key, settings[key] ?? ''];
      }),
    ];
  }
}

class _ParsedInviteLink {
  const _ParsedInviteLink({
    required this.workspaceId,
    required this.inviteId,
    required this.token,
  });

  final String workspaceId;
  final String inviteId;
  final String token;
}
