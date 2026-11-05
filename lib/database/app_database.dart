import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    show
        Batch,
        ConflictAlgorithm,
        Database,
        DatabaseFactory,
        OpenDatabaseOptions,
        QueryCursor,
        Transaction,
        databaseFactory,
        getDatabasesPath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:flutter/foundation.dart';

import '../models/snapshot_opening_balance.dart';
import '../services/workspace_service.dart';

/// Thrown whenever a write is attempted while the active workspace is linked
/// to a main device in read-only mode.
class ReadOnlyWorkspaceException implements Exception {
  const ReadOnlyWorkspaceException([
    this.message =
        'This device is linked in read-only mode. Ask the main device for edit access.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static bool _ffiInitialized = false;

  static const String customersTable = 'customers';
  static const String entriesTable = 'entries';
  static const String summarySnapshotsTable = 'summary_snapshots';
  static const String ledgerYearsTable = 'ledger_years';
  static const String appSettingsTable = 'app_settings';
  static const String syncTombstonesTable = 'sync_tombstones';
  static const String syncStateTable = 'sync_state';
  static const String syncOrphansTable = 'sync_orphans';
  static const String _activeYearSettingKey = 'activeYear';
  static const int _databaseVersion = 6;

  /// Tables that participate in linked-device synchronisation, in the order
  /// they must be applied so foreign keys always resolve.
  static const List<String> syncedTables = <String>[
    ledgerYearsTable,
    customersTable,
    entriesTable,
    summarySnapshotsTable,
    appSettingsTable,
  ];

  Database? _database;
  int _activeYear = DateTime.now().year;

  /// Guard installed by the linked-devices layer. When it returns `false` the
  /// workspace is read-only and every mutating call throws
  /// [ReadOnlyWorkspaceException] — the restriction is therefore enforced at
  /// the data layer, not only in the UI.
  bool Function()? writeGuard;

  bool _isApplyingRemoteChanges = false;

  /// `true` while the sync engine is writing records that came from the cloud.
  bool get isApplyingRemoteChanges => _isApplyingRemoteChanges;

  int get activeYear => _activeYear;

  /// Throws when the active workspace is linked in read-only mode.
  void _assertWritable() {
    if (_isApplyingRemoteChanges) {
      return;
    }
    final guard = writeGuard;
    if (guard == null) {
      return;
    }
    if (!guard()) {
      throw const ReadOnlyWorkspaceException();
    }
  }

  /// Runs [action] with the read-only guard suspended and without stamping
  /// local sync metadata, so remote records can be applied verbatim.
  Future<T> runAsRemoteApply<T>(Future<T> Function() action) async {
    final previous = _isApplyingRemoteChanges;
    _isApplyingRemoteChanges = true;
    try {
      return await action();
    } finally {
      _isApplyingRemoteChanges = previous;
    }
  }

  String _snapshotOpeningDebitSettingKey(int year) =>
      'snapshotOpeningDebit:$year';
  String _snapshotOpeningCreditSettingKey(int year) =>
      'snapshotOpeningCredit:$year';
  String _customerLedgerOpeningDebitSettingKey({
    required int year,
    required int customerId,
  }) => 'ledgerOpeningDebit:$year:$customerId';
  String _customerLedgerOpeningCreditSettingKey({
    required int year,
    required int customerId,
  }) => 'ledgerOpeningCredit:$year:$customerId';

  String _customerLedgerOpeningBuyBagsSettingKey({
    required int year,
    required int customerId,
  }) => 'ledgerOpeningBuyBags:$year:$customerId';

  String _customerLedgerOpeningSellBagsSettingKey({
    required int year,
    required int customerId,
  }) => 'ledgerOpeningSellBags:$year:$customerId';

  Future<void> initialize() async {
    await database;
  }

  Future<String> get databasePath => _resolveDatabasePath();

  Database? _rawDatabase;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    try {
      _rawDatabase ??= await _databaseFactory.openDatabase(
        await _resolveDatabasePath(),
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onConfigure: (Database db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await _createTables(db);
            await _ensureYearInfrastructure(db);
            await _ensureSyncInfrastructure(db);
            await _ensureIndexes(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            await _createTables(db);
            await _ensureYearInfrastructure(db);
            await _ensureSyncInfrastructure(db);
            await _ensureIndexes(db);
          },
          onOpen: (db) async {
            await _createTables(db);
            await _ensureYearInfrastructure(db);
            await _ensureSyncInfrastructure(db);
            await _ensureIndexes(db);
            await _loadActiveYear(db);
          },
        ),
      );
      _database = _ChangeReportingDatabase(
        _rawDatabase!,
        onLocalWrite: _onLocalWrite,
        watchedTables: <String>{...syncedTables, syncTombstonesTable},
      );
    } catch (error) {
      debugPrint('Database open failed: $error');
      rethrow;
    }

    return _database!;
  }

  /// A write on this device that the cloud still has to hear about.
  ///
  /// The sync engine debounces these into a single push, so a burst of edits
  /// costs one cycle rather than one cycle per keystroke.
  void _onLocalWrite() {
    if (_isApplyingRemoteChanges) return;
    AppDatabase.instance.notifyDataChanged();
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  DatabaseFactory get _databaseFactory {
    if (_isDesktop) {
      if (!_ffiInitialized) {
        sqfliteFfiInit();
        _ffiInitialized = true;
      }
      return databaseFactoryFfi;
    }

    return databaseFactory;
  }

  Future<String> _resolveDatabasePath() async {
    final basePath = await _resolveDatabaseBasePath();
    final databaseFolder = Directory(path.join(basePath, 'local'));
    if (!await databaseFolder.exists()) {
      await databaseFolder.create(recursive: true);
    }

    final dbName = WorkspaceService.instance.activeDatabaseName;
    return path.join(databaseFolder.path, dbName);
  }

  /// Closes the current database and reopens with the active workspace's DB.
  Future<void> switchDatabase() async {
    await close();
    await initialize();
  }

  /// Deletes the database file for a specific workspace.
  Future<void> deleteWorkspaceDatabase(String workspaceId) async {
    // If it's the default, we don't delete it (or we could, but it's risky)
    if (workspaceId == 'default') return;

    final basePath = await _resolveDatabaseBasePath();
    final dbName = WorkspaceService.instance.databaseNameForWorkspace(
      workspaceId,
    );
    final fullPath = path.join(basePath, 'local', dbName);
    final file = File(fullPath);
    if (await file.exists()) {
      // Ensure current DB is not this one
      if (_database != null) {
        final currentPath = await _resolveDatabasePath();
        if (currentPath == fullPath) {
          await close();
        }
      }
      await file.delete();
    }
  }

  Future<String> _resolveDatabaseBasePath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return path.join(await getDatabasesPath(), 'shop_ledger');
    }

    try {
      final baseDirectory = await getApplicationSupportDirectory();
      return path.join(baseDirectory.path, 'shop_ledger');
    } catch (_) {
      return path.join(_resolveDesktopFallbackPath(), 'shop_ledger');
    }
  }

