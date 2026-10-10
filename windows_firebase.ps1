<#
  Runs / builds the Windows target with the Firebase configuration for
  Linked Devices.

  Credentials are NOT stored in this file. They are read from the
  environment, optionally seeded from a git-ignored `firebase.local.ps1`
  next to this script.

  Setup:
    1. Copy-Item firebase.local.example.ps1 firebase.local.ps1
    2. Fill in your real values (that file is git-ignored)
    3. .\windows_firebase.ps1 run
#>
param(
  [ValidateSet('run', 'build')]
  [string]$Mode = 'run',

  [ValidateSet('debug', 'release')]
  [string]$Configuration = 'debug'
)

$ErrorActionPreference = 'Stop'

$localConfig = Join-Path $PSScriptRoot 'firebase.local.ps1'
if (Test-Path $localConfig) {
  . $localConfig
}

$requiredVars = @(
  'BD_FIREBASE_API_KEY',
  'BD_FIREBASE_PROJECT_ID',
  'BD_FIREBASE_MESSAGING_SENDER_ID',
  'BD_FIREBASE_APP_ID_WINDOWS'
)

$missing = @($requiredVars | Where-Object { -not [Environment]::GetEnvironmentVariable($_) })
if ($missing.Count -gt 0) {
  Write-Host ''
  Write-Host 'Missing Firebase configuration:' -ForegroundColor Red
  $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  Write-Host ''
  Write-Host 'Create firebase.local.ps1 (from firebase.local.example.ps1) or set'
  Write-Host 'these environment variables, then run this script again.'
  exit 1
}

$firebaseArgs = @(
  "--dart-define=FIREBASE_API_KEY=$([Environment]::GetEnvironmentVariable('BD_FIREBASE_API_KEY'))",
  "--dart-define=FIREBASE_PROJECT_ID=$([Environment]::GetEnvironmentVariable('BD_FIREBASE_PROJECT_ID'))",
  "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$([Environment]::GetEnvironmentVariable('BD_FIREBASE_MESSAGING_SENDER_ID'))",
  "--dart-define=FIREBASE_APP_ID_WINDOWS=$([Environment]::GetEnvironmentVariable('BD_FIREBASE_APP_ID_WINDOWS'))"
)

# Optional values — only forwarded when present.
$optionalVars = @(
  @{ Env = 'BD_FIREBASE_STORAGE_BUCKET'; Define = 'FIREBASE_STORAGE_BUCKET' },
  @{ Env = 'BD_FIREBASE_AUTH_DOMAIN'; Define = 'FIREBASE_AUTH_DOMAIN' },
  @{ Env = 'BD_FIREBASE_MEASUREMENT_ID'; Define = 'FIREBASE_MEASUREMENT_ID' }
)

foreach ($entry in $optionalVars) {
  $value = [Environment]::GetEnvironmentVariable($entry.Env)
  if ($value) {
    $firebaseArgs += "--dart-define=$($entry.Define)=$value"
  }
}

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
