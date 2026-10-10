import 'package:sqflite/sqflite.dart';

import '../../database/sync_tables.dart';
import '../../models/sync_op.dart';

/// One captured local mutation waiting to be pushed.
class PendingOp {
  const PendingOp({
    required this.outboxIds,
    required this.table,
    required this.rowId,
    required this.action,
    required this.payload,
  });

  /// Every outbox row this op collapses. All of them are marked pushed once
  /// the remote write succeeds.
  final List<int> outboxIds;
  final String table;
  final String rowId;
  final String action;
  final Map<String, Object?> payload;
}

/// Read/write access to the local sync tables.
///
/// All statements run against the same database as the ledger, so the outbox
/// and the business rows share a transaction boundary and cannot drift.
class SyncStore {
  const SyncStore();

  static const String _outboxTable = 'sync_outbox';
  static const String _rowStateTable = 'sync_row_state';
  static const String _appliedTable = 'sync_applied_ops';
  static const String _stateTable = 'sync_state';

  /// Attempts after which a failing remote op is parked instead of retried
  /// forever (e.g. an entry whose customer has not replicated yet).
  static const int maxApplyAttempts = 3;

  // ---------------------------------------------------------------- outbox

  /// Returns pending mutations, collapsing repeated writes to the same row so
  /// only the newest state is pushed.
  Future<List<PendingOp>> pendingOps(Database db) async {
    final List<Map<String, Object?>> rows = await db.query(
      _outboxTable,
      where: 'pushed = 0',
      orderBy: 'id ASC',
    );

    final Map<String, PendingOp> collapsed = <String, PendingOp>{};
    final Map<String, List<int>> idsByKey = <String, List<int>>{};

    for (final Map<String, Object?> row in rows) {
      final int id = (row['id'] ?? 0) as int;
      final String table = (row['tableName'] ?? '') as String;
      final String rowId = (row['rowId'] ?? '') as String;
      final String action = (row['action'] ?? SyncOp.actionUpsert) as String;
      final String key = '$table|$rowId';

      idsByKey.putIfAbsent(key, () => <int>[]).add(id);

      if (action == SyncOp.actionDelete) {
        collapsed[key] = PendingOp(
          outboxIds: <int>[],
          table: table,
          rowId: rowId,
          action: SyncOp.actionDelete,
          payload: const <String, Object?>{},
        );
        continue;
      }

      final Map<String, Object?>? current = await _readRow(db, table, rowId);
      if (current == null) {
        // Row was deleted after this capture — degrade to a tombstone.
        collapsed[key] = PendingOp(
          outboxIds: <int>[],
          table: table,
          rowId: rowId,
          action: SyncOp.actionDelete,
          payload: const <String, Object?>{},
        );
        continue;
      }

      collapsed[key] = PendingOp(
        outboxIds: <int>[],
        table: table,
        rowId: rowId,
        action: SyncOp.actionUpsert,
        payload: current,
      );
    }

    return collapsed.entries.map((MapEntry<String, PendingOp> entry) {
      final List<int> ids = idsByKey[entry.key] ?? const <int>[];
      return PendingOp(
        outboxIds: ids,
        table: entry.value.table,
        rowId: entry.value.rowId,
        action: entry.value.action,
        payload: entry.value.payload,
      );
    }).toList();
  }

  Future<void> markPushed(Database db, List<int> outboxIds) async {
    if (outboxIds.isEmpty) {
      return;
    }
    await db.update(
      _outboxTable,
      <String, Object?>{'pushed': 1},
      where: 'id IN (${List<String>.filled(outboxIds.length, '?').join(', ')})',
      whereArgs: outboxIds,
    );
  }

