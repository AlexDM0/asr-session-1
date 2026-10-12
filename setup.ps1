<#
.SYNOPSIS
  setup.ps1 - turn every project folder of the session 1 repository into its own git repository,
  on Windows.

.DESCRIPTION
  1. Checks that git works and that this folder is not inside another git repository
  2. Removes the .git of this folder, after asking: the clone's history goes, every file stays
  3. git init and a first commit in 1-vibecoding\, 2-vibecoding\ and 3-vibecoding\

  One repository per project keeps the agent away from your other rounds: Copilot CLI and worktree sessions
  work from the git root. Safe to run again: a project that is already a repository is left alone.
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
$script:FirstCommitMessage = 'Starter'
$script:FallbackAuthorName = 'Duinzicht workshop'
$script:FallbackAuthorEmail = 'workshop@duinzicht.example'

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
function Write-ErrorMessage($message) { Write-Host "$script:CrossGlyph $message" -ForegroundColor Red }

# Ask a yes/no question; anything but y counts as no.
function Confirm-Offer($question) {
    $answer = Read-Host "  $question [y/N]"
    return ($answer -eq 'y' -or $answer -eq 'Y')
}

# Runs git with the given arguments and returns whether it succeeded.
function Invoke-Git([string[]]$gitArguments) {
    $global:LASTEXITCODE = 1
    & git @gitArguments | Out-Host
    return ($LASTEXITCODE -eq 0)
}

# Returns the top folder of the repository that contains $folder, or $null when there is none.
function Get-EnclosingRepository($folder) {
    $global:LASTEXITCODE = 1
    $topFolder = (& git -C $folder rev-parse --show-toplevel 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $topFolder) { return $topFolder }
    return $null
}

function Get-GitValue($key) {
    return (& git config --get $key 2>$null | Out-String).Trim()
}

function Invoke-Setup {
    Write-Bold 'Splitting the session 1 repository into one repository per project'

    # --- 1. Checks -----------------------------------------------------------
    Write-Step '1/3 Checks'
    if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        Write-ErrorMessage 'git was not found. Install it from https://git-scm.com and run setup again.'
        $script:SetupExitCode = 1; return
    }
    Write-Ok "$((& git --version | Out-String).Trim()) works."

    foreach ($projectFolder in $script:ProjectFolders) {
        if (-not (Test-Path -Path $projectFolder -PathType Container)) {
            Write-ErrorMessage "The folder $projectFolder is missing. Run this script from the session 1 repository folder."
            $script:SetupExitCode = 1; return
        }
    }

    # Nested repositories inside someone else's repository would turn up there as embedded repositories.
    $parentFolder = Split-Path -Path (Get-Location).Path -Parent
    $enclosingRepository = Get-EnclosingRepository $parentFolder
    if ($enclosingRepository) {
        Write-ErrorMessage "This folder is inside another git repository: $enclosingRepository"
        Write-Info 'Copy the folder somewhere outside that repository and run setup there.'
        $script:SetupExitCode = 1; return
    }
    Write-Ok 'This folder is not inside another git repository.'

    # --- 2. Remove the repository of this folder -------------------------------
    Write-Step '2/3 Remove the repository of this folder'
    $repositoryPath = Join-Path (Get-Location).Path '.git'
    if (Test-Path -Path $repositoryPath) {
        Write-Info 'Every project gets its own repository, so the agent stays inside its project folder.'
        Write-Info "This removes $($repositoryPath): the history of this clone goes, every file stays."
        if (-not (Confirm-Offer 'Remove it now?')) {
            Write-ErrorMessage 'Nothing changed. Run setup again when you are ready.'
            $script:SetupExitCode = 1; return
        }
        # -Force also removes the read-only object files git writes on Windows.
        Remove-Item -Path $repositoryPath -Recurse -Force
        if (Test-Path -Path $repositoryPath) {
            Write-ErrorMessage "Could not remove $repositoryPath. Close VS Code and other programs that use it, then run setup again."
            $script:SetupExitCode = 1; return
        }
        Write-Ok 'Removed.'
    } else {
        Write-Ok 'This folder is no repository any more.'
    }

    # --- 3. One repository per project -----------------------------------------
    Write-Step '3/3 One repository per project'
    $commitIdentity = @()
    if (-not (Get-GitValue 'user.name') -or -not (Get-GitValue 'user.email')) {
        Write-Info "git has no name and email set up, so the first commits use `"$script:FallbackAuthorName`"."
        Write-Info 'Set your own for later commits:  git config --global user.name "Your Name"'
        $commitIdentity = @('-c', "user.name=$script:FallbackAuthorName", '-c', "user.email=$script:FallbackAuthorEmail")
    }

    foreach ($projectFolder in $script:ProjectFolders) {
        if (Test-Path -Path (Join-Path $projectFolder '.git')) {
            Write-Ok "$projectFolder is already its own repository."
            continue
        }
        # symbolic-ref instead of init --initial-branch, which git before 2.28 does not know.
        $succeeded = (Invoke-Git @('-C', $projectFolder, 'init', '--quiet')) -and
                     (Invoke-Git @('-C', $projectFolder, 'symbolic-ref', 'HEAD', 'refs/heads/main')) -and
                     (Invoke-Git @('-C', $projectFolder, 'add', '--all')) -and
                     (Invoke-Git (@('-C', $projectFolder) + $commitIdentity + @('commit', '--quiet', '--message', $script:FirstCommitMessage)))
        if (-not $succeeded) {
            Write-ErrorMessage "Making $projectFolder a repository failed. Read the messages above and run setup again."
            $script:SetupExitCode = 1; return
        }
        Write-Ok "$projectFolder is its own repository, with a first commit on main."
    }

    Write-Host ''
    Write-Info 'Next: open the folder of your round in VS Code, never this root folder.'
}

if ($PSScriptRoot) {
    Push-Location -Path $PSScriptRoot
    try { Invoke-Setup } finally { Pop-Location }
} else {
    Write-ErrorMessage 'Run this script as a file: double-click setup.cmd, or run .\setup.ps1 in the session 1 repository folder.'
    $script:SetupExitCode = 1
}

# Only exit when run as a script: exit in a dot-sourced file would close the caller's shell.
if ($MyInvocation.InvocationName -ne '.') { exit $script:SetupExitCode }
