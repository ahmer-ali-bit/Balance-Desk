import 'dart:convert';
import 'dart:typed_data';

import 'export_file_service.dart';

/// CSV export built on the shared direct-save pipeline
/// (see [ExportFileService]). Files always land on the device — Downloads on
/// desktop, Files app on iOS, Downloads (or the system save dialog) on Android.
class ExportService {
  const ExportService();

  static const ExportFileService _fileService = ExportFileService();

  Future<ExportFileResult> saveCsv({
    required String fileName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final buffer = StringBuffer('\ufeff');
    buffer.writeln(_toCsvLine(headers));
    for (final row in rows) {
      buffer.writeln(_toCsvLine(row));
    }

    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    return _fileService.saveBytes(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: 'Save CSV',
    );
  }

  String _toCsvLine(List<String> values) {
    return values.map(_escapeCsv).join(',');
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
