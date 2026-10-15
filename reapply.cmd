@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\m3ify\m3ify.ps1" apply
pause
