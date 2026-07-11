import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FirestoreRESTClient {
  static const String _projectId = 'balance-desk-4da9b';
  static const String _apiKey = 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q';
  static const String _baseUrl =
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

  static const int _maxRetries = 3;

  /// Retry helper for transient write failures (NOT quota — retrying on 429 only burns more writes)
  static Future<T> _retryTransient<T>(Future<T> Function() fn) async {
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await fn();
      } on _QuotaException {
        rethrow; // never retry on quota — daily limit won't reset mid-request
      } catch (_) {
        if (attempt + 1 >= _maxRetries) rethrow;
        final delay = Duration(seconds: 1 << attempt); // 1s, 2s, 4s
        debugPrint('Transient write failure, retrying in ${delay.inSeconds}s…');
        await Future.delayed(delay);
      }
    }
    throw Exception('Max retries exhausted');
  }

  /// ✅ Get a single document
  static Future<Map<String, dynamic>?> getDocument(
    String collection,
    String docId,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl/$collection/$docId?key=$_apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _simplifyDocument(data);
      }
      _logStatus(response.statusCode, response.body, 'getDocument');
      return null;
    } catch (e) {
      debugPrint('REST getDocument error: $e');
      return null;
    }
  }

  /// ✅ Set (Create/Replace) a document (retry on transient failure, NOT on quota)
  static Future<bool> setDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    return _retryTransient(() => _setDocumentOnce(collection, docId, data));
  }

  static Future<bool> _setDocumentOnce(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl/$collection/$docId?key=$_apiKey');
      final body = json.encode({'fields': _toFirestoreFields(data)});
      final response = await http.patch(url, body: body);
      if (response.statusCode == 200) return true;
      _throwIfQuota(response.statusCode);
      debugPrint(
        'REST setDocument failed [${response.statusCode}]: ${response.body}',
      );
      return false;
    } catch (e) {
      if (e is _QuotaException) rethrow;
      debugPrint('REST setDocument error: $e');
      return false;
    }
  }

  /// ✅ Update specific fields in a document (retry on transient failure, NOT on quota)
  static Future<bool> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    return _retryTransient(() => _updateDocumentOnce(collection, docId, data));
  }

  static Future<bool> _updateDocumentOnce(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      final updateMask = data.keys
          .map((k) => 'updateMask.fieldPaths=$k')
          .join('&');
      final url = Uri.parse(
        '$_baseUrl/$collection/$docId?$updateMask&key=$_apiKey',
      );
      final body = json.encode({'fields': _toFirestoreFields(data)});
      final response = await http.patch(url, body: body);
      if (response.statusCode == 200) return true;
      _throwIfQuota(response.statusCode);
      debugPrint(
        'REST updateDocument failed [${response.statusCode}]: ${response.body}',
      );
      return false;
    } catch (e) {
      if (e is _QuotaException) rethrow;
      debugPrint('REST updateDocument error: $e');
      return false;
    }
  }

  /// ✅ Get all documents in a collection (with optional query filters)
  static Future<List<Map<String, dynamic>>> getCollection(
    String collection, {
    String? whereField,
    String? isEqualTo,
  }) async {
    try {
      if (whereField != null && isEqualTo != null) {
        return runQuery(collection,
            whereField: whereField, isEqualTo: isEqualTo);
      }

      final url = Uri.parse('$_baseUrl/$collection?key=$_apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final documents = (data['documents'] as List?) ?? [];
        return documents
            .map((d) => _simplifyDocument(d))
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      debugPrint(
        'REST getCollection failed [${response.statusCode}]: ${response.body}',
      );
      return [];
    } catch (e) {
      debugPrint('REST getCollection error: $e');
      return [];
    }
  }

  /// ✅ Server-side query using Firestore REST runQuery
  static Future<List<Map<String, dynamic>>> runQuery(
    String collection, {
    required String whereField,
    required String isEqualTo,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl:runQuery?key=$_apiKey');
      final query = {
        'structuredQuery': {
          'from': [{'collectionId': collection}],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': whereField},
              'op': 'EQUAL',
              'value': _toFieldValue(isEqualTo),
            }
          },
        }
      };
      final response = await http.post(url, body: json.encode(query));
      if (response.statusCode == 200) {
        final results = json.decode(response.body) as List;
        return results
            .where((r) => r['document'] != null)
            .map((r) => _simplifyDocument(r['document'] as Map<String, dynamic>))
            .whereType<Map<String, dynamic>>()
            .toList();
      }
      debugPrint(
        'REST runQuery failed [${response.statusCode}]: ${response.body}',
      );
      return [];
    } catch (e) {
      debugPrint('REST runQuery error: $e');
      return [];
    }
  }

  /// ✅ Conversion helpers
  static Map<String, dynamic>? _simplifyDocument(Map<String, dynamic> doc) {
    if (doc['fields'] == null) return null;
    final fields = doc['fields'] as Map<String, dynamic>;
    final result = <String, dynamic>{};
    fields.forEach((key, value) {
      result[key] = _unwrapValue(value);
    });
    // Add document ID if available
    if (doc['name'] != null) {
      result['id'] = (doc['name'] as String).split('/').last;
    }
    return result;
  }

  static dynamic _unwrapValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse(value['integerValue']);
    }
    if (value.containsKey('doubleValue')) return value['doubleValue'];
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('mapValue')) {
      final map = value['mapValue']['fields'] as Map<String, dynamic>? ?? {};
      return map.map((k, v) => MapEntry(k, _unwrapValue(v)));
    }
    return null;
  }

  static Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value == null) return MapEntry(key, {'nullValue': null});
      if (value is String) return MapEntry(key, {'stringValue': value});
      if (value is bool) return MapEntry(key, {'booleanValue': value});
      if (value is int) {
        return MapEntry(key, {'integerValue': value.toString()});
      }
      if (value is double) return MapEntry(key, {'doubleValue': value});
      if (value is Map<String, dynamic>) {
        return MapEntry(key, {
          'mapValue': {'fields': _toFirestoreFields(value)},
        });
      }
      return MapEntry(key, {'stringValue': value.toString()});
    });
  }

  static Map<String, dynamic> _toFieldValue(String value) {
    if (value == 'true') return {'booleanValue': true};
    if (value == 'false') return {'booleanValue': false};
    final intVal = int.tryParse(value);
    if (intVal != null) return {'integerValue': value};
    final doubleVal = double.tryParse(value);
    if (doubleVal != null) return {'doubleValue': double.parse(value)};
    return {'stringValue': value};
  }

  static void _throwIfQuota(int statusCode) {
    if (statusCode == 429) throw const _QuotaException();
  }

  static void _logStatus(int statusCode, String body, String method) {
    if (statusCode == 429) {
      debugPrint('REST $method quota exceeded (429)');
    } else {
      debugPrint('REST $method failed [$statusCode]: $body');
    }
  }
}

class _QuotaException implements Exception {
  const _QuotaException();
  @override
  String toString() => 'Firestore quota exceeded';
}
