@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Local-Codex.ps1" %*
if errorlevel 1 pause
