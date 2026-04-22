import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_runtime_options.dart';

class FirebaseBootstrapResult {
  const FirebaseBootstrapResult({required this.isAvailable, this.message});

  final bool isAvailable;
  final String? message;
}

class FirebaseBootstrapService {
  FirebaseBootstrapService._();

  static final FirebaseBootstrapService instance = FirebaseBootstrapService._();

  FirebaseBootstrapResult? _cachedResult;

  Future<FirebaseBootstrapResult> initialize() async {
    if (_cachedResult != null) {
      return _cachedResult!;
    }

    try {
      if (Firebase.apps.isNotEmpty) {
        _cachedResult = const FirebaseBootstrapResult(isAvailable: true);
        return _cachedResult!;
      }

      final runtimeOptions = FirebaseRuntimeOptions.resolve();
      if (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        if (runtimeOptions == null) {
          _cachedResult = const FirebaseBootstrapResult(
            isAvailable: false,
            message:
                'Linked devices need Firebase options for this platform. '
                'Add the runtime dart-defines described in docs/firebase_auth_setup.md.',
          );
          return _cachedResult!;
        }

        await Firebase.initializeApp(options: runtimeOptions);
      } else if (runtimeOptions != null) {
        await Firebase.initializeApp(options: runtimeOptions);
      } else {
        await Firebase.initializeApp();
      }

      _cachedResult = const FirebaseBootstrapResult(isAvailable: true);
      return _cachedResult!;
    } catch (error, stackTrace) {
      debugPrint('FirebaseBootstrapService.initialize failed: $error');
      debugPrint('$stackTrace');
      _cachedResult = FirebaseBootstrapResult(
        isAvailable: false,
        message:
            'Linked devices are unavailable on this build until Firebase setup is complete for this platform.',
      );
      return _cachedResult!;
    }
  }
}
