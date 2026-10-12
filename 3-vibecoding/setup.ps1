<#
.SYNOPSIS
  setup.ps1 - install the Spec Kit CLI (specify) for the spec driven workshop on Windows.

.DESCRIPTION
  1. uv: checks that it works, offers the official installer when it is missing
  2. the Spec Kit CLI from PyPI at the pinned version: uv tool install specify-cli==<version>
  3. prints the next step: specify init my-app --integration copilot

  Safe to run again: an installed CLI at the pinned version is left alone, another version is
  replaced by the pinned one. Works in Windows PowerShell 5.1 and PowerShell 7. Deliberately pure
  ASCII, so 5.1 parses it without a BOM. setup.cmd next to this file starts it with the execution
  policy bypassed; setup.sh hands off to it on Git Bash.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
#>
[CmdletBinding()]
param()

# No global $ErrorActionPreference = 'Stop': Windows PowerShell 5.1 turns the progress a native
# command writes to stderr into a terminating error under Stop. Every native call checks
# $LASTEXITCODE instead.

# Every participant and trainer uses this one version: the one the session 2 starter's Spec Kit files
# were generated with. setup.sh, setup.cmd and README.md repeat it.
$script:SpecKitVersion = '1.1.1'
# The PATH this window started with, before this script added anything to it.
$script:StartingPath = $env:PATH

# Windows PowerShell 5.1 can still default to TLS 1.0, which astral.sh and GitHub refuse.
$script:ForceTls12Command = '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# --- Output helpers ----------------------------------------------------------
# Glyphs are built from code points so the source stays pure ASCII.
$script:BulletGlyph = [char]0x2022
$script:CheckGlyph  = [char]0x2713
$script:CrossGlyph  = [char]0x2717
$script:SetupExitCode = 0

function Write-Bold($message) { Write-Host $message -ForegroundColor White }
function Write-Step($message) { Write-Host ''; Write-Host $message -ForegroundColor White }
function Write-Info($message) { Write-Host "$script:BulletGlyph $message" -ForegroundColor Cyan }
function Write-Ok($message)   { Write-Host "$script:CheckGlyph $message" -ForegroundColor Green }
function Write-Warn($message) { Write-Host "! $message" -ForegroundColor Yellow }
function Write-ErrorMessage($message) { Write-Host "$script:CrossGlyph $message" -ForegroundColor Red }

# Ask a yes/no question; anything but y counts as no.
function Confirm-Offer($question) {
    $answer = Read-Host "  $question [y/N]"
    return ($answer -eq 'y' -or $answer -eq 'Y')
}

function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Show-UvInstallHelp {
    Write-Host ''
    Write-Info 'Install uv yourself, then open a new window and run setup again:'
    Write-Host '    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"'
    Write-Info 'More information: https://docs.astral.sh/uv/getting-started/installation/'
}

function Show-ManualInstallHelp {
    Write-Host ''
    Write-Info 'Install the Spec Kit CLI yourself with:'
    Write-Host "    uv tool install specify-cli==$script:SpecKitVersion --force"
}

# Where the official installer puts uv.
function Get-UvInstallDirectory {
    if ($env:UV_INSTALL_DIR) { return $env:UV_INSTALL_DIR }
    if ($env:XDG_BIN_HOME) { return $env:XDG_BIN_HOME }
    return (Join-Path (Join-Path $HOME '.local') 'bin')
}

# Installers write the user PATH in the registry; this window only sees it after a reopen, so read
# it back. uv's own installer directory goes first.
function Update-SessionPath {
    $pathEntries = @(
        (Get-UvInstallDirectory),
        $env:PATH,
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) | Where-Object { $_ }
    $env:PATH = $pathEntries -join [IO.Path]::PathSeparator
}

# Run a downloaded installer in a child PowerShell: installer scripts set their own
# ErrorActionPreference and may call exit, which must not end this script.
function Invoke-OfficialInstaller($installerUrl) {
    $powerShellExecutable = (Get-Process -Id $PID).Path
    $global:LASTEXITCODE = 1
    & $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -Command "$script:ForceTls12Command; irm $installerUrl | iex"
    return ($LASTEXITCODE -eq 0)
}

# Run a native command and return its output lines as an array, or $null when it fails or does
# not start.
function Invoke-NativeForOutput($executable, [string[]]$arguments) {
    try {
        # Reset first so a stale 0 from an earlier call cannot pass for success.
        $global:LASTEXITCODE = 1
        $outputLines = @(& $executable @arguments 2>$null)
        # The leading comma keeps a one-line result an array instead of unrolling it to a string.
        if ($LASTEXITCODE -eq 0) { return ,$outputLines }
    } catch { }
    return $null
}

