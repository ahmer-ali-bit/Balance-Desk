import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FirestoreException implements Exception {
  const FirestoreException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isPermissionDenied => statusCode == 401 || statusCode == 403;
  bool get isQuotaExceeded => statusCode == 429;
  bool get isOffline => statusCode == 0;

  @override
  String toString() => 'Firestore error $statusCode: $message';
}

class FirestoreWrite {
  const FirestoreWrite({
    required this.path,
    required this.fields,
    this.updateMask,
  });

  final String path;
  final Map<String, Object?> fields;
  final List<String>? updateMask;
}

class FirestoreRestClient {
  FirestoreRestClient._();

  static const String projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'balance-desk-4da9b',
  );

  static const String _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q',
  );
  static const String _root = 'projects/$projectId/databases/(default)/documents';
  static const String _baseUrl = 'https://firestore.googleapis.com/v1/$_root';

  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 20);
  static const int maxBatchSize = 50;

  static const Map<String, String> _jsonHeaders = <String, String>{
    'Content-Type': 'application/json',
  };

  static Future<Map<String, Object?>?> getDocument(String path) async {
    return _retry(() async {
      final response = await http
          .get(Uri.parse('$_baseUrl/$path?key=$_apiKey'))
          .timeout(_timeout);
      if (response.statusCode == 404) return null;
      _ensureSuccess(response, 'getDocument $path');
      return _simplifyDocument(
        json.decode(response.body) as Map<String, dynamic>,
      );
    });
  }

  static Future<void> setDocument(
    String path,
    Map<String, Object?> fields,
  ) async {
    await _retry(() async {
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/$path?key=$_apiKey'),
            headers: _jsonHeaders,
            body: json.encode(<String, Object?>{
              'fields': encodeFields(fields),
            }),
          )
          .timeout(_timeout);
      _ensureSuccess(response, 'setDocument $path');
      return null;
    });
  }

  static Future<void> updateDocument(
    String path,
    Map<String, Object?> fields, {
    List<String>? fieldPaths,
  }) async {
    final List<String> mask = fieldPaths ?? fields.keys.toList();
    final String maskQuery = mask
        .map(
          (String field) =>
              'updateMask.fieldPaths=${Uri.encodeQueryComponent(field)}',
        )
        .join('&');

    await _retry(() async {
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/$path?$maskQuery&key=$_apiKey'),
            headers: _jsonHeaders,
            body: json.encode(<String, Object?>{
              'fields': encodeFields(fields),
            }),
          )
          .timeout(_timeout);
      _ensureSuccess(response, 'updateDocument $path');
      return null;
    });
  }

  static Future<void> deleteDocument(String path) async {
    await _retry(() async {
      final response = await http
          .delete(Uri.parse('$_baseUrl/$path?key=$_apiKey'))
          .timeout(_timeout);
      if (response.statusCode == 404) return null;
      _ensureSuccess(response, 'deleteDocument $path');
      return null;
    });
  }

  static Future<void> commit(List<FirestoreWrite> writes) async {
    if (writes.isEmpty) return;

    final List<Map<String, Object?>> payload = writes.map((FirestoreWrite w) {
      final Map<String, Object?> entry = <String, Object?>{
        'update': <String, Object?>{
          'name': '$_root/${w.path}',
          'fields': encodeFields(w.fields),
        },
      };
      final List<String>? mask = w.updateMask;
      if (mask != null) {
        entry['updateMask'] = <String, Object?>{'fieldPaths': mask};
      }
      return entry;
    }).toList();

    await _retry(() async {
      final response = await http
          .post(
            Uri.parse(
              'https://firestore.googleapis.com/v1/'
              'projects/$projectId/databases/(default)/documents:commit'
              '?key=$_apiKey',
            ),
            headers: _jsonHeaders,
            body: json.encode(<String, Object?>{'writes': payload}),
          )
          .timeout(_timeout);
      _ensureSuccess(response, 'commit (${writes.length} writes)');
      return null;
    });
  }

  static Future<List<Map<String, Object?>>> queryPage({
    required String parentPath,
    required String collectionId,
    String? cursorUpdatedAt,
    String? cursorDocId,
    int limit = 300,
  }) async {
    final Map<String, Object?> structuredQuery = <String, Object?>{
      'from': <Object?>[
        <String, Object?>{'collectionId': collectionId},
      ],
      'orderBy': <Object?>[
        <String, Object?>{
          'field': <String, Object?>{'fieldPath': 'updatedAt'},
          'direction': 'ASCENDING',
        },
        <String, Object?>{
          'field': <String, Object?>{'fieldPath': '__name__'},
          'direction': 'ASCENDING',
        },
      ],
      'limit': limit,
    };

    if (cursorUpdatedAt != null &&
        cursorUpdatedAt.isNotEmpty &&
        cursorDocId != null &&
        cursorDocId.isNotEmpty) {
      final String reference = parentPath.isEmpty
          ? '$_root/$collectionId/$cursorDocId'
          : '$_root/$parentPath/$collectionId/$cursorDocId';
      structuredQuery['startAt'] = <String, Object?>{
        'values': <Object?>[
          <String, Object?>{'stringValue': cursorUpdatedAt},
          <String, Object?>{'referenceValue': reference},
        ],
        'before': false,
      };
    }

    final String suffix = parentPath.isEmpty ? '' : '/$parentPath';

    return _retry(() async {
      final response = await http
          .post(
            Uri.parse('$_baseUrl$suffix:runQuery?key=$_apiKey'),
            headers: _jsonHeaders,
            body: json.encode(<String, Object?>{
              'structuredQuery': structuredQuery,
            }),
          )
          .timeout(_timeout);
      _ensureSuccess(response, 'runQuery $collectionId');

      final decoded = json.decode(response.body);
      if (decoded is! List) return <Map<String, Object?>>[];
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      for (final Object? entry in decoded) {
        if (entry is! Map) continue;
        final Object? document = entry['document'];
        if (document is! Map<String, dynamic>) continue;
        final Map<String, Object?>? simplified = _simplifyDocument(document);
        if (simplified != null) rows.add(simplified);
      }
      return rows;
    });
  }

  static Stream<Map<String, Object?>?> watchDocument(String path) {
    late final StreamController<Map<String, Object?>?> controller;

    http.Client? client;
    int attempt = 0;
    bool stopped = false;

    Future<void> connect() async {
      if (stopped) return;
      final http.Client localClient = http.Client();
      client = localClient;
      try {
        final http.StreamedResponse response = await localClient.send(
          http.Request('POST', Uri.parse('$_baseUrl:listen?key=$_apiKey'))
            ..headers.addAll(_jsonHeaders)
            ..body = json.encode(<String, Object?>{
              'database': 'projects/$projectId/databases/(default)',
              'addTarget': <String, Object?>{
                'documents': <String, Object?>{
                  'documents': <String>['$_root/$path'],
                },
              },
            }),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final String body = await response.stream.bytesToString();
          throw FirestoreException(response.statusCode, _extractMessage(body));
        }

        attempt = 0;
        final _JsonObjectSplitter splitter = _JsonObjectSplitter();
        await for (final String text
            in response.stream.transform(utf8.decoder)) {
          if (stopped) return;
          for (final String raw in splitter.add(text)) {
            final Object? decoded = json.decode(raw);
            if (decoded is! Map) continue;
            final Object? document = decoded['document'];
            if (document is Map<String, dynamic>) {
              controller.add(_simplifyDocument(document));
            }
          }
        }
      } on FirestoreException catch (error) {
        if (!error.isPermissionDenied && !error.isQuotaExceeded) {
          debugPrint('Firestore watch $path dropped: $error');
        } else {
          stopped = true;
          controller.addError(error);
          await controller.close();
        }
      } catch (error) {
        debugPrint('Firestore watch $path dropped: $error');
      } finally {
        localClient.close();
        if (identical(client, localClient)) client = null;
      }

      if (stopped) return;
      attempt++;
      await Future<void>.delayed(_watchBackoff(attempt));
      if (!stopped) unawaited(connect());
    }

    controller = StreamController<Map<String, Object?>?>(
      onListen: () => unawaited(connect()),
      onCancel: () {
        stopped = true;
        client?.close();
        client = null;
      },
    );
    return controller.stream;
  }

  static Duration _watchBackoff(int attempt) {
    final int seconds = 1 << (attempt.clamp(1, 8));
    return Duration(seconds: seconds > 300 ? 300 : seconds);
  }

  static Future<T> _retry<T>(Future<T> Function() action) async {
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await action();
      } on FirestoreException catch (error) {
        if (error.isPermissionDenied || error.isQuotaExceeded) rethrow;
        if (attempt + 1 >= _maxRetries) rethrow;
      } on SocketException catch (error) {
        if (attempt + 1 >= _maxRetries) {
          throw FirestoreException(0, error.message);
        }
      } on http.ClientException catch (error) {
        if (attempt + 1 >= _maxRetries) {
          throw FirestoreException(0, error.message);
        }
      } on TimeoutException {
        if (attempt + 1 >= _maxRetries) {
          throw const FirestoreException(0, 'Request timed out');
        }
      } on FormatException catch (error) {
        throw FirestoreException(0, 'Malformed response: ${error.message}');
      }
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
    throw const FirestoreException(0, 'Request failed after retries');
  }

  static void _ensureSuccess(http.Response response, String label) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    debugPrint('Firestore $label failed [${response.statusCode}]');
    debugPrint('Firestore raw response: ${response.body}');
    throw FirestoreException(
      response.statusCode,
      _extractMessage(response.body),
    );
  }

  static String _extractMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final Object? message = (decoded['error'] as Map)['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {}
    return body.length > 200 ? body.substring(0, 200) : body;
  }

  static Map<String, Object?>? _simplifyDocument(Map<String, dynamic> doc) {
    final Object? name = doc['name'];
    final Object? fields = doc['fields'];

    final Map<String, Object?> result = <String, Object?>{};
    if (fields is Map<String, dynamic>) {
      fields.forEach((String key, Object? value) {
        result[key] = decodeValue(value);
      });
    }
    if (name is String) result['__id'] = name.split('/').last;
    return result;
  }

  @visibleForTesting
  static Object? decodeValue(Object? value) {
    if (value is! Map) return null;
    if (value.containsKey('stringValue')) {
      return value['stringValue'] as String?;
    }
    if (value.containsKey('booleanValue')) {
      return value['booleanValue'] as bool?;
    }
    if (value.containsKey('integerValue')) {
      final Object? raw = value['integerValue'];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '');
    }
    if (value.containsKey('doubleValue')) {
      final Object? raw = value['doubleValue'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '');
    }
    if (value.containsKey('timestampValue')) {
      return value['timestampValue'] as String?;
    }
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('mapValue')) {
      final Object? inner = value['mapValue'];
      if (inner is! Map) return <String, Object?>{};
      final Object? innerFields = inner['fields'];
      if (innerFields is! Map) return <String, Object?>{};
      final Map<String, Object?> map = <String, Object?>{};
      innerFields.forEach((Object? key, Object? entry) {
        map[key.toString()] = decodeValue(entry);
      });
      return map;
    }
    if (value.containsKey('arrayValue')) {
      final Object? inner = value['arrayValue'];
      if (inner is! Map) return <Object?>[];
      final Object? values = inner['values'];
      if (values is! List) return <Object?>[];
      return values.map(decodeValue).toList();
    }
    return null;
  }

  @visibleForTesting
  static Map<String, Object?> encodeFields(Map<String, Object?> data) {
    final Map<String, Object?> encoded = <String, Object?>{};
    data.forEach((String key, Object? value) {
      encoded[key] = _encodeValue(value);
    });
    return encoded;
  }

  static Map<String, Object?> _encodeValue(Object? value) {
    if (value == null) return <String, Object?>{'nullValue': null};
    if (value is String) return <String, Object?>{'stringValue': value};
    if (value is bool) return <String, Object?>{'booleanValue': value};
    if (value is int) {
      return <String, Object?>{'integerValue': value.toString()};
    }
    if (value is double) return <String, Object?>{'doubleValue': value};
    if (value is Map) {
      final Map<String, Object?> inner = <String, Object?>{};
      value.forEach((Object? key, Object? entry) {
        inner[key.toString()] = _encodeValue(entry);
      });
      return <String, Object?>{
        'mapValue': <String, Object?>{'fields': inner},
      };
    }
    if (value is Iterable) {
      return <String, Object?>{
        'arrayValue': <String, Object?>{
          'values': value.map(_encodeValue).toList(),
        },
      };
    }
    return <String, Object?>{'stringValue': value.toString()};
  }
}

class _JsonObjectSplitter {
  final StringBuffer _buffer = StringBuffer();
  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;
  bool _started = false;

  List<String> add(String chunk) {
    final List<String> complete = <String>[];
    for (int index = 0; index < chunk.length; index++) {
      final String char = chunk[index];

      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (char == r'\') {
          _escaped = true;
        } else if (char == '"') {
          _inString = false;
        }
        _buffer.write(char);
        continue;
      }

      switch (char) {
        case '"':
          _inString = true;
          _started = true;
          _buffer.write(char);
        case '{':
        case '[':
          if (char == '{' && _depth == 0) _buffer.clear();
          _depth++;
          _started = true;
          _buffer.write(char);
        case '}':
        case ']':
          _depth--;
          _buffer.write(char);
          if (_depth <= 0) {
            _depth = 0;
            if (_started) complete.add(_buffer.toString());
            _buffer.clear();
            _started = false;
          }
        default:
          if (_depth > 0) _buffer.write(char);
      }
    }
    return complete;
  }
}