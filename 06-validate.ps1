#Requires -Version 5.1
# =============================================================================
# 06-validate.ps1 — Validate the Alpine riscv64 .NET Docker images
#
# For each built image, runs:
#   uname -m            — must return "riscv64"
#   $DOTNET_ROOT        — must be /opt/dotnet
#   PATH contains …     — /opt/dotnet must be in PATH
#   dotnet binary       — must be executable
#   dotnet --version    — must print a version string
#   dotnet --info       — must show full SDK/runtime details
#
# Override: $env:IMAGE_NAME, $env:IMAGE_TAG_SDK, $env:IMAGE_TAG_RUNTIME
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir\config.ps1"

$Platform = 'linux/riscv64'
$Pass = 0
$Fail = 0

function Invoke-Check {
    param(
        [string]$Image,
        [string]$Label,
        [string]$Command
    )
    Write-Host "  > $Label"
    # Use array splat so PowerShell does not mangle the sh -c argument when
    # passing to docker on Windows (avoids double-quote escaping issues).
    $dockerArgs = @('run', '--rm', '--platform', $Platform, $Image, 'sh', '-c', $Command)
    & docker @dockerArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  [PASS]' -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  [FAIL] exit $LASTEXITCODE" -ForegroundColor Red
        $script:Fail++
    }
    Write-Host ''
}

function Test-Image {
    param([string]$Image)

    Write-Host ''
    Write-Host ('─' * 60) -ForegroundColor Cyan
    Write-Host "  Validating: $Image" -ForegroundColor Cyan
    Write-Host ('─' * 60) -ForegroundColor Cyan

    Invoke-Check $Image 'Architecture  (uname -m)' `
        'uname -m'

    # printenv avoids embedding quotes inside the sh -c string
    Invoke-Check $Image 'DOTNET_ROOT env var' `
        'printenv DOTNET_ROOT'

    # command -v relies on PATH being set correctly — no pipes or quotes needed
    Invoke-Check $Image 'PATH contains /opt/dotnet  (command -v dotnet)' `
        'command -v dotnet'

    # ls -la shows the file and its permissions in one shot
    Invoke-Check $Image 'dotnet binary is executable  (ls -la)' `
        'ls -la /opt/dotnet/dotnet'

    Invoke-Check $Image 'dotnet --version' `
        'dotnet --version'

    Invoke-Check $Image 'dotnet --info' `
        'dotnet --info'
}

Write-Host '============================================================'
Write-Host ' 06-validate.ps1 — Validate Alpine riscv64 .NET images'
Write-Host '============================================================'

$SdkImage     = "${IMAGE_NAME}:${IMAGE_TAG_SDK}"
$RuntimeImage = "${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}"

foreach ($Img in @($SdkImage, $RuntimeImage)) {
    $Exists = docker image inspect $Img 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Image '$Img' not found locally — skipping. Run 05-build-image.ps1 first."
        continue
    }
    Test-Image $Img
}

Write-Host ''
Write-Host '============================================================'
if ($Fail -eq 0) {
    Write-Host "  Results: $Pass passed, $Fail failed — ALL GOOD" -ForegroundColor Green
} else {
    Write-Host "  Results: $Pass passed, $Fail failed" -ForegroundColor Red
}
Write-Host '============================================================'

if ($Fail -gt 0) { exit 1 }
