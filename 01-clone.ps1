#Requires -Version 5.1
# =============================================================================
# 01-clone.ps1 — Clone the dotnet VMR (Virtual Monolithic Repository)
#
# Mirrors the "Clone repository" step in build.yml:
#   git clone --single-branch --depth 1 -b <branch> https://github.com/<fork>/dotnet
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
Write-Host ' 01-clone.ps1 — Clone dotnet VMR'
Write-Host '============================================================'
Write-Host "  Fork   : $FORK"
Write-Host "  Branch : $BRANCH"
Write-Host "  URL    : $CloneUrl"
Write-Host "  Target : $DotnetDir"
Write-Host ''

if (Test-Path (Join-Path $DotnetDir '.git')) {
    Write-Host 'Directory already contains a git repo — skipping clone.'
    Write-Host "To start fresh:  Remove-Item -Recurse -Force '$DotnetDir'"
    Write-Host ''
    git -C $DotnetDir log --oneline -1
    exit 0
}

if (Test-Path $DotnetDir) {
    Write-Error "'$DotnetDir' exists but is not a git repo. Remove it manually and re-run."
}

Write-Host 'Cloning (shallow, single-branch)…'
git clone --single-branch --depth 1 -b $BRANCH $CloneUrl $DotnetDir
if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Clone complete.'
git -C $DotnetDir log --oneline -1