  String _resolveDesktopFallbackPath() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return appData;
    }

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return userProfile;
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return home;
    }

    return Directory.systemTemp.path;
  }

  Future<void> _createTables(Database db) async {
    final defaultYear = DateTime.now().year;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $ledgerYearsTable(
        year INTEGER PRIMARY KEY,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $appSettingsTable(
        settingKey TEXT PRIMARY KEY,
        settingValue TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $customersTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        address TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        ledgerYear INTEGER NOT NULL DEFAULT $defaultYear,
        isStockLedger INTEGER NOT NULL DEFAULT 0,
        useWeight INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $entriesTable(
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
        FOREIGN KEY(customerId) REFERENCES $customersTable(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $summarySnapshotsTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ledgerYear INTEGER NOT NULL DEFAULT $defaultYear,
        savedAt TEXT NOT NULL,
        overallDebit REAL NOT NULL DEFAULT 0,
        overallCredit REAL NOT NULL DEFAULT 0,
        customerCount INTEGER NOT NULL DEFAULT 0,
        dailyLogPageNo TEXT NOT NULL DEFAULT ''
      )
    ''');

    // Deleted records are remembered here so a delete performed on one device
    // propagates to every other device and never gets resurrected by a stale
    // upload from a device that was offline when the delete happened.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncTombstonesTable(
        entity TEXT NOT NULL,
        syncId TEXT NOT NULL,
        deletedAt TEXT NOT NULL,
        pushPending INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY(entity, syncId)
      )
    ''');

    // Sync bookkeeping (link configuration + per-entity pull cursors). Never
    // synchronised and never part of a CSV backup, so it always describes the
    // device it lives on.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncStateTable(
        stateKey TEXT PRIMARY KEY,
        stateValue TEXT NOT NULL
      )
    ''');

    // Records that arrived before their parent (e.g. an entry whose customer
    // has not been downloaded yet). Retried on every sync cycle.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $syncOrphansTable(
        entity TEXT NOT NULL,
        syncId TEXT NOT NULL,
        payload TEXT NOT NULL,
        receivedAt TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(entity, syncId)
      )
    ''');
  }

  Future<void> _ensureYearInfrastructure(Database db) async {
    final defaultYear = DateTime.now().year;
    final now = DateTime.now().toIso8601String();

    await db.insert(ledgerYearsTable, <String, Object?>{
      'year': defaultYear,
      'createdAt': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await _ensureColumn(
      db: db,
      tableName: customersTable,
      columnName: 'ledgerYear',
      definition: 'INTEGER NOT NULL DEFAULT $defaultYear',
    );
    await _ensureColumn(
      db: db,
      tableName: customersTable,
      columnName: 'address',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db: db,
      tableName: customersTable,
      columnName: 'phone',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db: db,
      tableName: summarySnapshotsTable,
      columnName: 'ledgerYear',
      definition: 'INTEGER NOT NULL DEFAULT $defaultYear',
    );
    await _ensureColumn(
      db: db,
      tableName: entriesTable,
      columnName: 'pageNo',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db: db,
      tableName: entriesTable,
      columnName: 'dailyLogPageNo',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db: db,
      tableName: summarySnapshotsTable,
      columnName: 'dailyLogPageNo',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db: db,
      tableName: entriesTable,
      columnName: 'showInDailyLog',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      db: db,
      tableName: entriesTable,
      columnName: 'buyBags',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db: db,
      tableName: entriesTable,
      columnName: 'sellBags',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db: db,
      tableName: customersTable,
      columnName: 'isStockLedger',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db: db,
      tableName: customersTable,
      columnName: 'useWeight',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _ensureIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_ledger_year ON $customersTable(ledgerYear)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_customer_id ON $entriesTable(customerId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_entry_date ON $entriesTable(entryDate)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_entries_created_at ON $entriesTable(createdAt)',
    );

    for (final String table in <String>[
      customersTable,
      entriesTable,
      summarySnapshotsTable,
    ]) {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_sync_id ON $table(syncId)',
      );
    }
    for (final String table in syncedTables) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_${table}_push_pending ON $table(pushPending)',
      );
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_tombstones_pending ON $syncTombstonesTable(pushPending)',
    );
  }

  // ---------------------------------------------------------------------------
  // Linked-device sync infrastructure
  // ---------------------------------------------------------------------------

  /// SQL expression producing an ISO-8601 UTC stamp with millisecond
  /// precision. Matches [syncTimestamp] exactly so local and remote stamps can
  /// be compared as plain strings.
  static const String _sqlNow = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";

  /// SQL expression producing a random 128-bit identifier in UUID shape. Used
  /// as the cross-device identity of a row, because the local `id` columns are
  /// `AUTOINCREMENT` and therefore collide between devices.
  static const String _sqlUuid =
      "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' || "
      "lower(hex(randomblob(2))) || '-' || lower(hex(randomblob(2))) || '-' || "
      "lower(hex(randomblob(6)))";

  static const String _syncTriggerRevision = '1';

  /// Current time formatted exactly like [_sqlNow].
  static String syncTimestamp([DateTime? time]) {
    final DateTime value = (time ?? DateTime.now()).toUtc();
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
    ).toIso8601String();
  }

  Future<void> _ensureSyncInfrastructure(Database db) async {
    // Added after the first release: a received record used to be thrown away
    // on the first failure, so the retry counter has to exist on databases that
    // were created before it.
    await _ensureColumn(
      db: db,
      tableName: syncOrphansTable,
      columnName: 'attempts',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );

    for (final String table in <String>[
      customersTable,
      entriesTable,
      summarySnapshotsTable,
    ]) {
      await _ensureColumn(
        db: db,
        tableName: table,
        columnName: 'syncId',
        definition: 'TEXT',
      );
    }
    for (final String table in syncedTables) {
      await _ensureColumn(
        db: db,
        tableName: table,
        columnName: 'updatedAt',
        definition: 'TEXT',
      );
      await _ensureColumn(
        db: db,
        tableName: table,
        columnName: 'pushPending',
        definition: 'INTEGER NOT NULL DEFAULT 1',
      );
    }

    // Backfill identities for rows that existed before this migration.
    await db.execute(
      'UPDATE $customersTable SET syncId = $_sqlUuid WHERE syncId IS NULL OR syncId = \'\'',
    );
    await db.execute(
      'UPDATE $entriesTable SET syncId = $_sqlUuid WHERE syncId IS NULL OR syncId = \'\'',
    );
    await db.execute(
      'UPDATE $summarySnapshotsTable SET syncId = $_sqlUuid WHERE syncId IS NULL OR syncId = \'\'',
    );
    await db.execute(
      'UPDATE $entriesTable SET updatedAt = COALESCE(createdAt, $_sqlNow) WHERE updatedAt IS NULL',
    );
    await db.execute(
      'UPDATE $summarySnapshotsTable SET updatedAt = COALESCE(savedAt, $_sqlNow) WHERE updatedAt IS NULL',
    );
    await db.execute(
      'UPDATE $ledgerYearsTable SET updatedAt = COALESCE(createdAt, $_sqlNow) WHERE updatedAt IS NULL',
    );
    for (final String table in <String>[customersTable, appSettingsTable]) {
      await db.execute(
        'UPDATE $table SET updatedAt = $_sqlNow WHERE updatedAt IS NULL',
      );
    }

    final revisionRows = await db.query(
      syncStateTable,
      columns: <String>['stateValue'],
      where: 'stateKey = ?',
      whereArgs: <Object?>['schema.syncTriggers'],
      limit: 1,
    );
    if (revisionRows.isNotEmpty &&
        revisionRows.first['stateValue'] == _syncTriggerRevision) {
      return;
    }

    await _createRowSyncTriggers(db, customersTable);
    await _createRowSyncTriggers(db, entriesTable);
    await _createRowSyncTriggers(db, summarySnapshotsTable);
    await _createKeyedSyncTriggers(db, appSettingsTable, 'settingKey');
    await _createKeyedSyncTriggers(db, ledgerYearsTable, 'year');

    await db.insert(syncStateTable, <String, Object?>{
      'stateKey': 'schema.syncTriggers',
      'stateValue': _syncTriggerRevision,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Triggers for tables identified across devices by a generated `syncId`.
  Future<void> _createRowSyncTriggers(Database db, String table) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_${table}_sync_ins');
    await db.execute('DROP TRIGGER IF EXISTS trg_${table}_sync_upd');
    await db.execute('DROP TRIGGER IF EXISTS trg_${table}_sync_del');

    await db.execute('''
      CREATE TRIGGER trg_${table}_sync_ins
      AFTER INSERT ON $table
      WHEN NEW.updatedAt IS NULL
      BEGIN
        UPDATE $table
           SET syncId = COALESCE(NULLIF(NEW.syncId, ''), $_sqlUuid),
               updatedAt = $_sqlNow,
               pushPending = 1
         WHERE rowid = NEW.rowid;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_${table}_sync_upd
      AFTER UPDATE ON $table
      WHEN NEW.updatedAt IS OLD.updatedAt
       AND NEW.pushPending IS OLD.pushPending
      BEGIN
        UPDATE $table
           SET syncId = COALESCE(NULLIF(NEW.syncId, ''), $_sqlUuid),
               updatedAt = $_sqlNow,
               pushPending = 1
         WHERE rowid = NEW.rowid;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_${table}_sync_del
      AFTER DELETE ON $table
      WHEN OLD.syncId IS NOT NULL AND OLD.syncId != ''
      BEGIN
        INSERT OR REPLACE INTO $syncTombstonesTable(
          entity, syncId, deletedAt, pushPending
        ) VALUES('$table', OLD.syncId, $_sqlNow, 1);
      END
    ''');
  }

  /// Triggers for tables whose primary key is already globally unique.
  Future<void> _createKeyedSyncTriggers(
    Database db,
    String table,
    String keyColumn,
  ) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_${table}_sync_ins');
    await db.execute('DROP TRIGGER IF EXISTS trg_${table}_sync_upd');
    await db.execute('DROP TRIGGER IF EXISTS trg_${table}_sync_del');

    await db.execute('''
      CREATE TRIGGER trg_${table}_sync_ins
      AFTER INSERT ON $table
      WHEN NEW.updatedAt IS NULL
      BEGIN
        UPDATE $table
           SET updatedAt = $_sqlNow, pushPending = 1
         WHERE $keyColumn = NEW.$keyColumn;
        DELETE FROM $syncTombstonesTable
         WHERE entity = '$table' AND syncId = CAST(NEW.$keyColumn AS TEXT);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_${table}_sync_upd
      AFTER UPDATE ON $table
      WHEN NEW.updatedAt IS OLD.updatedAt
       AND NEW.pushPending IS OLD.pushPending
      BEGIN
        UPDATE $table
           SET updatedAt = $_sqlNow, pushPending = 1
         WHERE $keyColumn = NEW.$keyColumn;
        DELETE FROM $syncTombstonesTable
         WHERE entity = '$table' AND syncId = CAST(NEW.$keyColumn AS TEXT);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_${table}_sync_del
      AFTER DELETE ON $table
      BEGIN
        INSERT OR REPLACE INTO $syncTombstonesTable(
          entity, syncId, deletedAt, pushPending
        ) VALUES('$table', CAST(OLD.$keyColumn AS TEXT), $_sqlNow, 1);
      END
    ''');
  }

  Future<void> _ensureColumn({
    required Database db,
    required String tableName,
    required String columnName,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = columns.any(
      (Map<String, Object?> column) => column['name'] == columnName,
    );

    if (hasColumn) {
      return;
    }

    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $definition',
    );
  }

  Future<void> _loadActiveYear(Database db) async {
    final rows = await db.query(
      appSettingsTable,
      columns: <String>['settingValue'],
      where: 'settingKey = ?',
      whereArgs: <Object?>[_activeYearSettingKey],
      limit: 1,
    );

    final storedYear = rows.isEmpty
        ? null
        : int.tryParse(rows.first['settingValue'] as String? ?? '');
    final year = storedYear ?? DateTime.now().year;

    await _ensureLedgerYear(db, year);
    await _saveActiveYearSetting(db, year);
    _activeYear = year;
  }

  Future<void> _ensureLedgerYear(Database db, int year) async {
    await db.insert(ledgerYearsTable, <String, Object?>{
      'year': year,
      'createdAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _saveActiveYearSetting(Database db, int year) async {
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _activeYearSettingKey,
      'settingValue': year.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getAppSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      appSettingsTable,
      columns: <String>['settingValue'],
      where: 'settingKey = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['settingValue'] as String?;
  }

  Future<void> setAppSetting({
    required String key,
    required String value,
  }) async {
    if (isSyncableSettingKey(key)) {
      _assertWritable();
    }
    final db = await database;
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': key,
      'settingValue': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SnapshotOpeningBalance?> getSnapshotOpeningBalance() async {
    final debitSetting = await getAppSetting(
      _snapshotOpeningDebitSettingKey(_activeYear),
    );
    final creditSetting = await getAppSetting(
      _snapshotOpeningCreditSettingKey(_activeYear),
    );

    if (debitSetting == null && creditSetting == null) {
      return null;
    }

    return SnapshotOpeningBalance(
      debit: double.tryParse(debitSetting ?? '') ?? 0,
      credit: double.tryParse(creditSetting ?? '') ?? 0,
      buyBags: 0,
      sellBags: 0,
    );
  }

  Future<void> setSnapshotOpeningBalance({
    required double debit,
    required double credit,
  }) async {
    _assertWritable();
    final db = await database;
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _snapshotOpeningDebitSettingKey(_activeYear),
      'settingValue': debit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _snapshotOpeningCreditSettingKey(_activeYear),
      'settingValue': credit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearSnapshotOpeningBalance() async {
    _assertWritable();
    final db = await database;
    await db.delete(
      appSettingsTable,
      where: 'settingKey IN (?, ?)',
      whereArgs: <Object?>[
        _snapshotOpeningDebitSettingKey(_activeYear),
        _snapshotOpeningCreditSettingKey(_activeYear),
      ],
    );
  }

  Future<SnapshotOpeningBalance?> getCustomerLedgerOpeningBalance(
    int customerId,
  ) async {
    final debitSetting = await getAppSetting(
      _customerLedgerOpeningDebitSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
    );
    final creditSetting = await getAppSetting(
      _customerLedgerOpeningCreditSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
    );

    final buyBagsSetting = await getAppSetting(
      _customerLedgerOpeningBuyBagsSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
    );
    final sellBagsSetting = await getAppSetting(
      _customerLedgerOpeningSellBagsSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
    );

    if (debitSetting == null &&
        creditSetting == null &&
        buyBagsSetting == null &&
        sellBagsSetting == null) {
      return null;
    }

    return SnapshotOpeningBalance(
      debit: double.tryParse(debitSetting ?? '') ?? 0,
      credit: double.tryParse(creditSetting ?? '') ?? 0,
      buyBags: double.tryParse(buyBagsSetting ?? '') ?? 0,
      sellBags: double.tryParse(sellBagsSetting ?? '') ?? 0,
    );
  }

  Future<void> setCustomerLedgerOpeningBalance({
    required int customerId,
    required double debit,
    required double credit,
    double buyBags = 0,
    double sellBags = 0,
  }) async {
    _assertWritable();
    final db = await database;
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningDebitSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
      'settingValue': debit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningCreditSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
      'settingValue': credit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningBuyBagsSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
      'settingValue': buyBags.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningSellBagsSettingKey(
        year: _activeYear,
        customerId: customerId,
      ),
      'settingValue': sellBags.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearCustomerLedgerOpeningBalance(int customerId) async {
    _assertWritable();
    final db = await database;
    await db.delete(
      appSettingsTable,
      where: 'settingKey IN (?, ?, ?, ?)',
      whereArgs: <Object?>[
        _customerLedgerOpeningDebitSettingKey(
          year: _activeYear,
          customerId: customerId,
        ),
        _customerLedgerOpeningCreditSettingKey(
          year: _activeYear,
          customerId: customerId,
        ),
        _customerLedgerOpeningBuyBagsSettingKey(
          year: _activeYear,
          customerId: customerId,
        ),
        _customerLedgerOpeningSellBagsSettingKey(
          year: _activeYear,
          customerId: customerId,
        ),
      ],
    );
  }

  Future<int> addCustomer(
    String name, {
    String address = '',
    String phone = '',
  }) async {
    _assertWritable();
    final db = await database;
    return db.transaction<int>((Transaction txn) async {
      final countRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM $customersTable',
      );
      final countValue = countRows.isEmpty ? 0 : countRows.first['count'];
      final totalCustomers = countValue is int
          ? countValue
          : int.tryParse('$countValue') ?? 0;

      final values = <String, Object?>{
        'name': name.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'ledgerYear': _activeYear,
        'isStockLedger': 0,
      };

      if (totalCustomers == 0) {
        values['id'] = 0;
      }

      return txn.insert(customersTable, values);
    });
  }

  Future<bool> customerNameExists(
    String name, {
    int? excludingCustomerId,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return false;
    }

    final db = await database;
    final whereBuffer = StringBuffer(
      'ledgerYear = ? AND LOWER(TRIM(name)) = LOWER(TRIM(?))',
    );
    final whereArgs = <Object?>[_activeYear, trimmedName];

    if (excludingCustomerId != null) {
      whereBuffer.write(' AND id != ?');
      whereArgs.add(excludingCustomerId);
    }

    final rows = await db.query(
      customersTable,
      columns: <String>['id'],
      where: whereBuffer.toString(),
      whereArgs: whereArgs,
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> getCustomers() async {
    final db = await database;
    return db.query(
      customersTable,
      columns: <String>[
        'id',
        'name',
        'address',
        'phone',
        'isStockLedger',
        'useWeight',
      ],
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[_activeYear],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<Map<String, Object?>?> getCustomer(int id) async {
    final db = await database;
    final rows = await db.query(
      customersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> addEntry({
    required int customerId,
    required String entryDate,
    required String createdAt,
    required String pageNo,
    required String description,
    required double debit,
    required double credit,
  }) async {
    _assertWritable();
    final db = await database;
    return db.insert(entriesTable, <String, Object?>{
      'customerId': customerId,
      'entryDate': entryDate,
      'createdAt': createdAt,
      'pageNo': pageNo.trim(),
      'description': description.trim(),
      'debit': debit,
      'credit': credit,
      'buyBags': 0,
      'sellBags': 0,
    });
  }

  Future<int> addStockEntry({
    required int customerId,
    required String entryDate,
    required String createdAt,
    required String pageNo,
    required String description,
    required String buyBags,
    required double buyAmount,
    required String sellBags,
    required double sellAmount,
  }) async {
    _assertWritable();
    final db = await database;
    return db.insert(entriesTable, <String, Object?>{
      'customerId': customerId,
      'entryDate': entryDate,
      'createdAt': createdAt,
      'pageNo': pageNo.trim(),
      'description': description.trim(),
      'debit': buyAmount,
      'credit': sellAmount,
      'buyBags': buyBags,
      'sellBags': sellBags,
    });
  }

  Future<int> updateEntry({
    required int id,
    required String entryDate,
    required String pageNo,
    required String description,
    required double debit,
    required double credit,
  }) async {
    _assertWritable();
    final db = await database;
    return db.update(
      entriesTable,
      <String, Object?>{
        'entryDate': entryDate,
        'pageNo': pageNo.trim(),
        'description': description.trim(),
        'debit': debit,
        'credit': credit,
        'buyBags': 0,
        'sellBags': 0,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> transferEntry({
    required int entryId,
    required int newCustomerId,
  }) async {
    _assertWritable();
    final db = await database;
    return db.update(
      entriesTable,
      <String, Object?>{'customerId': newCustomerId},
      where: 'id = ?',
      whereArgs: <Object?>[entryId],
    );
  }

  Future<int> deleteEntry(int id) async {
    _assertWritable();
    final db = await database;
    return db.delete(entriesTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<int> updateStockEntry({
    required int id,
    required String entryDate,
    required String pageNo,
    required String description,
    required String buyBags,
    required double buyAmount,
    required String sellBags,
    required double sellAmount,
  }) async {
    _assertWritable();
    final db = await database;
    return db.update(
      entriesTable,
      <String, Object?>{
        'entryDate': entryDate,
        'pageNo': pageNo.trim(),
        'description': description.trim(),
        'debit': buyAmount,
        'credit': sellAmount,
        'buyBags': buyBags,
        'sellBags': sellBags,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> updateCustomer({
    required int id,
    required String name,
    String? address,
    String? phone,
  }) async {
    _assertWritable();
    final db = await database;
    final values = <String, Object?>{'name': name.trim()};
    if (address != null) {
      values['address'] = address.trim();
    }
    if (phone != null) {
      values['phone'] = phone.trim();
    }
    return db.update(
      customersTable,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateCustomerStockMode(int id, bool isStockLedger) async {
    _assertWritable();
    final db = await database;
    await db.update(
      customersTable,
      <String, Object?>{'isStockLedger': isStockLedger ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> updateCustomerWeightMode(int id, bool useWeight) async {
    _assertWritable();
    final db = await database;
    await db.update(
      customersTable,
      <String, Object?>{'useWeight': useWeight ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<Map<String, Object?>>> getEntriesByCustomer(
    int customerId,
  ) async {
    final db = await database;
    return db.query(
      entriesTable,
      columns: <String>[
        'id',
        'customerId',
        'entryDate',
        'createdAt',
        'pageNo',
        'dailyLogPageNo',
        'description',
        'debit',
        'credit',
        'buyBags',
        'sellBags',
        'showInDailyLog',
      ],
      where: 'customerId = ?',
      whereArgs: <Object?>[customerId],
      orderBy: 'createdAt DESC, entryDate DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getEntriesByDateRange({
    required int customerId,
    required String startDate,
    required String endDate,
  }) async {
    final db = await database;
    return db.query(
      entriesTable,
      columns: <String>[
        'id',
        'customerId',
        'entryDate',
        'createdAt',
        'pageNo',
        'description',
        'debit',
        'credit',
      ],
      where: 'customerId = ? AND entryDate >= ? AND entryDate <= ?',
      whereArgs: <Object?>[customerId, startDate, endDate],
      orderBy: 'createdAt DESC, entryDate DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getEntriesWithCustomerRange({
    String? startDate,
    required String endDate,
  }) async {
    final db = await database;
    final whereArgs = <Object?>[endDate];
    final whereClause = StringBuffer('e.createdAt <= ?');

    if (startDate != null) {
      whereClause.write(' AND e.createdAt > ?');
      whereArgs.add(startDate);
    }

    return db.rawQuery(
      '''
      SELECT
        e.id,
        e.customerId,
        e.entryDate,
        e.createdAt,
        e.pageNo,
        e.description,
        e.debit,
        e.credit,
        e.buyBags,
        e.sellBags,
        e.dailyLogPageNo,
        e.showInDailyLog,
        c.name AS customerName,
        c.useWeight,
        c.isStockLedger
      FROM $entriesTable e
      JOIN $customersTable c ON c.id = e.customerId
      WHERE ${whereClause.toString()} AND c.ledgerYear = ? AND e.showInDailyLog = 1
      ORDER BY e.createdAt DESC, e.entryDate DESC, e.id DESC
      ''',
      <Object?>[...whereArgs, _activeYear],
    );
  }

  Future<List<Map<String, Object?>>> getEntriesWithCustomerRangePaged({
    String? startDate,
    required String endDate,
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    final whereArgs = <Object?>[endDate];
    final whereClause = StringBuffer('e.createdAt <= ?');

    if (startDate != null) {
      whereClause.write(' AND e.createdAt > ?');
      whereArgs.add(startDate);
    }

    return db.rawQuery(
      '''
      SELECT
        e.id,
        e.customerId,
        e.entryDate,
        e.createdAt,
        e.pageNo,
        e.description,
        e.debit,
        e.credit,
        e.buyBags,
        e.sellBags,
        e.dailyLogPageNo,
        e.showInDailyLog,
        c.name AS customerName,
        c.useWeight,
        c.isStockLedger
      FROM $entriesTable e
      JOIN $customersTable c ON c.id = e.customerId
      WHERE ${whereClause.toString()} AND c.ledgerYear = ? AND e.showInDailyLog = 1
      ORDER BY e.createdAt DESC, e.entryDate DESC, e.id DESC
      LIMIT ? OFFSET ?
      ''',
      <Object?>[...whereArgs, _activeYear, limit, offset],
    );
  }

  Future<List<Map<String, Object?>>> getCustomerEntryTotalsSince({
    String? startCreatedAt,
  }) async {
    final db = await database;
    final args = <Object?>[_activeYear];
    final whereClause = StringBuffer('c.ledgerYear = ?');
    if (startCreatedAt != null) {
      whereClause.write(' AND e.createdAt > ?');
      args.add(startCreatedAt);
    }

    return db.rawQuery('''
      SELECT
        c.id AS customerId,
        SUM(e.debit) AS totalDebit,
        SUM(e.credit) AS totalCredit,
        COUNT(e.id) AS entryCount
      FROM $customersTable c
      JOIN $entriesTable e ON e.customerId = c.id
      WHERE ${whereClause.toString()}
      GROUP BY c.id
      ''', args);
  }

  Future<int> insertCustomer(
    String name, {
    String address = '',
    String phone = '',
  }) async {
    return addCustomer(name, address: address, phone: phone);
  }

  Future<int> addSummarySnapshot({
    required String savedAt,
    required double overallDebit,
    required double overallCredit,
    required int customerCount,
    String dailyLogPageNo = '',
  }) async {
    _assertWritable();
    final db = await database;
    return db.insert(summarySnapshotsTable, <String, Object?>{
      'ledgerYear': _activeYear,
      'savedAt': savedAt,
      'overallDebit': overallDebit,
      'overallCredit': overallCredit,
      'customerCount': customerCount,
      'dailyLogPageNo': dailyLogPageNo,
    });
  }

  Future<void> batchUpdateDailyLogPageNo({
    required List<int> entryIds,
    required String dailyLogPageNo,
  }) async {
    _assertWritable();
    final db = await database;
    final placeholders = entryIds.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE $entriesTable SET dailyLogPageNo = ? WHERE id IN ($placeholders)',
      [dailyLogPageNo, ...entryIds],
    );
  }

  Future<void> updateEntryDailyLogVisibility({
    required int entryId,
    required bool show,
  }) async {
    _assertWritable();
    final db = await database;
    await db.update(
      entriesTable,
      <String, Object?>{'showInDailyLog': show ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[entryId],
    );
  }

  Future<List<Map<String, Object?>>> getSummarySnapshots() async {
    final db = await database;
    return db.query(
      summarySnapshotsTable,
      columns: <String>[
        'id',
        'ledgerYear',
        'savedAt',
        'overallDebit',
        'overallCredit',
        'customerCount',
        'dailyLogPageNo',
      ],
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[_activeYear],
      orderBy: 'savedAt DESC, id DESC',
    );
  }

  Future<int> updateSummarySnapshotTotals({
    required int id,
    required double overallDebit,
    required double overallCredit,
  }) async {
    _assertWritable();
    final db = await database;
    return db.update(
      summarySnapshotsTable,
      <String, Object?>{
        'overallDebit': overallDebit,
        'overallCredit': overallCredit,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> updateSnapshotDailyLogPageNo({
    required int id,
    required String dailyLogPageNo,
  }) async {
    _assertWritable();
    final db = await database;
    return db.update(
      summarySnapshotsTable,
      <String, Object?>{'dailyLogPageNo': dailyLogPageNo},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> deleteSummarySnapshot(int id) async {
    _assertWritable();
    final db = await database;
    return db.delete(
      summarySnapshotsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> clearSummarySnapshots() async {
    _assertWritable();
    final db = await database;
    return db.delete(
      summarySnapshotsTable,
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[_activeYear],
    );
  }

  Future<void> addEntryToSavedSnapshot({
    required int entryId,
    required String savedAt,
    required String? dailyLogPageNo,
  }) async {
    _assertWritable();
    final db = await database;
    await db.update(
      entriesTable,
      <String, Object?>{
        'showInDailyLog': 1,
        'createdAt': savedAt,
        'dailyLogPageNo': ?dailyLogPageNo,
      },
      where: 'id = ?',
      whereArgs: <Object?>[entryId],
    );
    await recalculateAllSnapshots();
  }

  Future<void> recalculateAllSnapshots() async {
    _assertWritable();
    final snapshotRows = await getSummarySnapshots();
    final snapshots = List<Map<String, Object?>>.from(snapshotRows);
    snapshots.sort((a, b) {
      final savedAtA = a['savedAt'] as String;
      final savedAtB = b['savedAt'] as String;
      return savedAtA.compareTo(savedAtB);
    });

    final openingBalance = await getSnapshotOpeningBalance();

    String? previousSavedAt;
    SnapshotOpeningBalance currentStartingBalance =
        openingBalance ?? const SnapshotOpeningBalance(debit: 0, credit: 0);

    for (final snapshot in snapshots) {
      final snapshotId = snapshot['id'] as int?;
      final savedAt = snapshot['savedAt'] as String;
      if (snapshotId == null) continue;

      final entries = await getEntriesWithCustomerRangePaged(
        startDate: previousSavedAt,
        endDate: savedAt,
        limit: 1000000,
        offset: 0,
      );

      double debitSum = currentStartingBalance.debit;
      double creditSum = currentStartingBalance.credit;

      for (final entryRow in entries) {
        debitSum += (entryRow['debit'] as num?)?.toDouble() ?? 0.0;
        creditSum += (entryRow['credit'] as num?)?.toDouble() ?? 0.0;
      }

      await updateSummarySnapshotTotals(
        id: snapshotId,
        overallDebit: debitSum,
        overallCredit: creditSum,
      );

      final finalBalance = debitSum - creditSum;
      currentStartingBalance = _balanceToOpeningBalance(finalBalance);
      previousSavedAt = savedAt;
    }
  }

  Future<List<int>> getLedgerYears() async {
    final db = await database;
    final rows = await db.query(
      ledgerYearsTable,
      columns: <String>['year'],
      orderBy: 'year DESC',
    );

    return rows
        .map<int>((Map<String, Object?> row) => row['year'] as int)
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> getAllCustomersWithYear() async {
    final db = await database;
    return db.query(
      customersTable,
      columns: <String>[
        'id',
        'name',
        'address',
        'phone',
        'ledgerYear',
        'isStockLedger',
        'useWeight',
      ],
      orderBy: 'ledgerYear DESC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getAllEntries() async {
    final db = await database;
    return db.query(
      entriesTable,
      columns: <String>[
        'id',
        'customerId',
        'entryDate',
        'createdAt',
        'pageNo',
        'description',
        'debit',
        'credit',
        'buyBags',
        'sellBags',
        'dailyLogPageNo',
        'showInDailyLog',
      ],
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getAllSummarySnapshots() async {
    final db = await database;
    return db.query(
      summarySnapshotsTable,
      columns: <String>[
        'id',
        'ledgerYear',
        'savedAt',
        'overallDebit',
        'overallCredit',
        'customerCount',
        'dailyLogPageNo',
      ],
      orderBy: 'ledgerYear DESC, savedAt DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getAllAppSettings() async {
    final db = await database;
    return db.query(
      appSettingsTable,
      columns: <String>['settingKey', 'settingValue'],
      orderBy: 'settingKey ASC',
    );
  }

  Future<void> restoreFromCsv({
    required List<List<String>> customers,
    required List<List<String>> entries,
    required List<List<String>> snapshots,
    required List<List<String>> years,
    required List<List<String>> settings,
  }) async {
    _assertWritable();
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(entriesTable);
      await txn.delete(customersTable);
      await txn.delete(summarySnapshotsTable);
      await txn.delete(ledgerYearsTable);
      await txn.delete(appSettingsTable);

      for (final row in years.skip(1)) {
        if (row.isEmpty || row.first.trim().isEmpty) {
          continue;
        }
        final year = int.tryParse(row.first.trim());
        if (year == null) {
          continue;
        }
        await txn.insert(ledgerYearsTable, <String, Object?>{
          'year': year,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      for (final row in settings.skip(1)) {
        if (row.length < 2) {
          continue;
        }
        await txn.insert(appSettingsTable, <String, Object?>{
          'settingKey': row[0],
          'settingValue': row[1],
        });
      }

      for (final row in customers.skip(1)) {
        if (row.length < 3) {
          continue;
        }
        await txn.insert(customersTable, <String, Object?>{
          'id': int.tryParse(row[0]),
          'name': row[1],
          'address': row.length > 3 ? row[3] : '',
          'phone': row.length > 4 ? row[4] : '',
          'ledgerYear': int.tryParse(row[2]) ?? DateTime.now().year,
          'isStockLedger': row.length > 5 ? (int.tryParse(row[5]) ?? 0) : 0,
          'useWeight': row.length > 6 ? (int.tryParse(row[6]) ?? 0) : 0,
        });
      }

      for (final row in entries.skip(1)) {
        if (row.length < 8) {
          continue;
        }
        await txn.insert(entriesTable, <String, Object?>{
          'id': int.tryParse(row[0]),
          'customerId': int.tryParse(row[1]),
          'entryDate': row[2],
          'createdAt': row[3],
          'pageNo': row[4],
          'description': row[5],
          'debit': double.tryParse(row[6]) ?? 0,
          'credit': double.tryParse(row[7]) ?? 0,
          'buyBags': row.length > 8 ? (double.tryParse(row[8]) ?? 0) : 0,
          'sellBags': row.length > 9 ? (double.tryParse(row[9]) ?? 0) : 0,
          'dailyLogPageNo': row.length > 10 ? row[10] : '',
          'showInDailyLog': row.length > 11 ? (int.tryParse(row[11]) ?? 1) : 1,
        });
      }

      for (final row in snapshots.skip(1)) {
        if (row.length < 6) {
          continue;
        }
        await txn.insert(summarySnapshotsTable, <String, Object?>{
          'id': int.tryParse(row[0]),
          'ledgerYear': int.tryParse(row[1]) ?? DateTime.now().year,
          'savedAt': row[2],
          'overallDebit': double.tryParse(row[3]) ?? 0,
          'overallCredit': double.tryParse(row[4]) ?? 0,
          'customerCount': int.tryParse(row[5]) ?? 0,
          'dailyLogPageNo': row.length > 6 ? row[6] : '',
        });
      }
    });

    await _loadActiveYear(db);
  }

  Future<void> addLedgerYear(int year) async {
    _assertWritable();
    final db = await database;
    await db.transaction((Transaction txn) async {
      final existingYear = await txn.query(
        ledgerYearsTable,
        columns: <String>['year'],
        where: 'year = ?',
        whereArgs: <Object?>[year],
        limit: 1,
      );

      if (existingYear.isNotEmpty) {
        return;
      }

      await txn.insert(ledgerYearsTable, <String, Object?>{
        'year': year,
        'createdAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final sourceYear = _activeYear;
      final sourceYearBalance = await _calculateYearClosingBalance(
        txn,
        year: sourceYear,
      );

      final lastSnapshotRows = await txn.query(
        summarySnapshotsTable,
        columns: <String>['overallDebit', 'overallCredit'],
        where: 'ledgerYear = ?',
        whereArgs: <Object?>[sourceYear],
        orderBy: 'savedAt DESC',
        limit: 1,
      );

      double dailyLogClosingBalance = 0.0;
      if (lastSnapshotRows.isNotEmpty) {
        final lastSnapshot = lastSnapshotRows.first;
        final snapshotDebit = _readDoubleValue(lastSnapshot['overallDebit']);
        final snapshotCredit = _readDoubleValue(lastSnapshot['overallCredit']);
        dailyLogClosingBalance = snapshotDebit - snapshotCredit;
      } else {
        dailyLogClosingBalance = sourceYearBalance;
      }

      final snapshotOpeningBalance = _balanceToOpeningBalance(
        dailyLogClosingBalance,
      );

      if (snapshotOpeningBalance.hasValue) {
        await _setSnapshotOpeningBalanceForYear(
          txn,
          year: year,
          debit: snapshotOpeningBalance.debit,
          credit: snapshotOpeningBalance.credit,
        );
      }

      final sourceCustomerClosingBalances = await _loadCustomerClosingBalances(
        txn,
        year: sourceYear,
      );
      final sourceCustomerClosingBags = await _loadCustomerClosingBags(
        txn,
        year: sourceYear,
      );
      final sourceCustomers = await txn.query(
        customersTable,
        columns: <String>[
          'id',
          'name',
          'address',
          'phone',
          'isStockLedger',
          'useWeight',
        ],
        where: 'ledgerYear = ?',
        whereArgs: <Object?>[sourceYear],
        orderBy: 'id ASC',
      );

      for (final customer in sourceCustomers) {
        final sourceCustomerId = customer['id'] as int?;
        final newCustomerId = await txn
            .insert(customersTable, <String, Object?>{
              'name': customer['name'] as String? ?? '',
              'address': customer['address'] as String? ?? '',
              'phone': customer['phone'] as String? ?? '',
              'isStockLedger': customer['isStockLedger'] as int? ?? 0,
              'useWeight': customer['useWeight'] as int? ?? 0,
              'ledgerYear': year,
            });

        if (sourceCustomerId == null) {
          continue;
        }

        final closingBalance =
            sourceCustomerClosingBalances[sourceCustomerId] ?? 0;
        final openingBalance = _balanceToOpeningBalance(closingBalance);

        final closingBags = sourceCustomerClosingBags[sourceCustomerId] ?? 0;
        final openingBags = _bagsToOpeningBags(closingBags);

        final combinedOpening = SnapshotOpeningBalance(
          debit: openingBalance.debit,
          credit: openingBalance.credit,
          buyBags: openingBags.buyBags,
          sellBags: openingBags.sellBags,
        );

        if (!combinedOpening.hasValue) {
          continue;
        }

        await _setCustomerLedgerOpeningBalanceForYear(
          txn,
          year: year,
          customerId: newCustomerId,
          debit: combinedOpening.debit,
          credit: combinedOpening.credit,
          buyBags: combinedOpening.buyBags,
          sellBags: combinedOpening.sellBags,
        );
      }
    });
  }

  Future<double> _calculateYearClosingBalance(
    Transaction txn, {
    required int year,
  }) async {
    final debitSetting = await _getTransactionAppSetting(
      txn,
      _snapshotOpeningDebitSettingKey(year),
    );
    final creditSetting = await _getTransactionAppSetting(
      txn,
      _snapshotOpeningCreditSettingKey(year),
    );
    final totalsRows = await txn.rawQuery(
      '''
      SELECT
        SUM(e.debit) AS totalDebit,
        SUM(e.credit) AS totalCredit
      FROM $entriesTable e
      JOIN $customersTable c ON c.id = e.customerId
      WHERE c.ledgerYear = ?
      ''',
      <Object?>[year],
    );
    final totals = totalsRows.isEmpty
        ? const <String, Object?>{}
        : totalsRows.first;
    final openingDebit = double.tryParse(debitSetting ?? '') ?? 0;
    final openingCredit = double.tryParse(creditSetting ?? '') ?? 0;
    final entriesDebit = _readDoubleValue(totals['totalDebit']);
    final entriesCredit = _readDoubleValue(totals['totalCredit']);
    return (openingDebit + entriesDebit) - (openingCredit + entriesCredit);
  }

  Future<Map<int, double>> _loadCustomerClosingBalances(
    Transaction txn, {
    required int year,
  }) async {
    final entryTotalsRows = await txn.rawQuery(
      '''
      SELECT
        c.id AS customerId,
        SUM(e.debit) AS totalDebit,
        SUM(e.credit) AS totalCredit
      FROM $customersTable c
      LEFT JOIN $entriesTable e ON e.customerId = c.id
      WHERE c.ledgerYear = ?
      GROUP BY c.id
      ''',
      <Object?>[year],
    );

    final debitPrefix = 'ledgerOpeningDebit:$year:';
    final creditPrefix = 'ledgerOpeningCredit:$year:';
    final openingSettingRows = await txn.query(
      appSettingsTable,
      columns: <String>['settingKey', 'settingValue'],
      where: 'settingKey LIKE ? OR settingKey LIKE ?',
      whereArgs: <Object?>['$debitPrefix%', '$creditPrefix%'],
    );

    final openingDebitByCustomerId = <int, double>{};
    final openingCreditByCustomerId = <int, double>{};
    for (final row in openingSettingRows) {
      final key = row['settingKey'] as String? ?? '';
      final value = double.tryParse(row['settingValue'] as String? ?? '') ?? 0;

      if (key.startsWith(debitPrefix)) {
        final customerId = int.tryParse(key.substring(debitPrefix.length));
        if (customerId != null) {
          openingDebitByCustomerId[customerId] = value;
        }
        continue;
      }

      if (key.startsWith(creditPrefix)) {
        final customerId = int.tryParse(key.substring(creditPrefix.length));
        if (customerId != null) {
          openingCreditByCustomerId[customerId] = value;
        }
      }
    }

    final balancesByCustomerId = <int, double>{};
    for (final row in entryTotalsRows) {
      final customerId = row['customerId'] as int?;
      if (customerId == null) {
        continue;
      }

      final openingDebit = openingDebitByCustomerId[customerId] ?? 0;
      final openingCredit = openingCreditByCustomerId[customerId] ?? 0;
      final totalDebit = _readDoubleValue(row['totalDebit']);
      final totalCredit = _readDoubleValue(row['totalCredit']);
      balancesByCustomerId[customerId] =
          (openingDebit + totalDebit) - (openingCredit + totalCredit);
    }

    return balancesByCustomerId;
  }

  Future<String?> _getTransactionAppSetting(Transaction txn, String key) async {
    final rows = await txn.query(
      appSettingsTable,
      columns: <String>['settingValue'],
      where: 'settingKey = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['settingValue'] as String?;
  }

  Future<void> _setSnapshotOpeningBalanceForYear(
    Transaction txn, {
    required int year,
    required double debit,
    required double credit,
  }) async {
    await txn.insert(appSettingsTable, <String, Object?>{
      'settingKey': _snapshotOpeningDebitSettingKey(year),
      'settingValue': debit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert(appSettingsTable, <String, Object?>{
      'settingKey': _snapshotOpeningCreditSettingKey(year),
      'settingValue': credit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _setCustomerLedgerOpeningBalanceForYear(
    Transaction txn, {
    required int year,
    required int customerId,
    required double debit,
    required double credit,
    double buyBags = 0,
    double sellBags = 0,
  }) async {
    await txn.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningDebitSettingKey(
        year: year,
        customerId: customerId,
      ),
      'settingValue': debit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningCreditSettingKey(
        year: year,
        customerId: customerId,
      ),
      'settingValue': credit.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningBuyBagsSettingKey(
        year: year,
        customerId: customerId,
      ),
      'settingValue': buyBags.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.insert(appSettingsTable, <String, Object?>{
      'settingKey': _customerLedgerOpeningSellBagsSettingKey(
        year: year,
        customerId: customerId,
      ),
      'settingValue': sellBags.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  SnapshotOpeningBalance _bagsToOpeningBags(double netBags) {
    if (netBags > 0) {
      return SnapshotOpeningBalance(
        debit: 0,
        credit: 0,
        buyBags: netBags,
        sellBags: 0,
      );
    }
    if (netBags < 0) {
      return SnapshotOpeningBalance(
        debit: 0,
        credit: 0,
        buyBags: 0,
        sellBags: netBags.abs(),
      );
    }
    return const SnapshotOpeningBalance(debit: 0, credit: 0);
  }

  Future<Map<int, double>> _loadCustomerClosingBags(
    Transaction txn, {
    required int year,
  }) async {
    final entryTotalsRows = await txn.rawQuery(
      '''
      SELECT
        c.id AS customerId,
        SUM(e.buyBags) AS totalBuyBags,
        SUM(e.sellBags) AS totalSellBags
      FROM $customersTable c
      LEFT JOIN $entriesTable e ON e.customerId = c.id
      WHERE c.ledgerYear = ?
      GROUP BY c.id
      ''',
      <Object?>[year],
    );

    final buyBagsPrefix = 'ledgerOpeningBuyBags:$year:';
    final sellBagsPrefix = 'ledgerOpeningSellBags:$year:';
    final openingSettingRows = await txn.query(
      appSettingsTable,
      columns: <String>['settingKey', 'settingValue'],
      where: 'settingKey LIKE ? OR settingKey LIKE ?',
      whereArgs: <Object?>['$buyBagsPrefix%', '$sellBagsPrefix%'],
    );

    final openingBuyBagsByCustomerId = <int, double>{};
    final openingSellBagsByCustomerId = <int, double>{};
    for (final row in openingSettingRows) {
      final key = row['settingKey'] as String? ?? '';
      final value = double.tryParse(row['settingValue'] as String? ?? '') ?? 0;

      if (key.startsWith(buyBagsPrefix)) {
        final customerId = int.tryParse(key.substring(buyBagsPrefix.length));
        if (customerId != null) {
          openingBuyBagsByCustomerId[customerId] = value;
        }
        continue;
      }

      if (key.startsWith(sellBagsPrefix)) {
        final customerId = int.tryParse(key.substring(sellBagsPrefix.length));
        if (customerId != null) {
          openingSellBagsByCustomerId[customerId] = value;
        }
      }
    }

    final bagsByCustomerId = <int, double>{};
    for (final row in entryTotalsRows) {
      final customerId = row['customerId'] as int?;
      if (customerId == null) {
        continue;
      }

      final openingBuyBags = openingBuyBagsByCustomerId[customerId] ?? 0;
      final openingSellBags = openingSellBagsByCustomerId[customerId] ?? 0;
      final totalBuyBags = _readDoubleValue(row['totalBuyBags']);
      final totalSellBags = _readDoubleValue(row['totalSellBags']);
      bagsByCustomerId[customerId] =
          (openingBuyBags + totalBuyBags) - (openingSellBags + totalSellBags);
    }

    return bagsByCustomerId;
  }

  SnapshotOpeningBalance _balanceToOpeningBalance(double balance) {
    if (balance > 0) {
      return SnapshotOpeningBalance(debit: balance, credit: 0);
    }
    if (balance < 0) {
      return SnapshotOpeningBalance(debit: 0, credit: balance.abs());
    }
    return const SnapshotOpeningBalance(debit: 0, credit: 0);
  }

  double _readDoubleValue(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse('$value') ?? 0;
  }

  Future<void> deleteLedgerYear(int year) async {
    _assertWritable();
    final db = await database;
    final remainingRows = await db.query(
      ledgerYearsTable,
      columns: <String>['year'],
      where: 'year != ?',
      whereArgs: <Object?>[year],
      orderBy: 'year DESC',
    );
    final remainingYears = remainingRows
        .map<int>((Map<String, Object?> row) => row['year'] as int)
        .toList(growable: false);

    await db.delete(
      summarySnapshotsTable,
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      entriesTable,
      where:
          'customerId IN (SELECT id FROM $customersTable WHERE ledgerYear = ?)',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      customersTable,
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      ledgerYearsTable,
      where: 'year = ?',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      appSettingsTable,
      where: 'settingKey IN (?, ?) OR settingKey LIKE ? OR settingKey LIKE ?',
      whereArgs: <Object?>[
        _snapshotOpeningDebitSettingKey(year),
        _snapshotOpeningCreditSettingKey(year),
        'ledgerOpeningDebit:$year:%',
        'ledgerOpeningCredit:$year:%',
      ],
    );

    if (year == _activeYear) {
      final nextYear = remainingYears.isNotEmpty
          ? remainingYears.first
          : DateTime.now().year;
      await _ensureLedgerYear(db, nextYear);
      await _saveActiveYearSetting(db, nextYear);
      _activeYear = nextYear;
    }
  }

  Future<void> setActiveYear(int year) async {
    final db = await database;
    await _ensureLedgerYear(db, year);
    await _saveActiveYearSetting(db, year);
    _activeYear = year;
  }

  Future<int> deleteCustomer(int id) async {
    _assertWritable();
    final db = await database;
    await clearCustomerLedgerOpeningBalance(id);
    await db.delete(
      entriesTable,
      where: 'customerId = ?',
      whereArgs: <Object?>[id],
    );
    return db.delete(customersTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<bool> resetCustomerIdSequence() async {
    _assertWritable();
    final db = await database;
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $customersTable',
    );
    final countValue = countRows.isEmpty ? 0 : countRows.first['count'];
    final totalCustomers = countValue is int
        ? countValue
        : int.tryParse('$countValue') ?? 0;
    if (totalCustomers > 0) {
      return false;
    }

    final sequenceRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'",
    );
    if (sequenceRows.isEmpty) {
      return true;
    }

    await db.delete(
      'sqlite_sequence',
      where: 'name = ?',
      whereArgs: <Object?>[customersTable],
    );
    return true;
  }

  // ---------------------------------------------------------------------------
  // Sync primitives used by the linked-devices engine
  // ---------------------------------------------------------------------------

  static const Set<String> deviceLocalSettingKeys = <String>{
    'appPin',
    'appPinHash',
    'appPinSalt',
    'appPinSetupDismissed',
    'autoBackupPath',
    'companyLogoPath',
    'biometricUnlockEnabled',
    'companyProfilePromptSkipped',
    'ledger.lastSelectedDate',
    _activeYearSettingKey,
  };

  static const List<String> _deviceLocalSettingPrefixes = <String>[
    'linked.',
    'sync.',
  ];

  static bool isSyncableSettingKey(String key) {
    if (deviceLocalSettingKeys.contains(key)) {
      return false;
    }
    for (final String prefix in _deviceLocalSettingPrefixes) {
      if (key.startsWith(prefix)) {
        return false;
      }
    }
    return true;
  }

  String get _settingKeyExclusionSql {
    final placeholders = deviceLocalSettingKeys.map((_) => '?').join(', ');
    final prefixClauses = _deviceLocalSettingPrefixes
        .map((String prefix) => "settingKey NOT LIKE '$prefix%'")
        .join(' AND ');
    return 'settingKey NOT IN ($placeholders) AND $prefixClauses';
  }

  Future<String?> getSyncState(String key) async {
    final db = await database;
    final rows = await db.query(
      syncStateTable,
      columns: <String>['stateValue'],
      where: 'stateKey = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['stateValue'] as String?;
  }

  Future<void> setSyncState(String key, String value) async {
    final db = await database;
    await db.insert(syncStateTable, <String, Object?>{
      'stateKey': key,
      'stateValue': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSyncState(String key) async {
    final db = await database;
    await db.delete(
      syncStateTable,
      where: 'stateKey = ?',
      whereArgs: <Object?>[key],
    );
  }

  Future<Map<String, String>> getSyncStateWithPrefix(String prefix) async {
    final db = await database;
    final rows = await db.query(
      syncStateTable,
      where: 'stateKey LIKE ?',
      whereArgs: <Object?>['$prefix%'],
    );
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        row['stateKey'] as String: row['stateValue'] as String,
    };
  }

  Future<void> deleteSyncStateWithPrefix(String prefix) async {
    final db = await database;
    await db.delete(
      syncStateTable,
      where: 'stateKey LIKE ?',
      whereArgs: <Object?>['$prefix%'],
    );
  }

  Future<List<Map<String, Object?>>> pendingRows(
    String table, {
    int limit = 400,
  }) async {
    final db = await database;

    if (table == entriesTable) {
      return db.rawQuery(
        '''
        SELECT e.*, c.syncId AS customerSyncId
        FROM $entriesTable e
        JOIN $customersTable c ON c.id = e.customerId
        WHERE e.pushPending = 1
        ORDER BY e.updatedAt ASC
        LIMIT ?
        ''',
        <Object?>[limit],
      );
    }

    if (table == appSettingsTable) {
      return db.query(
        appSettingsTable,
        where: 'pushPending = 1 AND $_settingKeyExclusionSql',
        whereArgs: <Object?>[...deviceLocalSettingKeys],
        orderBy: 'updatedAt ASC',
        limit: limit,
      );
    }

    return db.query(
      table,
      where: 'pushPending = 1',
      orderBy: 'updatedAt ASC',
      limit: limit,
    );
  }

  Future<void> markRowsPushed({
    required String table,
    required String keyColumn,
    required List<Object?> keys,
  }) async {
    if (keys.isEmpty) {
      return;
    }
    final db = await database;
    final placeholders = keys.map((_) => '?').join(', ');
    await db.rawUpdate(
      'UPDATE $table SET pushPending = 0 WHERE $keyColumn IN ($placeholders)',
      keys,
    );
  }

  Future<List<Map<String, Object?>>> pendingTombstones({
    int limit = 400,
  }) async {
    final db = await database;
    return db.query(
      syncTombstonesTable,
      where: 'pushPending = 1',
      orderBy: 'deletedAt ASC',
      limit: limit,
    );
  }

  Future<void> markTombstonePushed(String entity, String syncId) async {
    final db = await database;
    await db.update(
      syncTombstonesTable,
      <String, Object?>{'pushPending': 0},
      where: 'entity = ? AND syncId = ?',
      whereArgs: <Object?>[entity, syncId],
    );
  }

  Future<String?> tombstoneDeletedAt(String entity, String syncId) async {
    final db = await database;
    final rows = await db.query(
      syncTombstonesTable,
      columns: <String>['deletedAt'],
      where: 'entity = ? AND syncId = ?',
      whereArgs: <Object?>[entity, syncId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['deletedAt'] as String?;
  }

  Future<void> rememberTombstone({
    required String entity,
    required String syncId,
    required String deletedAt,
    bool pushPending = false,
  }) async {
    final db = await database;
    await db.insert(syncTombstonesTable, <String, Object?>{
      'entity': entity,
      'syncId': syncId,
      'deletedAt': deletedAt,
      'pushPending': pushPending ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> forgetTombstone(String entity, String syncId) async {
    final db = await database;
    await db.delete(
      syncTombstonesTable,
      where: 'entity = ? AND syncId = ?',
      whereArgs: <Object?>[entity, syncId],
    );
  }

  Future<Map<String, Object?>?> rowBySyncId(String table, String syncId) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'syncId = ?',
      whereArgs: <Object?>[syncId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int?> customerIdForSyncId(String syncId) async {
    final row = await rowBySyncId(customersTable, syncId);
    return row?['id'] as int?;
  }

  Future<String?> customerSyncIdForId(int customerId) async {
    final db = await database;
    final rows = await db.query(
      customersTable,
      columns: <String>['syncId'],
      where: 'id = ?',
      whereArgs: <Object?>[customerId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['syncId'] as String?;
  }

  Future<void> applyRemoteRow({
    required String table,
    required String syncId,
    required Map<String, Object?> values,
  }) async {
    final db = await database;
    final payload = <String, Object?>{
      ...values,
      'syncId': syncId,
      'pushPending': 0,
    };

    final existing = await db.query(
      table,
      columns: <String>['id'],
      where: 'syncId = ?',
      whereArgs: <Object?>[syncId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert(table, payload);
      return;
    }

    await db.update(
      table,
      payload,
      where: 'syncId = ?',
      whereArgs: <Object?>[syncId],
    );
  }

  Future<void> applyRemoteRowDelete({
    required String table,
    required String syncId,
  }) async {
    final db = await database;
    if (table == customersTable) {
      final rows = await db.query(
        customersTable,
        columns: <String>['id'],
        where: 'syncId = ?',
        whereArgs: <Object?>[syncId],
        limit: 1,
      );
      final int? customerId = rows.isEmpty ? null : rows.first['id'] as int?;
      if (customerId != null) {
        await db.delete(
          appSettingsTable,
          where:
              "settingKey LIKE 'ledgerOpening%:' || ? "
              "OR settingKey = 'ledger.pageNo:' || ?",
          whereArgs: <Object?>[customerId, customerId],
        );
      }
      await db.delete(
        entriesTable,
        where:
            'customerId IN (SELECT id FROM $customersTable WHERE syncId = ?)',
        whereArgs: <Object?>[syncId],
      );
    }
    await db.delete(table, where: 'syncId = ?', whereArgs: <Object?>[syncId]);
  }

  Future<void> applyRemoteSetting({
    required String settingKey,
    required String settingValue,
    required String updatedAt,
  }) async {
    final db = await database;
    await db.insert(appSettingsTable, <String, Object?>{
      'settingKey': settingKey,
      'settingValue': settingValue,
      'updatedAt': updatedAt,
      'pushPending': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> applyRemoteSettingDelete(String settingKey) async {
    final db = await database;
    await db.delete(
      appSettingsTable,
      where: 'settingKey = ?',
      whereArgs: <Object?>[settingKey],
    );
  }

  Future<void> applyRemoteYear({
    required int year,
    required String createdAt,
    required String updatedAt,
  }) async {
    final db = await database;
    await db.insert(ledgerYearsTable, <String, Object?>{
      'year': year,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'pushPending': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> applyRemoteYearDelete(int year) async {
    final db = await database;
    await db.delete(
      entriesTable,
      where:
          'customerId IN (SELECT id FROM $customersTable WHERE ledgerYear = ?)',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      customersTable,
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      summarySnapshotsTable,
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[year],
    );
    await db.delete(
      ledgerYearsTable,
      where: 'year = ?',
      whereArgs: <Object?>[year],
    );
  }

  Future<void> rememberOrphan({
    required String entity,
    required String syncId,
    required String payload,
  }) async {
    final db = await database;
    await db.insert(syncOrphansTable, <String, Object?>{
      'entity': entity,
      'syncId': syncId,
      'payload': payload,
      'receivedAt': syncTimestamp(),
      'attempts': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> pendingOrphans({int limit = 200}) async {
    final db = await database;
    return db.query(
      syncOrphansTable,
      columns: <String>['entity', 'syncId', 'payload', 'receivedAt', 'attempts'],
      orderBy: 'receivedAt ASC',
      limit: limit,
    );
  }

  /// Counts one failed attempt at applying an orphan record.
  Future<void> bumpOrphanAttempt(String entity, String syncId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $syncOrphansTable SET attempts = attempts + 1 '
      'WHERE entity = ? AND syncId = ?',
      <Object?>[entity, syncId],
    );
  }

  Future<void> forgetOrphan(String entity, String syncId) async {
    final db = await database;
    await db.delete(
      syncOrphansTable,
      where: 'entity = ? AND syncId = ?',
      whereArgs: <Object?>[entity, syncId],
    );
  }

  Future<void> markEverythingForUpload() async {
    final db = await database;
    for (final String table in syncedTables) {
      await db.rawUpdate('UPDATE $table SET pushPending = 1');
    }
    await db.rawUpdate('UPDATE $syncTombstonesTable SET pushPending = 1');
  }

  Future<void> clearAllPendingUploads() async {
    final db = await database;
    for (final String table in syncedTables) {
      await db.rawUpdate('UPDATE $table SET pushPending = 0');
    }
    await db.rawUpdate('UPDATE $syncTombstonesTable SET pushPending = 0');
  }

  Future<int> pendingUploadCount() async {
    final db = await database;
    int total = 0;
    for (final String table in syncedTables) {
      final rows = table == appSettingsTable
          ? await db.rawQuery(
              'SELECT COUNT(*) AS count FROM $appSettingsTable '
              'WHERE pushPending = 1 AND $_settingKeyExclusionSql',
              <Object?>[...deviceLocalSettingKeys],
            )
          : await db.rawQuery(
              'SELECT COUNT(*) AS count FROM $table WHERE pushPending = 1',
            );
      total += (rows.first['count'] as int?) ?? 0;
    }
    final tombstoneRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $syncTombstonesTable WHERE pushPending = 1',
    );
    return total + ((tombstoneRows.first['count'] as int?) ?? 0);
  }

  Future<bool> isWorkspaceEmpty() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT '
      '(SELECT COUNT(*) FROM $customersTable) AS customers, '
      '(SELECT COUNT(*) FROM $entriesTable) AS entries, '
      '(SELECT COUNT(*) FROM $summarySnapshotsTable) AS snapshots',
    );
    if (rows.isEmpty) {
      return true;
    }
    final row = rows.first;
    return ((row['customers'] as int?) ?? 0) == 0 &&
        ((row['entries'] as int?) ?? 0) == 0 &&
        ((row['snapshots'] as int?) ?? 0) == 0;
  }

  Future<void> clearSyncBookkeeping() async {
    final db = await database;
    await db.delete(syncTombstonesTable);
    await db.delete(syncOrphansTable);
    await db.delete(
      syncStateTable,
      where: 'stateKey != ?',
      whereArgs: <Object?>['schema.syncTriggers'],
    );
  }

  // ---------------------------------------------------------------------------
  // Guest Workspace Backup / Restore (for Linked Devices feature)
  // ---------------------------------------------------------------------------

  /// Path of the ".db.bak" backup file used when this device joins a
  /// linked workspace. On disconnect the backup is restored so the guest's
  /// own data comes back exactly as it was before joining.
  Future<String> _resolveGuestBackupPath() async {
    final activePath = await _resolveDatabasePath();
    return '$activePath.bak';
  }

  /// Called BEFORE this device joins a linked (admin) workspace.
  /// Copies the current SQLite DB file to a ".bak" file so the guest's
  /// own data can be restored later on disconnect.
  Future<void> createGuestBackup() async {
    try {
      final activePath = await _resolveDatabasePath();
      final backupPath = await _resolveGuestBackupPath();

      // Close active DB connection so file is safe to copy
      await close();

      final activeFile = File(activePath);
      if (await activeFile.exists()) {
        // Overwrite any previous backup
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
        await activeFile.copy(backupPath);
        debugPrint('Guest backup created at: $backupPath');
      }

      // Reopen DB connection
      await initialize();
    } catch (error) {
      debugPrint('createGuestBackup failed: $error');
      // Make sure DB reopens even on failure
      await initialize();
      rethrow;
    }
  }

  /// Called ON DISCONNECT from a linked workspace.
  /// Deletes the admin's data (current active DB file) and restores
  /// the guest's own backup DB file. If no backup exists, a fresh
  /// empty DB is created so the app stays usable.
  Future<void> restoreGuestBackup() async {
    try {
      final activePath = await _resolveDatabasePath();
      final backupPath = await _resolveGuestBackupPath();

      await close();

      final backupFile = File(backupPath);
      final activeFile = File(activePath);

      // Delete admin's data (current active DB)
      if (await activeFile.exists()) {
        await activeFile.delete();
      }

      // Restore guest's backup, if it exists
      if (await backupFile.exists()) {
        await backupFile.copy(activePath);
        // Cleanup backup after restore
        await backupFile.delete();
        debugPrint('Guest workspace restored from backup');
      } else {
        debugPrint('No guest backup found — fresh workspace will be created');
      }

      // Reopen DB — creates fresh one if no backup existed
      await initialize();
    } catch (error) {
      debugPrint('restoreGuestBackup failed: $error');
      await initialize();
      rethrow;
    }
  }

  /// True if a guest backup exists (i.e., this device is currently linked
  /// to an admin workspace).
  Future<bool> hasGuestBackup() async {
    try {
      final backupPath = await _resolveGuestBackupPath();
      return File(backupPath).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _rawDatabase = null;
    if (db != null) {
      await db.close();
    }
  }
}

/// Reports every write that goes through the database.
///
/// This is the single point where the app learns that a record was created,
/// changed or removed, so the sync engine gets its push signal without every
/// mutating method having to remember to raise it. Reads pass straight
/// through, and schema statements never count as a change.
class _ChangeReportingDatabase implements Database {
  _ChangeReportingDatabase(
    this._inner, {
    required this.onLocalWrite,
    required this.watchedTables,
  });

  final Database _inner;
  final void Function() onLocalWrite;

  /// Tables whose writes the cloud has to hear about. Sync bookkeeping lives in
  /// other tables, so ignoring those keeps a sync cycle from waking itself up.
  final Set<String> watchedTables;

  bool _isWatched(String table) => watchedTables.contains(table);

  @override
  String get path => _inner.path;

  @override
  bool get isOpen => _inner.isOpen;

  @override
  Database get database => this;

  // -- Reads -----------------------------------------------------------------

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _inner.rawQuery(sql, arguments);
  }

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) {
    return _inner.queryCursor(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      bufferSize: bufferSize,
    );
  }

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) {
    return _inner.rawQueryCursor(sql, arguments, bufferSize: bufferSize);
  }

  // -- Schema (never a data change) -----------------------------------------

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    return _inner.execute(sql, arguments);
  }

  // -- Writes ----------------------------------------------------------------

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    try {
      return await _inner.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );
    } finally {
      if (_isWatched(table)) onLocalWrite();
    }
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    try {
      return await _inner.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );
    } finally {
      if (_isWatched(table)) onLocalWrite();
    }
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    try {
      return await _inner.delete(table, where: where, whereArgs: whereArgs);
    } finally {
      if (_isWatched(table)) onLocalWrite();
    }
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async {
    try {
      return await _inner.rawInsert(sql, arguments);
    } finally {
      onLocalWrite();
    }
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async {
    try {
      return await _inner.rawUpdate(sql, arguments);
    } finally {
      onLocalWrite();
    }
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async {
    try {
      return await _inner.rawDelete(sql, arguments);
    } finally {
      onLocalWrite();
    }
  }

  // -- Transactions ----------------------------------------------------------

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    try {
      return await _inner.transaction(
        (Transaction txn) => action(txn),
        exclusive: exclusive,
      );
    } finally {
      onLocalWrite();
    }
  }

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) {
    return _inner.readTransaction(action);
  }

  @override
  Batch batch() => _inner.batch();

  // -- Lifecycle -------------------------------------------------------------

  @override
  Future<void> close() => _inner.close();

  @override
  @Deprecated('Dev only')
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) {
    return _inner.devInvokeMethod<T>(method, arguments);
  }

  @override
  @Deprecated('Dev only')
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) {
    return _inner.devInvokeSqlMethod<T>(method, sql, arguments);
  }
}

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  final StreamController<void> _dataChangedController =
      StreamController<void>.broadcast();
  Stream<void> get onDataChanged => _dataChangedController.stream;

  void notifyDataChanged() {
    _dataChangedController.add(null);
  }

  int get activeYear => _helper.activeYear;

  Future<void> initialize() => _helper.initialize();

  /// Closes the current database and reopens with the active workspace's DB.
  Future<void> switchDatabase() => _helper.switchDatabase();

  /// Deletes the database file for a specific workspace.
  Future<void> deleteWorkspaceDatabase(String workspaceId) =>
      _helper.deleteWorkspaceDatabase(workspaceId);

  Future<Database> get database => _helper.database;

  Future<String> get databasePath => _helper.databasePath;

  Future<int> addCustomer(
    String name, {
    String address = '',
    String phone = '',
  }) => _helper.addCustomer(name, address: address, phone: phone);

  Future<List<Map<String, Object?>>> getCustomers() => _helper.getCustomers();

  Future<Map<String, Object?>?> getCustomer(int id) => _helper.getCustomer(id);

  Future<bool> customerNameExists(String name, {int? excludingCustomerId}) {
    return _helper.customerNameExists(
      name,
      excludingCustomerId: excludingCustomerId,
    );
  }

  Future<int> addEntry({
    required int customerId,
    required String entryDate,
    required String createdAt,
    required String pageNo,
    required String description,
    required double debit,
    required double credit,
  }) {
    return _helper.addEntry(
      customerId: customerId,
      entryDate: entryDate,
      createdAt: createdAt,
      pageNo: pageNo,
      description: description,
      debit: debit,
      credit: credit,
    );
  }

  Future<int> updateEntry({
    required int id,
    required String entryDate,
    required String pageNo,
    required String description,
    required double debit,
    required double credit,
  }) {
    return _helper.updateEntry(
      id: id,
      entryDate: entryDate,
      pageNo: pageNo,
      description: description,
      debit: debit,
      credit: credit,
    );
  }

  Future<int> transferEntry({
    required int entryId,
    required int newCustomerId,
  }) {
    return _helper.transferEntry(
      entryId: entryId,
      newCustomerId: newCustomerId,
    );
  }

  Future<int> deleteEntry(int id) => _helper.deleteEntry(id);

  Future<int> updateCustomer({
    required int id,
    required String name,
    String? address,
    String? phone,
  }) {
    return _helper.updateCustomer(
      id: id,
      name: name,
      address: address,
      phone: phone,
    );
  }

  Future<void> updateCustomerStockMode(int id, bool isStockLedger) {
    return _helper.updateCustomerStockMode(id, isStockLedger);
  }

  Future<void> updateCustomerWeightMode(int id, bool useWeight) {
    return _helper.updateCustomerWeightMode(id, useWeight);
  }

  Future<int> addStockEntry({
    required int customerId,
    required String entryDate,
    required String createdAt,
    required String pageNo,
    required String description,
    required String buyBags,
    required double buyAmount,
    required String sellBags,
    required double sellAmount,
  }) {
    return _helper.addStockEntry(
      customerId: customerId,
      entryDate: entryDate,
      createdAt: createdAt,
      pageNo: pageNo,
      description: description,
      buyBags: buyBags,
      buyAmount: buyAmount,
      sellBags: sellBags,
      sellAmount: sellAmount,
    );
  }

  Future<int> updateStockEntry({
    required int id,
    required String entryDate,
    required String pageNo,
    required String description,
    required String buyBags,
    required double buyAmount,
    required String sellBags,
    required double sellAmount,
  }) {
    return _helper.updateStockEntry(
      id: id,
      entryDate: entryDate,
      pageNo: pageNo,
      description: description,
      buyBags: buyBags,
      buyAmount: buyAmount,
      sellBags: sellBags,
      sellAmount: sellAmount,
    );
  }

  Future<List<Map<String, Object?>>> getEntriesByCustomer(int customerId) {
    return _helper.getEntriesByCustomer(customerId);
  }

  Future<List<Map<String, Object?>>> getEntriesByDateRange({
    required int customerId,
    required String startDate,
    required String endDate,
  }) {
    return _helper.getEntriesByDateRange(
      customerId: customerId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<List<Map<String, Object?>>> getEntriesWithCustomerRange({
    String? startDate,
    required String endDate,
  }) {
    return _helper.getEntriesWithCustomerRange(
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<List<Map<String, Object?>>> getEntriesWithCustomerRangePaged({
    String? startDate,
    required String endDate,
    required int limit,
    required int offset,
  }) {
    return _helper.getEntriesWithCustomerRangePaged(
      startDate: startDate,
      endDate: endDate,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insertCustomer(
    String name, {
    String address = '',
    String phone = '',
  }) => _helper.insertCustomer(name, address: address, phone: phone);

  Future<int> addSummarySnapshot({
    required String savedAt,
    required double overallDebit,
    required double overallCredit,
    required int customerCount,
    String dailyLogPageNo = '',
  }) {
    return _helper.addSummarySnapshot(
      savedAt: savedAt,
      overallDebit: overallDebit,
      overallCredit: overallCredit,
      customerCount: customerCount,
      dailyLogPageNo: dailyLogPageNo,
    );
  }

  Future<void> batchUpdateDailyLogPageNo({
    required List<int> entryIds,
    required String dailyLogPageNo,
  }) {
    return _helper.batchUpdateDailyLogPageNo(
      entryIds: entryIds,
      dailyLogPageNo: dailyLogPageNo,
    );
  }

  Future<void> updateEntryDailyLogVisibility({
    required int entryId,
    required bool show,
  }) {
    return _helper.updateEntryDailyLogVisibility(entryId: entryId, show: show);
  }

  Future<List<Map<String, Object?>>> getSummarySnapshots() {
    return _helper.getSummarySnapshots();
  }

  Future<int> updateSummarySnapshotTotals({
    required int id,
    required double overallDebit,
    required double overallCredit,
  }) {
    return _helper.updateSummarySnapshotTotals(
      id: id,
      overallDebit: overallDebit,
      overallCredit: overallCredit,
    );
  }

  Future<int> deleteSummarySnapshot(int id) {
    return _helper.deleteSummarySnapshot(id);
  }

  Future<int> updateSnapshotDailyLogPageNo({
    required int id,
    required String dailyLogPageNo,
  }) {
    return _helper.updateSnapshotDailyLogPageNo(
      id: id,
      dailyLogPageNo: dailyLogPageNo,
    );
  }

  Future<int> clearSummarySnapshots() {
    return _helper.clearSummarySnapshots();
  }

  Future<List<int>> getLedgerYears() {
    return _helper.getLedgerYears();
  }

  Future<List<Map<String, Object?>>> getAllCustomersWithYear() {
    return _helper.getAllCustomersWithYear();
  }

  Future<List<Map<String, Object?>>> getAllEntries() {
    return _helper.getAllEntries();
  }

  Future<List<Map<String, Object?>>> getAllSummarySnapshots() {
    return _helper.getAllSummarySnapshots();
  }

  Future<List<Map<String, Object?>>> getAllAppSettings() {
    return _helper.getAllAppSettings();
  }

  Future<List<Map<String, Object?>>> getCustomerEntryTotalsSince({
    String? startCreatedAt,
  }) {
    return _helper.getCustomerEntryTotalsSince(startCreatedAt: startCreatedAt);
  }

  Future<void> restoreFromCsv({
    required List<List<String>> customers,
    required List<List<String>> entries,
    required List<List<String>> snapshots,
    required List<List<String>> years,
    required List<List<String>> settings,
  }) {
    return _helper.restoreFromCsv(
      customers: customers,
      entries: entries,
      snapshots: snapshots,
      years: years,
      settings: settings,
    );
  }

  Future<void> addLedgerYear(int year) {
    return _helper.addLedgerYear(year);
  }

  Future<void> deleteLedgerYear(int year) {
    return _helper.deleteLedgerYear(year);
  }

  Future<void> setActiveYear(int year) {
    return _helper.setActiveYear(year);
  }

  Future<String?> getAppSetting(String key) {
    return _helper.getAppSetting(key);
  }

  Future<void> setAppSetting({required String key, required String value}) {
    return _helper.setAppSetting(key: key, value: value);
  }

  Future<SnapshotOpeningBalance?> getSnapshotOpeningBalance() {
    return _helper.getSnapshotOpeningBalance();
  }

  Future<void> setSnapshotOpeningBalance({
    required double debit,
    required double credit,
  }) {
    return _helper.setSnapshotOpeningBalance(debit: debit, credit: credit);
  }

  Future<void> clearSnapshotOpeningBalance() {
    return _helper.clearSnapshotOpeningBalance();
  }

  Future<SnapshotOpeningBalance?> getCustomerLedgerOpeningBalance(
    int customerId,
  ) {
    return _helper.getCustomerLedgerOpeningBalance(customerId);
  }

  Future<void> setCustomerLedgerOpeningBalance({
    required int customerId,
    required double debit,
    required double credit,
    double buyBags = 0,
    double sellBags = 0,
  }) {
    return _helper.setCustomerLedgerOpeningBalance(
      customerId: customerId,
      debit: debit,
      credit: credit,
      buyBags: buyBags,
      sellBags: sellBags,
    );
  }

  Future<void> clearCustomerLedgerOpeningBalance(int customerId) {
    return _helper.clearCustomerLedgerOpeningBalance(customerId);
  }

  Future<int> deleteCustomer(int id) => _helper.deleteCustomer(id);

  Future<bool> resetCustomerIdSequence() => _helper.resetCustomerIdSequence();

  Future<void> addEntryToSavedSnapshot({
    required int entryId,
    required String savedAt,
    required String? dailyLogPageNo,
  }) {
    return _helper.addEntryToSavedSnapshot(
      entryId: entryId,
      savedAt: savedAt,
      dailyLogPageNo: dailyLogPageNo,
    );
  }

  Future<void> recalculateAllSnapshots() {
    return _helper.recalculateAllSnapshots();
  }

  // ---------------------------------------------------------------------------
  // Guest Workspace Backup / Restore (for Linked Devices feature)
  // ---------------------------------------------------------------------------

  /// Creates a backup of the guest's own DB before joining an admin workspace.
  Future<void> createGuestBackup() => _helper.createGuestBackup();

  /// Restores the guest's own DB from backup after disconnecting.
  Future<void> restoreGuestBackup() => _helper.restoreGuestBackup();

  /// True if a guest backup file exists.
  Future<bool> hasGuestBackup() => _helper.hasGuestBackup();

  Future<void> close() => _helper.close();
}
