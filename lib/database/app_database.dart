import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    show
        ConflictAlgorithm,
        Database,
        DatabaseFactory,
        OpenDatabaseOptions,
        Transaction,
        databaseFactory,
        getDatabasesPath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;
import 'package:flutter/foundation.dart';

import '../models/snapshot_opening_balance.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static bool _ffiInitialized = false;

  static const String customersTable = 'customers';
  static const String entriesTable = 'entries';
  static const String summarySnapshotsTable = 'summary_snapshots';
  static const String ledgerYearsTable = 'ledger_years';
  static const String appSettingsTable = 'app_settings';
  static const String _activeYearSettingKey = 'activeYear';
  static const int _databaseVersion = 5;
  static const String _databaseName = 'shop_desktop.db';
  static const String _defaultUserKey = 'local';
  static const String _signedOutUserKey = 'signed_out';

  Database? _database;
  int _activeYear = DateTime.now().year;
  String _userKey = _defaultUserKey;

  int get activeYear => _activeYear;
  String get userKey => _userKey;

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

  Future<void> initialize() async {
    await database;
  }

  Future<String> get databasePath => _resolveDatabasePath();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    try {
      _database = await _databaseFactory.openDatabase(
        await _resolveDatabasePath(),
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onConfigure: (Database db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await _createTables(db);
            await _ensureYearInfrastructure(db);
            await _ensureIndexes(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            await _createTables(db);
            await _ensureYearInfrastructure(db);
            await _ensureIndexes(db);
          },
          onOpen: (db) async {
            await _createTables(db);
            await _ensureYearInfrastructure(db);
            await _ensureIndexes(db);
            await _loadActiveYear(db);
          },
        ),
      );
    } catch (error) {
      debugPrint('Database open failed: $error');
      rethrow;
    }

    return _database!;
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
    final databaseFolder = Directory(path.join(basePath, _userKey));
    if (!await databaseFolder.exists()) {
      await databaseFolder.create(recursive: true);
    }

    return path.join(databaseFolder.path, _databaseName);
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

  String _normalizeUserKey(String? rawKey) {
    final trimmed = rawKey?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _signedOutUserKey;
    }
    final safe = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return safe.isEmpty ? _signedOutUserKey : safe;
  }

  Future<void> setUserKey(String? rawKey) async {
    final nextKey = _normalizeUserKey(rawKey ?? _defaultUserKey);
    if (nextKey == _userKey) {
      return;
    }
    await close();
    _userKey = nextKey;
    _activeYear = DateTime.now().year;
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
        ledgerYear INTEGER NOT NULL DEFAULT $defaultYear
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
    );
  }

  Future<void> setSnapshotOpeningBalance({
    required double debit,
    required double credit,
  }) async {
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

    if (debitSetting == null && creditSetting == null) {
      return null;
    }

    return SnapshotOpeningBalance(
      debit: double.tryParse(debitSetting ?? '') ?? 0,
      credit: double.tryParse(creditSetting ?? '') ?? 0,
    );
  }

  Future<void> setCustomerLedgerOpeningBalance({
    required int customerId,
    required double debit,
    required double credit,
  }) async {
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
  }

  Future<void> clearCustomerLedgerOpeningBalance(int customerId) async {
    final db = await database;
    await db.delete(
      appSettingsTable,
      where: 'settingKey IN (?, ?)',
      whereArgs: <Object?>[
        _customerLedgerOpeningDebitSettingKey(
          year: _activeYear,
          customerId: customerId,
        ),
        _customerLedgerOpeningCreditSettingKey(
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
      columns: <String>['id', 'name', 'address', 'phone'],
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[_activeYear],
      orderBy: 'name COLLATE NOCASE',
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
  }) async {
    final db = await database;
    return db.insert(entriesTable, <String, Object?>{
      'customerId': customerId,
      'entryDate': entryDate,
      'createdAt': createdAt,
      'pageNo': pageNo.trim(),
      'description': description.trim(),
      'debit': debit,
      'credit': credit,
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
    final db = await database;
    return db.update(
      entriesTable,
      <String, Object?>{
        'entryDate': entryDate,
        'pageNo': pageNo.trim(),
        'description': description.trim(),
        'debit': debit,
        'credit': credit,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> transferEntry({
    required int entryId,
    required int newCustomerId,
  }) async {
    final db = await database;
    return db.update(
      entriesTable,
      <String, Object?>{'customerId': newCustomerId},
      where: 'id = ?',
      whereArgs: <Object?>[entryId],
    );
  }

  Future<int> deleteEntry(int id) async {
    final db = await database;
    return db.delete(entriesTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<int> updateCustomer({
    required int id,
    required String name,
    String? address,
    String? phone,
  }) async {
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
        e.showInDailyLog,
        c.name AS customerName
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
        e.showInDailyLog,
        c.name AS customerName
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

  Future<int> deleteSummarySnapshot(int id) async {
    final db = await database;
    return db.delete(
      summarySnapshotsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> clearSummarySnapshots() async {
    final db = await database;
    return db.delete(
      summarySnapshotsTable,
      where: 'ledgerYear = ?',
      whereArgs: <Object?>[_activeYear],
    );
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
      columns: <String>['id', 'name', 'address', 'phone', 'ledgerYear'],
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
        });
      }
    });

    await _loadActiveYear(db);
  }

  Future<void> addLedgerYear(int year) async {
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
      final sourceYearOpeningBalance = _balanceToOpeningBalance(
        sourceYearBalance,
      );
      if (sourceYearOpeningBalance.hasValue) {
        await _setSnapshotOpeningBalanceForYear(
          txn,
          year: year,
          debit: sourceYearOpeningBalance.debit,
          credit: sourceYearOpeningBalance.credit,
        );
      }

      final sourceCustomerClosingBalances = await _loadCustomerClosingBalances(
        txn,
        year: sourceYear,
      );
      final sourceCustomers = await txn.query(
        customersTable,
        columns: <String>['id', 'name', 'address', 'phone'],
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
              'ledgerYear': year,
            });

        if (sourceCustomerId == null) {
          continue;
        }

        final closingBalance =
            sourceCustomerClosingBalances[sourceCustomerId] ?? 0;
        final openingBalance = _balanceToOpeningBalance(closingBalance);
        if (!openingBalance.hasValue) {
          continue;
        }

        await _setCustomerLedgerOpeningBalanceForYear(
          txn,
          year: year,
          customerId: newCustomerId,
          debit: openingBalance.debit,
          credit: openingBalance.credit,
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
    final db = await database;
    await clearCustomerLedgerOpeningBalance(id);
    return db.delete(customersTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<bool> resetCustomerIdSequence() async {
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

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null) {
      await db.close();
    }
  }
}

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  final DatabaseHelper _helper = DatabaseHelper.instance;

  int get activeYear => _helper.activeYear;
  String get userKey => _helper.userKey;

  Future<void> initialize() => _helper.initialize();
  Future<void> setUserKey(String? userKey) => _helper.setUserKey(userKey);

  Future<Database> get database => _helper.database;

  Future<String> get databasePath => _helper.databasePath;

  Future<int> addCustomer(
    String name, {
    String address = '',
    String phone = '',
  }) => _helper.addCustomer(name, address: address, phone: phone);

  Future<List<Map<String, Object?>>> getCustomers() => _helper.getCustomers();

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
  }) {
    return _helper.setCustomerLedgerOpeningBalance(
      customerId: customerId,
      debit: debit,
      credit: credit,
    );
  }

  Future<void> clearCustomerLedgerOpeningBalance(int customerId) {
    return _helper.clearCustomerLedgerOpeningBalance(customerId);
  }

  Future<int> deleteCustomer(int id) => _helper.deleteCustomer(id);

  Future<bool> resetCustomerIdSequence() => _helper.resetCustomerIdSequence();

  Future<void> close() => _helper.close();
}
