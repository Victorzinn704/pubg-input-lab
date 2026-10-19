@echo off
setlocal
if not exist "%~dp0runtime\AutoHotkey64.exe" (
    echo Interpretador ausente. Execute scripts\Setup-Runtime.ps1 antes de iniciar.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Prepare-LocalConfig.ps1"
if errorlevel 1 (
    pause
    exit /b 1
)
start "Recoil Lab" "%~dp0runtime\AutoHotkey64.exe" "%~dp0RecoilLab.ahk"
