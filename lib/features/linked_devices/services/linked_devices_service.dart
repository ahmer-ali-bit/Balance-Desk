import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../firebase_options.dart';
import '../.././../models/linked_device_models.dart';
import 'firestore_rest_client.dart';

class LinkedDevicesService {
  LinkedDevicesService._();
  static final LinkedDevicesService instance = LinkedDevicesService._();

  bool get _isDesktop => !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.macOS);

  FirebaseFirestore get _db {
    if (!_isDesktop) _ensureInitialized();
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

  static Future<void> _doInit() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('Firebase Lazy Init Error: $e');
    }
  }

  // ── Collection paths ──
  static const String _invitesCol = 'linked_invites';
  static const String _sessionsCol = 'linked_sessions';

  // ────────────────────────────────────────────────────────
  // ADMIN: Register this device as admin & generate invite
  // ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> registerAsAdmin(String deviceId, String deviceName) async {
    final token = _generateToken();
    final expiry = DateTime.now().add(const Duration(hours: 24));
    final data = {
      'adminDeviceId': deviceId,
      'adminDeviceName': deviceName,
      'token': token,
      'expiresAt': expiry.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'used': false,
    };

    try {
      if (_isDesktop) {
        final success = await FirestoreRESTClient.setDocument(_invitesCol, token, data);
        if (!success) throw Exception('REST set failed');
      } else {
        await _db.collection(_invitesCol).doc(token).set(data);
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
  Future<Map<String, dynamic>> joinWorkspace(String joiningDeviceId, String token) async {
    try {
      Map<String, dynamic>? inviteData;
      if (_isDesktop) {
        inviteData = await FirestoreRESTClient.getDocument(_invitesCol, token);
      } else {
        final snap = await _db.collection(_invitesCol).doc(token).get();
        inviteData = snap.data();
      }

      if (inviteData == null) {
        return {'success': false, 'error': 'Invalid or expired invite link.'};
      }

      final expiresAt = DateTime.tryParse(inviteData['expiresAt'] as String? ?? '');
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        return {'success': false, 'error': 'Invite link has expired.'};
      }
      if (inviteData['used'] == true) {
        return {'success': false, 'error': 'Invite link has already been used.'};
      }

      final adminDeviceId = inviteData['adminDeviceId'] as String;
      final sessionId = 'session_${joiningDeviceId}_$adminDeviceId';
      final sessionData = {
        'sessionId': sessionId,
        'adminDeviceId': adminDeviceId,
        'linkedDeviceId': joiningDeviceId,
        'permission': 'read',
        'editableCode': null,
        'status': 'active',
        'joinedAt': DateTime.now().toIso8601String(),
      };

      if (_isDesktop) {
        await FirestoreRESTClient.setDocument(_sessionsCol, sessionId, sessionData);
        await FirestoreRESTClient.updateDocument(_invitesCol, token, {'used': true});
      } else {
        await _db.collection(_sessionsCol).doc(sessionId).set(sessionData);
        await _db.collection(_invitesCol).doc(token).update({'used': true});
      }

      return {'success': true, 'sessionId': sessionId};
    } catch (e) {
      debugPrint('joinWorkspace error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // ────────────────────────────────────────────────────────
  // ADMIN: Stream of all active sessions for this admin
  // ────────────────────────────────────────────────────────
  Stream<List<LinkedSession>> activeSessionsStream(String adminDeviceId) {
    if (_isDesktop) {
      final controller = StreamController<List<LinkedSession>>();
      Timer? timer;
      
      void fetchData() async {
        final results = await FirestoreRESTClient.getCollection(_sessionsCol, 
          whereField: 'adminDeviceId', isEqualTo: adminDeviceId);
        if (!controller.isClosed) {
          controller.add(results
            .where((m) => m['status'] == 'active')
            .map((m) => LinkedSession.fromMap(m))
            .toList());
        }
      }

      timer = Timer.periodic(const Duration(seconds: 4), (_) => fetchData());
      fetchData();
      
      controller.onCancel = () => timer?.cancel();
      return controller.stream;
    }

    return _db
        .collection(_sessionsCol)
        .where('adminDeviceId', isEqualTo: adminDeviceId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) => snap.docs.map((d) => LinkedSession.fromMap(d.data())).toList());
  }

  // ────────────────────────────────────────────────────────
  // GUEST: Real-time stream for a specific session
  // ────────────────────────────────────────────────────────
  Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStream(String sessionId) {
    if (_isDesktop) {
       final controller = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
       Timer? timer;

       void fetchData() async {
         final data = await FirestoreRESTClient.getDocument(_sessionsCol, sessionId);
         if (!controller.isClosed) {
           controller.add(_MockDocumentSnapshot(data, sessionId) as DocumentSnapshot<Map<String, dynamic>>);
         }
       }

       timer = Timer.periodic(const Duration(seconds: 4), (_) => fetchData());
       fetchData();

       controller.onCancel = () => timer?.cancel();
       return controller.stream;
    }

    return _db.collection(_sessionsCol).doc(sessionId).snapshots();
  }

  Future<LinkedSession?> getSession(String sessionId) async {
    try {
      Map<String, dynamic>? data;
      if (_isDesktop) {
        data = await FirestoreRESTClient.getDocument(_sessionsCol, sessionId);
      } else {
        final snap = await _db.collection(_sessionsCol).doc(sessionId).get();
        data = snap.data();
      }
      if (data == null || data['status'] != 'active') return null;
      return LinkedSession.fromMap(data);
    } catch (e) {
      return null;
    }
  }

  Future<void> updateSessionPermission(String sessionId, SessionPermission permission) async {
    final permStr = permission == SessionPermission.write ? 'write' : 'read';
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, {'permission': permStr});
    } else {
      await _db.collection(_sessionsCol).doc(sessionId).update({'permission': permStr});
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
      await _db.collection(_sessionsCol).doc(sessionId).update(data);
    }
  }

  /// ✅ Alias for backward compatibility with Admin Panel
  Future<void> removeLinkedDevice(String adminId, String linkedId, String sessionId) async {
    await disconnectSession(sessionId);
  }

  Future<String> generateEditableCode(String sessionId, String adminDeviceId) async {
    final code = _generateOtp();
    final data = {
      'editableCode': code,
      'permission': 'read',
    };
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, data);
    } else {
      await _db.collection(_sessionsCol).doc(sessionId).update(data);
    }
    return code;
  }

  Future<void> revokeEditAccess(String sessionId) async {
    final data = {
      'permission': 'read',
      'editableCode': null,
    };
    if (_isDesktop) {
      await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, data);
    } else {
      await _db.collection(_sessionsCol).doc(sessionId).update(data);
    }
  }

  Future<Map<String, dynamic>> verifyEditCode(String sessionId, String enteredCode) async {
    try {
      Map<String, dynamic>? data;
      if (_isDesktop) {
        data = await FirestoreRESTClient.getDocument(_sessionsCol, sessionId);
      } else {
        final doc = await _db.collection(_sessionsCol).doc(sessionId).get();
        data = doc.data();
      }

      if (data == null) return {'success': false, 'error': 'Session not found.'};

      final storedCode = data['editableCode'] as String?;
      if (storedCode == null || storedCode.isEmpty) {
        return {'success': false, 'error': 'No edit code generated.'};
      }
      if (storedCode.trim() != enteredCode.trim()) {
        return {'success': false, 'error': 'Incorrect code.'};
      }

      final updateData = {'permission': 'write', 'editableCode': null};
      if (_isDesktop) {
        await FirestoreRESTClient.updateDocument(_sessionsCol, sessionId, updateData);
      } else {
        await _db.collection(_sessionsCol).doc(sessionId).update(updateData);
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
}

class _MockDocumentSnapshot {
  final Map<String, dynamic>? _data;
  final String _id;
  _MockDocumentSnapshot(this._data, this._id);
  bool get exists => _data != null;
  Map<String, dynamic>? data() => _data;
  String get id => _id;
}
