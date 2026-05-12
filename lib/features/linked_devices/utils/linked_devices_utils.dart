import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LinkedDevicesUtils {
  static const String _deviceIdKey = 'linked_device_persistent_id';
  static const String _deviceNameKey = 'linked_device_persistent_name';

  /// Returns a persistent device ID, generating one if it doesn't exist.
  static Future<String> getPersistentDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_deviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;

      final newId = _generateDeviceId();
      await prefs.setString(_deviceIdKey, newId);
      return newId;
    } catch (e) {
      debugPrint('getPersistentDeviceId error: $e');
      return _generateDeviceId();
    }
  }

  /// Returns a persistent device name, generating one if it doesn't exist.
  static Future<String> getPersistentDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_deviceNameKey);
      if (existing != null && existing.isNotEmpty) return existing;

      final platform = defaultTargetPlatform.name;
      final newName = 'Device-${platform.substring(0, min(3, platform.length)).toUpperCase()}-${_randomSuffix(4)}';
      await prefs.setString(_deviceNameKey, newName);
      return newName;
    } catch (e) {
      return 'Unknown Device';
    }
  }

  /// Formats a device ID for display (first 8 chars uppercase).
  static String formatDeviceId(String id) {
    if (id.isEmpty) return 'UNKNOWN';
    final clean = id.replaceAll('-', '').toUpperCase();
    return clean.length >= 8 ? clean.substring(0, 8) : clean;
  }

  static String _generateDeviceId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    String part() => List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    return '${part()}-${part()}-${part()}';
  }

  static String _randomSuffix(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
