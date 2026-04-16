#Requires -Version 5.1
# =============================================================================
# 02-patch.ps1 — Apply the linux-musl-riscv64 runtime patch
#
# Mirrors the "Apply patches" step in build.yml:
#   curl … | git apply -v --directory=src/runtime   (with || true)
#
# The patch (am11/runtime fa6e00a) is needed for .NET 10 linux-musl-riscv64.
# It is applied with failure allowed (same as build.yml) because it may
# already be merged in the chosen branch.
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DotnetDir  = Join-Path $RepoRoot $DOTNET_SRC_DIRNAME
$PatchUrl   = 'https://github.com/am11/runtime/commit/fa6e00abe9be4a451d81a29309c933435db8fe40.patch'
$PatchSubdir = 'src/runtime'

Write-Host '============================================================'
Write-Host ' 02-patch.ps1 — Apply runtime patch'
Write-Host '============================================================'
Write-Host "  Patch URL : $PatchUrl"
Write-Host "  Apply dir : $PatchSubdir  (relative to dotnet VMR root)"
Write-Host ''

if (-not (Test-Path (Join-Path $DotnetDir '.git'))) {
    Write-Error "'$DotnetDir' is not a git repo. Run 01-clone.ps1 first."
}

# Download patch to a temp file (Invoke-WebRequest is the PowerShell-native curl)
$TempPatch = [System.IO.Path]::GetTempFileName()
try {
    Write-Host 'Downloading patch…'
    Invoke-WebRequest -Uri $PatchUrl -OutFile $TempPatch -UseBasicParsing

    Write-Host 'Applying patch (failure is non-fatal — may already be included in branch)…'
    git -C $DotnetDir apply -v --directory=$PatchSubdir $TempPatch
    if ($LASTEXITCODE -eq 0) {
        Write-Host ''
        Write-Host 'Patch applied successfully.'
    } else {
        Write-Host ''
        Write-Warning "git apply returned exit code $LASTEXITCODE — continuing anyway (matches build.yml '|| true' behaviour)."
    }
} finally {
    Remove-Item $TempPatch -ErrorAction SilentlyContinue
}
