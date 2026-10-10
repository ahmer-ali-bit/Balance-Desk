@echo off
rem Thin wrapper so both .cmd and .ps1 stay in sync.
rem All logic (and all credential loading) lives in windows_firebase.ps1.
setlocal

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows_firebase.ps1" %1 %2
exit /b %errorlevel%
