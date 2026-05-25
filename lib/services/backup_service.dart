import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

class BackupService {
  BackupService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<String?> backupDatabase() async {
    final backupFileName = _buildBackupFileName();
    String? savePath;
    try {
      savePath = await FilePicker.saveFile(
        dialogTitle: 'Create Backup File',
        fileName: backupFileName,
        type: FileType.custom,
        allowedExtensions: const <String>['db', 'sqlite', 'sqlite3'],
      );
    } catch (_) {
      savePath = await _resolveAndroidFallbackPath('backups', backupFileName);
    }

    if (savePath == null || savePath.isEmpty) {
      return null;
    }

    final sourcePath = await _database.databasePath;
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const BackupServiceException('Database file not found.');
    }

    await _database.close();

    try {
      final targetFile = File(savePath);
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await sourceFile.copy(savePath);
      return savePath;
    } on FileSystemException catch (error) {
      throw BackupServiceException('Unable to save backup: ${error.message}');
    } finally {
      await _database.initialize();
    }
  }

  Future<String?> restoreDatabase() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.custom,
      allowedExtensions: const <String>['db', 'sqlite', 'sqlite3'],
      withData: false,
    );

    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.isEmpty) {
      return null;
    }

    final backupFile = File(selectedPath);
    if (!await backupFile.exists()) {
      throw const BackupServiceException('Selected backup file was not found.');
    }

    final targetPath = await _database.databasePath;
    await _database.close();

    try {
      final targetFile = File(targetPath);
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await backupFile.copy(targetPath);
      return targetPath;
    } on FileSystemException catch (error) {
      throw BackupServiceException(
        'Unable to restore backup: ${error.message}',
      );
    }
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
    return 'shop_ledger_backup_$stamp.db';
  }

  Future<String> _resolveAndroidFallbackPath(
    String directoryName,
    String fileName,
  ) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      path.join(documentsDirectory.path, 'shop_ledger', directoryName),
    );

    if (!await backupDirectory.exists()) {
      await backupDirectory.create(recursive: true);
    }

    return path.join(backupDirectory.path, fileName);
  }
}

class BackupServiceException implements Exception {
  const BackupServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
