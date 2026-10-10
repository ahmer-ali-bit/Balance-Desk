import 'package:flutter_test/flutter_test.dart';
import 'package:shop/database/sync_tables.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These tests run the **real** `ensureSyncSchema()` against a real SQLite
/// database (sqflite_common_ffi), so the capture triggers that Linked Devices
/// depends on are exercised exactly as they will be on a device.
///
/// The business tables below mirror `DatabaseHelper._createTables`; they only
/// exist so the triggers have something to observe.
const String _businessSchema = '''
CREATE TABLE IF NOT EXISTS ledger_years(
  year INTEGER PRIMARY KEY,
  createdAt TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS app_settings(
  settingKey TEXT PRIMARY KEY,
  settingValue TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS customers(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  address TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  ledgerYear INTEGER NOT NULL DEFAULT 2026,
  isStockLedger INTEGER NOT NULL DEFAULT 0,
  useWeight INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS entries(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  customerId INTEGER NOT NULL,
  entryDate TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  pageNo TEXT NOT NULL DEFAULT '',
  dailyLogPageNo TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL,
  debit REAL NOT NULL DEFAULT 0,
  credit REAL NOT NULL DEFAULT 0,
  buyBags REAL NOT NULL DEFAULT 0,
  sellBags REAL NOT NULL DEFAULT 0,
  showInDailyLog INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY(customerId) REFERENCES customers(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS summary_snapshots(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ledgerYear INTEGER NOT NULL DEFAULT 2026,
  savedAt TEXT NOT NULL,
  overallDebit REAL NOT NULL DEFAULT 0,
  overallCredit REAL NOT NULL DEFAULT 0,
  customerCount INTEGER NOT NULL DEFAULT 0,
  dailyLogPageNo TEXT NOT NULL DEFAULT ''
);
''';

Future<List<Map<String, Object?>>> _outbox(Database db) =>
    db.query('sync_outbox', orderBy: 'id ASC');

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    for (final String statement in _businessSchema.split(';')) {
      if (statement.trim().isNotEmpty) {
        await db.execute(statement);
      }
    }
    await ensureSyncSchema(db);
  });

  tearDown(() async => db.close());

  test('creates the four sync tables', () async {
    final List<Map<String, Object?>> tables = await db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: "type = 'table'",
    );
    final Set<String> names =
        tables.map((Map<String, Object?> row) => row['name'] as String).toSet();

    expect(
      names,
      containsAll(<String>[
        'sync_outbox',
        'sync_row_state',
        'sync_applied_ops',
        'sync_state',
      ]),
    );
  });

  test('installs one insert/update/delete trigger per synced table', () async {
    final List<Map<String, Object?>> triggers = await db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: "type = 'trigger'",
    );

    // 5 synced tables x 3 trigger kinds.
    expect(triggers.length, kSyncedTables.length * 3);

    for (final String table in kSyncedTables) {
      expect(
        triggers.map((Map<String, Object?> row) => row['name']),
        containsAll(<String>['sync_ai_$table', 'sync_au_$table', 'sync_ad_$table']),
      );
    }
  });

  test('is idempotent — running it twice does not break anything', () async {
    await expectLater(ensureSyncSchema(db), completes);
    await db.insert('customers', <String, Object?>{'name': 'Ali'});
    expect((await _outbox(db)).length, 1);
  });

  group('capture', () {
    test('journals inserts, updates and deletes', () async {
      await db.insert('customers', <String, Object?>{'name': 'Ali'});
      await db.update(
        'customers',
        <String, Object?>{'phone': '0300'},
        where: 'id = 1',
      );
      await db.delete('customers', where: 'id = 1');

      final List<Map<String, Object?>> rows = await _outbox(db);
      expect(rows.length, 3);
      expect(
        rows.map((Map<String, Object?> r) => r['action']).toList(),
        <String>['upsert', 'upsert', 'delete'],
      );
      expect(
        rows.every((Map<String, Object?> r) => r['tableName'] == 'customers'),
        isTrue,
      );
      expect(
        rows.every((Map<String, Object?> r) => r['rowId'] == '1'),
        isTrue,
      );
    });

    test('uses the ledger_years primary key (year), not a rowid', () async {
      await db.insert(
        'ledger_years',
        <String, Object?>{'year': 2027, 'createdAt': '2026-01-01'},
      );

      final List<Map<String, Object?>> rows = await _outbox(db);
      expect(rows.single['tableName'], 'ledger_years');
      expect(rows.single['rowId'], '2027');
    });

    test('journals a cascade delete caused by removing a customer', () async {
      await db.insert('customers', <String, Object?>{'name': 'Ali'});
      await db.insert('entries', <String, Object?>{
        'customerId': 1,
        'entryDate': '2026-01-01',
        'createdAt': '2026-01-01',
        'description': 'sale',
        'debit': 100,
      });
      await db.delete('customers', where: 'id = 1');

      final List<Map<String, Object?>> rows = await _outbox(db);
      final List<String> deleted = rows
          .where((Map<String, Object?> r) => r['action'] == 'delete')
          .map((Map<String, Object?> r) => r['tableName'] as String)
          .toList();

      expect(deleted, containsAll(<String>['customers', 'entries']));
    });
  });

  group('app_settings filtering', () {
    for (final String key in kLocalOnlySettings) {
      test('"$key" is per-device and never replicates', () async {
        await db.insert(
          'app_settings',
          <String, Object?>{'settingKey': key, 'settingValue': 'x'},
        );
        expect(await _outbox(db), isEmpty);
      });
    }

    test('opening balances do replicate', () async {
      await db.insert('app_settings', <String, Object?>{
        'settingKey': 'ledgerOpeningDebit:2026:1',
        'settingValue': '500',
      });

      final List<Map<String, Object?>> rows = await _outbox(db);
      expect(rows.single['tableName'], 'app_settings');
      expect(rows.single['rowId'], 'ledgerOpeningDebit:2026:1');
    });
  });

  group('capture suspension', () {
    test('stops the echo-back while remote ops are applied', () async {
      await db.insert('customers', <String, Object?>{'name': 'Ali'});
      expect((await _outbox(db)).length, 1);

      // This is the exact statement the sync engine runs before applying.
      await db.execute(kSyncCaptureSuspendSql);
      await db.insert('customers', <String, Object?>{'name': 'Bilal'});
      expect(
        (await _outbox(db)).length,
        1,
        reason: 'an applied remote change must not be pushed back out',
      );

      await db.execute(kSyncCaptureResumeSql);
      await db.insert('customers', <String, Object?>{'name': 'Usman'});
      expect((await _outbox(db)).length, 2);
    });

    test('capture is on by default, before any state row exists', () async {
      final List<Map<String, Object?>> state = await db.query('sync_state');
      expect(state, isEmpty);

      await db.insert('customers', <String, Object?>{'name': 'Ali'});
      expect((await _outbox(db)).length, 1);
    });
  });
}
