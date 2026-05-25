import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FirestoreRESTClient {
  static const String _projectId = 'balance-desk-4da9b';
  static const String _apiKey = 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q';
  static const String _baseUrl =
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

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
      debugPrint(
        'REST getDocument failed [${response.statusCode}]: ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('REST getDocument error: $e');
      return null;
    }
  }

  /// ✅ Set (Create/Replace) a document
  static Future<bool> setDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      final url = Uri.parse('$_baseUrl/$collection/$docId?key=$_apiKey');
      final body = json.encode({'fields': _toFirestoreFields(data)});
      final response = await http.patch(url, body: body);
      if (response.statusCode == 200) return true;

      debugPrint(
        'REST setDocument failed [${response.statusCode}]: ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('REST setDocument error: $e');
      return false;
    }
  }

  /// ✅ Update specific fields in a document
  static Future<bool> updateDocument(
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

      debugPrint(
        'REST updateDocument failed [${response.statusCode}]: ${response.body}',
      );
      return false;
    } catch (e) {
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
      final url = Uri.parse('$_baseUrl/$collection?key=$_apiKey');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final documents = (data['documents'] as List?) ?? [];
        final results = documents
            .map((d) => _simplifyDocument(d))
            .whereType<Map<String, dynamic>>()
            .toList();

        if (whereField != null && isEqualTo != null) {
          return results.where((doc) => doc[whereField] == isEqualTo).toList();
        }
        return results;
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
}
