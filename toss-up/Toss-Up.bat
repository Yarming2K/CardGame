@echo off
setlocal
title Toss-Up
rem Opens Toss-Up in its own window, like an installed app.
rem Uses Microsoft Edge or Google Chrome "app mode". If neither is found,
rem it opens in your default browser instead.
set "APP=%~dp0index.html"
set "URL=file:///%APP:\=/%"
set "BROWSER="
for %%B in (
  "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
  "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
  "%LocalAppData%\Microsoft\Edge\Application\msedge.exe"
  "%ProgramFiles%\Google\Chrome\Application\chrome.exe"
  "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
  "%LocalAppData%\Google\Chrome\Application\chrome.exe"
) do if not defined BROWSER if exist "%%~B" set "BROWSER=%%~B"

if defined BROWSER (
  start "" "%BROWSER%" --app="%URL%" --window-size=1300,900
) else (
  start "" "%APP%"
)
endlocal
