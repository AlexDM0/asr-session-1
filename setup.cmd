@echo off
rem Double-click this file to give every project folder of the session 1 repository its own git
rem repository and install the Spec Kit CLI for round 3 on Windows. It runs setup.ps1 next to it
rem with the execution policy bypassed for this run only and keeps the window open so the
rem messages stay readable.
setlocal
set "SETUP_SCRIPT=%~dp0setup.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%" %*
set "SETUP_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%SETUP_EXIT_CODE%"=="0" (
  echo Setup finished. Press any key to close this window.
) else (
  echo Setup did not finish. Read the messages above.
  echo Press any key to close this window.
)
pause >nul
exit /b %SETUP_EXIT_CODE%
