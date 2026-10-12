@echo off
rem Double-click this file to install the Spec Kit CLI (specify) on Windows.
rem It runs setup.ps1 next to it with the execution policy bypassed for this run only, passes any
rem arguments through and keeps the window open so the next step stays readable.
setlocal
set "SETUP_SCRIPT=%~dp0setup.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%" %*
set "SETUP_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%SETUP_EXIT_CODE%"=="0" (
  echo Setup finished. Press any key to close this window.
) else (
  echo Setup did not finish. Read the messages above.
  echo If PowerShell refused to run setup.ps1, install uv from https://docs.astral.sh/uv/ and run:
  echo     uv tool install specify-cli==1.1.1 --force
  echo Press any key to close this window.
)
pause >nul
exit /b %SETUP_EXIT_CODE%
