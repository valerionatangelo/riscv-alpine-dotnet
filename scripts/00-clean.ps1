#Requires -Version 5.1
# =============================================================================
# 00-clean.ps1 - Remove previous (including failed) build state
#
# Three cleanup levels - use the narrowest one that fits your situation:
#
#   .\scripts\00-clean.ps1              # Default: artifacts + docker context
#   .\scripts\00-clean.ps1 -Full        # Also removes the dotnet-src clone
#   .\scripts\00-clean.ps1 -Images      # Also removes the local Docker images
#   .\scripts\00-clean.ps1 -Full -Images  # Everything - truly fresh start
#
# Default (no flags) is the typical "retry a failed build" case: the 435 MB
# clone is kept so you don't have to re-download it, but all build outputs
# and staged Docker context are wiped.
# =============================================================================
param(
    [switch]$Full,    # Remove the dotnet-src clone as well
    [switch]$Images   # Remove the built Docker images from the local daemon
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DotnetDir        = Join-Path $RepoRoot $DOTNET_SRC_DIRNAME
$DockerContextDir = Join-Path $RepoRoot 'docker\context'

function Remove-IfExists([string]$Path, [string]$Label) {
    if (Test-Path $Path) {
        Write-Host "  Removing $Label..."
        Write-Host "    $Path"
        Remove-Item -Recurse -Force $Path
        Write-Host "  Done."
    } else {
        Write-Host "  $Label - not present, skipping."
    }
}

Write-Host '============================================================'
Write-Host ' 00-clean.ps1 - Clean build state'
Write-Host '============================================================'
Write-Host "  -Full   : $Full"
Write-Host "  -Images : $Images"
Write-Host ''

# -- Always: build artifacts inside the clone ---------------------------------
# These are safe to remove without losing the 435 MB object download.
Write-Host '[1] Build artifacts (dotnet-src\artifacts\)'
Remove-IfExists (Join-Path $DotnetDir 'artifacts') 'build artifacts'

Write-Host ''
Write-Host '[2] NuGet / package caches inside the clone'
Remove-IfExists (Join-Path $DotnetDir '.packages')  'NuGet package cache (.packages)'
Remove-IfExists (Join-Path $DotnetDir '.dotnet')     'local dotnet tool (.dotnet)'

Write-Host ''
Write-Host '[3] Docker build context staging area (docker\context\)'
Remove-IfExists $DockerContextDir 'docker context (staged tarball)'

# -- -Full: also remove the clone itself --------------------------------------
if ($Full) {
    Write-Host ''
    Write-Host '[4] dotnet-src clone  (-Full specified)'
    Remove-IfExists $DotnetDir 'dotnet-src clone'
    Write-Host '    Next run of 01-clone.ps1 will re-download ~435 MB.'
} else {
    Write-Host ''
    Write-Host '[4] dotnet-src clone  (skipped - use -Full to also remove the clone)'
}

# -- -Images: remove Docker images --------------------------------------------
if ($Images) {
    Write-Host ''
    Write-Host '[5] Docker images  (-Images specified)'

    foreach ($Tag in @($IMAGE_TAG_SDK, $IMAGE_TAG_RUNTIME)) {
        $Ref = "${IMAGE_NAME}:${Tag}"
        $Exists = docker image inspect $Ref 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Removing image $Ref..."
            docker rmi $Ref
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "  docker rmi $Ref failed - image may be in use. Stop any containers and retry."
            } else {
                Write-Host "  Removed."
            }
        } else {
            Write-Host "  Image $Ref - not present, skipping."
        }
    }
} else {
    Write-Host ''
    Write-Host '[5] Docker images  (skipped - use -Images to also remove built images)'
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' Cleanup complete.' -ForegroundColor Green
Write-Host '============================================================'
