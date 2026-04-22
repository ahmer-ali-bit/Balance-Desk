import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/platform_helper.dart';

class ManualUpdateService {
  ManualUpdateService._();

  static final ManualUpdateService instance = ManualUpdateService._();

  Future<AppVersionInfo> getAppVersionInfo() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }

  Future<ManualUpdateResult> pickUpdateFile() async {
    final allowedExtensions = PlatformHelper.isAndroid
        ? const <String>['apk']
        : const <String>['exe', 'zip'];
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      dialogTitle: 'Select update file',
    );

    if (result == null || result.files.isEmpty) {
      return ManualUpdateResult.cancelled('No file selected.');
    }

    final picked = result.files.first;
    final path = picked.path ?? '';
    if (path.isEmpty) {
      return ManualUpdateResult.failure('Invalid file selected.');
    }

    final extension = _fileExtension(path);
    if (!_isValidExtension(extension)) {
      return ManualUpdateResult.failure(
        PlatformHelper.isAndroid
            ? 'Please select a valid APK file.'
            : 'Please select a valid EXE or ZIP file.',
      );
    }

    final file = File(path);
    if (!await file.exists()) {
      return ManualUpdateResult.failure('Selected file was not found.');
    }
    final length = await file.length();
    if (length == 0) {
      return ManualUpdateResult.failure('Selected file appears to be empty.');
    }

    final versionInfo = await getAppVersionInfo();
    final parsedVersion = _extractVersionFromFileName(picked.name);
    final versionStatus = parsedVersion == null
        ? ManualUpdateVersionStatus.unknown
        : _compareVersions(parsedVersion, versionInfo.version) > 0
        ? ManualUpdateVersionStatus.newer
        : ManualUpdateVersionStatus.notNewer;

    return ManualUpdateResult.success(
      ManualUpdateFile(
        path: path,
        name: picked.name,
        extension: extension,
        parsedVersion: parsedVersion,
      ),
      currentVersion: versionInfo.version,
      versionStatus: versionStatus,
    );
  }

  Future<ManualUpdateResult> openInstaller(ManualUpdateFile file) async {
    if (PlatformHelper.isAndroid) {
      final result = await OpenFilex.open(file.path);
      if (result.type == ResultType.done) {
        return ManualUpdateResult.success(
          file,
          message: 'Opening installer...',
        );
      }
      return ManualUpdateResult.failure(
        result.message.isNotEmpty
            ? result.message
            : 'Unable to open installer.',
      );
    }

    return ManualUpdateResult.success(
      file,
      message: 'Close the app and run the installer.',
    );
  }

  bool _isValidExtension(String extension) {
    if (PlatformHelper.isAndroid) {
      return extension == 'apk';
    }
    return extension == 'exe' || extension == 'zip';
  }

  String _fileExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return '';
    }
    return path.substring(dotIndex + 1).toLowerCase();
  }

  String? _extractVersionFromFileName(String name) {
    final match = RegExp(r'(\d+\.\d+\.\d+(?:\+\d+)?)').firstMatch(name);
    return match?.group(1);
  }

  int _compareVersions(String a, String b) {
    List<int> parse(String value) {
      final cleaned = value.split('+').first;
      final parts = cleaned.split('.');
      return <int>[
        int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
        int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
        int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
      ];
    }

    final left = parse(a);
    final right = parse(b);
    for (var i = 0; i < 3; i++) {
      final diff = left[i].compareTo(right[i]);
      if (diff != 0) {
        return diff;
      }
    }
    return 0;
  }
}

class ManualUpdateFile {
  const ManualUpdateFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.parsedVersion,
  });

  final String path;
  final String name;
  final String extension;
  final String? parsedVersion;
}

enum ManualUpdateVersionStatus { unknown, newer, notNewer }

class ManualUpdateResult {
  ManualUpdateResult._({
    required this.isSuccess,
    required this.message,
    this.file,
    this.currentVersion,
    this.versionStatus = ManualUpdateVersionStatus.unknown,
  });

  factory ManualUpdateResult.success(
    ManualUpdateFile file, {
    String? message,
    String? currentVersion,
    ManualUpdateVersionStatus versionStatus = ManualUpdateVersionStatus.unknown,
  }) {
    return ManualUpdateResult._(
      isSuccess: true,
      message: message ?? 'Update file ready.',
      file: file,
      currentVersion: currentVersion,
      versionStatus: versionStatus,
    );
  }

  factory ManualUpdateResult.failure(String message) {
    return ManualUpdateResult._(isSuccess: false, message: message);
  }

  factory ManualUpdateResult.cancelled(String message) {
    return ManualUpdateResult._(isSuccess: false, message: message);
  }

  final bool isSuccess;
  final String message;
  final ManualUpdateFile? file;
  final String? currentVersion;
  final ManualUpdateVersionStatus versionStatus;
}

class AppVersionInfo {
  const AppVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label =>
      buildNumber.trim().isEmpty ? version : '$version+$buildNumber';
}
