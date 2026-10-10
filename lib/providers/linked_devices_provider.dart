import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/link_invite.dart';
import '../models/linked_device.dart';
import '../services/app_deep_link_service.dart';
import '../services/firebase/firebase_options.dart';
import '../services/sync/device_identity_service.dart';
import '../services/sync/link_service.dart';
import '../services/sync/sync_engine.dart';
import '../services/workspace_service.dart';

/// UI-facing state for the Linked Devices feature.
///
/// Owns the [SyncEngine] lifetime and translates its low-level state into
/// something the screens can render. It deliberately touches no ledger
/// calculation: applying remote rows simply notifies
/// `AppDatabase.onDataChanged`, which the existing providers already listen
/// to.
class LinkedDevicesProvider extends ChangeNotifier {
  LinkedDevicesProvider({SyncEngine? engine})
      : _engine = engine ??
            SyncEngine(
              database: () => AppDatabase.instance.database,
            ) {
    _engine.onDataChanged = AppDatabase.instance.notifyDataChanged;
    _deepLinkSub = AppDeepLinkService.instance.inviteLinks.listen(
      (PendingInviteLink link) {
        _pendingLink = link;
        notifyListeners();
      },
    );
    _pendingLink = AppDeepLinkService.instance.pendingInvite;
  }

  final SyncEngine _engine;

  StreamSubscription<PendingInviteLink>? _deepLinkSub;
  StreamSubscription<List<LinkedDevice>>? _membersSub;

  List<LinkedDevice> _devices = <LinkedDevice>[];
  LinkInvite? _activeInvite;
  PendingInviteLink? _pendingLink;
  DeviceRole? _myRole;
  bool _busy = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _bootstrapped = false;

  // ------------------------------------------------------------- read-only

  bool get isFirebaseConfigured => DefaultFirebaseOptions.isConfigured;

  SyncStatus get status => _engine.status;
  String? get statusMessage => _engine.statusMessage;
  String? get workspaceId => _engine.workspaceId;
  bool get isLinked => _engine.isLinked;
  int get pendingCount => _engine.pendingCount;
  int get appliedCount => _engine.appliedCount;

  List<LinkedDevice> get devices => List<LinkedDevice>.unmodifiable(_devices);

  int get deviceCount => _devices.length;

  DeviceRole? get myRole => _myRole;

  bool get canManageDevices => _myRole == DeviceRole.owner;

  bool get canEditLedger => _myRole?.canEditLedger ?? true;

  LinkedDevice? get thisDevice {
    final String id = DeviceIdentityService.instance.deviceId;
    for (final LinkedDevice device in _devices) {
      if (device.deviceId == id) {
        return device;
      }
    }
    return null;
  }

  LinkInvite? get activeInvite => _activeInvite;
  PendingInviteLink? get pendingLink => _pendingLink;
  bool get hasPendingLink => _pendingLink != null;
  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;

  String get deviceName => DeviceIdentityService.instance.displayName;
  String get deviceId => DeviceIdentityService.instance.deviceId;

  // --------------------------------------------------------------- actions

  /// Called once after the app starts: makes sure identity exists and, when
  /// Firebase is configured, resumes the previous link.
  Future<void> bootstrap() async {
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;

    if (!isFirebaseConfigured) {
      _engine.markDisabled();
      notifyListeners();
      return;
    }

    await DeviceIdentityService.instance.initialize();
    await _engine.restore();
    if (_engine.isLinked) {
      _watchMembers(_engine.workspaceId!);
      await _refreshMyRole(_engine.workspaceId!);
    }
    notifyListeners();
  }

  /// Creates a workspace for the current local workspace and publishes the
  /// whole ledger so the first invited device has something to receive.
  Future<bool> startSharing() async {
    return _guard(() async {
      await DeviceIdentityService.instance.initialize();

      final String workspaceId = _newWorkspaceId();
      final String name = WorkspaceService.instance.activeWorkspace.name;

      await _engine.linkService.createWorkspace(
        workspaceId: workspaceId,
        name: name.trim().isEmpty ? 'Balance Desk' : name.trim(),
      );
      await _engine.start(workspaceId);
      await _engine.publishFullSnapshot();

      _watchMembers(workspaceId);
      await _refreshMyRole(workspaceId);

      _infoMessage = 'This device is now the owner. Invite another device to link it.';
    });
  }

