<#
.SYNOPSIS
  setup.ps1 - install the Spec Kit CLI (specify) for the spec driven workshop on Windows. Runs
  unattended.

.DESCRIPTION
  1. uv: checks that it works, installs a pinned uv release from GitHub when it is missing
  2. the Spec Kit CLI from GitHub at the pinned tag: uv tool install specify-cli --from <tag archive>
  3. puts specify on the PATH of new windows and prints the next step: specify init my-app --integration copilot

  Safe to run again: a working CLI at the pinned version is left alone; anything else, another
  version or a broken install, is replaced by the pinned one. Works in Windows PowerShell 5.1 and
  PowerShell 7. Deliberately pure ASCII, so 5.1 parses it without a BOM. setup.cmd next to this
  file starts it with the execution policy bypassed; setup.sh hands off to it on Git Bash.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
#>
[CmdletBinding()]
param()

# No global $ErrorActionPreference = 'Stop': Windows PowerShell 5.1 turns the progress a native
# command writes to stderr into a terminating error under Stop. Every native call checks
# $LASTEXITCODE instead.

# Every participant and trainer uses this one version: the one session 2's setup installs its Spec Kit skills
# with. setup.sh, setup.cmd and README.md repeat it.
$script:SpecKitVersion = '1.1.3'
# The tag archive instead of git+https: uv downloads it itself, so neither git nor git's proxy and
# certificate settings are needed.
$script:SpecKitSource = "https://github.com/github/spec-kit/archive/refs/tags/v$script:SpecKitVersion.zip"
# A pinned uv release, checked against its published SHA-256, instead of piping an installer script
# into iex: deterministic, and not the download pattern endpoint security software blocks.
$script:UvVersion = '0.11.29'
$script:UvArchiveChecksums = @{
    'x86_64'  = 'a047d55651bc3e0ca24595b25ec4cfcb10f9dca9fb56514e661269b37d4fae68'
    'aarch64' = '55b597ae81bc29531a7c352a1431a8a73cc2755d7a5b9ec454580cbe02e5154f'
}
# The PATH this window started with, before this script added anything to it.
$script:StartingPath = $env:PATH
# AppLocker and WDAC run scripts from a user folder in ConstrainedLanguage, where .NET calls fail.
$script:IsFullLanguage = ($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage')
$script:SystemProxy = $null
$script:SetupExitCode = 0

# --- Output helpers ----------------------------------------------------------
# ASCII markers: the console font of Windows PowerShell 5.1 has no check mark glyph.
function Write-Bold($message) { Write-Host $message -ForegroundColor White }
function Write-Step($message) { Write-Host ''; Write-Host $message -ForegroundColor White }
function Write-Info($message) { Write-Host "- $message" -ForegroundColor Cyan }
function Write-Ok($message)   { Write-Host "+ $message" -ForegroundColor Green }
function Write-Warn($message) { Write-Host "! $message" -ForegroundColor Yellow }
function Write-ErrorMessage($message) { Write-Host "x $message" -ForegroundColor Red }

function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Show-UvInstallHelp {
    Write-Host ''
    Write-Info 'Install uv yourself, then open a new window and run setup again:'
    Write-Host '    winget install --id astral-sh.uv --exact'
    Write-Info 'More information: https://docs.astral.sh/uv/getting-started/installation/'
}

function Show-ManualInstallHelp {
    Write-Host ''
    Write-Info 'Install the Spec Kit CLI yourself with:'
    Write-Host "    uv tool install --force specify-cli --from $script:SpecKitSource"
    Write-Info 'Behind a proxy, set it first, for example:  $env:HTTPS_PROXY = "http://proxy.example:8080"'
}

function Show-LockedDownHelp($whatIsMissing) {
    Write-ErrorMessage "PowerShell runs in a locked-down mode on this computer ($($ExecutionContext.SessionState.LanguageMode)), so setup cannot install $whatIsMissing."
    Write-Info "Ask IT to install $whatIsMissing (it is on the preinstall list of the training), then run setup again."
}

# Where the official installer and this script put uv. USERPROFILE, not $HOME: in Windows PowerShell
# 5.1 $HOME is the home folder from Active Directory, often a network drive, which uv does not use.
function Get-UvInstallDirectory {
    if ($env:UV_INSTALL_DIR) { return $env:UV_INSTALL_DIR }
    if ($env:XDG_BIN_HOME) { return $env:XDG_BIN_HOME }
    return (Join-Path (Join-Path $env:USERPROFILE '.local') 'bin')
}

# Where uv tool install puts specify. Derived instead of asking uv: Windows PowerShell 5.1 decodes
# uv's UTF-8 output with the console code page, which garbles a user name like Mueller with an umlaut.
function Get-ToolBinDirectory {
    if ($env:UV_TOOL_BIN_DIR) { return $env:UV_TOOL_BIN_DIR }
    if ($env:XDG_BIN_HOME) { return $env:XDG_BIN_HOME }
    return (Join-Path (Join-Path $env:USERPROFILE '.local') 'bin')
}

# The PATH a new window starts with, read from the registry with cmdlets that also work when
# PowerShell is locked down.
function Get-PersistedPath {
    $machinePath = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -Name Path -ErrorAction SilentlyContinue).Path
    $userPath = (Get-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue).Path
    return (@($machinePath, $userPath) | Where-Object { $_ }) -join ';'
}

