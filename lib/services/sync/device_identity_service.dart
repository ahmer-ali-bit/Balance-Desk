import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_helper.dart';

/// Stable identity for this installation.
///
/// The device id is a 48-bit random value persisted in shared_preferences. It
/// is what the device roster, the invite ledger and every op's
/// `originDeviceId` refer to. It is not derived from hardware identifiers, so
/// nothing device-fingerprinting ever leaves the app.
class DeviceIdentityService {
  DeviceIdentityService._();

  static final DeviceIdentityService instance = DeviceIdentityService._();

  static const String _deviceIdKey = 'linked_device_id';
  static const String _displayNameKey = 'linked_device_name';
  static const int _deviceIdLength = 12;

  String _deviceId = '';
  String _displayName = '';

  String get deviceId => _deviceId;
  String get displayName => _displayName;
  String get platformLabel => PlatformHelper.platformLabel;

  bool get isReady => _deviceId.isNotEmpty;

  Future<void> initialize() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    _deviceId = prefs.getString(_deviceIdKey) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _generateDeviceId();
      await prefs.setString(_deviceIdKey, _deviceId);
    }

    _displayName = prefs.getString(_displayNameKey) ?? '';
    if (_displayName.isEmpty) {
      _displayName = _defaultDisplayName();
      await prefs.setString(_displayNameKey, _displayName);
    }
  }

  /// Local rename; pushed to the roster on the next sync pass.
  Future<void> rename(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      return;
    }
    _displayName = trimmed;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, trimmed);
  }

  String _generateDeviceId() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(6, (_) => random.nextInt(256));
    return sha256.convert(bytes).toString().substring(0, _deviceIdLength);
  }

  String _defaultDisplayName() =>
      '$platformLabel-${_deviceId.substring(0, 4)}';
}
