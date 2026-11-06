@echo off
setlocal
cd /d "%~dp0"
title Voice Clone
if not exist ".venv\Scripts\python.exe" goto notinstalled

rem After an update, install anything new (for example the app's own parts).
".venv\Scripts\python.exe" -c "import gradio, silero_vad" >nul 2>nul
if errorlevel 1 ".venv\Scripts\python.exe" -m pip install -r requirements.txt

echo.
echo  Voice Clone is opening in your browser.
echo  Keep this window open while you use it - close it to quit.
echo.
".venv\Scripts\python.exe" app.py
if errorlevel 1 pause
exit /b

:notinstalled
echo  Voice Clone isn't set up yet. Double-click Install.bat first.
echo.
pause
exit /b 1
