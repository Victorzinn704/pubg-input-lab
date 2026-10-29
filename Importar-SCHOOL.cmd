@echo off
setlocal
if not exist "%~dp0runtime\AutoHotkey64.exe" (
    echo Runtime ausente. Execute scripts\Setup-Runtime.ps1 antes.
    pause
    exit /b 1
)
"%~dp0runtime\AutoHotkey64.exe" /ErrorStdOut=utf-8 "%~dp0scripts\Install-SchoolPresets.ahk" --install
if errorlevel 1 (
    echo Nao foi possivel importar. Feche o Recoil Lab e tente novamente.
    pause
    exit /b 1
)
pause
