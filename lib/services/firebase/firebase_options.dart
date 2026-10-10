import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase configuration used by the Linked Devices feature.
///
/// Every value is injected at build time with `--dart-define`, so no
/// credential is ever committed to this repository. See
/// `docs/firebase_auth_setup.md` for the full list of supported keys and for
/// `windows_firebase.ps1` / the GitHub Actions workflow that supply them.
///
/// If the required defines are missing, [isConfigured] is `false` and the app
/// runs exactly as before — local ledger only, Linked Devices disabled.
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const String _measurementId =
      String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

  static const String _appIdAndroid =
      String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const String _appIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const String _appIdMacos =
      String.fromEnvironment('FIREBASE_APP_ID_MACOS');
  static const String _appIdWindows =
      String.fromEnvironment('FIREBASE_APP_ID_WINDOWS');
  static const String _appIdWeb = String.fromEnvironment('FIREBASE_APP_ID_WEB');
  static const String _appIdFallback = String.fromEnvironment('FIREBASE_APP_ID');

  /// True when enough configuration is present to initialise Firebase.
  static bool get isConfigured =>
      _apiKey.isNotEmpty && _projectId.isNotEmpty && _appIdFor(currentTarget).isNotEmpty;

  static TargetPlatform get currentTarget =>
      kIsWeb ? TargetPlatform.android : defaultTargetPlatform;

  static String _appIdFor(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return _firstNonEmpty(_appIdAndroid, _appIdFallback, _appIdWeb);
      case TargetPlatform.iOS:
        return _firstNonEmpty(_appIdIos, _appIdFallback, _appIdWeb);
      case TargetPlatform.macOS:
        return _firstNonEmpty(_appIdMacos, _appIdFallback, _appIdWeb);
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return _firstNonEmpty(_appIdWindows, _appIdFallback, _appIdWeb);
    }
  }

  static String _firstNonEmpty(String a, String b, String c) {
    if (a.isNotEmpty) return a;
    if (b.isNotEmpty) return b;
    return c;
  }

  /// Options for the platform the app is running on.
  ///
  /// Throws [StateError] when the configuration is incomplete — callers must
  /// check [isConfigured] first.
  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError(
        'Firebase is not configured. Rebuild with '
        '--dart-define=FIREBASE_API_KEY / FIREBASE_PROJECT_ID / '
        'FIREBASE_APP_ID_<PLATFORM>. See docs/firebase_auth_setup.md.',
      );
    }

    final TargetPlatform platform = currentTarget;

    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appIdFor(platform),
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
      authDomain: _authDomain.isEmpty ? null : _authDomain,
      measurementId: _measurementId.isEmpty ? null : _measurementId,
      iosBundleId: platform == TargetPlatform.iOS
          ? const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID')
          : null,
    );
  }
}
