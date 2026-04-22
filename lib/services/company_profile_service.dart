import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../utils/platform_helper.dart';

class CompanyProfile {
  const CompanyProfile({required this.name, required this.logoPath});

  final String name;
  final String? logoPath;

  bool get isEmpty =>
      name.trim().isEmpty && (logoPath == null || logoPath!.trim().isEmpty);

  CompanyProfile copyWith({String? name, String? logoPath}) {
    return CompanyProfile(
      name: name ?? this.name,
      logoPath: logoPath ?? this.logoPath,
    );
  }
}

class CompanyProfileService {
  CompanyProfileService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  static const String _nameKey = 'companyName';
  static const String _logoKey = 'companyLogoPath';
  static const String _promptSkipKey = 'companyProfilePromptSkipped';
  static const String _logoFileBase = 'company_logo';

  final AppDatabase _database;

  Future<CompanyProfile> loadProfile() async {
    final name = await _database.getAppSetting(_nameKey) ?? '';
    final logoPath = await _database.getAppSetting(_logoKey);
    return CompanyProfile(name: name, logoPath: logoPath);
  }

  Future<void> saveProfile({required String name, String? logoPath}) async {
    await _database.setAppSetting(key: _nameKey, value: name.trim());
    if (logoPath != null) {
      await _database.setAppSetting(key: _logoKey, value: logoPath);
    }
  }

  Future<void> clearLogo() async {
    await _database.setAppSetting(key: _logoKey, value: '');
  }

  Future<bool> hasSkippedInitialPrompt() async {
    final value = await _database.getAppSetting(_promptSkipKey);
    return value == 'true';
  }

  Future<void> markInitialPromptSkipped() async {
    await _database.setAppSetting(key: _promptSkipKey, value: 'true');
  }

  Future<CompanyLogoAsset?> exportLogoAsset() async {
    final logoPath = await _database.getAppSetting(_logoKey);
    if (logoPath == null || logoPath.trim().isEmpty) {
      return null;
    }

    final logoFile = File(logoPath);
    if (!await logoFile.exists()) {
      return null;
    }

    final bytes = await logoFile.readAsBytes();
    final extension = path.extension(logoPath).isEmpty
        ? '.png'
        : path.extension(logoPath);
    return CompanyLogoAsset(bytes: bytes, extension: extension);
  }

  Future<String?> copyLogoToAppDir(String sourcePath) async {
    if (sourcePath.trim().isEmpty) {
      return null;
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return null;
    }

    final baseDir = await _resolveBrandingDir();
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final ext = path.extension(sourcePath).isEmpty
        ? '.png'
        : path.extension(sourcePath);
    final targetPath = path.join(baseDir.path, '$_logoFileBase$ext');
    final targetFile = File(targetPath);
    await sourceFile.copy(targetFile.path);
    return targetFile.path;
  }

  Future<String?> importLogoFromBackup(File backupFile) async {
    if (!await backupFile.exists()) {
      return null;
    }

    final baseDir = await _resolveBrandingDir();
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final ext = path.extension(backupFile.path).isEmpty
        ? '.png'
        : path.extension(backupFile.path);
    final targetPath = path.join(baseDir.path, '$_logoFileBase$ext');
    final targetFile = File(targetPath);
    await backupFile.copy(targetFile.path);
    return targetFile.path;
  }

  Future<String?> saveLogoBytes({
    required Uint8List bytes,
    String extension = '.png',
  }) async {
    if (bytes.isEmpty) {
      return null;
    }

    final baseDir = await _resolveBrandingDir();
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final normalizedExtension = extension.trim().isEmpty
        ? '.png'
        : extension.trim();
    final targetPath = path.join(
      baseDir.path,
      '$_logoFileBase$normalizedExtension',
    );
    final targetFile = File(targetPath);
    await targetFile.writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  Future<Directory> _resolveBrandingDir() async {
    if (PlatformHelper.isAndroid) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(path.join(docs.path, 'shop_ledger', 'branding'));
    }

    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'shop_ledger', 'branding'));
  }
}

class CompanyLogoAsset {
  const CompanyLogoAsset({required this.bytes, required this.extension});

  final Uint8List bytes;
  final String extension;
}
