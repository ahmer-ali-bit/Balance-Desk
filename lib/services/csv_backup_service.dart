import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import 'company_profile_service.dart';

class CsvBackupService {
  CsvBackupService({
    AppDatabase? database,
    CompanyProfileService? companyProfileService,
  }) : _database = database ?? AppDatabase.instance,
       _companyProfileService =
           companyProfileService ?? CompanyProfileService();

  static const int _backupSchemaVersion = 2;
  static const String _backupExtension = 'json';
  static const String _backupType = 'balancedesk-manual-backup';
  static const Set<String> _localOnlySettingKeys = <String>{
    'appPin',
    'appPinHash',
    'appPinSalt',
    'appPinSetupDismissed',
    'autoBackupPath',
    'companyLogoPath',
  };

  final AppDatabase _database;
  final CompanyProfileService _companyProfileService;

  Future<String?> createBackupFile() async {
    final bytes = await _buildBackupBytes();
    final fileName = _buildBackupFileName();

    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save Backup File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>[_backupExtension],
        bytes: bytes,
      );
      if (path != null && path.isNotEmpty) {
        return path;
      }
    } catch (e) {
      debugPrint('FilePicker.saveFile failed: $e');
    }

    final fallbackPath = await _resolveAndroidFallbackPath(fileName);
    final file = File(fallbackPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
    return fallbackPath;
  }

  Future<void> backupToFile(String filePath) async {
    final normalizedPath = _normalizeBackupPath(filePath);
    if (normalizedPath.isEmpty) {
      throw const CsvBackupException('Backup file path is invalid.');
    }

    final file = File(normalizedPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final bytes = await _buildBackupBytes();
    try {
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw CsvBackupException('Unable to save backup: ${error.message}');
    }
  }

  Future<Uint8List> _buildBackupBytes() async {
    final customers = await _database.getAllCustomersWithYear();
    final entries = await _database.getAllEntries();
    final snapshots = await _database.getAllSummarySnapshots();
    final years = await _database.getLedgerYears();
    final settings = await _loadSharedSettings();
    final logo = await _companyProfileService.exportLogoAsset();

    final payload = <String, Object?>{
      'backupType': _backupType,
      'schemaVersion': _backupSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'activeYear': _database.activeYear,
      'customers': customers
          .map<Map<String, Object?>>(
            (Map<String, Object?> row) => <String, Object?>{
              'id': row['id'],
              'name': row['name'],
              'address': row['address'],
              'phone': row['phone'],
              'ledgerYear': row['ledgerYear'],
              'isStockLedger': row['isStockLedger'],
              'useWeight': row['useWeight'],
            },
          )
          .toList(growable: false),
      'entries': entries
          .map<Map<String, Object?>>(
            (Map<String, Object?> row) => <String, Object?>{
              'id': row['id'],
              'customerId': row['customerId'],
              'entryDate': row['entryDate'],
              'createdAt': row['createdAt'],
              'pageNo': row['pageNo'],
              'description': row['description'],
              'debit': row['debit'],
              'credit': row['credit'],
              'buyBags': row['buyBags'],
              'sellBags': row['sellBags'],
              'dailyLogPageNo': row['dailyLogPageNo'],
              'showInDailyLog': row['showInDailyLog'],
            },
          )
          .toList(growable: false),
      'snapshots': snapshots
          .map<Map<String, Object?>>(
            (Map<String, Object?> row) => <String, Object?>{
              'id': row['id'],
              'ledgerYear': row['ledgerYear'],
              'savedAt': row['savedAt'],
              'overallDebit': row['overallDebit'],
              'overallCredit': row['overallCredit'],
              'customerCount': row['customerCount'],
              'dailyLogPageNo': row['dailyLogPageNo'],
            },
          )
          .toList(growable: false),
      'years': years,
      'settings': settings,
      'companyLogo': logo == null
          ? null
          : <String, Object?>{
              'extension': logo.extension,
              'base64': base64Encode(logo.bytes),
            },
    };

    final encoder = const JsonEncoder.withIndent('  ');
    return Uint8List.fromList(utf8.encode(encoder.convert(payload)));
  }

  Future<String?> restoreBackupFile() async {
    final restorePath = await _pickBackupFilePath();
    if (restorePath == null || restorePath.isEmpty) {
      return null;
    }

    await restoreFromFile(restorePath);
    return restorePath;
  }

  Future<void> restoreFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const CsvBackupException('Selected backup file was not found.');
    }

    Map<String, dynamic> payload;
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Backup root must be a JSON object.');
      }
      payload = decoded;
    } on FileSystemException catch (error) {
      throw CsvBackupException('Unable to read backup: ${error.message}');
    } on FormatException {
      throw const CsvBackupException(
        'Backup file is unreadable or uses an invalid format.',
      );
    }

    try {
      final backupData = _decodeBackupPayload(payload);
      final preservedLocalSettings = await _loadLocalOnlySettings();
      final mergedSettings = _mergeRestoredSettings(
        backupData.settings,
        preservedLocalSettings,
      );

      await _database.restoreFromCsv(
        customers: backupData.customersCsv,
        entries: backupData.entriesCsv,
        snapshots: backupData.snapshotsCsv,
        years: backupData.yearsCsv,
        settings: mergedSettings,
      );

      if (backupData.logoBase64 == null || backupData.logoBase64!.isEmpty) {
        await _companyProfileService.clearLogo();
        return;
      }

      try {
        final bytes = base64Decode(backupData.logoBase64!);
        final logoPath = await _companyProfileService.saveLogoBytes(
          bytes: bytes,
          extension: backupData.logoExtension ?? '.png',
        );
        if (logoPath == null || logoPath.isEmpty) {
          return;
        }
        final profile = await _companyProfileService.loadProfile();
        await _companyProfileService.saveProfile(
          name: profile.name,
          logoPath: logoPath,
        );
      } on FormatException {
        throw const CsvBackupException(
          'Backup logo data is invalid and could not be restored.',
        );
      }
    } catch (error) {
      if (error is CsvBackupException) {
        rethrow;
      }
      throw CsvBackupException('Unable to restore backup: $error');
    }
  }

  Future<Map<String, String>> _loadSharedSettings() async {
    final rows = await _database.getAllAppSettings();
    final settings = <String, String>{};
    for (final row in rows) {
      final key = '${row['settingKey'] ?? ''}'.trim();
      if (key.isEmpty || _localOnlySettingKeys.contains(key)) {
        continue;
      }
      settings[key] = '${row['settingValue'] ?? ''}';
    }
    return settings;
  }

  Future<Map<String, String>> _loadLocalOnlySettings() async {
    final rows = await _database.getAllAppSettings();
    final settings = <String, String>{};
    for (final row in rows) {
      final key = '${row['settingKey'] ?? ''}'.trim();
      if (!_localOnlySettingKeys.contains(key)) {
        continue;
      }
      settings[key] = '${row['settingValue'] ?? ''}';
    }
    return settings;
  }

  List<List<String>> _mergeRestoredSettings(
    Map<String, String> restoredSettings,
    Map<String, String> preservedLocalSettings,
  ) {
    final merged = <String, String>{...restoredSettings};
    preservedLocalSettings.forEach((String key, String value) {
      merged[key] = value;
    });

    final rows = <List<String>>[
      const <String>['settingKey', 'settingValue'],
    ];
    final keys = merged.keys.toList(growable: false)..sort();
    for (final key in keys) {
      rows.add(<String>[key, merged[key] ?? '']);
    }
    return rows;
  }

  _DecodedBackupPayload _decodeBackupPayload(Map<String, dynamic> payload) {
    final settings = <String, String>{};
    final rawSettings = payload['settings'];
    if (rawSettings is Map) {
      rawSettings.forEach((Object? key, Object? value) {
        final normalizedKey = '${key ?? ''}'.trim();
        if (normalizedKey.isEmpty) {
          return;
        }
        settings[normalizedKey] = '${value ?? ''}';
      });
    }

    final customers = _mapList(payload['customers']);
    final entries = _mapList(payload['entries']);
    final snapshots = _mapList(payload['snapshots']);
    final years = _intList(payload['years']);
    final rawLogo = payload['companyLogo'];
    String? logoBase64;
    String? logoExtension;
    if (rawLogo is Map) {
      logoBase64 = '${rawLogo['base64'] ?? ''}'.trim();
      logoExtension = '${rawLogo['extension'] ?? '.png'}'.trim();
    }

    return _DecodedBackupPayload(
      customersCsv: <List<String>>[
        const <String>[
          'id',
          'name',
          'ledgerYear',
          'address',
          'phone',
          'isStockLedger',
          'useWeight',
        ],
        ...customers.map<List<String>>((Map<String, dynamic> row) {
          return <String>[
            '${row['id'] ?? ''}',
            '${row['name'] ?? ''}',
            '${row['ledgerYear'] ?? ''}',
            '${row['address'] ?? ''}',
            '${row['phone'] ?? ''}',
            '${row['isStockLedger'] ?? '0'}',
            '${row['useWeight'] ?? '0'}',
          ];
        }),
      ],
      entriesCsv: <List<String>>[
        const <String>[
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
        ...entries.map<List<String>>((Map<String, dynamic> row) {
          return <String>[
            '${row['id'] ?? ''}',
            '${row['customerId'] ?? ''}',
            '${row['entryDate'] ?? ''}',
            '${row['createdAt'] ?? ''}',
            '${row['pageNo'] ?? ''}',
            '${row['description'] ?? ''}',
            '${row['debit'] ?? ''}',
            '${row['credit'] ?? ''}',
            '${row['buyBags'] ?? '0'}',
            '${row['sellBags'] ?? '0'}',
            '${row['dailyLogPageNo'] ?? ''}',
            '${row['showInDailyLog'] ?? '1'}',
          ];
        }),
      ],
      snapshotsCsv: <List<String>>[
        const <String>[
          'id',
          'ledgerYear',
          'savedAt',
          'overallDebit',
          'overallCredit',
          'customerCount',
          'dailyLogPageNo',
        ],
        ...snapshots.map<List<String>>((Map<String, dynamic> row) {
          return <String>[
            '${row['id'] ?? ''}',
            '${row['ledgerYear'] ?? ''}',
            '${row['savedAt'] ?? ''}',
            '${row['overallDebit'] ?? ''}',
            '${row['overallCredit'] ?? ''}',
            '${row['customerCount'] ?? ''}',
            '${row['dailyLogPageNo'] ?? ''}',
          ];
        }),
      ],
      yearsCsv: <List<String>>[
        const <String>['year'],
        ...years.map<List<String>>((int year) => <String>['$year']),
      ],
      settings: settings,
      logoBase64: logoBase64,
      logoExtension: logoExtension,
    );
  }

  List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map<Map<String, dynamic>>(
          (Map entry) => entry.map<String, dynamic>(
            (Object? key, Object? item) => MapEntry('${key ?? ''}', item),
          ),
        )
        .toList(growable: false);
  }

  List<int> _intList(Object? value) {
    if (value is! List) {
      return const <int>[];
    }

    return value
        .map<int?>((Object? item) => int.tryParse('${item ?? ''}'))
        .whereType<int>()
        .toList(growable: false);
  }

  Future<String?> _pickBackupFilePath() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.custom,
      allowedExtensions: const <String>[_backupExtension],
      withData: false,
    );
    return result?.files.single.path;
  }

  String _normalizeBackupPath(String rawPath) {
    final trimmedPath = rawPath.trim();
    if (trimmedPath.isEmpty) {
      return '';
    }
    final extension = path.extension(trimmedPath).toLowerCase();
    if (extension == '.$_backupExtension') {
      return trimmedPath;
    }
    return '$trimmedPath.$_backupExtension';
  }

  String _buildBackupFileName() {
    final now = DateTime.now();
    final stamp =
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'balance_desk_backup_$stamp.$_backupExtension';
  }

  Future<String> _resolveAndroidFallbackPath(String fileName) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      path.join(documentsDirectory.path, 'shop_ledger', 'backups'),
    );

    if (!await backupDirectory.exists()) {
      await backupDirectory.create(recursive: true);
    }

    return path.join(backupDirectory.path, fileName);
  }
}

class CsvBackupException implements Exception {
  const CsvBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DecodedBackupPayload {
  const _DecodedBackupPayload({
    required this.customersCsv,
    required this.entriesCsv,
    required this.snapshotsCsv,
    required this.yearsCsv,
    required this.settings,
    this.logoBase64,
    this.logoExtension,
  });

  final List<List<String>> customersCsv;
  final List<List<String>> entriesCsv;
  final List<List<String>> snapshotsCsv;
  final List<List<String>> yearsCsv;
  final Map<String, String> settings;
  final String? logoBase64;
  final String? logoExtension;
}
