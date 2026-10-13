<#
.SYNOPSIS
  setup.ps1 - turn every project folder of the session 1 repository into its own git repository
  and install what the rounds need, on Windows. Runs unattended.

.DESCRIPTION
  1. Checks that git works and that this folder is not inside another git repository
  2. Removes the .git of this folder when it holds no work that exists nowhere else
  3. git init and a first commit in 1-vibecoding\, 2-vibecoding\ and 3-vibecoding\
  4. The Spec Kit CLI for round 3, through 3-vibecoding\setup.ps1

  One repository per project keeps the agent away from your other rounds: Copilot CLI and worktree sessions
  work from the git root. Safe to run again: a project that already has its first commit is left alone.
  Works in Windows PowerShell 5.1 and PowerShell 7. Deliberately pure ASCII, so 5.1 parses it
  without a BOM. setup.cmd next to this file starts it with the execution policy bypassed.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
#>
[CmdletBinding()]
param()

# No global $ErrorActionPreference = 'Stop': Windows PowerShell 5.1 turns the progress a native
# command writes to stderr into a terminating error under Stop. Every native call checks
# $LASTEXITCODE instead.

$script:ProjectFolders = @('1-vibecoding', '2-vibecoding', '3-vibecoding')
$script:SpecKitSetupScript = '3-vibecoding\setup.ps1'
$script:FirstCommitMessage = 'Starter'
$script:FallbackAuthorName = 'Duinzicht workshop'
$script:FallbackAuthorEmail = 'workshop@duinzicht.example'
$script:SetupExitCode = 0

# --- Output helpers ----------------------------------------------------------
# ASCII markers: the console font of Windows PowerShell 5.1 has no check mark glyph.
function Write-Bold($message) { Write-Host $message -ForegroundColor White }
function Write-Step($message) { Write-Host ''; Write-Host $message -ForegroundColor White }
function Write-Info($message) { Write-Host "- $message" -ForegroundColor Cyan }
function Write-Ok($message)   { Write-Host "+ $message" -ForegroundColor Green }
function Write-ErrorMessage($message) { Write-Host "x $message" -ForegroundColor Red }

