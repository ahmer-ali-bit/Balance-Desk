import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/platform_helper.dart';

/// Outcome of an export save operation.
///
/// `savedPath` is a filesystem path for direct saves (desktop / iOS / Android
/// public Downloads) or a content URI string when the system picker wrote the
/// bytes (Android SAF). It is `null` when the user cancelled the picker.
///
/// `locationLabel` is a short, human friendly description of where the file
/// went, suitable for a snackbar such as `Saved to $locationLabel`.
class ExportFileResult {
  const ExportFileResult({required this.savedPath, required this.locationLabel});

  final String? savedPath;
  final String locationLabel;

  bool get isSaved => savedPath != null && savedPath!.isNotEmpty;
}

/// Shared output pipeline for every export in the app (PDF, CSV).
///
/// Direct-save strategy per platform:
/// - macOS / Windows / Linux: write into the user's Downloads folder and open
///   the file with the OS default handler.
/// - iOS: write into `Documents/Exports` (visible in the Files app because the
///   app ships `UIFileSharingEnabled`) and open it with the system preview.
/// - Android: try the public Downloads folder (works where permitted); when
///   that is blocked by scoped storage, fall back to the system SAF
///   "Save as" flow via file_picker, which needs no storage permissions and
///   defaults to Downloads.
/// - Otherwise: system save dialog.
class ExportFileService {
  const ExportFileService();

  Future<ExportFileResult> saveBytes({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
    bool openAfterSave = true,
  }) async {
    if (PlatformHelper.isMacOS ||
        PlatformHelper.isWindows ||
        PlatformHelper.isLinux) {
      try {
        final directory = await getDownloadsDirectory();
        if (directory != null) {
          final file = await _writeUnique(directory, fileName, bytes);
          if (openAfterSave) {
            await _openSavedFile(file.path);
          }
          return ExportFileResult(
            savedPath: file.path,
            locationLabel: 'Downloads/${path.basename(file.path)}',
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          'ExportFileService: direct Downloads save failed; '
          'opening the system save dialog: $error',
        );
        debugPrint('$stackTrace');
      }
    } else if (PlatformHelper.isIOS) {
      try {
        final documents = await getApplicationDocumentsDirectory();
        final exportsDirectory = Directory(path.join(documents.path, 'Exports'));
        if (!await exportsDirectory.exists()) {
          await exportsDirectory.create(recursive: true);
        }
        final file = await _writeUnique(exportsDirectory, fileName, bytes);
        if (openAfterSave) {
          await _openSavedFile(file.path);
        }
        return ExportFileResult(
          savedPath: file.path,
          locationLabel:
              'Files app › Balance Desk › Exports/${path.basename(file.path)}',
        );
      } catch (error, stackTrace) {
        debugPrint(
          'ExportFileService: direct iOS save failed; '
          'opening the system save dialog: $error',
        );
        debugPrint('$stackTrace');
      }
    } else if (PlatformHelper.isAndroid) {
      try {
        final directory = await getDownloadsDirectory();
        if (directory != null) {
          final file = await _writeUnique(directory, fileName, bytes);
          return ExportFileResult(
            savedPath: file.path,
            locationLabel: 'Downloads/${path.basename(file.path)}',
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          'ExportFileService: direct Downloads write not allowed ($error), '
          'using system save dialog',
        );
        debugPrint('$stackTrace');
      }
    }

    final uri = await _saveWithSystemDialog(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: dialogTitle,
    );
    return ExportFileResult(
      savedPath: uri,
      locationLabel: 'the chosen location',
    );
  }

  Future<void> _openSavedFile(String filePath) async {
    try {
      await OpenFilex.open(filePath);
    } catch (error, stackTrace) {
      // Opening is a convenience; a successfully written export must still
      // count as saved even if this platform cannot preview that file type.
      debugPrint('ExportFileService: could not open saved file: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<String?> _saveWithSystemDialog({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    final extension = path.extension(fileName).replaceAll('.', '');
    final location = await FilePicker.saveFile(
      dialogTitle: dialogTitle ?? 'Save $fileName',
      fileName: fileName,
      type: extension.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extension.isEmpty ? null : <String>[extension],
      bytes: bytes,
    );
    if (location == null || location.isEmpty) {
      return location;
    }
    // Content URIs (Android SAF) are written by the plugin itself; plain
    // filesystem paths (desktop, iOS) are written here.
    if (!location.startsWith('content:')) {
      final file = File(location);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes, flush: true);
    }
    return location;
  }

  Future<File> _writeUnique(
    Directory directory,
    String fileName,
    Uint8List bytes,
  ) async {
    var target = path.join(directory.path, fileName);
    if (await File(target).exists()) {
      final extension = path.extension(fileName);
      final baseName = fileName.substring(0, fileName.length - extension.length);
      var index = 1;
      while (await File(
        path.join(directory.path, '$baseName ($index)$extension'),
      ).exists()) {
        index++;
      }
      target = path.join(directory.path, '$baseName ($index)$extension');
    }
    final file = File(target);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file.writeAsBytes(bytes, flush: true);
  }
}
