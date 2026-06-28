import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

class AppPinService {
  static const String _pinHashKey = 'appPinHash';
  static const String _pinSaltKey = 'appPinSalt';
  static const String _pinKey = 'appPin';
  static const String _setupDismissedKey = 'appPinSetupDismissed';

  Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  Future<bool> hasPin() async {
    final prefs = await _prefs;
    final hash = prefs.getString(_pinHashKey);
    if (hash != null && hash.trim().isNotEmpty) {
      return true;
    }
    final legacyPin = prefs.getString(_pinKey);
    return (legacyPin?.trim().isNotEmpty ?? false);
  }

  Future<bool> shouldShowSetupPrompt() async {
    if (await hasPin()) {
      return false;
    }
    return !await isSetupPromptDismissed();
  }

  Future<bool> isSetupPromptDismissed() async {
    final prefs = await _prefs;
    return prefs.getString(_setupDismissedKey) == 'true';
  }

  Future<void> dismissSetupPrompt() async {
    final prefs = await _prefs;
    await prefs.setString(_setupDismissedKey, 'true');
  }

  Future<void> savePin(String pin) async {
    final normalizedPin = pin.trim();
    final salt = _generateSalt();
    final hash = _hashPin(normalizedPin, salt);
    final prefs = await _prefs;
    await prefs.setString(_pinHashKey, hash);
    await prefs.setString(_pinSaltKey, salt);
    await prefs.setString(_pinKey, '');
    await prefs.setString(_setupDismissedKey, 'true');
  }

  Future<bool> verifyPin(String pin) async {
    final normalizedPin = pin.trim();
    final prefs = await _prefs;
    final hash = prefs.getString(_pinHashKey);
    final salt = prefs.getString(_pinSaltKey);
    if ((hash ?? '').isNotEmpty && (salt ?? '').isNotEmpty) {
      return _hashPin(normalizedPin, salt!) == hash;
    }

    final legacyPin = prefs.getString(_pinKey);
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
    final prefs = await _prefs;
    await prefs.setString(_pinKey, '');
    await prefs.setString(_pinHashKey, '');
    await prefs.setString(_pinSaltKey, '');
    await prefs.setString(_setupDismissedKey, 'true');
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
