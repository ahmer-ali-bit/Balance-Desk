# Firebase Setup For Linked Devices

Linked devices in this app use Firebase Auth + Cloud Firestore. The ledger still
works offline locally, but QR/link pairing and cross-device sync need Firebase.

## 1. Create Firebase apps

Create one Firebase project, then add the platforms you want to support:

- Android
- iOS
- macOS
- Windows

## 2. Enable required products

In Firebase Console:

- Authentication: enable `Anonymous`
- Firestore Database: create a database in production mode

## 3. Add platform config

### Android / iOS

Use the native Firebase config files:

- Android: `android/app/google-services.json`
- iOS/macOS: `GoogleService-Info.plist`

This repo already contains an Android `google-services.json`, and the Gradle
plugin is wired in the app build.

### Desktop / fallback runtime config

If you want Windows or macOS without generated options, run with dart-defines:

```powershell
flutter run `
  --dart-define=FIREBASE_API_KEY=your_api_key `
  --dart-define=FIREBASE_PROJECT_ID=your_project_id `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=your_sender_id `
  --dart-define=FIREBASE_APP_ID_WINDOWS=your_windows_app_id
```

Supported app id keys:

- `FIREBASE_APP_ID_ANDROID`
- `FIREBASE_APP_ID_IOS`
- `FIREBASE_APP_ID_MACOS`
- `FIREBASE_APP_ID_WINDOWS`
- `FIREBASE_APP_ID_WEB`

Optional keys:

- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_MEASUREMENT_ID`
- `FIREBASE_ANDROID_CLIENT_ID`
- `FIREBASE_IOS_CLIENT_ID`
- `FIREBASE_IOS_BUNDLE_ID`

## 4. Publish Firestore rules

Deploy the included [firestore.rules](/f:/Flutter/shop/firestore.rules:1).

Those rules enforce:

- owner can create invites and edit codes
- linked devices join with invite tokens
- viewer devices stay read-only
- only owner/editor devices can upload synced workspace revisions

## 5. Important behavior

- Invite QR and invite link contain pairing tokens only, not raw ledger data.
- Linked devices join as `viewer` first.
- Owner generates a short edit code to upgrade a specific linked device.
- Firebase Dynamic Links are not used. This implementation uses shareable invite
  links that can be pasted into the app, and the same link is encoded into QR.
