import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ExportService {
  const ExportService();

  Future<String?> saveCsv({
    required String dialogTitle,
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    String? savePath;
    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['csv'],
      );
    } catch (error, stackTrace) {
      debugPrint('ExportService.saveCsv failed: $error');
      debugPrint('$stackTrace');
      savePath = await _resolveAndroidFallbackPath('exports', fileName);
    }

    if (savePath == null || savePath.isEmpty) {
      return null;
    }

    final buffer = StringBuffer('\ufeff');
    buffer.writeln(_toCsvLine(headers));
    for (final row in rows) {
      buffer.writeln(_toCsvLine(row));
    }

    final file = File(savePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(buffer.toString(), flush: true);
    return savePath;
  }

  Future<String> _resolveAndroidFallbackPath(
    String directoryName,
    String fileName,
  ) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final exportDirectory = Directory(
      path.join(documentsDirectory.path, 'shop_ledger', directoryName),
    );

    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }

    return path.join(exportDirectory.path, fileName);
  }

  String _toCsvLine(List<String> values) {
    return values.map(_escapeCsv).join(',');
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