  /// Seeds the outbox with the *entire* current ledger.
  ///
  /// Triggers only capture changes made after they exist, so a device that
  /// links an existing ledger would otherwise publish nothing. Returns the
  /// number of rows queued.
  Future<int> queueFullSnapshot(Database db) async {
    int queued = 0;
    for (final String table in kSyncedTables) {
      final String pk = kSyncPrimaryKeys[table]!;
      final String filter = table == 'app_settings'
          ? ' WHERE settingKey NOT IN '
              '(${kLocalOnlySettings.map((String k) => "'$k'").join(', ')})'
          : '';
      final int count = await db.rawInsert(
        'INSERT INTO sync_outbox(tableName, rowId, action, capturedAt) '
        "SELECT '$table', CAST($pk AS TEXT), 'upsert', "
        "CAST(strftime('%s', 'now') AS INTEGER) * 1000 "
        'FROM $table$filter',
      );
      if (count > 0) {
        queued += count;
      }
    }
    return queued;
  }

  /// Drops rows already pushed, keeping the outbox from growing forever.
  Future<void> prunePushed(Database db, {int keep = 500}) async {
    await db.rawDelete(
      'DELETE FROM $_outboxTable WHERE pushed = 1 AND id NOT IN '
      '(SELECT id FROM $_outboxTable WHERE pushed = 1 ORDER BY id DESC LIMIT ?)',
      <Object?>[keep],
    );
  }

  // ------------------------------------------------------------- row state

  /// Last-writer-wins record for one row, or null when never synced.
  Future<({int updatedAt, String origin})?> rowState(
    Database db,
    String table,
    String rowId,
  ) async {
    final List<Map<String, Object?>> rows = await db.query(
      _rowStateTable,
      where: 'tableName = ? AND rowId = ?',
      whereArgs: <Object?>[table, rowId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return (
      updatedAt: (rows.first['updatedAt'] ?? 0) as int,
      origin: (rows.first['origin'] ?? '') as String,
    );
  }

  Future<void> putRowState(
    Database db, {
    required String table,
    required String rowId,
    required int updatedAt,
    required String origin,
  }) async {
    await db.insert(
      _rowStateTable,
      <String, Object?>{
        'tableName': table,
        'rowId': rowId,
        'updatedAt': updatedAt,
        'origin': origin,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ----------------------------------------------------------- applied ops

  Future<bool> isApplied(Database db, String opId) async {
    final List<Map<String, Object?>> rows = await db.query(
      _appliedTable,
      columns: <String>['opId'],
      where: 'opId = ?',
      whereArgs: <Object?>[opId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markApplied(Database db, String opId) async {
    await db.insert(
      _appliedTable,
      <String, Object?>{
        'opId': opId,
        'appliedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Records a failed apply and reports whether the op should be retried.
  Future<bool> registerFailedApply(Database db, String opId) async {
    final List<Map<String, Object?>> rows = await db.query(
      _appliedTable,
      where: 'opId = ?',
      whereArgs: <Object?>[opId],
      limit: 1,
    );
    final int attempts = rows.isEmpty
        ? 1
        : ((rows.first['attempts'] ?? 0) as int) + 1;

    await db.insert(
      _appliedTable,
      <String, Object?>{
        'opId': opId,
        'appliedAt': DateTime.now().millisecondsSinceEpoch,
        'attempts': attempts,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return attempts < maxApplyAttempts;
  }

  // ----------------------------------------------------------- state store

  Future<String?> state(Database db, String key) async {
    final List<Map<String, Object?>> rows = await db.query(
      _stateTable,
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> setStateValue(Database db, String key, String value) async {
    await db.insert(
      _stateTable,
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearState(Database db, String key) async {
    await db.delete(_stateTable, where: 'key = ?', whereArgs: <Object?>[key]);
  }

  // ---------------------------------------------------------------- helpers

  Future<Map<String, Object?>?> _readRow(
    Database db,
    String table,
    String rowId,
  ) async {
    final String? pk = kSyncPrimaryKeys[table];
    if (pk == null) {
      return null;
    }
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: '$pk = ?',
      whereArgs: <Object?>[_coercePk(rowId, table)],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// sqflite needs the right Dart type for the primary key comparison.
  Object? _coercePk(String rowId, String table) {
    final String? pk = kSyncPrimaryKeys[table];
    if (pk == 'settingKey') {
      return rowId;
    }
    return int.tryParse(rowId) ?? rowId;
  }
}
