// File generated & manually configured for balance-desk-4da9b
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return desktop;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q',
    appId: '1:732686454468:web:balance_desk_web',
    messagingSenderId: '732686454468',
    projectId: 'balance-desk-4da9b',
    storageBucket: 'balance-desk-4da9b.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q',
    appId: '1:732686454468:android:eda4493a3a8aa75822c391',
    messagingSenderId: '732686454468',
    projectId: 'balance-desk-4da9b',
    storageBucket: 'balance-desk-4da9b.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q',
    appId: '1:732686454468:ios:balance_desk_ios',
    messagingSenderId: '732686454468',
    projectId: 'balance-desk-4da9b',
    storageBucket: 'balance-desk-4da9b.firebasestorage.app',
    iosBundleId: 'com.shop.ledger',
  );

  static const FirebaseOptions desktop = FirebaseOptions(
    apiKey: 'AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q',
    appId: '1:732686454468:windows:balance_desk_desktop',
    messagingSenderId: '732686454468',
    projectId: 'balance-desk-4da9b',
    storageBucket: 'balance-desk-4da9b.firebasestorage.app',
  );
}
