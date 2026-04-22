param(
  [ValidateSet('run', 'build')]
  [string]$Mode = 'run',

  [ValidateSet('debug', 'release')]
  [string]$Configuration = 'debug'
)

$ErrorActionPreference = 'Stop'

$firebaseArgs = @(
  '--dart-define=FIREBASE_API_KEY=AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q',
  '--dart-define=FIREBASE_PROJECT_ID=balance-desk-4da9b',
  '--dart-define=FIREBASE_MESSAGING_SENDER_ID=732686454468',
  '--dart-define=FIREBASE_APP_ID_WINDOWS=1:732686454468:web:8a26469f4625306022c391',
  '--dart-define=FIREBASE_STORAGE_BUCKET=balance-desk-4da9b.firebasestorage.app'
)

if ($Mode -eq 'run') {
  $flutterArgs = @('run', '-d', 'windows') + $firebaseArgs
} else {
  $flutterArgs = @('build', 'windows', "--$Configuration") + $firebaseArgs
}

Write-Host "Running: flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
& flutter @flutterArgs

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
