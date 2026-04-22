import '../database/app_database.dart';

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class AppPinService {
  AppPinService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static const String _pinKey = 'appPin';
  static const String _pinHashKey = 'appPinHash';
  static const String _pinSaltKey = 'appPinSalt';
  static const String _setupDismissedKey = 'appPinSetupDismissed';

  Future<bool> hasPin() async {
    final hash = await _database.getAppSetting(_pinHashKey);
    if (hash != null && hash.trim().isNotEmpty) {
      return true;
    }
    final legacyPin = await _database.getAppSetting(_pinKey);
    return (legacyPin?.trim().isNotEmpty ?? false);
  }

  Future<bool> shouldShowSetupPrompt() async {
    if (await hasPin()) {
      return false;
    }

    return !await isSetupPromptDismissed();
  }

  Future<bool> isSetupPromptDismissed() async {
    final value = await _database.getAppSetting(_setupDismissedKey);
    return value == 'true';
  }

  Future<void> dismissSetupPrompt() async {
    await _database.setAppSetting(key: _setupDismissedKey, value: 'true');
  }

  Future<void> savePin(String pin) async {
    final normalizedPin = pin.trim();
    final salt = _generateSalt();
    final hash = _hashPin(normalizedPin, salt);
    await _database.setAppSetting(key: _pinHashKey, value: hash);
    await _database.setAppSetting(key: _pinSaltKey, value: salt);
    await _database.setAppSetting(key: _pinKey, value: '');
    await _database.setAppSetting(key: _setupDismissedKey, value: 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final normalizedPin = pin.trim();
    final hash = await _database.getAppSetting(_pinHashKey);
    final salt = await _database.getAppSetting(_pinSaltKey);
    if ((hash ?? '').isNotEmpty && (salt ?? '').isNotEmpty) {
      return _hashPin(normalizedPin, salt!) == hash;
    }

    final legacyPin = await _database.getAppSetting(_pinKey);
    final matches =
        (legacyPin?.trim().isNotEmpty ?? false) && legacyPin == normalizedPin;
    if (matches) {
      await savePin(normalizedPin);
    }
    return matches;
  }

  Future<bool> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final matches = await verifyPin(currentPin);
    if (!matches) {
      return false;
    }

    await savePin(newPin);
    return true;
  }

  Future<bool> disablePin(String currentPin) async {
    final matches = await verifyPin(currentPin);
    if (!matches) {
      return false;
    }

    await _database.setAppSetting(key: _pinKey, value: '');
    await _database.setAppSetting(key: _pinHashKey, value: '');
    await _database.setAppSetting(key: _pinSaltKey, value: '');
    await _database.setAppSetting(key: _setupDismissedKey, value: 'true');
    return true;
  }

  static String? validatePin(String? value) {
    final pin = value?.trim() ?? '';
    if (pin.isEmpty) {
      return 'PIN is required.';
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) {
      return 'PIN must contain digits only.';
    }
    if (pin.length < 4 || pin.length > 6) {
      return 'Use a 4 to 6 digit PIN.';
    }
    return null;
  }

  String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}
