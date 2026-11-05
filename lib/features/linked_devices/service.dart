import 'package:flutter/foundation.dart';

import '../../database/app_database.dart';
import 'firestore_rest_client.dart';
import 'models.dart';
import 'identity.dart';

class LinkedDevicesException implements Exception {
  const LinkedDevicesException(this.message, {this.statusCode = 0});

  final String message;
  final int statusCode;

  bool get isQuotaExceeded => statusCode == 429;
  bool get isPermissionDenied => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class LinkedDevicesService {
  LinkedDevicesService._();

  static final LinkedDevicesService instance = LinkedDevicesService._();

  static const String workspacesCollection = 'linked_workspaces';
  static const String invitesCollection = 'linked_invites';

  static String workspacePath(String workspaceId) =>
      '$workspacesCollection/$workspaceId';

  static String _invitePath(String token) => '$invitesCollection/$token';

  static String _deviceFieldKey(String deviceId) => '\`_$deviceId\`';

  Future<LinkedWorkspaceDoc> createWorkspace({
    required String workspaceName,
  }) async {
    final String deviceId = await LinkedDeviceIdentity.deviceId();
    final String deviceName = await LinkedDeviceIdentity.deviceName();
    final String workspaceId = LinkedDeviceIdentity.newWorkspaceId();
    final String now = DatabaseHelper.syncTimestamp();

    final LinkedDevice host = LinkedDevice(
      deviceId: deviceId,
      name: deviceName,
      platform: PlatformName.current,
      permission: DevicePermission.write,
      status: DeviceStatus.active,
      role: LinkRole.host,
      joinedAt: now,
      lastSeenAt: now,
    );

    final Map<String, Object?> fields = <String, Object?>{
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'hostDeviceId': deviceId,
      'hostDeviceName': deviceName,
      'createdAt': now,
      'dataChangedAt': now,
      'devices': <String, Object?>{deviceId: host.toMap()},
    };

    await _guard(
      () => FirestoreRestClient.setDocument(workspacePath(workspaceId), fields),
    );

    return LinkedWorkspaceDoc.fromMap(fields)!;
  }

  Future<LinkedWorkspaceDoc?> fetchWorkspace(String workspaceId) async {
    final Map<String, Object?>? raw = await _guard(
      () => FirestoreRestClient.getDocument(workspacePath(workspaceId)),
    );
    return LinkedWorkspaceDoc.fromMap(raw);
  }

  Stream<LinkedWorkspaceDoc?> watchWorkspace(String workspaceId) {
    return FirestoreRestClient.watchDocument(workspacePath(workspaceId))
        .map(LinkedWorkspaceDoc.fromMap);
  }

  Future<void> renameWorkspace({
    required String workspaceId,
    required String workspaceName,
  }) async {
    await _guard(
      () => FirestoreRestClient.updateDocument(
        workspacePath(workspaceId),
        <String, Object?>{'workspaceName': workspaceName},
      ),
    );
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    await _guard(
      () => FirestoreRestClient.deleteDocument(workspacePath(workspaceId)),
    );
    await purgeWorkspaceData(workspaceId);
  }

  static const List<String> syncedCollections = <String>[
    'entries',
    'summary_snapshots',
    'customers',
    'ledger_years',
    'app_settings',
  ];

  Future<int> purgeWorkspaceData(String workspaceId) async {
    const int pageSize = 200;
    const int maxPagesPerCollection = 25;
    final String parentPath = workspacePath(workspaceId);

    int deleted = 0;
    for (final String collection in syncedCollections) {
      for (int page = 0; page < maxPagesPerCollection; page++) {
        List<Map<String, Object?>> documents;
        try {
          documents = await FirestoreRestClient.queryPage(
            parentPath: parentPath,
            collectionId: collection,
            limit: pageSize,
          );
        } catch (error) {
          debugPrint('Purge $collection stopped: $error');
          break;
        }
        if (documents.isEmpty) break;

        for (final Map<String, Object?> document in documents) {
          final String? id = document['__id'] as String?;
          if (id == null || id.isEmpty) continue;
          try {
            await FirestoreRestClient.deleteDocument(
              '$parentPath/$collection/$id',
            );
            deleted++;
          } catch (error) {
            debugPrint('Purge $collection/$id failed: $error');
          }
        }
      }
      if (deleted > 0) {
        debugPrint('Purged $deleted workspace records so far ($collection)');
      }
    }

    return deleted;
  }

  Future<LinkedInvite> createInvite({
    required LinkedWorkspaceDoc workspace,
  }) async {
    final String token = LinkedDeviceIdentity.newInviteToken();
    final DateTime expiry = DateTime.now().toUtc().add(LinkedInvite.validity);

    final LinkedInvite invite = LinkedInvite(
      token: token,
      workspaceId: workspace.workspaceId,
      workspaceName: workspace.workspaceName,
      hostDeviceName: workspace.hostDeviceName,
      expiresAt: DatabaseHelper.syncTimestamp(expiry),
      consumed: false,
    );

    await _guard(() async {
      await FirestoreRestClient.setDocument(_invitePath(token), invite.toMap());
      await FirestoreRestClient.updateDocument(
        workspacePath(workspace.workspaceId),
        <String, Object?>{'invite': invite.toMap()},
      );
    });

    return invite;
  }

  Future<LinkedInvite?> lookupInvite(String token) async {
    final Map<String, Object?>? raw = await _guard(
      () => FirestoreRestClient.getDocument(_invitePath(token)),
    );
    return LinkedInvite.fromMap(raw);
  }

  Future<void> revokeInvite({
    required String workspaceId,
    required String token,
  }) async {
    await _guard(() async {
      await FirestoreRestClient.updateDocument(
        _invitePath(token),
        <String, Object?>{'consumed': true},
      );
      await FirestoreRestClient.updateDocument(
        workspacePath(workspaceId),
        <String, Object?>{'invite': null},
      );
    });
  }

  Future<LinkedWorkspaceDoc> joinWorkspace(String rawToken) async {
    final String token = normaliseToken(rawToken);
    if (token.isEmpty) {
      throw const LinkedDevicesException(
        'Enter the invite code from the main device.',
      );
    }

    final LinkedInvite? invite = await lookupInvite(token);
    if (invite == null) {
      throw const LinkedDevicesException(
        'That invite code was not found. Check it and try again.',
      );
    }
    if (invite.consumed) {
      throw const LinkedDevicesException(
        'That invite code has already been used. Ask for a new one.',
      );
    }
    if (invite.isExpired) {
      throw const LinkedDevicesException(
        'That invite code has expired. Ask for a new one.',
      );
    }

    final LinkedWorkspaceDoc? workspace = await fetchWorkspace(
      invite.workspaceId,
    );
    if (workspace == null) {
      throw const LinkedDevicesException(
        'The shared workspace no longer exists on the main device.',
      );
    }

    final String deviceId = await LinkedDeviceIdentity.deviceId();
    final String deviceName = await LinkedDeviceIdentity.deviceName();
    final String now = DatabaseHelper.syncTimestamp();
    final LinkedDevice? existing = workspace.deviceById(deviceId);

    final LinkedDevice self = LinkedDevice(
      deviceId: deviceId,
      name: existing?.name ?? deviceName,
      platform: PlatformName.current,
      permission: existing?.permission ?? DevicePermission.write,
      status: DeviceStatus.active,
      role: existing?.role ?? LinkRole.guest,
      joinedAt: existing?.joinedAt ?? now,
      lastSeenAt: now,
    );

    await _guard(() async {
      await FirestoreRestClient.updateDocument(
        workspacePath(workspace.workspaceId),
        <String, Object?>{
          'devices': <String, Object?>{deviceId: self.toMap()},
        },
        fieldPaths: <String>['devices.${_deviceFieldKey(deviceId)}'],
      );
      await FirestoreRestClient.updateDocument(
        _invitePath(token),
        <String, Object?>{'consumed': true},
      );
    });

    return (await fetchWorkspace(workspace.workspaceId)) ?? workspace;
  }

  static String normaliseToken(String value) {
    String candidate = value.trim();
    if (candidate.isEmpty) return '';

    final Uri? uri = Uri.tryParse(candidate);
    final String? fromQuery = uri?.queryParameters['token'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) {
      candidate = fromQuery.trim();
    } else {
      final Match? match = RegExp(
        r'token=([A-Za-z0-9]+)',
      ).firstMatch(candidate);
      if (match != null) candidate = match.group(1)!;
    }

    return candidate.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  Future<void> setDevicePermission({
    required String workspaceId,
    required String deviceId,
    required DevicePermission permission,
  }) async {
    await _mutateDevice(
      workspaceId: workspaceId,
      deviceId: deviceId,
      fields: <String, Object?>{'permission': permission.wireValue},
    );
  }

  Future<void> renameDevice({
    required String workspaceId,
    required String deviceId,
    required String name,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _mutateDevice(
      workspaceId: workspaceId,
      deviceId: deviceId,
      fields: <String, Object?>{'name': trimmed},
    );
  }

  Future<void> removeDevice({
    required String workspaceId,
    required String deviceId,
  }) async {
    await _mutateDevice(
      workspaceId: workspaceId,
      deviceId: deviceId,
      fields: <String, Object?>{
        'status': DeviceStatus.removed.wireValue,
        'permission': DevicePermission.read.wireValue,
      },
    );
  }

  Future<void> touchDevice({
    required String workspaceId,
    required String deviceId,
  }) async {
    final LinkedWorkspaceDoc? workspace = await fetchWorkspace(workspaceId);
    if (workspace == null || workspace.deviceById(deviceId) == null) return;

    await _guard(
      () => FirestoreRestClient.updateDocument(
        workspacePath(workspaceId),
        <String, Object?>{
          'devices': <String, Object?>{
            deviceId: <String, Object?>{
              'lastSeenAt': DatabaseHelper.syncTimestamp(),
            },
          },
        },
        fieldPaths: <String>['devices.${_deviceFieldKey(deviceId)}.lastSeenAt'],
      ),
    );
  }

  Future<String> markDataChanged(String workspaceId) async {
    final String stamp = DatabaseHelper.syncTimestamp();
    await _guard(
      () => FirestoreRestClient.updateDocument(
        workspacePath(workspaceId),
        <String, Object?>{'dataChangedAt': stamp},
      ),
    );
    return stamp;
  }

  Future<void> _mutateDevice({
    required String workspaceId,
    required String deviceId,
    required Map<String, Object?> fields,
  }) async {
    if (fields.isEmpty) return;

    final LinkedWorkspaceDoc? workspace = await fetchWorkspace(workspaceId);
    if (workspace == null) {
      throw const LinkedDevicesException(
        'The shared workspace could not be reached.',
      );
    }

    if (workspace.deviceById(deviceId) == null) {
      throw const LinkedDevicesException(
        'That device is no longer part of the workspace.',
      );
    }

    await _guard(
      () => FirestoreRestClient.updateDocument(
        workspacePath(workspaceId),
        <String, Object?>{
          'devices': <String, Object?>{deviceId: fields},
        },
        fieldPaths: fields.keys
            .map((String field) => 'devices.${_deviceFieldKey(deviceId)}.$field')
            .toList(growable: false),
      ),
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirestoreException catch (error) {
      debugPrint('LinkedDevicesService failed: $error');
      throw LinkedDevicesException(
        describeFirestoreError(error),
        statusCode: error.statusCode,
      );
    } catch (error) {
      throw LinkedDevicesException(error.toString());
    }
  }

  static String describeFirestoreError(FirestoreException error) {
    if (error.isOffline) {
      return 'No internet connection. Changes are saved on this device and '
          'will sync automatically.';
    }
    if (error.isPermissionDenied) {
      final String raw = error.message.toLowerCase();
      if (raw.contains('has not been used in project') ||
          raw.contains('is disabled') ||
          raw.contains('service_disabled')) {
        return 'Cloud Firestore API is not enabled. Please enable it in the '
            'Google Cloud console.';
      }
      return 'The cloud rejected the request. Please check your Firebase '
          'configuration.';
    }
    if (error.isQuotaExceeded) {
      return 'Daily cloud limit reached. Sync will resume tomorrow; your data '
          'stays safe on this device.';
    }
    return 'Cloud sync failed: ${error.message}';
  }
}

class PlatformName {
  PlatformName._();

  static String get current {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
    }
  }
}