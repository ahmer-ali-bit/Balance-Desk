import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart'
    as sqlite
    show ConflictAlgorithm, Transaction;
import '../../../firebase_options.dart';
import 'firestore_rest_client.dart';
import '../../../database/app_database.dart';

class WorkspaceSyncService {
  WorkspaceSyncService._();
  static final WorkspaceSyncService instance = WorkspaceSyncService._();

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _canUseSdk =>
      !kIsWeb &&
      defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.linux;

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
      debugPrint('Firebase Lazy Init Error (Sync): $e');
    }
  }

  static const String _snapshotsCol = 'workspace_snapshots';

  static Future<T> _retrySdk<T>(Future<T> Function() fn) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        return await fn();
      } on FirebaseException catch (e) {
        if (e.code == 'resource-exhausted') rethrow;
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

  // ── Upload the current local DB as a Firestore snapshot ──
  /// Returns the ISO-8601 timestamp of the upload, or null on failure.
  Future<String?> uploadFullSnapshot(String deviceId) async {
    try {
      final now = DateTime.now().toIso8601String();
      final payload = await _buildSnapshotPayload(
        deviceId: deviceId,
        uploadedAt: now,
      );

      if (_isDesktop) {
        final success = await FirestoreRESTClient.setDocument(
          _snapshotsCol,
          deviceId,
          payload,
        );
        if (!success) throw Exception('REST snapshot upload failed');
      } else {
        await _retrySdk(() async => (await _db).collection(_snapshotsCol).doc(deviceId).set(payload).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Firestore write timed out'),
        ));
      }
      debugPrint('[WorkspaceSync] Snapshot uploaded for $deviceId');
      return now;
    } catch (e) {
      debugPrint('[WorkspaceSync] uploadFullSnapshot error: $e');
      return null;
    }
  }

  /// Returns true when every workspace table on this device has zero rows.
  /// Used to avoid overwriting an empty joiner workspace with the admin's
  /// snapshot during a fresh join.
  Future<bool> isLocalWorkspaceEmpty() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final tables = const [
        'customers',
        'entries',
        'summary_snapshots',
        'app_settings',
        'ledger_years',
      ];
      for (final table in tables) {
        final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
        final count = result.first['c'];
        final n = count is int
            ? count
            : int.tryParse(count?.toString() ?? '') ?? 0;
        if (n > 0) return false;
      }
      return true;
    } catch (e) {
      debugPrint('[WorkspaceSync] isLocalWorkspaceEmpty error: $e');
      // Fail safe: if we can't tell, assume non-empty so the existing
      // sync behaviour is preserved.
      return false;
    }
  }

  Future<String?> localFingerprint() async {
    try {
      final payload = await _buildSnapshotPayload(
        deviceId: null,
        uploadedAt: null,
      );
      return jsonEncode(payload);
    } catch (e) {
      debugPrint('[WorkspaceSync] localFingerprint error: $e');
      return null;
    }
  }

  // ── Download admin snapshot and import into local DB ──
  Future<bool> downloadAndImportSnapshot(String adminDeviceId) async {
    try {
      Map<String, dynamic>? data;
      if (_isDesktop) {
        data = await FirestoreRESTClient.getDocument(
          _snapshotsCol,
          adminDeviceId,
        );
      } else {
        final doc = await (await _db)
            .collection(_snapshotsCol)
            .doc(adminDeviceId)
            .get();
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
            await txn.insert(
              'ledger_years',
              _sanitize(row),
              conflictAlgorithm: sqlite.ConflictAlgorithm.replace,
            );
          }
          for (final row in customers) {
            await txn.insert(
              'customers',
              _sanitize(row),
              conflictAlgorithm: sqlite.ConflictAlgorithm.replace,
            );
          }
          for (final row in entries) {
            await txn.insert(
              'entries',
              _sanitize(row),
              conflictAlgorithm: sqlite.ConflictAlgorithm.replace,
            );
          }
          for (final row in snapshots) {
            await txn.insert(
              'summary_snapshots',
              _sanitize(row),
              conflictAlgorithm: sqlite.ConflictAlgorithm.replace,
            );
          }
          for (final row in settings) {
            await txn.insert(
              'app_settings',
              _sanitize(row),
              conflictAlgorithm: sqlite.ConflictAlgorithm.replace,
            );
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

  Future<bool> mergeSnapshotFromDevice(String deviceId) async {
    try {
      final data = await _getSnapshotDocument(deviceId);
      if (data == null) {
        debugPrint('[WorkspaceSync] No snapshot found for $deviceId');
        return false;
      }

      final customers = _decodeList(data['customers']);
      final entries = _decodeList(data['entries']);
      final years = _decodeList(data['ledgerYears']);
      final db = await DatabaseHelper.instance.database;

      await db.transaction((txn) async {
        for (final row in years) {
          await txn.insert(
            'ledger_years',
            _sanitize(row),
            conflictAlgorithm: sqlite.ConflictAlgorithm.ignore,
          );
        }

        final customerIdMap = <int, int>{};
        for (final row in customers) {
          final sanitized = _sanitize(row);
          final oldId = _asInt(sanitized['id']);
          final targetId = await _upsertCustomerForMerge(txn, sanitized);
          if (oldId != null && targetId != null) {
            customerIdMap[oldId] = targetId;
          }
        }

        for (final row in entries) {
          final sanitized = _sanitize(row);
          final oldCustomerId = _asInt(sanitized['customerId']);
          if (oldCustomerId != null &&
              customerIdMap.containsKey(oldCustomerId)) {
            sanitized['customerId'] = customerIdMap[oldCustomerId];
          }

          if (await _entryExists(txn, sanitized)) continue;

          final entryId = _asInt(sanitized['id']);
          if (entryId != null && await _rowIdExists(txn, 'entries', entryId)) {
            sanitized.remove('id');
          }

          await txn.insert(
            'entries',
            sanitized,
            conflictAlgorithm: sqlite.ConflictAlgorithm.ignore,
          );
        }
      });

      debugPrint('[WorkspaceSync] Snapshot merged from $deviceId');
      return true;
    } catch (e) {
      debugPrint('[WorkspaceSync] mergeSnapshotFromDevice error: $e');
      return false;
    }
  }

  // ── Restore local backup (undo sync) ──
  Future<bool> restoreLocalSnapshot(String myDeviceId) async {
    try {
      bool exists = false;
      if (_isDesktop) {
        final data = await FirestoreRESTClient.getDocument(
          _snapshotsCol,
          myDeviceId,
        );
        exists = data != null;
      } else {
        final doc = await (await _db).collection(_snapshotsCol).doc(myDeviceId).get();
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

  /// Fetch the latest snapshot timestamp for a device (without downloading full data).
  Future<String?> getSnapshotTimestamp(String deviceId) async {
    try {
      final data = await _getSnapshotDocument(deviceId);
      return data?['uploadedAt'] as String?;
    } catch (e) {
      debugPrint('[WorkspaceSync] getSnapshotTimestamp error: $e');
      return null;
    }
  }

  // ── Helpers ──
  Future<Map<String, dynamic>> _buildSnapshotPayload({
    required String? deviceId,
    required String? uploadedAt,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final customers = await db.rawQuery('SELECT * FROM customers ORDER BY id');
    final entries = await db.rawQuery('SELECT * FROM entries ORDER BY id');
    final snapshots = await db.rawQuery(
      'SELECT * FROM summary_snapshots ORDER BY id',
    );
    final settings = await db.rawQuery(
      'SELECT * FROM app_settings ORDER BY settingKey',
    );
    final years = await db.rawQuery('SELECT * FROM ledger_years ORDER BY year');

    final payload = <String, dynamic>{
      'customers': jsonEncode(customers),
      'entries': jsonEncode(entries),
      'summarySnapshots': jsonEncode(snapshots),
      'appSettings': jsonEncode(settings),
      'ledgerYears': jsonEncode(years),
    };
    if (deviceId != null) payload['deviceId'] = deviceId;
    if (uploadedAt != null) payload['uploadedAt'] = uploadedAt;
    return payload;
  }

  Future<Map<String, dynamic>?> _getSnapshotDocument(String deviceId) async {
    if (_isDesktop) {
      return FirestoreRESTClient.getDocument(_snapshotsCol, deviceId);
    }

    final doc = await (await _db).collection(_snapshotsCol).doc(deviceId).get();
    return doc.data();
  }

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

  Future<int?> _upsertCustomerForMerge(
    sqlite.Transaction txn,
    Map<String, dynamic> customer,
  ) async {
    final id = _asInt(customer['id']);
    if (id != null) {
      final existing = await txn.query(
        'customers',
        columns: ['id', 'name', 'ledgerYear'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          'customers',
          customer,
          conflictAlgorithm: sqlite.ConflictAlgorithm.ignore,
        );
        return id;
      }

      final existingRow = existing.first;
      if (existingRow['name'] == customer['name'] &&
          _asInt(existingRow['ledgerYear']) == _asInt(customer['ledgerYear'])) {
        return id;
      }
    }

    final matchedId = await _findCustomerIdByIdentity(txn, customer);
    if (matchedId != null) return matchedId;

    final insertable = Map<String, dynamic>.from(customer)..remove('id');
    return txn.insert('customers', insertable);
  }

  Future<int?> _findCustomerIdByIdentity(
    sqlite.Transaction txn,
    Map<String, dynamic> customer,
  ) async {
    final rows = await txn.query(
      'customers',
      columns: ['id'],
      where: 'name = ? AND ledgerYear = ?',
      whereArgs: [
        customer['name']?.toString() ?? '',
        _asInt(customer['ledgerYear']) ?? DateTime.now().year,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _asInt(rows.first['id']);
  }

  Future<bool> _entryExists(
    sqlite.Transaction txn,
    Map<String, dynamic> entry,
  ) async {
    final rows = await txn.query(
      'entries',
      columns: ['id'],
      where:
          'customerId = ? AND entryDate = ? AND createdAt = ? AND description = ? AND debit = ? AND credit = ? AND buyBags = ? AND sellBags = ? AND pageNo = ? AND dailyLogPageNo = ?',
      whereArgs: [
        _asInt(entry['customerId']),
        entry['entryDate']?.toString() ?? '',
        entry['createdAt']?.toString() ?? '',
        entry['description']?.toString() ?? '',
        _asDouble(entry['debit']),
        _asDouble(entry['credit']),
        _asDouble(entry['buyBags']),
        _asDouble(entry['sellBags']),
        entry['pageNo']?.toString() ?? '',
        entry['dailyLogPageNo']?.toString() ?? '',
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _rowIdExists(
    sqlite.Transaction txn,
    String table,
    int id,
  ) async {
    final rows = await txn.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