# Runs git with the given arguments, shows its output and returns whether it succeeded.
function Invoke-Git([string[]]$gitArguments) {
    $global:LASTEXITCODE = 1
    & git @gitArguments | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# Runs git and returns @{ Succeeded; Output } with stdout and stderr as one English text.
function Get-GitResult([string[]]$gitArguments) {
    $previousLanguage = $env:LC_ALL
    $env:LC_ALL = 'C'
    try {
        $global:LASTEXITCODE = 1
        $gitOutput = (& git @gitArguments 2>&1 | ForEach-Object { "$_" } | Out-String).Trim()
        return @{ Succeeded = ($LASTEXITCODE -eq 0); Output = $gitOutput }
    } finally {
        $env:LC_ALL = $previousLanguage
    }
}

function Get-GitValue($key) {
    $configResult = Get-GitResult @('config', '--get', $key)
    if ($configResult.Succeeded) { return $configResult.Output }
    return ''
}

# Why removing the .git of this folder would lose work, or $null when it is safe. Any git error
# counts as unsafe, so a repository git cannot read is never removed blindly.
function Get-WorkOnlyInThisClone {
    $statusResult = Get-GitResult @('status', '--porcelain')
    if (-not $statusResult.Succeeded) { return "git cannot read this repository:`n$($statusResult.Output)" }
    if ($statusResult.Output) { return 'It has changed or new files.' }
    $stashResult = Get-GitResult @('stash', 'list')
    if (-not $stashResult.Succeeded) { return "git cannot read the stashes of this repository:`n$($stashResult.Output)" }
    if ($stashResult.Output) { return 'It has stashed changes.' }
    if ((Get-GitResult @('rev-parse', '--verify', '--quiet', 'HEAD')).Succeeded -and
        (Get-GitResult @('rev-list', 'HEAD', '--not', '--remotes')).Output) {
        return 'It has commits that are on no remote.'
    }
    return $null
}

# Renames first, so a folder that antivirus or OneDrive keeps busy cannot stop setup halfway.
function Remove-RootRepository($repositoryPath) {
    $removedName = '.git-removed-' + (Get-Date -Format 'yyyyMMddHHmmss')
    try {
        Rename-Item -LiteralPath $repositoryPath -NewName $removedName -ErrorAction Stop
    } catch {
        return $false
    }
    $removedPath = Join-Path (Split-Path -Parent $repositoryPath) $removedName
    Remove-Item -LiteralPath $removedPath -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $removedPath) { & cmd.exe /d /c rmdir /s /q "`"$removedPath`"" 2>$null | Out-Null }
    if (Test-Path -LiteralPath $removedPath) {
        Write-Info "Windows still holds $removedName open; delete that folder later, setup does not need it."
    }
    return $true
}

function Invoke-Setup($rootFolder) {
    Write-Bold 'Setting up the session 1 repository: one repository per project, and Spec Kit for round 3'

    # --- 1. Checks -----------------------------------------------------------
    Write-Step '1/4 Checks'
    $gitVersion = if (Get-Command 'git' -ErrorAction SilentlyContinue) { Get-GitResult @('--version') } else { $null }
    if (-not $gitVersion -or -not $gitVersion.Succeeded) {
        Write-ErrorMessage 'git was not found. Install it from https://git-scm.com and run setup again.'
        $script:SetupExitCode = 1; return
    }
    Write-Ok "$($gitVersion.Output) works."

    foreach ($projectFolder in $script:ProjectFolders) {
        if (-not (Test-Path -LiteralPath $projectFolder -PathType Container)) {
            Write-ErrorMessage "The folder $projectFolder is missing. Run this script from the session 1 repository folder."
            $script:SetupExitCode = 1; return
        }
    }

    # Nested repositories inside someone else's repository would turn up there as embedded repositories.
    # Any answer but "not a git repository" counts as inside one, so an unreadable parent never passes.
    $parentFolder = Split-Path -Path $rootFolder -Parent
    $enclosingResult = Get-GitResult @('-C', $parentFolder, 'rev-parse', '--show-toplevel')
    if ($enclosingResult.Succeeded -or $enclosingResult.Output -notmatch 'not a git repository') {
        Write-ErrorMessage 'This folder is inside another git repository, or git cannot tell:'
        Write-Host $enclosingResult.Output
        Write-Info 'Copy the folder somewhere outside that repository and run setup there.'
        $script:SetupExitCode = 1; return
    }
    Write-Ok 'This folder is not inside another git repository.'

    # --- 2. Remove the repository of this folder -------------------------------
    Write-Step '2/4 Remove the repository of this folder'
    $repositoryPath = Join-Path $rootFolder '.git'
    if (Test-Path -LiteralPath $repositoryPath) {
        $workOnlyInThisClone = Get-WorkOnlyInThisClone
        if ($workOnlyInThisClone) {
            Write-ErrorMessage "This folder's repository holds work that exists nowhere else, so setup leaves it alone."
            Write-Host $workOnlyInThisClone
            Write-Info 'Push or remove that work, or clone the repository again in a new folder, and run setup there.'
            $script:SetupExitCode = 1; return
        }
        Write-Info 'Every project gets its own repository, so the agent stays inside its project folder.'
        if (-not (Remove-RootRepository $repositoryPath)) {
            Write-ErrorMessage "Could not remove $repositoryPath. Close VS Code and other programs that use it, then run setup again."
            $script:SetupExitCode = 1; return
        }
        Write-Ok "Removed $($repositoryPath): the history of this clone is gone, every file stays."
    } else {
        Write-Ok 'This folder is no repository any more.'
    }

    # --- 3. One repository per project -----------------------------------------
    Write-Step '3/4 One repository per project'
    $usesFallbackIdentity = (-not (Get-GitValue 'user.name') -or -not (Get-GitValue 'user.email'))
    if ($usesFallbackIdentity) {
        Write-Info "git has no name and email set up, so the project repositories use `"$script:FallbackAuthorName`"."
        Write-Info 'Set your own with:  git config --global user.name "Your Name"'
    }

    foreach ($projectFolder in $script:ProjectFolders) {
        if ((Get-GitResult @('-C', $projectFolder, 'rev-parse', '--verify', '--quiet', 'HEAD')).Succeeded) {
            Write-Ok "$projectFolder is already its own repository."
            continue
        }
        # A .git without a commit is what an interrupted run leaves behind; init again finishes it.
        # symbolic-ref instead of init --initial-branch, which git before 2.28 does not know.
        # The first commit skips the user's signing and hooks: a gpg or hook setup must not block it.
        $succeeded = (Invoke-Git @('-C', $projectFolder, 'init', '--quiet')) -and
                     (Invoke-Git @('-C', $projectFolder, 'symbolic-ref', 'HEAD', 'refs/heads/main')) -and
                     (-not $usesFallbackIdentity -or
                      ((Invoke-Git @('-C', $projectFolder, 'config', 'user.name', $script:FallbackAuthorName)) -and
                       (Invoke-Git @('-C', $projectFolder, 'config', 'user.email', $script:FallbackAuthorEmail)))) -and
                     (Invoke-Git @('-C', $projectFolder, 'add', '--all')) -and
                     (Invoke-Git @('-C', $projectFolder, '-c', 'commit.gpgsign=false', 'commit', '--quiet', '--no-verify', '--message', $script:FirstCommitMessage))
        if (-not $succeeded) {
            Write-ErrorMessage "Making $projectFolder a repository failed. Read the messages above and run setup again."
            $script:SetupExitCode = 1; return
        }
        Write-Ok "$projectFolder is its own repository, with a first commit on main."
    }

    # --- 4. Spec Kit for round 3 ----------------------------------------------
    Write-Step '4/4 Spec Kit for round 3'
    $global:LASTEXITCODE = 1
    & (Join-Path $rootFolder $script:SpecKitSetupScript)
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMessage 'Installing Spec Kit did not finish. Rounds 1 and 2 are ready; double-click setup.cmd in 3-vibecoding before round 3.'
        $script:SetupExitCode = 1; return
    }

    Write-Host ''
    Write-Info 'Next: open the folder of your round in VS Code, never this root folder.'
}

if ($PSScriptRoot) {
    # ProviderPath keeps a network share a plain \\server\share path that git understands.
    Push-Location -LiteralPath $PSScriptRoot
    try {
        Invoke-Setup (Get-Location).ProviderPath
    } catch {
        Write-ErrorMessage "Setup stopped unexpectedly: $($_.Exception.Message)"
        $script:SetupExitCode = 1
    } finally {
        Pop-Location
    }
} else {
    Write-ErrorMessage 'Run this script as a file: double-click setup.cmd, or run .\setup.ps1 in the session 1 repository folder.'
    $script:SetupExitCode = 1
}

# Only exit when run as a script: exit in a dot-sourced file would close the caller's shell.
if ($MyInvocation.InvocationName -ne '.') { exit $script:SetupExitCode }
