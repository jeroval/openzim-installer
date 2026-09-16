@echo off
setlocal
cd /d "%~dp0"
title Assistant OpenZIM MCP
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-OpenZimAssistant.ps1"
if errorlevel 1 (
    echo.
    echo Une erreur a empeche le demarrage de l'assistant.
    echo Consultez le message affiche ci-dessus.
    pause
)
endlocal