  /// Mints a new invite (QR + pasteable link).
  Future<LinkInvite?> createInvite({
    DeviceRole role = DeviceRole.viewer,
    Duration ttl = const Duration(minutes: 15),
    int maxUses = 5,
  }) async {
    final String? workspaceId = _engine.workspaceId;
    if (workspaceId == null) {
      _errorMessage = 'Start sharing before inviting a device.';
      notifyListeners();
      return null;
    }

    try {
      _setBusy(true);
      final LinkInvite invite = await _engine.linkService.createInvite(
        workspaceId: workspaceId,
        role: role,
        ttl: ttl,
        maxUses: maxUses,
      );
      _activeInvite = invite;
      _errorMessage = null;
      return invite;
    } on LinkServiceException catch (error) {
      _errorMessage = error.message;
      return null;
    } catch (error) {
      _errorMessage = 'Could not create the invite: $error';
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> revokeActiveInvite() async {
    final LinkInvite? invite = _activeInvite;
    final String? workspaceId = _engine.workspaceId;
    if (invite == null || workspaceId == null) {
      return;
    }
    await _guard(() async {
      await _engine.linkService.revokeInvite(
        workspaceId: workspaceId,
        token: invite.token,
      );
      _activeInvite = null;
      _infoMessage = 'Invite revoked.';
    });
  }

  /// Redeems an invite link that arrived through the OS (deep link).
  Future<bool> acceptPendingLink() async {
    final PendingInviteLink? link = _pendingLink;
    if (link == null) {
      return false;
    }
    final bool ok = await joinWorkspace(
      workspaceId: link.workspaceId,
      token: link.token,
    );
    _pendingLink = null;
    AppDeepLinkService.instance.clearPendingInvite();
    notifyListeners();
    return ok;
  }

  void dismissPendingLink() {
    _pendingLink = null;
    AppDeepLinkService.instance.clearPendingInvite();
    notifyListeners();
  }

  /// Joins a workspace with a pasted invite code, or a full invite link.
  Future<bool> joinWorkspace({
    required String workspaceId,
    required String token,
  }) async {
    return _guard(() async {
      await DeviceIdentityService.instance.initialize();

      final DeviceRole role = await _engine.linkService.joinWorkspace(
        workspaceId: workspaceId,
        token: token,
      );

      await _engine.start(workspaceId);
      await _engine.catchUp();

      _watchMembers(workspaceId);
      await _refreshMyRole(workspaceId);

      _infoMessage = role == DeviceRole.editor
          ? 'Linked with edit access.'
          : 'Linked in view-only mode. Ask the owner for edit access.';
    });
  }

  /// Accepts raw user input: either a full link or a bare token. The
  /// workspace id is required for a bare token.
  Future<bool> joinFromUserInput({
    required String input,
    String? fallbackWorkspaceId,
  }) async {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      _errorMessage = 'Paste the invite link or code first.';
      notifyListeners();
      return false;
    }

    final PendingInviteLink? parsed =
        AppDeepLinkService.parseInviteLink(trimmed);
    if (parsed != null) {
      return joinWorkspace(
        workspaceId: parsed.workspaceId,
        token: parsed.token,
      );
    }

    if (fallbackWorkspaceId == null || fallbackWorkspaceId.isEmpty) {
      _errorMessage =
          'That does not look like an invite link. Paste the full '
          'balancedesk://link-device link.';
      notifyListeners();
      return false;
    }

    return joinWorkspace(workspaceId: fallbackWorkspaceId, token: trimmed);
  }

  Future<void> changeRole(LinkedDevice device, DeviceRole role) async {
    final String? workspaceId = _engine.workspaceId;
    if (workspaceId == null || device.uid.isEmpty) {
      return;
    }
    await _guard(() async {
      await _engine.linkService.setMemberRole(
        workspaceId: workspaceId,
        memberUid: device.uid,
        role: role,
      );
      _infoMessage = '${device.displayName} is now ${role.label.toLowerCase()}.';
      await _refreshMyRole(workspaceId);
    });
  }

  /// Owner removes a device from the workspace.
  Future<void> unlinkDevice(LinkedDevice device) async {
    final String? workspaceId = _engine.workspaceId;
    if (workspaceId == null) {
      return;
    }
    await _guard(() async {
      await _engine.linkService.removeMember(
        workspaceId: workspaceId,
        memberUid: device.uid,
      );
      _infoMessage = '${device.displayName} was unlinked.';
    });
  }

  /// This device leaves the workspace and stops syncing.
  Future<void> leaveWorkspace() async {
    final String? workspaceId = _engine.workspaceId;
    if (workspaceId == null) {
      return;
    }
    await _guard(() async {
      await _engine.linkService.leaveWorkspace(workspaceId);
      await _engine.stop();
      await _membersSub?.cancel();
      _membersSub = null;
      _devices = <LinkedDevice>[];
      _myRole = null;
      _activeInvite = null;
      _infoMessage = 'This device is no longer linked.';
    });
  }

  Future<void> renameThisDevice(String name) async {
    await DeviceIdentityService.instance.rename(name);
    final String? workspaceId = _engine.workspaceId;
    if (workspaceId != null) {
      await _engine.linkService.heartbeat(workspaceId);
    }
    notifyListeners();
  }

  Future<void> syncNow() async {
    await _engine.catchUp();
    await _engine.pushPending();
  }

  void clearMessages() {
    if (_errorMessage == null && _infoMessage == null) {
      return;
    }
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  // --------------------------------------------------------------- internal

  void _watchMembers(String workspaceId) {
    _membersSub?.cancel();
    _membersSub = _engine.linkService.watchMembers(workspaceId).listen(
      (List<LinkedDevice> members) {
        _devices = members;
        notifyListeners();
      },
      onError: (Object error) {
        _errorMessage = 'Could not load linked devices: $error';
        notifyListeners();
      },
    );
  }

  Future<void> _refreshMyRole(String workspaceId) async {
    try {
      _myRole = await _engine.linkService.readMyRole(workspaceId);
    } catch (_) {
      _myRole = null;
    }
  }

  /// Runs [action] with busy/error plumbing. Returns true on success.
  Future<bool> _guard(Future<void> Function() action) async {
    _setBusy(true);
    _errorMessage = null;
    try {
      await action();
      return true;
    } on LinkServiceException catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (error) {
      _errorMessage = 'Something went wrong: $error';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  static String _newWorkspaceId() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(10, (_) => random.nextInt(256));
    return 'ws-${sha256.convert(bytes).toString().substring(0, 20)}';
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _membersSub?.cancel();
    _engine.dispose();
    super.dispose();
  }
}
