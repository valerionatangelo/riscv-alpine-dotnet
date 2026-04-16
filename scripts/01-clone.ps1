#Requires -Version 5.1
# =============================================================================
# 01-clone.ps1 - Clone the dotnet VMR (Virtual Monolithic Repository)
#
# Mirrors the "Clone repository" step in build.yml:
#   git clone --single-branch --depth 1 -b <branch> https://github.com/<fork>/dotnet
#
# NOTE: the dotnet VMR contains file paths longer than 260 characters.
# Windows MAX_PATH support and git core.longpaths must both be enabled before
# cloning.  This script checks both and aborts with clear instructions if not.
#
# Override defaults:  $env:FORK = "my-fork";  $env:BRANCH = "release/10.0"
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DotnetDir = Join-Path $RepoRoot $DOTNET_SRC_DIRNAME
$CloneUrl  = "https://github.com/$FORK/dotnet"

Write-Host '============================================================'
Write-Host ' 01-clone.ps1 - Clone dotnet VMR'
Write-Host '============================================================'
Write-Host "  Fork   : $FORK"
Write-Host "  Branch : $BRANCH"
Write-Host "  URL    : $CloneUrl"
Write-Host "  Target : $DotnetDir"
Write-Host ''

# -- Long-path preflight checks -----------------------------------------------
# The dotnet VMR has paths well over 260 chars (Razor test fixtures, OpenAPI
# snapshots, etc.).  Without both fixes below, git checkout will fail silently
# on those files.

# 1. git core.longpaths
$gitLongPaths = git config --global core.longpaths 2>$null
if ($gitLongPaths -ne 'true') {
    Write-Host "  [fix] Enabling git core.longpaths globally..."
    git config --global core.longpaths true
    if ($LASTEXITCODE -ne 0) { Write-Error "Could not set git core.longpaths. Run: git config --global core.longpaths true" }
    Write-Host "  [ok]  git core.longpaths = true"
} else {
    Write-Host "  [ok]  git core.longpaths already enabled"
}

# 2. Windows LongPathsEnabled registry key (requires prior one-time admin step)
$fsKey     = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$osLongPath = (Get-ItemProperty -Path $fsKey -Name LongPathsEnabled -ErrorAction SilentlyContinue).LongPathsEnabled
if ($osLongPath -ne 1) {
    Write-Host ''
    Write-Host '  [REQUIRED] Windows long-path support is NOT enabled.' -ForegroundColor Red
    Write-Host '  Some files in the dotnet VMR exceed 260 characters and will fail to check out.' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Run the following command ONCE in an elevated (Admin) PowerShell, then re-run this script:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "    Set-ItemProperty -Path '$fsKey' ``" -ForegroundColor Cyan
    Write-Host "        -Name LongPathsEnabled -Value 1 -Force" -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  No reboot required - takes effect immediately for new processes.' -ForegroundColor Yellow
    Write-Host ''
    Write-Error "Aborting: enable Windows long paths (see instructions above) then re-run."
}

Write-Host "  [ok]  Windows LongPathsEnabled = 1"
Write-Host ''
# -- End preflight ------------------------------------------------------------

if (Test-Path (Join-Path $DotnetDir '.git')) {
    Write-Host 'Directory already contains a git repo - skipping clone.'
    Write-Host "To start fresh:  Remove-Item -Recurse -Force '$DotnetDir'"
    Write-Host ''
    git -C $DotnetDir log --oneline -1
    exit 0
}

if (Test-Path $DotnetDir) {
    Write-Error "'$DotnetDir' exists but is not a git repo. Remove it manually and re-run."
}

Write-Host 'Cloning (shallow, single-branch)...'
git clone --single-branch --depth 1 -b $BRANCH $CloneUrl $DotnetDir
if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Clone complete.'
git -C $DotnetDir log --oneline -1