function Update-SessionPath {
    $pathEntries = @((Get-UvInstallDirectory), $env:PATH, (Get-PersistedPath)) | Where-Object { $_ }
    $env:PATH = $pathEntries -join ';'
}

function Test-PathListContains($directory, $pathList) {
    if (-not $directory -or -not $pathList) { return $false }
    $normalizedDirectory = $directory.TrimEnd('\', '/')
    foreach ($entry in ($pathList -split ';')) {
        if ($entry -and $entry.TrimEnd('\', '/') -ieq $normalizedDirectory) { return $true }
    }
    return $false
}

# Adds $directory to the user PATH in the registry, keeping %VARIABLE% entries as they are, and
# tells Windows so windows opened from now on see it.
function Add-UserPathEntry($directory) {
    $environmentKey = Get-Item -LiteralPath 'HKCU:\Environment'
    $userPath = [string]$environmentKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    if (Test-PathListContains $directory $userPath) { return }
    $newUserPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $directory } else { $directory }
    Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Value $newUserPath -Type ExpandString
    # Clearing a variable through .NET broadcasts the environment change that Set-ItemProperty does not.
    [Environment]::SetEnvironmentVariable('DuinzichtSetupPathRefresh', $null, 'User')
}

# uv and git only read HTTPS_PROXY, not the Windows proxy settings, so copy those over. The
# credentials let a proxy that signs in with the Windows account accept the downloads.
function Initialize-SystemProxy {
    if (-not $script:IsFullLanguage) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
        if ($env:HTTPS_PROXY -or $env:https_proxy) { return }
        $probeAddress = [uri]'https://pypi.org'
        $proxyAddress = [Net.WebRequest]::GetSystemWebProxy().GetProxy($probeAddress)
        if ($proxyAddress -and $proxyAddress.Host -ne $probeAddress.Host) {
            $script:SystemProxy = $proxyAddress.AbsoluteUri
            $env:HTTPS_PROXY = $script:SystemProxy
            $env:HTTP_PROXY = $script:SystemProxy
            Write-Info "Using the Windows proxy $script:SystemProxy."
        }
    } catch { }
}

function Invoke-Download($address, $destination) {
    $downloadArguments = @{ Uri = $address; OutFile = $destination; UseBasicParsing = $true }
    if ($script:SystemProxy) {
        $downloadArguments.Proxy = $script:SystemProxy
        $downloadArguments.ProxyUseDefaultCredentials = $true
    }
    # The progress bar of Windows PowerShell 5.1 slows a download down many times over.
    $previousProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest @downloadArguments -ErrorAction Stop } finally { $ProgressPreference = $previousProgressPreference }
}

