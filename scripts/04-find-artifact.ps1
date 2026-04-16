#Requires -Version 5.1
# =============================================================================
# 04-find-artifact.ps1 - Locate the SDK tarball produced by 03-build-sdk.ps1
#
# Mirrors the "List assets directory" + artifact-path pattern from build.yml:
#   dotnet-src/artifacts/assets/Release/Sdk/*/dotnet-sdk-*-linux-musl-riscv64.tar.gz
#
# Returns the full path via Write-Output so callers can capture it:
#   $SDK = & .\scripts\04-find-artifact.ps1
#
# Writes progress/diagnostics to the host (not stdout) so captures are clean.
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DotnetDir     = Join-Path $RepoRoot $DOTNET_SRC_DIRNAME
$ArtifactsBase = Join-Path $DotnetDir 'artifacts'

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' 04-find-artifact.ps1 - Locate SDK tarball'                   -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "  Searching under : $ArtifactsBase"
Write-Host "  Pattern         : dotnet-sdk-*-$RID.tar.gz"
Write-Host ''

if (-not (Test-Path $ArtifactsBase)) {
    Write-Error "'$ArtifactsBase' does not exist. Has 03-build-sdk.ps1 completed successfully?"
}

# Primary search: build.yml artifact upload path
$Found = Get-ChildItem -Path (Join-Path $ArtifactsBase 'assets\Release\Sdk') `
             -Filter "dotnet-sdk-*-$RID.tar.gz" -Recurse -ErrorAction SilentlyContinue |
         Select-Object -First 1

# Fallback: anywhere under artifacts/
if (-not $Found) {
    $Found = Get-ChildItem -Path $ArtifactsBase `
                 -Filter "dotnet-sdk-*-$RID.tar.gz" -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
}

if (-not $Found) {
    Write-Host 'All .tar.gz files found under artifacts/:' -ForegroundColor Yellow
    Get-ChildItem -Path $ArtifactsBase -Filter '*.tar.gz' -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $($_.FullName)" }
    Write-Error "No tarball matching 'dotnet-sdk-*-$RID.tar.gz' was found. Has the build completed?"
}

Write-Host "Found: $($Found.FullName)" -ForegroundColor Green
Write-Host ''

# Return just the path to stdout for callers
Write-Output $Found.FullName
