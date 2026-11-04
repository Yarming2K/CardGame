@echo off
setlocal
title Max Visuals - uninstall
rem Runs the PowerShell script next to this file. ExecutionPolicy Bypass applies
rem to this one run only; it does not change your system settings.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
echo.
pause
