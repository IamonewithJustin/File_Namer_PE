@echo off
REM Batch file to launch the Biotech Version File Renamer
REM This bypasses execution policy for the PowerShell script

powershell.exe -ExecutionPolicy Bypass -File "%~dp0FileRenamer.ps1"
