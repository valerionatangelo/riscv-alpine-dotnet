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
    docker run --rm --platform $Platform $Image sh -c $Command
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

    Invoke-Check $Image 'DOTNET_ROOT env var' `
        'echo "DOTNET_ROOT=${DOTNET_ROOT}"'

    Invoke-Check $Image 'PATH contains /opt/dotnet' `
        'echo "$PATH" | tr : "\n" | grep -q /opt/dotnet && echo "PATH OK: /opt/dotnet is present"'

    Invoke-Check $Image 'dotnet binary is executable' `
        'test -x "${DOTNET_ROOT}/dotnet" && echo "binary found: ${DOTNET_ROOT}/dotnet"'

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
