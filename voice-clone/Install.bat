@echo off
setlocal
cd /d "%~dp0"
title Voice Clone - setup
echo.
echo  Setting up Voice Clone. The first time takes 5-10 minutes.
echo.

py -3.13 -c "import sys" >nul 2>nul
if errorlevel 1 goto nopython

py -3.13 -c "import os, sys; sys.exit(0 if len(os.getcwd()) <= 115 else 1)"
if errorlevel 1 goto longpath

if exist ".venv\Scripts\python.exe" goto install
echo  Creating a private Python environment in .venv ...
py -3.13 -m venv .venv
if errorlevel 1 goto failed

:install
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 goto failed
".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto failed

where ffmpeg >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Note: FFmpeg isn't installed. You need it for videos and phone recordings.
  echo  To install it, open PowerShell and run:  winget install Gyan.FFmpeg
)
echo.
echo  All done! Double-click "Start Voice Clone.bat" to open the app.
echo.
pause
exit /b 0

:nopython
echo  Python 3.13 isn't installed.
echo  Get the latest 3.13.x "Windows installer (64-bit)" from https://www.python.org/downloads/
echo  - not 3.14 or newer - and tick "Add python.exe to PATH" in the installer.
echo  Then double-click Install.bat again.
echo.
pause
exit /b 1

:longpath
echo  This folder is too deep inside other folders for Windows to install PyTorch:
echo    %CD%
echo  Move the voice-clone folder somewhere shorter, for example:
echo    %USERPROFILE%\voice-clone
echo  then double-click Install.bat again.
echo.
pause
exit /b 1

:failed
echo.
echo  Something went wrong - see the messages above.
echo.
pause
exit /b 1
