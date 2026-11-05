/// Firebase configuration template for linked devices feature.
///
/// Copy this file to firebase_config.dart and fill in your credentials.
/// Do not commit firebase_config.dart - it's in .gitignore.
class FirebaseConfig {
  static const String projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'YOUR_PROJECT_ID',
  );

  static const String apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'YOUR_API_KEY',
  );
}