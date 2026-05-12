import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../../../firebase_options.dart';
import 'firestore_rest_client.dart';
import '../../../database/app_database.dart';

class WorkspaceSyncService {
  WorkspaceSyncService._();
  static final WorkspaceSyncService instance = WorkspaceSyncService._();

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
      debugPrint('Firebase Lazy Init Error (Sync): $e');
    }
  }

  static const String _snapshotsCol = 'workspace_snapshots';

  // ── Upload the current local DB as a Firestore snapshot ──
  Future<void> uploadFullSnapshot(String deviceId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      
      final customers = await db.rawQuery('SELECT * FROM customers');
      final entries = await db.rawQuery('SELECT * FROM entries');
      final snapshots = await db.rawQuery('SELECT * FROM summary_snapshots');
      final settings = await db.rawQuery('SELECT * FROM app_settings');
      final years = await db.rawQuery('SELECT * FROM ledger_years');

      final payload = {
        'deviceId': deviceId,
        'uploadedAt': DateTime.now().toIso8601String(),
        'customers': jsonEncode(customers),
        'entries': jsonEncode(entries),
        'summarySnapshots': jsonEncode(snapshots),
        'appSettings': jsonEncode(settings),
        'ledgerYears': jsonEncode(years),
      };

      if (_isDesktop) {
        final success = await FirestoreRESTClient.setDocument(_snapshotsCol, deviceId, payload);
        if (!success) throw Exception('REST snapshot upload failed');
      } else {
        await _db.collection(_snapshotsCol).doc(deviceId).set(payload);
      }
      debugPrint('[WorkspaceSync] Snapshot uploaded for $deviceId');
    } catch (e) {
      debugPrint('[WorkspaceSync] uploadFullSnapshot error: $e');
    }
  }

  // ── Download admin snapshot and import into local DB ──
  Future<bool> downloadAndImportSnapshot(String adminDeviceId) async {
    try {
      Map<String, dynamic>? data;
      if (_isDesktop) {
        data = await FirestoreRESTClient.getDocument(_snapshotsCol, adminDeviceId);
      } else {
        final doc = await _db.collection(_snapshotsCol).doc(adminDeviceId).get();
        data = doc.data();
      }

      if (data == null) {
        debugPrint('[WorkspaceSync] No snapshot found for $adminDeviceId');
        return false;
      }

      final customers = _decodeList(data['customers']);
      final entries = _decodeList(data['entries']);
      final snapshots = _decodeList(data['summarySnapshots']);
      final settings = _decodeList(data['appSettings']);
      final years = _decodeList(data['ledgerYears']);

      final db = await DatabaseHelper.instance.database;

      try {
        await db.transaction((txn) async {
          // Clear existing data
          await txn.execute('DELETE FROM entries');
          await txn.execute('DELETE FROM customers');
          await txn.execute('DELETE FROM summary_snapshots');
          await txn.execute('DELETE FROM ledger_years');
          await txn.execute('DELETE FROM app_settings');

          // Re-insert
          for (final row in years) {
            await txn.insert('ledger_years', _sanitize(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final row in customers) {
            await txn.insert('customers', _sanitize(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final row in entries) {
            await txn.insert('entries', _sanitize(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final row in snapshots) {
            await txn.insert('summary_snapshots', _sanitize(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final row in settings) {
            await txn.insert('app_settings', _sanitize(row), conflictAlgorithm: ConflictAlgorithm.replace);
          }
        });

        debugPrint('[WorkspaceSync] Snapshot imported from $adminDeviceId');
        return true;
      } catch (e) {
        debugPrint('[WorkspaceSync] downloadAndImportSnapshot inner error: $e');
        return false;
      }
    } catch (e) {
      debugPrint('[WorkspaceSync] downloadAndImportSnapshot error: $e');
      return false;
    }
  }

  // ── Restore local backup (undo sync) ──
  Future<bool> restoreLocalSnapshot(String myDeviceId) async {
    try {
      bool exists = false;
      if (_isDesktop) {
        final data = await FirestoreRESTClient.getDocument(_snapshotsCol, myDeviceId);
        exists = data != null;
      } else {
        final doc = await _db.collection(_snapshotsCol).doc(myDeviceId).get();
        exists = doc.exists;
      }

      if (!exists) {
        debugPrint('[WorkspaceSync] No local backup found for $myDeviceId');
        return false;
      }
      return downloadAndImportSnapshot(myDeviceId);
    } catch (e) {
      debugPrint('[WorkspaceSync] restoreLocalSnapshot error: $e');
      return false;
    }
  }

  // ── Helpers ──
  List<Map<String, dynamic>> _decodeList(dynamic raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw as String) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _sanitize(Map<String, dynamic> row) {
    return row.map((k, v) => MapEntry(k, v?.toString() == 'null' ? null : v));
  }
}
