@echo off
rem Double-click this file to give every project folder of the session 1 repository its own git
rem repository and install the Spec Kit CLI for round 3 on Windows. It runs setup.ps1 next to it
rem with the execution policy bypassed for this run only and keeps the window open so the
rem messages stay readable.
setlocal
set "SETUP_DIRECTORY=%~dp0"
set "SETUP_SCRIPT=%~dp0setup.ps1"

rem Explorer runs a .cmd straight from a zip in a temporary folder, without the files next to it.
if not exist "%SETUP_SCRIPT%" (
  echo setup.ps1 is not next to this file. If you opened the zip, extract it first:
  echo right-click the zip, choose Extract All, and double-click setup.cmd in the extracted folder.
  echo Press any key to close this window.
  pause >nul
  exit /b 1
)

rem Files from a downloaded zip carry the Mark of the Web, which a RemoteSigned policy refuses to run.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:SETUP_DIRECTORY -Recurse -File -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SETUP_SCRIPT%" %*
set "SETUP_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%SETUP_EXIT_CODE%"=="0" (
  echo Setup finished. Press any key to close this window.
) else (
  echo Setup did not finish. Read the messages above.
  echo If PowerShell refused to run setup.ps1, show this window to a trainer.
  echo Press any key to close this window.
)
pause >nul
exit /b %SETUP_EXIT_CODE%
