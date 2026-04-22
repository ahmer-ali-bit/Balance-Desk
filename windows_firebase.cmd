@echo off
setlocal

set MODE=%~1
set CONFIG=%~2

if "%MODE%"=="" set MODE=run
if /I "%CONFIG%"=="" set CONFIG=debug

set FIREBASE_ARGS=--dart-define=FIREBASE_API_KEY=AIzaSyAai0vmWJtHS-otwGgVev3m7cegXBbUd7Q --dart-define=FIREBASE_PROJECT_ID=balance-desk-4da9b --dart-define=FIREBASE_MESSAGING_SENDER_ID=732686454468 --dart-define=FIREBASE_APP_ID_WINDOWS=1:732686454468:web:8a26469f4625306022c391 --dart-define=FIREBASE_STORAGE_BUCKET=balance-desk-4da9b.firebasestorage.app

if /I "%MODE%"=="run" (
  echo Running: flutter run -d windows %FIREBASE_ARGS%
  flutter run -d windows %FIREBASE_ARGS%
  goto :end
)

if /I "%MODE%"=="build" (
  echo Running: flutter build windows --%CONFIG% %FIREBASE_ARGS%
  flutter build windows --%CONFIG% %FIREBASE_ARGS%
  goto :end
)

echo Usage:
echo   windows_firebase.cmd
echo   windows_firebase.cmd run
echo   windows_firebase.cmd build release
echo   windows_firebase.cmd build debug
exit /b 1

:end
exit /b %errorlevel%
