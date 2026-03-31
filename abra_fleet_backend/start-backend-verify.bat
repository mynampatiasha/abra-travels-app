@echo off
echo ================================================================================
echo STARTING BACKEND WITH VERIFICATION
echo ================================================================================
echo.

echo Checking Node.js version...
node --version
echo.

echo Checking npm packages...
npm list node-cron --depth=0
echo.

echo Starting backend server...
echo Press Ctrl+C to stop
echo.
node index.js
