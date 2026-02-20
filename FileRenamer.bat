@echo off
echo Starting File Renamer...
powershell -ExecutionPolicy Bypass -File "%~dp0FileRenamer.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo An error occurred. Press any key to exit...
    pause >nul
)