function Test-PathListContains($directory, $pathList) {
    if (-not $directory -or -not $pathList) { return $false }
    $normalizedDirectory = $directory.TrimEnd('\', '/')
    foreach ($entry in ($pathList -split [IO.Path]::PathSeparator)) {
        if ($entry -and $entry.TrimEnd('\', '/') -ieq $normalizedDirectory) { return $true }
    }
    return $false
}

# The file a new window runs for $commandName: the first match in $pathList, or $null.
function Find-CommandInPathList($commandName, $pathList) {
    if (-not $pathList) { return $null }
    foreach ($entry in ($pathList -split [IO.Path]::PathSeparator)) {
        if (-not $entry) { continue }
        $directory = [Environment]::ExpandEnvironmentVariables($entry)
        foreach ($extension in @('.exe', '.cmd', '.bat', '.ps1', '')) {
            try {
                $candidate = Join-Path $directory ($commandName + $extension)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            } catch { }
        }
    }
    return $null
}

function Invoke-Setup {
    Write-Bold "Setting up the Spec Kit CLI $script:SpecKitVersion (windows)"
    $needsNewWindow = $false

    # --- 1. uv ---------------------------------------------------------------
    Write-Step '1/3 uv'
    $uvInstallDirectory = Get-UvInstallDirectory
    # A uv installed in another window is only on this window's PATH after a reopen.
    if (Test-Path $uvInstallDirectory) { $env:PATH = $uvInstallDirectory + [IO.Path]::PathSeparator + $env:PATH }

    if (-not (Test-CommandExists 'uv')) {
        Write-ErrorMessage 'uv was not found.'
        if (-not (Confirm-Offer 'Install uv now with the official installer (irm https://astral.sh/uv/install.ps1 | iex)?')) {
            Write-ErrorMessage 'uv is required.'
            Show-UvInstallHelp
            $script:SetupExitCode = 1; return
        }
        if (-not (Invoke-OfficialInstaller 'https://astral.sh/uv/install.ps1')) {
            Write-ErrorMessage 'The uv installer did not finish.'
            Show-UvInstallHelp
            $script:SetupExitCode = 1; return
        }
        Update-SessionPath
        # Windows that were already open, VS Code's terminals among them, do not see the new PATH.
        $needsNewWindow = $true
        if (-not (Test-CommandExists 'uv')) {
            Write-ErrorMessage 'uv was installed but this window cannot find it. Close it, open a new one and run setup again.'
            $script:SetupExitCode = 1; return
        }
    }

    # A broken or half-finished install is found on PATH but fails here.
    $uvVersionLines = Invoke-NativeForOutput 'uv' @('--version')
    if (-not $uvVersionLines) {
        Write-ErrorMessage "Found uv at $((Get-Command uv).Source), but it does not run. The install looks broken."
        Show-UvInstallHelp
        $script:SetupExitCode = 1; return
    }
    Write-Ok "$(([string]$uvVersionLines[0]).Trim()) works ($((Get-Command uv).Source))."

    # --- 2. The Spec Kit CLI -------------------------------------------------
    Write-Step "2/3 The Spec Kit CLI (specify-cli $script:SpecKitVersion)"
    $installedSpecKitVersion = $null
    foreach ($toolLine in @(Invoke-NativeForOutput 'uv' @('tool', 'list'))) {
        if ([string]$toolLine -match '^specify-cli v(\S+)') { $installedSpecKitVersion = $Matches[1]; break }
    }
    $otherSpecifyCommand = Get-Command specify -ErrorAction SilentlyContinue

    if ($installedSpecKitVersion -eq $script:SpecKitVersion) {
        Write-Ok "specify-cli $script:SpecKitVersion is already installed."
    } else {
        # --force replaces another version, including one installed from git, and a specify command
        # another installer left in uv's bin directory.
        $installArguments = @('tool', 'install', "specify-cli==$script:SpecKitVersion")
        if ($installedSpecKitVersion) {
            Write-Warn "specify-cli $installedSpecKitVersion is installed. Replacing it with $script:SpecKitVersion, the version the workshop uses."
            $installArguments += '--force'
        } elseif ($otherSpecifyCommand) {
            Write-Warn "Another specify command is on your PATH ($($otherSpecifyCommand.Source)). Installing $script:SpecKitVersion with uv."
            $installArguments += '--force'
        }
        Write-Info "Running uv $($installArguments -join ' ')..."
        $global:LASTEXITCODE = 1
        & uv @installArguments
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage 'Installing the Spec Kit CLI failed. Check your internet connection (or HTTPS_PROXY behind a proxy).'
            Show-ManualInstallHelp
            $script:SetupExitCode = 1; return
        }
        Write-Ok "specify-cli $script:SpecKitVersion installed."
    }

    $toolBinLines = Invoke-NativeForOutput 'uv' @('tool', 'dir', '--bin')
    $toolBinDirectory = if ($toolBinLines) { ([string]$toolBinLines[0]).Trim() } else { $null }
    if ($toolBinDirectory) { $env:PATH = $toolBinDirectory + [IO.Path]::PathSeparator + $env:PATH }

    $specifyVersionLines = Invoke-NativeForOutput 'specify' @('--version')
    if (-not $specifyVersionLines) {
        Write-ErrorMessage "specify does not run after the install (uv tool bin directory: $toolBinDirectory)."
        Show-ManualInstallHelp
        $script:SetupExitCode = 1; return
    }
    $specifyVersionOutput = ([string]$specifyVersionLines[0]).Trim()
    $specifyCommandPath = (Get-Command specify).Source
    if ($specifyVersionOutput -notlike "*$script:SpecKitVersion*") {
        Write-ErrorMessage "specify reports '$specifyVersionOutput' instead of $script:SpecKitVersion ($specifyCommandPath)."
        Show-ManualInstallHelp
        $script:SetupExitCode = 1; return
    }
    Write-Ok "$specifyVersionOutput works ($specifyCommandPath)."

    # How the participant reaches specify after this script ends: plainly, in a new window, or by
    # its full path when its folder stays off PATH.
    $specifyInvocation = 'specify'
    $specifyDirectory = Split-Path -Parent $specifyCommandPath
    # The PATH a new window starts with, read after any install wrote it to the registry.
    $persistedPath = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) | Where-Object { $_ }
    $newWindowPath = if ($persistedPath) { $persistedPath -join [IO.Path]::PathSeparator } else { $script:StartingPath }
    if (-not (Test-PathListContains $specifyDirectory $newWindowPath)) {
        Write-Warn "$specifyDirectory is not on your PATH yet, so a new window does not find specify."
        $pathUpdated = $false
        if (Confirm-Offer 'Add it to your PATH now (uv tool update-shell)?') {
            $global:LASTEXITCODE = 1
            & uv tool update-shell
            $pathUpdated = ($LASTEXITCODE -eq 0)
        }
        if ($pathUpdated) {
            Write-Ok 'Added. It takes effect in new windows.'
            $needsNewWindow = $true
        } else {
            $specifyInvocation = "& `"$specifyCommandPath`""
            Write-Info 'Add it later with:  uv tool update-shell'
        }
    } else {
        $specifyInNewWindow = Find-CommandInPathList 'specify' $newWindowPath
        if ($specifyInNewWindow -and ([IO.Path]::GetFullPath($specifyInNewWindow) -ne [IO.Path]::GetFullPath($specifyCommandPath))) {
            Write-Warn "Another specify comes first on your PATH ($specifyInNewWindow), so a plain specify runs that one."
            $specifyInvocation = "& `"$specifyCommandPath`""
        }
    }

    # --- 3. Next step --------------------------------------------------------
    Write-Step '3/3 Next step'
    Write-Ok 'Spec Kit is ready.'
    if ($specifyInvocation -ne 'specify') {
        Write-Info 'Open a PowerShell terminal, go to the folder where your project should live and run:'
    } elseif ($needsNewWindow) {
        Write-Info 'Open a new terminal, go to the folder where your project should live and run:'
    } else {
        Write-Info 'Open a terminal, go to the folder where your project should live and run:'
    }
    Write-Host "    $specifyInvocation init my-app --integration copilot"
    Write-Info 'Then open the new my-app folder in VS Code and open Copilot Chat in agent mode.'
}

# Run from this script's own folder, so a relative path never lands somewhere unexpected.
if ($PSScriptRoot) { Push-Location -Path $PSScriptRoot } else { Push-Location -Path (Get-Location) }
try { Invoke-Setup } finally { Pop-Location }

# Only exit when run as a script: exit in a dot-sourced file would close the caller's shell.
if ($MyInvocation.InvocationName -ne '.') { exit $script:SetupExitCode }
