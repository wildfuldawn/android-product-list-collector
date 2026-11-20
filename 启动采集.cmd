@echo off
chcp 65001 >nul
if exist "%~dp0tools\adb.exe" set "ADB_PATH=%~dp0tools\adb.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ps-list-pipeline\scripts\start.ps1"
pause
