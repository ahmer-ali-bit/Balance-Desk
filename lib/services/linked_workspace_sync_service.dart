import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'linked_device_api.dart';
import 'linked_device_credentials.dart';

class LinkedSyncResult {
  const LinkedSyncResult({
    required this.cursor,
    required this.changedRecords,
    required this.pendingRecords,
    required this.conflictCount,
    required this.permission,
    required this.role,
  });
  final int cursor;
  final int changedRecords;
  final int pendingRecords;
  final int conflictCount;
  final String permission;
  final String role;
}

class _SyncRecord {
  const _SyncRecord(this.entity, this.recordId, this.payload);
  final String entity;
  final String recordId;
  final Map<String, Object?> payload;
  String get key => '$entity\u0000$recordId';
  String get encoded => _canonicalJson(payload);
}

/// Local-first record synchronizer. Each entity has an independent stable ID,
/// optimistic cloud revision and tombstone; simultaneous edits are surfaced as
/// conflicts rather than silently overwritten.
class LinkedWorkspaceSyncService {
  LinkedWorkspaceSyncService({
    LinkedDeviceApi? api,
    LinkedDeviceCredentials? credentials,
  }) : _api = api ?? LinkedDeviceApi(),
       _credentials = credentials ?? LinkedDeviceCredentials();

  final LinkedDeviceApi _api;
  final LinkedDeviceCredentials _credentials;

  static const List<String> _entityOrder = <String>[
    'ledger_years',
    'customers',
    'entries',
    'summary_snapshots',
    'app_settings',
  ];

  static const Set<String> _deviceOnlySettingKeys = <String>{
    'activeYear',
    'appPin',
    'appPinHash',
    'appPinSalt',
    'appPinSetupDismissed',
    'autoBackupPath',
    'companyLogoPath',
    'companyProfilePromptSkipped',
    'biometricUnlockEnabled',
    'ledger.lastSelectedDate',
    'themeMode',
  };

