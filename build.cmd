@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" %*
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" echo Build failed - read the message above.
pause
exit /b %RC%
