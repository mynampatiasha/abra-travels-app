@echo off
echo Cleaning Flutter build cache...
echo.

echo Step 1: Cleaning Flutter build directory...
flutter clean

echo.
echo Step 2: Getting dependencies...
flutter pub get

echo.
echo Step 3: Build cache cleaned successfully!
echo.
echo Now you can run: flutter run -d chrome
echo.
pause