  Future<LinkedSyncResult> sync(
    LinkedWorkspaceConfig config, {
    bool pullOnly = false,
  }) async {
    final token = await _credentials.readToken(config.localWorkspaceId);
    if (token == null || token.length < 40) {
      throw const LinkedDeviceException('Secure device credential is missing.');
    }
    final db = await AppDatabase.instance.database;
    await _ensureStableIds(db, config);
    final initialPullRows = await db.query(
      'sync_state',
      where: 'stateKey = ?',
      whereArgs: const <Object?>['initial_pull_complete'],
      limit: 1,
    );
    final isInitialLinkedPull =
        config.role == 'linked' && initialPullRows.isEmpty;
    final snapshot = await _snapshot(db);
    final shadows = await _loadShadows(db);
    final unresolved = await db.query('sync_conflicts');
    final unresolvedKeys = unresolved
        .map((Map<String, Object?> row) => '${row['entity']}\u0000${row['recordId']}')
        .toSet();
    final pending = pullOnly || config.isReadOnly || isInitialLinkedPull
        ? <_SyncRecord>[]
        : _diff(snapshot, shadows, unresolvedKeys);

    var cursor = config.cursor;
    var hasMoreRemoteChanges = false;
    var permission = config.permission;
    var role = config.role;
    var changedCount = 0;
    final pageLimit = 12;
    for (var page = 0; page < pageLimit; page++) {
      final batch = pending.skip(page * 100).take(100).toList();
      final requestChanges = batch
          .map((record) => <String, Object?>{
            'entity': record.entity,
            'record_id': record.recordId,
            'payload': record.payload,
            'is_deleted': false,
            'base_revision': (shadows[record.key]?['revision'] as num?)?.toInt() ?? 0,
          })
          .toList(growable: false);
      // Deletions are represented by the synthetic record marker below.
      for (var index = 0; index < requestChanges.length; index++) {
        final record = batch[index];
        if (record.payload['__bd_deleted'] == true) {
          requestChanges[index]['is_deleted'] = true;
          requestChanges[index]['payload'] = <String, Object?>{};
        }
      }
      final response = await _api.rpc('bd_sync', <String, Object?>{
        'p_workspace_id': config.cloudWorkspaceId,
        'p_device_id': config.deviceId,
        'p_device_token': token,
        'p_changes': requestChanges,
        'p_cursor': cursor,
        'p_limit': 300,
      });
      if (response is! Map) {
        throw const LinkedDeviceException('The cloud returned an invalid sync response.');
      }
      final body = Map<String, dynamic>.from(response);
      final acks = _asList(body['accepted']);
      final conflicts = _asList(body['conflicts']);
      final remoteChanges = _asList(body['changes']);

      for (final rawAck in acks) {
        if (rawAck is! Map) continue;
        final ack = Map<String, dynamic>.from(rawAck);
        final key = '${ack['entity']}\u0000${ack['record_id']}';
        final record = _firstRecord(batch, key);
        if (record == null) continue;
        final deleted = record.payload['__bd_deleted'] == true;
        await _writeShadow(
          db,
          record.entity,
          record.recordId,
          deleted ? '{}' : record.encoded,
          (ack['revision'] as num).toInt(),
          isDeleted: deleted,
        );
      }

      for (final rawConflict in conflicts) {
        if (rawConflict is! Map) continue;
        final conflict = Map<String, dynamic>.from(rawConflict);
        final key = '${conflict['entity']}\u0000${conflict['record_id']}';
        final record = _firstRecord(batch, key);
        if (record == null) continue;
        final cloud = conflict['cloud'];
        final cloudMap = cloud is Map ? Map<String, dynamic>.from(cloud) : null;
        await db.insert(
          'sync_conflicts',
          <String, Object?>{
            'entity': record.entity,
            'recordId': record.recordId,
            'localPayload': record.payload['__bd_deleted'] == true ? '{}' : record.encoded,
            'cloudPayload': cloudMap == null
                ? '{}'
                : _canonicalJson(cloudMap['payload'] ?? <String, Object?>{}),
            'cloudRevision': (cloudMap?['revision'] as num?)?.toInt() ?? 0,
            'cloudDeleted': cloudMap?['is_deleted'] == true ? 1 : 0,
            'detectedAt': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final conflictKeys = conflicts.whereType<Map>().map((raw) {
        final map = Map<String, dynamic>.from(raw);
        return '${map['entity']}\u0000${map['record_id']}';
      }).toSet();
      for (final rawChange in remoteChanges) {
        if (rawChange is! Map) continue;
        final change = Map<String, dynamic>.from(rawChange);
        final entity = change['entity']?.toString() ?? '';
        final recordId = change['record_id']?.toString() ?? '';
        final key = '$entity\u0000$recordId';
        if (conflictKeys.contains(key) || unresolvedKeys.contains(key)) continue;
        final payload = change['payload'] is Map
            ? Map<String, Object?>.from(change['payload'] as Map)
            : <String, Object?>{};
        final deleted = change['is_deleted'] == true;
        await DatabaseHelper.instance.runAsRemoteApply(() async {
          await _applyRemoteRecord(
            db,
            entity: entity,
            recordId: recordId,
            payload: payload,
            deleted: deleted,
          );
        });
        await _writeShadow(
          db,
          entity,
          recordId,
          _canonicalJson(payload),
          (change['revision'] as num).toInt(),
          isDeleted: deleted,
        );
        changedCount++;
      }

      cursor = (body['cursor'] as num?)?.toInt() ?? cursor;
      permission = body['permission']?.toString() ?? permission;
      role = body['role']?.toString() ?? role;
      hasMoreRemoteChanges = body['has_more'] == true;
      if (!hasMoreRemoteChanges) break;
    }

    if (isInitialLinkedPull && !hasMoreRemoteChanges) {
      await db.insert('sync_state', <String, Object?>{
        'stateKey': 'initial_pull_complete',
        'stateValue': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final conflictsNow = await db.query('sync_conflicts');
    return LinkedSyncResult(
      cursor: cursor,
      changedRecords: changedCount,
      pendingRecords: pending.length > 100 ? pending.length - 100 : 0,
      conflictCount: conflictsNow.length,
      permission: permission,
      role: role,
    );
  }

  Future<void> resolveConflict({
    required String localWorkspaceId,
    required String entity,
    required String recordId,
    required bool keepThisDevice,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'sync_conflicts',
      where: 'entity = ? AND recordId = ?',
      whereArgs: <Object?>[entity, recordId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final conflict = rows.first;
    final cloudPayload = jsonDecode(conflict['cloudPayload'] as String);
    final cloudMap = cloudPayload is Map
        ? Map<String, Object?>.from(cloudPayload)
        : <String, Object?>{};
    final cloudDeleted = (conflict['cloudDeleted'] as int? ?? 0) == 1;
    final cloudRevision = conflict['cloudRevision'] as int? ?? 0;

    if (keepThisDevice) {
      await db.insert('sync_shadow', <String, Object?>{
        'entity': entity,
        'recordId': recordId,
        'payload': _canonicalJson(cloudMap),
        'revision': cloudRevision,
        'isDeleted': cloudDeleted ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await DatabaseHelper.instance.runAsRemoteApply(() async {
        await _applyRemoteRecord(
          db,
          entity: entity,
          recordId: recordId,
          payload: cloudMap,
          deleted: cloudDeleted,
        );
      });
      await _writeShadow(
        db,
        entity,
        recordId,
        _canonicalJson(cloudMap),
        cloudRevision,
        isDeleted: cloudDeleted,
      );
    }
    await db.delete(
      'sync_conflicts',
      where: 'entity = ? AND recordId = ?',
      whereArgs: <Object?>[entity, recordId],
    );
    AppDatabase.instance.notifyDataChanged();
  }

  List<_SyncRecord> _diff(
    Map<String, _SyncRecord> current,
    Map<String, Map<String, Object?>> shadows,
    Set<String> conflictKeys,
  ) {
    final changes = <_SyncRecord>[];
    for (final record in current.values) {
      if (conflictKeys.contains(record.key)) continue;
      final shadow = shadows[record.key];
      if (shadow == null ||
          shadow['isDeleted'] == 1 ||
          shadow['payload'] != record.encoded) {
        changes.add(record);
      }
    }
    for (final entry in shadows.entries) {
      if (conflictKeys.contains(entry.key) || entry.value['isDeleted'] == 1) continue;
      if (!current.containsKey(entry.key)) {
        changes.add(
          _SyncRecord(
            entry.value['entity'] as String,
            entry.value['recordId'] as String,
            <String, Object?>{'__bd_deleted': true},
          ),
        );
      }
    }
    changes.sort((a, b) {
      final indexA = _entityOrder.indexOf(a.entity);
      final indexB = _entityOrder.indexOf(b.entity);
      return indexA.compareTo(indexB);
    });
    return changes;
  }

  Future<Map<String, _SyncRecord>> _snapshot(Database db) async {
    final records = <String, _SyncRecord>{};
    final customerSyncIds = <int, String>{};
    final customerRows = await db.query('customers', orderBy: 'id');
    for (final row in customerRows) {
      final id = row['id'] as int;
      final syncId = row['syncId']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      customerSyncIds[id] = syncId;
      final payload = <String, Object?>{
        'name': row['name'],
        'address': row['address'] ?? '',
        'phone': row['phone'] ?? '',
        'ledgerYear': row['ledgerYear'],
        'isStockLedger': row['isStockLedger'] ?? 0,
        'useWeight': row['useWeight'] ?? 0,
      };
      final record = _SyncRecord('customers', syncId, payload);
      records[record.key] = record;
    }

    final entryRows = await db.query('entries', orderBy: 'id');
    for (final row in entryRows) {
      final syncId = row['syncId']?.toString() ?? '';
      final customerId = row['customerId'] as int;
      final customerSyncId = customerSyncIds[customerId];
      if (syncId.isEmpty || customerSyncId == null) continue;
      final payload = <String, Object?>{
        'customerSyncId': customerSyncId,
        'entryDate': row['entryDate'],
        'createdAt': row['createdAt'],
        'pageNo': row['pageNo'] ?? '',
        'dailyLogPageNo': row['dailyLogPageNo'] ?? '',
        'description': row['description'] ?? '',
        'debit': row['debit'] ?? 0,
        'credit': row['credit'] ?? 0,
        'buyBags': row['buyBags'] ?? 0,
        'sellBags': row['sellBags'] ?? 0,
        'showInDailyLog': row['showInDailyLog'] ?? 1,
      };
      final record = _SyncRecord('entries', syncId, payload);
      records[record.key] = record;
    }

    for (final row in await db.query('summary_snapshots', orderBy: 'id')) {
      final syncId = row['syncId']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final record = _SyncRecord('summary_snapshots', syncId, <String, Object?>{
        'ledgerYear': row['ledgerYear'],
        'savedAt': row['savedAt'],
        'overallDebit': row['overallDebit'] ?? 0,
        'overallCredit': row['overallCredit'] ?? 0,
        'customerCount': row['customerCount'] ?? 0,
        'dailyLogPageNo': row['dailyLogPageNo'] ?? '',
      });
      records[record.key] = record;
    }

    for (final row in await db.query('ledger_years', orderBy: 'year')) {
      final year = row['year']?.toString() ?? '';
      if (year.isEmpty) continue;
      final record = _SyncRecord('ledger_years', year, <String, Object?>{
        'year': row['year'],
        'createdAt': row['createdAt'],
      });
      records[record.key] = record;
    }

    for (final row in await db.query('app_settings', orderBy: 'settingKey')) {
      final localKey = row['settingKey']?.toString() ?? '';
      final localValue = row['settingValue']?.toString() ?? '';
      final cloudKey = _toCloudSettingKey(localKey, customerSyncIds);
      if (cloudKey == null) continue;
      final record = _SyncRecord('app_settings', cloudKey, <String, Object?>{
        'settingKey': cloudKey,
        'settingValue': localValue,
      });
      records[record.key] = record;
    }
    return records;
  }

  Future<void> _ensureStableIds(Database db, LinkedWorkspaceConfig config) async {
    if (config.isReadOnly) return;
    for (final table in <String>['customers', 'entries', 'summary_snapshots']) {
      final rows = await db.query(table, columns: <String>['id', 'syncId']);
      for (final row in rows) {
        if ((row['syncId']?.toString() ?? '').isEmpty) {
          await db.update(
            table,
            <String, Object?>{'syncId': LinkedDeviceCredentials.newUuid()},
            where: 'id = ?',
            whereArgs: <Object?>[row['id']],
          );
        }
      }
    }
  }

  Future<Map<String, Map<String, Object?>>> _loadShadows(Database db) async {
    final shadows = <String, Map<String, Object?>>{};
    for (final row in await db.query('sync_shadow')) {
      final entity = row['entity'] as String;
      final id = row['recordId'] as String;
      shadows['$entity\u0000$id'] = <String, Object?>{
        ...row,
        'entity': entity,
        'recordId': id,
        'isDeleted': row['isDeleted'],
      };
    }
    return shadows;
  }

  Future<void> _writeShadow(
    Database db,
    String entity,
    String recordId,
    String payload,
    int revision, {
    required bool isDeleted,
  }) async {
    await db.insert('sync_shadow', <String, Object?>{
      'entity': entity,
      'recordId': recordId,
      'payload': payload,
      'revision': revision,
      'isDeleted': isDeleted ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _applyRemoteRecord(
    Database db, {
    required String entity,
    required String recordId,
    required Map<String, Object?> payload,
    required bool deleted,
  }) async {
    switch (entity) {
      case 'customers':
        final rows = await db.query(
          'customers',
          columns: <String>['id'],
          where: 'syncId = ?',
          whereArgs: <Object?>[recordId],
          limit: 1,
        );
        if (deleted) {
          if (rows.isNotEmpty) {
            await db.delete('customers', where: 'id = ?', whereArgs: <Object?>[rows.first['id']]);
          }
          return;
        }
        final values = <String, Object?>{
          ...payload,
          'syncId': recordId,
          'isStockLedger': payload['isStockLedger'] ?? 0,
          'useWeight': payload['useWeight'] ?? 0,
        };
        if (rows.isEmpty) {
          await db.insert('customers', values);
        } else {
          await db.update('customers', values, where: 'id = ?', whereArgs: <Object?>[rows.first['id']]);
        }
        return;
      case 'entries':
        final rows = await db.query(
          'entries',
          columns: <String>['id'],
          where: 'syncId = ?',
          whereArgs: <Object?>[recordId],
          limit: 1,
        );
        if (deleted) {
          if (rows.isNotEmpty) {
            await db.delete('entries', where: 'id = ?', whereArgs: <Object?>[rows.first['id']]);
          }
          return;
        }
        final customerSyncId = payload['customerSyncId']?.toString() ?? '';
        final customerRows = await db.query(
          'customers',
          columns: <String>['id'],
          where: 'syncId = ?',
          whereArgs: <Object?>[customerSyncId],
          limit: 1,
        );
        if (customerRows.isEmpty) {
          throw const LinkedDeviceException('A linked entry is waiting for its customer record.');
        }
        final values = <String, Object?>{
          'syncId': recordId,
          'customerId': customerRows.first['id'],
          'entryDate': payload['entryDate'],
          'createdAt': payload['createdAt'],
          'pageNo': payload['pageNo'] ?? '',
          'dailyLogPageNo': payload['dailyLogPageNo'] ?? '',
          'description': payload['description'] ?? '',
          'debit': payload['debit'] ?? 0,
          'credit': payload['credit'] ?? 0,
          'buyBags': payload['buyBags'] ?? 0,
          'sellBags': payload['sellBags'] ?? 0,
          'showInDailyLog': payload['showInDailyLog'] ?? 1,
        };
        if (rows.isEmpty) {
          await db.insert('entries', values);
        } else {
          await db.update('entries', values, where: 'id = ?', whereArgs: <Object?>[rows.first['id']]);
        }
        return;
      case 'summary_snapshots':
        final rows = await db.query(
          'summary_snapshots',
          columns: <String>['id'],
          where: 'syncId = ?',
          whereArgs: <Object?>[recordId],
          limit: 1,
        );
        if (deleted) {
          if (rows.isNotEmpty) {
            await db.delete('summary_snapshots', where: 'id = ?', whereArgs: <Object?>[rows.first['id']]);
          }
          return;
        }
        final values = <String, Object?>{...payload, 'syncId': recordId};
        if (rows.isEmpty) {
          await db.insert('summary_snapshots', values);
        } else {
          await db.update('summary_snapshots', values, where: 'id = ?', whereArgs: <Object?>[rows.first['id']]);
        }
        return;
      case 'ledger_years':
        if (deleted) {
          await db.delete('ledger_years', where: 'year = ?', whereArgs: <Object?>[int.tryParse(recordId)]);
        } else {
          await db.insert('ledger_years', payload, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
      case 'app_settings':
        final localKey = _fromCloudSettingKey(recordId, await _customerIdMap(db));
        if (localKey == null || _deviceOnlySettingKeys.contains(localKey)) return;
        if (deleted) {
          await db.delete('app_settings', where: 'settingKey = ?', whereArgs: <Object?>[localKey]);
        } else {
          await db.insert('app_settings', <String, Object?>{
            'settingKey': localKey,
            'settingValue': payload['settingValue']?.toString() ?? '',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        return;
      default:
        throw LinkedDeviceException('Unknown synced record type: $entity');
    }
  }

  Future<Map<String, int>> _customerIdMap(Database db) async {
    final result = <String, int>{};
    for (final row in await db.query('customers', columns: <String>['id', 'syncId'])) {
      final syncId = row['syncId']?.toString() ?? '';
      if (syncId.isNotEmpty) result[syncId] = row['id'] as int;
    }
    return result;
  }

  String? _toCloudSettingKey(String localKey, Map<int, String> customerSyncIds) {
    if (_deviceOnlySettingKeys.contains(localKey) ||
        localKey.startsWith('linked.') ||
        localKey.startsWith('sync.')) return null;
    final pageNo = RegExp(r'^ledger\.pageNo:(\d+)$').firstMatch(localKey);
    if (pageNo != null) {
      final id = int.parse(pageNo.group(1)!);
      final syncId = customerSyncIds[id];
      return syncId == null ? null : 'ledger.pageNo:customer:$syncId';
    }
    final opening = RegExp(r'^ledgerOpening(Debit|Credit|BuyBags|SellBags):(\d+):(\d+)$').firstMatch(localKey);
    if (opening != null) {
      final syncId = customerSyncIds[int.parse(opening.group(3)!)];
      return syncId == null
          ? null
          : 'ledgerOpening${opening.group(1)}:${opening.group(2)}:customer:$syncId';
    }
    return localKey;
  }

  String? _fromCloudSettingKey(String cloudKey, Map<String, int> customerIds) {
    final pageNo = RegExp(r'^ledger\.pageNo:customer:([0-9a-fA-F-]+)$').firstMatch(cloudKey);
    if (pageNo != null) {
      final id = customerIds[pageNo.group(1)!];
      return id == null ? null : 'ledger.pageNo:$id';
    }
    final opening = RegExp(r'^ledgerOpening(Debit|Credit|BuyBags|SellBags):(\d+):customer:([0-9a-fA-F-]+)$').firstMatch(cloudKey);
    if (opening != null) {
      final id = customerIds[opening.group(3)!];
      return id == null ? null : 'ledgerOpening${opening.group(1)}:${opening.group(2)}:$id';
    }
    return cloudKey;
  }

  static List<dynamic> _asList(dynamic value) => value is List ? value : const <dynamic>[];
}

_SyncRecord? _firstRecord(List<_SyncRecord> records, String key) {
  for (final record in records) {
    if (record.key == key) return record;
  }
  return null;
}

String _canonicalJson(Object? value) {
  Object? canonicalize(Object? input) {
    if (input is Map) {
      final keys = input.keys.map((Object? key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: canonicalize(input[key]),
      };
    }
    if (input is List) return input.map(canonicalize).toList(growable: false);
    return input;
  }

  return jsonEncode(canonicalize(value));
}
