import 'dart:convert';

class WorkspaceSnapshotPayload {
  const WorkspaceSnapshotPayload({
    required this.schemaVersion,
    required this.exportedAt,
    required this.workspaceName,
    required this.customers,
    required this.entries,
    required this.snapshots,
    required this.years,
    required this.settings,
    required this.logoBase64,
    required this.logoExtension,
  });

  final int schemaVersion;
  final String exportedAt;
  final String workspaceName;
  final List<Map<String, Object?>> customers;
  final List<Map<String, Object?>> entries;
  final List<Map<String, Object?>> snapshots;
  final List<int> years;
  final Map<String, String> settings;
  final String? logoBase64;
  final String? logoExtension;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt,
      'workspaceName': workspaceName,
      'customers': customers,
      'entries': entries,
      'snapshots': snapshots,
      'years': years,
      'settings': settings,
      'logoBase64': logoBase64,
      'logoExtension': logoExtension,
    };
  }

  String encode() => jsonEncode(toJson());

  factory WorkspaceSnapshotPayload.fromEncoded(String value) {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return WorkspaceSnapshotPayload.fromJson(decoded);
  }

  factory WorkspaceSnapshotPayload.fromJson(Map<String, dynamic> map) {
    return WorkspaceSnapshotPayload(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      exportedAt: map['exportedAt'] as String? ?? '',
      workspaceName: map['workspaceName'] as String? ?? 'Balance Desk',
      customers: _listOfMaps(map['customers']),
      entries: _listOfMaps(map['entries']),
      snapshots: _listOfMaps(map['snapshots']),
      years: (map['years'] as List<dynamic>? ?? const <dynamic>[])
          .map<int>((dynamic value) => (value as num).toInt())
          .toList(growable: false),
      settings:
          (map['settings'] as Map<String, dynamic>? ??
                  const <String, dynamic>{})
              .map<String, String>(
                (String key, dynamic value) => MapEntry(key, '${value ?? ''}'),
              ),
      logoBase64: map['logoBase64'] as String?,
      logoExtension: map['logoExtension'] as String?,
    );
  }

  static List<Map<String, Object?>> _listOfMaps(Object? value) {
    return (value as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map<Map<String, Object?>>((Map<dynamic, dynamic> row) {
          return row.map<String, Object?>(
            (dynamic key, dynamic entryValue) =>
                MapEntry('${key ?? ''}', entryValue),
          );
        })
        .toList(growable: false);
  }
}
