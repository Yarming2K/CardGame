@echo off
setlocal
title Toss-Up - add shortcuts
rem Adds a Toss-Up shortcut to your Desktop and Start menu.
rem ExecutionPolicy Bypass applies to this one run only; it does not change your system settings.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\make-shortcuts.ps1"
echo.
pause
