import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../firebase_options.dart';
import '../../../models/linked_device_models.dart';
import 'firestore_rest_client.dart';

class LinkedDevicesService {
  LinkedDevicesService._();
  static final LinkedDevicesService instance = LinkedDevicesService._();

  bool get _isDesktop => _isRunningOnDesktop;

  Future<FirebaseFirestore> get _db async {
    if (_canUseSdk) await _ensureInitialized();
    return FirebaseFirestore.instance;
  }

  static bool _initialized = false;
  static Future<void>? _initFuture;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (_initFuture != null) return _initFuture;

    _initFuture = _doInit();
    await _initFuture;
  }

  /// Public entry point to guarantee Firebase is ready before any _db access.
  /// Desktop uses REST API, so Firebase initialization is not needed.
  static Future<void> ensureFirebase() async {
    if (_isRunningOnDesktop) return;
    await _ensureInitialized();
  }

  static Future<T> _retrySdk<T>(Future<T> Function() fn) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await fn();
      } on FirebaseException catch (e) {
        if (e.code == 'resource-exhausted') rethrow; // quota — don't retry
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        rethrow;
      } on TimeoutException {
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        rethrow;
      }
    }
    throw TimeoutException('Firestore write timed out after retries');
  }

  static bool get _isRunningOnDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static bool get _isWindowsOrLinux =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get _canUseSdk =>
      !_isWindowsOrLinux;

  static Future<void> _doInit() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _initialized = true;
    } catch (e) {
      _initFuture = null;
      debugPrint('Firebase Lazy Init Error: $e');
    }
  }

  // ── Collection paths ──
  static const String _invitesCol = 'linked_invites';
  static const String _sessionsCol = 'linked_sessions';

  // ────────────────────────────────────────────────────────
  // ADMIN: Register this device as admin & generate invite
  // ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> registerAsAdmin(
    String deviceId,
    String deviceName,
  ) async {
    final token = _generateToken();
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    try {
      await _expireOpenInvitesForAdmin(deviceId);

      final data = {
        'adminDeviceId': deviceId,
        'adminDeviceName': deviceName,
        'token': token,
        'expiresAt': expiry.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'used': false,
        'revoked': false,
      };

      if (_isDesktop) {
        final success = await FirestoreRESTClient.setDocument(
          _invitesCol,
          token,
          data,
        );
        if (!success) throw Exception('REST set failed');
      } else {
        await _retrySdk(() async => (await _db).collection(_invitesCol).doc(token).set(data));
      }

      return {'success': true, 'inviteToken': token, 'expiresAt': expiry};
    } catch (e) {
      debugPrint('registerAsAdmin error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ────────────────────────────────────────────────────────
  // GUEST: Join workspace using invite token
  // ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> joinWorkspace(
    String joiningDeviceId,
    String token, {
    String? joiningDeviceName,
  }) async {
    try {
      final inviteToken = token.trim().toUpperCase();
      Map<String, dynamic>? inviteData;
      if (_isDesktop) {
        inviteData = await FirestoreRESTClient.getDocument(
          _invitesCol,
          inviteToken,
        );
      } else {
        final snap = await (await _db).collection(_invitesCol).doc(inviteToken).get().timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Firestore read timed out'),
        );
        inviteData = snap.data();
      }

      if (inviteData == null) {
        return {'success': false, 'error': 'Invalid or expired invite code.'};
      }

      final expiresAt = DateTime.tryParse(
        inviteData['expiresAt'] as String? ?? '',
      );
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        return {'success': false, 'error': 'Invite code has expired.'};
      }
      if (inviteData['used'] == true || inviteData['revoked'] == true) {
        return {
          'success': false,
          'error': 'Invite code has already been used.',
        };
      }

      final adminDeviceId = inviteData['adminDeviceId'] as String;
      final adminDeviceName = inviteData['adminDeviceName']?.toString();
      final sessionId = 'session_${joiningDeviceId}_$adminDeviceId';
      final sessionData = {
        'sessionId': sessionId,
        'adminDeviceId': adminDeviceId,
        'adminDeviceName': adminDeviceName,
        'linkedDeviceId': joiningDeviceId,
        'linkedDeviceName': joiningDeviceName,
        'permission': 'read',
        'editableCode': null,
        'editableCodeExpiresAt': null,
        'status': 'active',
        'joinedAt': DateTime.now().toIso8601String(),
        'lastSnapshotAt': null,
        'lastGuestSnapshotAt': null,
        'lastAdminAppliedGuestSnapshotAt': null,
      };

      if (_isDesktop) {
        await FirestoreRESTClient.setDocument(
          _sessionsCol,
          sessionId,
          sessionData,
        );
        await FirestoreRESTClient.updateDocument(_invitesCol, inviteToken, {
          'used': true,
          'usedAt': DateTime.now().toIso8601String(),
          'usedByDeviceId': joiningDeviceId,
        });
      } else {
        await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).set(sessionData).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Firestore write timed out'),
        ));
        await _retrySdk(() async => (await _db).collection(_invitesCol).doc(inviteToken).update({
          'used': true,
          'usedAt': DateTime.now().toIso8601String(),
          'usedByDeviceId': joiningDeviceId,
        }).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Firestore write timed out'),
        ));
      }

      return {
        'success': true,
        'sessionId': sessionId,
        'adminDeviceId': adminDeviceId,
        'adminDeviceName': adminDeviceName,
      };
    } catch (e) {
      debugPrint('joinWorkspace error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ────────────────────────────────────────────────────────
  // ADMIN: Stream of all active sessions for this admin
  // ────────────────────────────────────────────────────────
  Stream<List<LinkedSession>> activeSessionsStream(String adminDeviceId) {
    if (_canUseSdk) {
      final controller = StreamController<List<LinkedSession>>.broadcast();
      _db.then((db) {
        db.collection(_sessionsCol)
            .where('adminDeviceId', isEqualTo: adminDeviceId)
            .snapshots()
            .map(
              (snap) => snap.docs
                  .map((d) => d.data())
                  .where((m) => m['status'] == 'active')
                  .map((m) => LinkedSession.fromMap(m))
                  .toList(),
            )
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
      });
      return controller.stream;
    }

    final controller = StreamController<List<LinkedSession>>();
    Timer? timer;

    void fetchData() async {
      final results = await FirestoreRESTClient.getCollection(
        _sessionsCol,
        whereField: 'adminDeviceId',
        isEqualTo: adminDeviceId,
      );
      if (!controller.isClosed) {
        controller.add(
          results
              .where((m) => m['status'] == 'active')
              .map((m) => LinkedSession.fromMap(m))
              .toList(),
        );
      }
    }

    timer = Timer.periodic(const Duration(seconds: 2), (_) => fetchData());
    fetchData();

    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  /// One-time fetch of active linked device IDs for an admin (bi-directional sync).
  Future<List<String>> getActiveLinkedDeviceIds(String adminDeviceId) async {
    try {
      List<Map<String, dynamic>> results;
      if (_isDesktop) {
        results = await FirestoreRESTClient.getCollection(
          _sessionsCol,
          whereField: 'adminDeviceId',
          isEqualTo: adminDeviceId,
        );
      } else {
        final snap = await (await _db)
            .collection(_sessionsCol)
            .where('adminDeviceId', isEqualTo: adminDeviceId)
            .get();
        results = snap.docs.map((d) => d.data()).toList();
      }
      return results
          .where((m) => m['status'] == 'active')
          .map((m) => m['linkedDeviceId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('getActiveLinkedDeviceIds error: $e');
      return [];
    }
  }

  /// One-time fetch of all active sessions for an admin.
  Future<List<LinkedSession>> getAllActiveSessions(String adminDeviceId) async {
    try {
      List<Map<String, dynamic>> results;
      if (_isDesktop) {
        results = await FirestoreRESTClient.getCollection(
          _sessionsCol,
          whereField: 'adminDeviceId',
          isEqualTo: adminDeviceId,
        );
      } else {
        final snap = await (await _db)
            .collection(_sessionsCol)
            .where('adminDeviceId', isEqualTo: adminDeviceId)
            .get();
        results = snap.docs.map((d) => d.data()).toList();
      }
      return results
          .where((m) => m['status'] == 'active')
          .map((m) => LinkedSession.fromMap(m))
          .toList();
    } catch (e) {
      debugPrint('getAllActiveSessions error: $e');
      return [];
    }
  }

  // ────────────────────────────────────────────────────────
  // GUEST: Real-time stream for a specific session
  // ────────────────────────────────────────────────────────
  /// Returns session data as a stream. On mobile/macOS returns [DocumentSnapshot],
  /// on Windows/Linux returns [Map] with `exists` and `data` keys.
  Stream<dynamic> sessionStream(String sessionId) {
    if (_canUseSdk) {
      final controller = StreamController<dynamic>.broadcast();
      _db.then((db) {
        db.collection(_sessionsCol).doc(sessionId).snapshots().listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      });
      return controller.stream;
    }

    final controller = StreamController<dynamic>();
    Timer? timer;

    void fetchData() async {
      final data = await FirestoreRESTClient.getDocument(
        _sessionsCol,
        sessionId,
      );
      if (!controller.isClosed) {
        controller.add({
          'exists': data != null,
          'data': data,
          'status': data?['status'] ?? 'disconnected',
          'permission': data?['permission'] ?? 'read',
        });
      }
    }

    timer = Timer.periodic(const Duration(seconds: 2), (_) => fetchData());
    fetchData();

    controller.onCancel = () => timer?.cancel();
    return controller.stream;
  }

  Future<LinkedSession?> getSession(String sessionId) async {
    try {
      Map<String, dynamic>? data;
      if (_isDesktop) {
        data = await FirestoreRESTClient.getDocument(_sessionsCol, sessionId);
      } else {
        final snap = await (await _db).collection(_sessionsCol).doc(sessionId).get();
        data = snap.data();
      }
      if (data == null || data['status'] != 'active') return null;
      return LinkedSession.fromMap(data);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateSessionPermission(
    String sessionId,
    SessionPermission permission,
  ) async {
    final permStr = permission == SessionPermission.write ? 'write' : 'read';
    final data = {
      'permission': permStr,
      'editableCode': null,
      'editableCodeExpiresAt': null,
    };
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, data);
    } else {
      await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).update(data));
    }
  }

  Future<void> disconnectSession(String sessionId) async {
    final data = {
      'status': 'disconnected',
      'disconnectedAt': DateTime.now().toIso8601String(),
    };
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, data);
    } else {
      await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).update(data));
    }
  }



  Future<String> generateEditableCode(
    String sessionId,
    String adminDeviceId,
  ) async {
    final code = _generateOtp();
    final expiry = DateTime.now().add(const Duration(minutes: 10));
    final data = {
      'editableCode': code,
      'editableCodeExpiresAt': expiry.toIso8601String(),
      'editableCodeGeneratedAt': DateTime.now().toIso8601String(),
      'permission': 'read',
    };
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, data);
    } else {
      await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).update(data));
    }
    return code;
  }

  Future<void> revokeEditAccess(String sessionId) async {
    final data = {
      'permission': 'read',
      'editableCode': null,
      'editableCodeExpiresAt': null,
    };
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, data);
    } else {
      await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).update(data));
    }
  }

  /// Update a field in the session document.
  Future<void> updateSessionField(
    String sessionId,
    Map<String, dynamic> fields,
  ) async {
    try {
      if (_isDesktop) {
        await FirestoreRESTClient.updateDocument(
          _sessionsCol,
          sessionId,
          fields,
        );
      } else {
        await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).update(fields));
      }
    } catch (e) {
      debugPrint('updateSessionField error: $e');
    }
  }

  Future<Map<String, dynamic>> verifyEditCode(
    String sessionId,
    String enteredCode,
  ) async {
    try {
      Map<String, dynamic>? data;
      if (_isDesktop) {
        data = await FirestoreRESTClient.getDocument(_sessionsCol, sessionId);
      } else {
        final doc = await (await _db).collection(_sessionsCol).doc(sessionId).get();
        data = doc.data();
      }

      if (data == null) {
        return {'success': false, 'error': 'Session not found.'};
      }

      final rawStoredCode = data['editableCode']?.toString();
      final storedCode = rawStoredCode == 'null' ? null : rawStoredCode;
      if (storedCode == null || storedCode.isEmpty) {
        return {'success': false, 'error': 'No edit code generated.'};
      }
      if (storedCode.trim() != enteredCode.trim()) {
        return {'success': false, 'error': 'Incorrect code.'};
      }

      final expiresAtStr = data['editableCodeExpiresAt'] as String?;
      if (expiresAtStr != null) {
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
          return {'success': false, 'error': 'Edit code has expired.'};
        }
      }

      final updateData = {
        'permission': 'write',
        'editableCode': null,
        'editableCodeExpiresAt': null,
      };
      if (_isDesktop) {
        await FirestoreRESTClient.updateDocument(
          _sessionsCol,
          sessionId,
          updateData,
        );
      } else {
        await _retrySdk(() async => (await _db).collection(_sessionsCol).doc(sessionId).update(updateData));
      }
      return {'success': true};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  String _generateToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(8, (i) => chars[rand.nextInt(chars.length)]).join();
  }

  String _generateOtp() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  Future<void> _expireOpenInvitesForAdmin(String adminDeviceId) async {
    try {
      final now = DateTime.now().toIso8601String();
      if (_isDesktop) {
        final invites = await FirestoreRESTClient.getCollection(
          _invitesCol,
          whereField: 'adminDeviceId',
          isEqualTo: adminDeviceId,
        );
        for (final invite in invites) {
          final docId = invite['id']?.toString();
          if (docId == null || docId.isEmpty) continue;
          if (invite['used'] == true || invite['revoked'] == true) continue;
          await FirestoreRESTClient.updateDocument(_invitesCol, docId, {
            'used': true,
            'revoked': true,
            'expiresAt': now,
            'revokedAt': now,
          });
        }
        return;
      }

      final snap = await (await _db)
          .collection(_invitesCol)
          .where('adminDeviceId', isEqualTo: adminDeviceId)
          .where('used', isEqualTo: false)
          .get()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('Firestore read timed out'),
          );
      for (final doc in snap.docs) {
        await _retrySdk(() => doc.reference.update({
          'used': true,
          'revoked': true,
          'expiresAt': now,
          'revokedAt': now,
        }));
      }
    } catch (e) {
      debugPrint('expireOpenInvitesForAdmin error: $e');
    }
  }
}
