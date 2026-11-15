import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/supabase_config.dart';

class LinkedDeviceException implements Exception {
  const LinkedDeviceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Minimal Supabase PostgREST RPC client. It deliberately has no table APIs:
/// all cloud reads/writes go through narrowly scoped, capability-checked SQL
/// functions. Only the publishable key ships in the client binary.
class LinkedDeviceApi {
  LinkedDeviceApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 20);

  Future<dynamic> rpc(String function, Map<String, Object?> arguments) async {
    final uri = Uri.parse(
      '${SupabaseConfig.url}/rest/v1/rpc/$function',
    );
    late http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'apikey': SupabaseConfig.publishableKey,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(arguments),
          )
          .timeout(_timeout);
    } on Exception catch (error) {
      throw LinkedDeviceException(
        'Could not reach the secure sync service. Check your connection and try again. ($error)',
      );
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? (decoded['message'] ?? decoded['details'] ?? decoded['hint'] ?? decoded['code'])
          : decoded;
      throw LinkedDeviceException(
        (message ?? 'Secure sync request failed (${response.statusCode}).').toString(),
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void close() => _client.close();
}