# Downloads the pinned uv release, checks its SHA-256 and unpacks uv.exe and uvx.exe into the
# directory the official installer uses. Returns whether uv.exe is there.
function Install-PinnedUv {
    $processorArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $uvArchitecture = switch ($processorArchitecture) { 'AMD64' { 'x86_64' } 'ARM64' { 'aarch64' } default { $null } }
    if (-not $uvArchitecture) {
        Write-ErrorMessage "uv has no Windows release for this processor ($processorArchitecture)."
        return $false
    }
    $archiveName = "uv-$uvArchitecture-pc-windows-msvc.zip"
    $downloadFolder = Join-Path ([IO.Path]::GetTempPath()) ("uv-setup-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $downloadFolder -Force | Out-Null
    try {
        $archivePath = Join-Path $downloadFolder $archiveName
        Write-Info "Downloading uv $script:UvVersion from GitHub ($archiveName)..."
        Invoke-Download "https://github.com/astral-sh/uv/releases/download/$script:UvVersion/$archiveName" $archivePath
        $archiveChecksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($archiveChecksum -ine $script:UvArchiveChecksums[$uvArchitecture]) {
            Write-ErrorMessage "The downloaded $archiveName does not match its published checksum. A proxy may have changed it."
            return $false
        }
        $uvInstallDirectory = Get-UvInstallDirectory
        New-Item -ItemType Directory -Path $uvInstallDirectory -Force | Out-Null
        Expand-Archive -LiteralPath $archivePath -DestinationPath $uvInstallDirectory -Force
        Add-UserPathEntry $uvInstallDirectory
        return (Test-Path -LiteralPath (Join-Path $uvInstallDirectory 'uv.exe'))
    } catch {
        Write-ErrorMessage "Downloading uv failed: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $downloadFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
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

# The version line specify prints when it runs at the pinned version, or $null.
function Get-PinnedSpecifyVersion {
    $specifyVersionLines = Invoke-NativeForOutput 'specify' @('--version')
    if (-not $specifyVersionLines) { return $null }
    $specifyVersionOutput = ([string]$specifyVersionLines[0]).Trim()
    if ($specifyVersionOutput -like "*$script:SpecKitVersion*") { return $specifyVersionOutput }
    return $null
}

# The file a new window runs for $commandName: the first match in $pathList, or $null.
function Find-CommandInPathList($commandName, $pathList) {
    if (-not $pathList) { return $null }
    foreach ($entry in ($pathList -split ';')) {
        if (-not $entry) { continue }
        foreach ($extension in @('.exe', '.cmd', '.bat', '.ps1', '')) {
            try {
                $candidate = Join-Path $entry ($commandName + $extension)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            } catch { }
        }
    }
    return $null
}

function Invoke-Setup {
    Write-Bold "Setting up the Spec Kit CLI $script:SpecKitVersion (windows)"
    $needsNewWindow = $false
    Initialize-SystemProxy

    # --- 1. uv ---------------------------------------------------------------
    Write-Step '1/3 uv'
    $uvInstallDirectory = Get-UvInstallDirectory
    # A uv installed in another window is only on this window's PATH after a reopen.
    if (Test-Path -LiteralPath $uvInstallDirectory) { $env:PATH = $uvInstallDirectory + ';' + $env:PATH }

    if (-not (Test-CommandExists 'uv')) {
        if (-not $script:IsFullLanguage) {
            Show-LockedDownHelp 'uv'
            $script:SetupExitCode = 1; return
        }
        Write-Info 'uv was not found. Installing it...'
        if (-not (Install-PinnedUv)) {
            Write-ErrorMessage 'Installing uv did not finish.'
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

    # A broken or half-finished install is found on PATH but fails here; AppLocker blocking uv.exe
    # in the user profile looks the same.
    $uvVersionLines = Invoke-NativeForOutput 'uv' @('--version')
    if (-not $uvVersionLines) {
        Write-ErrorMessage "Found uv at $((Get-Command uv).Source), but it does not run. The install looks broken, or the computer blocks programs in your user folder."
        Show-UvInstallHelp
        $script:SetupExitCode = 1; return
    }
    $uvVersion = ([string]$uvVersionLines[0]).Trim()
    $uvToolHelp = Invoke-NativeForOutput 'uv' @('tool', 'install', '--help')
    if (-not $uvToolHelp) {
        Write-ErrorMessage "$uvVersion is too old for uv tool. Update it with:  uv self update"
        $script:SetupExitCode = 1; return
    }
    Write-Ok "$uvVersion works ($((Get-Command uv).Source))."

    # A TLS-inspecting proxy re-signs traffic with a company certificate that only the Windows
    # certificate store trusts; uv's own certificate bundle would reject it.
    if (-not $env:UV_SYSTEM_CERTS -and -not $env:UV_NATIVE_TLS) {
        if (($uvToolHelp -join "`n") -match '--system-certs') { $env:UV_SYSTEM_CERTS = '1' } else { $env:UV_NATIVE_TLS = '1' }
    }

    # --- 2. The Spec Kit CLI -------------------------------------------------
    Write-Step "2/3 The Spec Kit CLI (specify-cli $script:SpecKitVersion)"
    $toolBinDirectory = Get-ToolBinDirectory
    $env:PATH = $toolBinDirectory + ';' + $env:PATH
    $installedSpecKitVersion = $null
    $toolLines = Invoke-NativeForOutput 'uv' @('tool', 'list')
    foreach ($toolLine in $toolLines) {
        if ([string]$toolLine -match '^specify-cli v(\S+)') { $installedSpecKitVersion = $Matches[1]; break }
    }

    if ($installedSpecKitVersion -eq $script:SpecKitVersion -and (Get-PinnedSpecifyVersion)) {
        Write-Ok "specify-cli $script:SpecKitVersion is already installed."
    } else {
        if ($installedSpecKitVersion -and $installedSpecKitVersion -ne $script:SpecKitVersion) {
            Write-Warn "specify-cli $installedSpecKitVersion is installed. Replacing it with $script:SpecKitVersion, the version the workshop uses."
        }
        # --force replaces another version, a broken tool environment, and a specify command another
        # installer left in uv's bin directory.
        Write-Info "Installing specify-cli $script:SpecKitVersion from GitHub. The first time this can take a few minutes..."
        $global:LASTEXITCODE = 1
        & uv tool install --force specify-cli --from $script:SpecKitSource | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMessage 'Installing the Spec Kit CLI failed. Check your internet connection (or HTTPS_PROXY behind a proxy).'
            Show-ManualInstallHelp
            $script:SetupExitCode = 1; return
        }
        Write-Ok "specify-cli $script:SpecKitVersion installed."
    }

    $specifyVersionOutput = Get-PinnedSpecifyVersion
    if (-not $specifyVersionOutput) {
        Write-ErrorMessage "specify does not run at version $script:SpecKitVersion after the install (uv tool bin directory: $toolBinDirectory)."
        Show-ManualInstallHelp
        $script:SetupExitCode = 1; return
    }
    $specifyCommandPath = (Get-Command specify).Source
    Write-Ok "$specifyVersionOutput works ($specifyCommandPath)."

    # How the participant reaches specify after this script ends: plainly in a new window, or by its
    # full path when another specify comes first or the PATH could not be updated.
    $specifyInvocation = 'specify'
    $specifyDirectory = Split-Path -Parent $specifyCommandPath
    $newWindowPath = Get-PersistedPath
    if (-not $newWindowPath) { $newWindowPath = $script:StartingPath }
    if (-not (Test-PathListContains $specifyDirectory $newWindowPath)) {
        Write-Info "$specifyDirectory is not on your PATH yet. Adding it to your user PATH..."
        $pathUpdated = $false
        if ($script:IsFullLanguage) {
            try { Add-UserPathEntry $specifyDirectory; $pathUpdated = $true } catch { }
        }
        if ($pathUpdated) {
            Write-Ok 'Added. It takes effect in new windows.'
            $needsNewWindow = $true
        } else {
            Write-Warn 'Could not add it. Add it later with:  uv tool update-shell'
            $specifyInvocation = "& `"$specifyCommandPath`""
        }
    } else {
        $specifyInNewWindow = Find-CommandInPathList 'specify' $newWindowPath
        if ($specifyInNewWindow -and ($specifyInNewWindow -ine $specifyCommandPath)) {
            Write-Warn "Another specify comes first on your PATH ($specifyInNewWindow), so a plain specify runs that one."
            $specifyInvocation = "& `"$specifyCommandPath`""
        }
    }
    if (-not (Test-PathListContains $specifyDirectory $script:StartingPath)) { $needsNewWindow = $true }

    # --- 3. Next step --------------------------------------------------------
    Write-Step '3/3 Next step'
    Write-Ok 'Spec Kit is ready.'
    if ($needsNewWindow) {
        Write-Info 'Open a new terminal (in VS Code: close every VS Code window and start it again), go to the folder where your project should live and run:'
    } else {
        Write-Info 'Open a terminal, go to the folder where your project should live and run:'
    }
    Write-Host "    $specifyInvocation init my-app --integration copilot"
    if ($specifyInvocation -eq 'specify' -and $needsNewWindow) {
        Write-Info 'Or, in a PowerShell terminal that does not find specify yet:'
        Write-Host "    & `"$specifyCommandPath`" init my-app --integration copilot"
    }
    Write-Info 'Then open the new my-app folder in VS Code and open Copilot Chat in agent mode.'
}

# Run from this script's own folder, so a relative path never lands somewhere unexpected.
if ($PSScriptRoot) { Push-Location -LiteralPath $PSScriptRoot } else { Push-Location -LiteralPath (Get-Location).ProviderPath }
try {
    Invoke-Setup
} catch {
    Write-ErrorMessage "Setup stopped unexpectedly: $($_.Exception.Message)"
    $script:SetupExitCode = 1
} finally {
    Pop-Location
}

# Only exit when run as a script: exit in a dot-sourced file would close the caller's shell.
if ($MyInvocation.InvocationName -ne '.') { exit $script:SetupExitCode }
