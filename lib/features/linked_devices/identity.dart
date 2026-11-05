import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LinkedDeviceIdentity {
  LinkedDeviceIdentity._();

  static const String _deviceIdKey = 'linked.identity.deviceId';
  static const String _deviceNameKey = 'linked.identity.deviceName';

  static String? _cachedId;
  static String? _cachedName;

  static Future<String> deviceId() async {
    if (_cachedId != null && _cachedId!.isNotEmpty) {
      return _cachedId!;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _cachedId = existing;
      return existing;
    }

    final String generated = _generateDeviceId();
    await prefs.setString(_deviceIdKey, generated);
    _cachedId = generated;
    return generated;
  }

  static Future<String> deviceName() async {
    if (_cachedName != null && _cachedName!.isNotEmpty) {
      return _cachedName!;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString(_deviceNameKey);
    if (saved != null && saved.isNotEmpty) {
      _cachedName = saved;
      return saved;
    }

    final String generated = await _resolveDeviceName();
    await prefs.setString(_deviceNameKey, generated);
    _cachedName = generated;
    return generated;
  }

  static Future<void> setDeviceName(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceNameKey, trimmed);
    _cachedName = trimmed;
  }

  static String shortId(String id) {
    if (id.length <= 6) return id.toUpperCase();
    return id
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase()
        .substring(0, 6);
  }

  static const int inviteTokenLength = 12;

  static String newInviteToken() {
    const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final Random rand = Random.secure();
    return List<String>.generate(
      inviteTokenLength,
      (_) => alphabet[rand.nextInt(alphabet.length)],
    ).join();
  }

  static String newWorkspaceId() {
    final Random rand = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generateDeviceId() {
    final Random rand = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final String hex = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  static Future<String> _resolveDeviceName() async {
    try {
      final DeviceInfoPlugin info = DeviceInfoPlugin();
      if (kIsWeb) {
        return 'Web Device';
      }
      if (Platform.isAndroid) {
        final AndroidDeviceInfo android = await info.androidInfo;
        final String brand = android.brand;
        final String model = android.model;
        return '$brand $model'.trim().isEmpty
            ? _fallbackName('AND')
            : '$brand $model';
      }
      if (Platform.isIOS) {
        final IosDeviceInfo ios = await info.iosInfo;
        return ios.name.isNotEmpty ? ios.name : _fallbackName('IOS');
      }
      if (Platform.isWindows) {
        final WindowsDeviceInfo win = await info.windowsInfo;
        return win.computerName.isNotEmpty
            ? win.computerName
            : _fallbackName('WIN');
      }
      if (Platform.isMacOS) {
        final MacOsDeviceInfo mac = await info.macOsInfo;
        return mac.computerName.isNotEmpty
            ? mac.computerName
            : _fallbackName('MAC');
      }
      if (Platform.isLinux) {
        final LinuxDeviceInfo linux = await info.linuxInfo;
        return linux.prettyName.isNotEmpty
            ? linux.prettyName
            : _fallbackName('LNX');
      }
    } catch (error) {
      debugPrint('device name resolve failed: $error');
    }
    return _fallbackName('DEV');
  }

  static String _fallbackName(String prefix) {
    final Random rand = Random.secure();
    final String suffix = (rand.nextInt(0xFFFF)).toRadixString(16).toUpperCase().padLeft(4, '0');
    return 'Device-$prefix-$suffix';
  }
}