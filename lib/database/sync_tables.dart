import 'package:sqflite/sqflite.dart';

/// Local schema and capture plumbing for the Linked Devices sync engine.
///
/// Design goal: **capture every local mutation without touching a single line
/// of business/calculation logic.** That is achieved with SQLite triggers, so
/// no write path in `DatabaseHelper` had to be modified — any INSERT/UPDATE/
/// DELETE that reaches these tables is journaled automatically, including the
/// ones produced by CSV restore or snapshot recalculation.
///
/// Tables created here:
///  * `sync_outbox`     – pending local mutations waiting to be pushed.
///  * `sync_row_state`  – last-writer-wins metadata per row.
///  * `sync_applied_ops`– ids of remote ops already applied (replay safety).
///  * `sync_state`      – small key/value store (cursor, capture switch, …).
library;

/// Tables whose contents replicate to linked devices.
const List<String> kSyncedTables = <String>[
  'customers',
  'entries',
  'summary_snapshots',
  'ledger_years',
  'app_settings',
];

/// Primary key column of every synced table.
const Map<String, String> kSyncPrimaryKeys = <String, String>{
  'customers': 'id',
  'entries': 'id',
  'summary_snapshots': 'id',
  'ledger_years': 'year',
  'app_settings': 'settingKey',
};

/// `app_settings` keys that are per-device preferences and must not replicate.
const List<String> kLocalOnlySettings = <String>[
  'activeYear',
  'sidebar.notes',
];

/// `sync_state` key that suspends outbox capture while remote ops are applied.
const String kSyncCaptureStateKey = 'syncCapture';

/// Value written to [kSyncCaptureStateKey] to suspend capture.
const String kSyncCaptureOff = 'off';

/// `sync_state` key holding the id of the newest remote op already applied.
const String kSyncCursorStateKey = 'lastAppliedOpId';

/// `sync_state` key holding this device's workspace membership document id.
const String kSyncWorkspaceStateKey = 'linkedWorkspaceId';

const String _syncOutboxTable = 'sync_outbox';
const String _syncRowStateTable = 'sync_row_state';
const String _syncAppliedOpsTable = 'sync_applied_ops';
const String _syncStateTable = 'sync_state';

/// SQL that turns capture back on. Kept as a constant so the engine and the
/// schema module cannot drift apart.
const String kSyncCaptureResumeSql =
    "INSERT OR REPLACE INTO $_syncStateTable(key, value) "
    "VALUES('$kSyncCaptureStateKey', 'on')";

/// SQL that suspends capture.
const String kSyncCaptureSuspendSql =
    "INSERT OR REPLACE INTO $_syncStateTable(key, value) "
    "VALUES('$kSyncCaptureStateKey', '$kSyncCaptureOff')";

/// Creates the sync tables, indexes and capture triggers.
///
/// Safe to call on every database open — everything is `IF NOT EXISTS`.
Future<void> ensureSyncSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS $_syncOutboxTable(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      action TEXT NOT NULL,
      capturedAt INTEGER NOT NULL,
      pushed INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS $_syncRowStateTable(
      tableName TEXT NOT NULL,
      rowId TEXT NOT NULL,
      updatedAt INTEGER NOT NULL,
      origin TEXT NOT NULL,
      PRIMARY KEY(tableName, rowId)
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS $_syncAppliedOpsTable(
      opId TEXT PRIMARY KEY,
      appliedAt INTEGER NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS $_syncStateTable(
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending '
    'ON $_syncOutboxTable(pushed, id)',
  );

  for (final String table in kSyncedTables) {
    final String pk = kSyncPrimaryKeys[table]!;
    // `capture` is on by default: `NULL IS NOT 'off'` evaluates to true, so a
    // fresh database journals mutations before any state row exists.
    const String captureGuard =
        "(SELECT value FROM $_syncStateTable WHERE key = '$kSyncCaptureStateKey') "
        "IS NOT '$kSyncCaptureOff'";

    String settingsFilter(String alias) => table == 'app_settings'
        ? " AND $alias.settingKey NOT IN "
            "(${kLocalOnlySettings.map((String k) => "'$k'").join(', ')})"
        : '';

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS sync_ai_$table
      AFTER INSERT ON $table
      WHEN $captureGuard${settingsFilter('NEW')}
      BEGIN
        INSERT INTO $_syncOutboxTable(tableName, rowId, action, capturedAt)
        VALUES ('$table', CAST(NEW.$pk AS TEXT), 'upsert',
                CAST(strftime('%s', 'now') AS INTEGER) * 1000);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS sync_au_$table
      AFTER UPDATE ON $table
      WHEN $captureGuard${settingsFilter('NEW')}
      BEGIN
        INSERT INTO $_syncOutboxTable(tableName, rowId, action, capturedAt)
        VALUES ('$table', CAST(NEW.$pk AS TEXT), 'upsert',
                CAST(strftime('%s', 'now') AS INTEGER) * 1000);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS sync_ad_$table
      AFTER DELETE ON $table
      WHEN $captureGuard${settingsFilter('OLD')}
      BEGIN
        INSERT INTO $_syncOutboxTable(tableName, rowId, action, capturedAt)
        VALUES ('$table', CAST(OLD.$pk AS TEXT), 'delete',
                CAST(strftime('%s', 'now') AS INTEGER) * 1000);
      END
    ''');
  }
}
