@echo off
echo.
echo ========================================
echo   RESTARTING BACKEND SERVER
echo ========================================
echo.

echo Step 1: Stopping any running Node processes on port 3000...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :3000 ^| findstr LISTENING') do (
    echo Found process: %%a
    taskkill /F /PID %%a 2>nul
)
echo.

echo Step 2: Waiting 2 seconds...
timeout /t 2 /nobreak >nul
echo.

echo Step 3: Starting backend server...
echo.
echo ========================================
echo   Backend is starting...
echo   Press Ctrl+C to stop
echo ========================================
echo.

node index.js
