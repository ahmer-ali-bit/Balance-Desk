import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseRuntimeOptions {
  const FirebaseRuntimeOptions._();

  static const String _windowsApiKey = 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q';
  static const String _windowsAppId =
      '1:732686454468:web:8a26469f4625306022c391';
  static const String _windowsProjectId = 'balance-desk-4da9b';
  static const String _windowsSenderId = '732686454468';
  static const String _windowsStorageBucket =
      'balance-desk-4da9b.firebasestorage.app';

  static FirebaseOptions? resolve() {
    if (kIsWeb) {
      return _buildWebOptions();
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _buildAndroidOptions();
      case TargetPlatform.iOS:
        return _buildIosOptions();
      case TargetPlatform.macOS:
        return _buildMacosOptions();
      case TargetPlatform.windows:
        return _buildWindowsOptions();
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  static bool get hasPlatformOptions => resolve() != null;

  static FirebaseOptions? _buildWebOptions() => _buildOptions(
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
    appId: const String.fromEnvironment('FIREBASE_APP_ID_WEB'),
    projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    senderId: const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    measurementId: const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
    iosClientId: const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
    iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    androidClientId: const String.fromEnvironment('FIREBASE_ANDROID_CLIENT_ID'),
  );

  static FirebaseOptions? _buildAndroidOptions() => _buildOptions(
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
    appId: const String.fromEnvironment('FIREBASE_APP_ID_ANDROID'),
    projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    senderId: const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    measurementId: const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
    iosClientId: const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
    iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    androidClientId: const String.fromEnvironment('FIREBASE_ANDROID_CLIENT_ID'),
  );

  static FirebaseOptions? _buildIosOptions() => _buildOptions(
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
    appId: const String.fromEnvironment('FIREBASE_APP_ID_IOS'),
    projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    senderId: const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    measurementId: const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
    iosClientId: const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
    iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    androidClientId: const String.fromEnvironment('FIREBASE_ANDROID_CLIENT_ID'),
  );

  static FirebaseOptions? _buildMacosOptions() => _buildOptions(
    apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
    appId: const String.fromEnvironment('FIREBASE_APP_ID_MACOS'),
    projectId: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    senderId: const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    measurementId: const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
    iosClientId: const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
    iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    androidClientId: const String.fromEnvironment('FIREBASE_ANDROID_CLIENT_ID'),
  );

  static FirebaseOptions? _buildWindowsOptions() => _buildOptions(
    apiKey: _resolveValue(
      const String.fromEnvironment('FIREBASE_API_KEY'),
      _windowsApiKey,
    ),
    appId: _resolveValue(
      const String.fromEnvironment('FIREBASE_APP_ID_WINDOWS'),
      _windowsAppId,
    ),
    projectId: _resolveValue(
      const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      _windowsProjectId,
    ),
    senderId: _resolveValue(
      const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
      _windowsSenderId,
    ),
    storageBucket: _resolveOptionalValue(
      const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
      _windowsStorageBucket,
    ),
    authDomain: _resolveOptionalValue(
      const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    ),
    measurementId: _resolveOptionalValue(
      const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
    ),
    iosClientId: _resolveOptionalValue(
      const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
    ),
    iosBundleId: _resolveOptionalValue(
      const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
    ),
    androidClientId: _resolveOptionalValue(
      const String.fromEnvironment('FIREBASE_ANDROID_CLIENT_ID'),
    ),
  );

  static FirebaseOptions? _buildOptions({
    required String apiKey,
    required String appId,
    required String projectId,
    required String senderId,
    String? storageBucket,
    String? authDomain,
    String? measurementId,
    String? iosClientId,
    String? iosBundleId,
    String? androidClientId,
  }) {
    if (apiKey.isEmpty ||
        appId.isEmpty ||
        projectId.isEmpty ||
        senderId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
      storageBucket: _normalizeOptional(storageBucket),
      authDomain: _normalizeOptional(authDomain),
      measurementId: _normalizeOptional(measurementId),
      iosClientId: _normalizeOptional(iosClientId),
      iosBundleId: _normalizeOptional(iosBundleId),
      androidClientId: _normalizeOptional(androidClientId),
    );
  }

  static String? _normalizeOptional(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static String _resolveValue(String value, String fallback) {
    if (value.isNotEmpty) {
      return value;
    }
    return fallback;
  }

  static String? _resolveOptionalValue(String value, [String? fallback]) {
    if (value.isNotEmpty) {
      return value;
    }
    return fallback;
  }
}
