import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../database/app_database.dart';
import '../utils/platform_helper.dart';

/// Service that wraps the `local_auth` plugin to provide biometric
/// authentication (fingerprint / Face ID / Touch ID).
///
/// All biometric data stays on-device — no network calls are made.
class BiometricAuthService {
  BiometricAuthService({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _biometricEnabledKey = 'biometricUnlockEnabled';

  // ---------------------------------------------------------------------------
  // Device capability
  // ---------------------------------------------------------------------------

  /// Returns `true` when the current device has biometric hardware **and** at
  /// least one fingerprint / face is enrolled.
  Future<bool> isBiometricAvailable() async {
    // Windows and Linux don't have reliable biometric support via local_auth.
    if (PlatformHelper.isWindows || PlatformHelper.isLinux) {
      return false;
    }

    try {
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } catch (error) {
      debugPrint('BiometricAuthService.isBiometricAvailable error: $error');
      return false;
    }
  }

  /// Returns a human-readable label for the primary biometric type available
  /// on this device (e.g. "Fingerprint", "Face ID", "Touch ID").
  Future<String> getBiometricLabel() async {
    try {
      final biometrics = await _localAuth.getAvailableBiometrics();

      if (biometrics.contains(BiometricType.face)) {
        return PlatformHelper.isIOS ? 'Face ID' : 'Face Unlock';
      }
      if (biometrics.contains(BiometricType.fingerprint)) {
        return PlatformHelper.isMacOS ? 'Touch ID' : 'Fingerprint';
      }
      if (biometrics.contains(BiometricType.iris)) {
        return 'Iris';
      }
      // Generic fallback
      return 'Biometric';
    } catch (_) {
      return 'Biometric';
    }
  }

  // ---------------------------------------------------------------------------
  // User preference
  // ---------------------------------------------------------------------------

  /// Whether the user has opted-in to biometric unlock in settings.
  Future<bool> isBiometricEnabled() async {
    final value = await _database.getAppSetting(_biometricEnabledKey);
    return value == 'true';
  }

  /// Persist the user's biometric-unlock preference.
  Future<void> setBiometricEnabled(bool enabled) async {
    await _database.setAppSetting(
      key: _biometricEnabledKey,
      value: enabled ? 'true' : 'false',
    );
  }

  // ---------------------------------------------------------------------------
  // Authentication
  // ---------------------------------------------------------------------------

  /// Trigger the system biometric prompt. Returns `true` on success.
  ///
  /// The [reason] is displayed to the user in the system dialog.
  Future<bool> authenticate({
    String reason = 'Unlock Balance Desk',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
        ),
      );
    } catch (error) {
      debugPrint('BiometricAuthService.authenticate error: $error');
      return false;
    }
  }
}
