# Copy this file to `firebase.local.ps1` and fill in the real values.
# `firebase.local.ps1` is git-ignored — never commit real credentials.
#
# Where to find them: Firebase Console → Project settings → General
# (Web app config for the Windows target, Android app for google-services.json).

$env:BD_FIREBASE_API_KEY = 'AIza...'
$env:BD_FIREBASE_PROJECT_ID = 'your-project-id'
$env:BD_FIREBASE_MESSAGING_SENDER_ID = '000000000000'
$env:BD_FIREBASE_APP_ID_WINDOWS = '1:000000000000:web:0000000000000000000000'

# Optional
$env:BD_FIREBASE_STORAGE_BUCKET = 'your-project-id.firebasestorage.app'
# $env:BD_FIREBASE_AUTH_DOMAIN = 'your-project-id.firebaseapp.com'
# $env:BD_FIREBASE_MEASUREMENT_ID = 'G-XXXXXXXXXX'
