@echo off
echo Building TrackoSpeed Release APK...
echo.

cd /d "%~dp0"

echo Step 1: Cleaning previous build...
call flutter clean

echo.
echo Step 2: Getting dependencies...
call flutter pub get

echo.
echo Step 3: Building release APK...
call flutter build apk --release --split-per-abi

echo.
echo Build complete!
echo.
echo APK files can be found in:
echo build\app\outputs\flutter-apk\
echo.
pause

