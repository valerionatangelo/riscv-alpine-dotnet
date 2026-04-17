#Requires -Version 5.1
# =============================================================================
# 07-test-helloworld.ps1 - Build and run the Hello World app on RISC-V Alpine
#
# Verifies the full end-to-end pipeline:
#   1. Build a .NET console app inside the locally-built SDK image
#   2. Package the published output into the runtime image
#   3. Run the container and check the output
#
# Prerequisites:
#   - 05-build-image.ps1 must have completed (SDK + runtime images present)
#   - hello-world/ directory must exist at the repo root
#
# The test image is tagged:  dotnet-alpine-riscv64:helloworld
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$Platform      = 'linux/riscv64'
$SdkImage      = "${IMAGE_NAME}:${IMAGE_TAG_SDK}"
$RuntimeImage  = "${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}"
$TestTag       = 'helloworld'
$TestImage     = "${IMAGE_NAME}:${TestTag}"
$Dockerfile    = Join-Path $RepoRoot 'docker\Dockerfile.helloworld'

Write-Host '============================================================'
Write-Host ' 07-test-helloworld.ps1 - Hello World on RISC-V Alpine'
Write-Host '============================================================'

# -- Preflight checks ---------------------------------------------------------
foreach ($Img in @($SdkImage, $RuntimeImage)) {
    $Id = docker image ls -q $Img
    if (-not $Id) {
        Write-Error "Required image '$Img' not found. Run 05-build-image.ps1 first."
    }
}

if (-not (Test-Path $Dockerfile)) {
    Write-Error "Dockerfile not found: $Dockerfile"
}

$AppDir = Join-Path $RepoRoot 'hello-world'
if (-not (Test-Path $AppDir)) {
    Write-Error "hello-world/ directory not found at: $AppDir"
}

# -- Build the hello-world image ----------------------------------------------
Write-Host ''
Write-Host 'Building hello-world image...'
Write-Host "  Dockerfile : $Dockerfile"
Write-Host "  SDK image  : $SdkImage"
Write-Host "  Runtime    : $RuntimeImage"
Write-Host "  Tag        : $TestImage"
Write-Host ''

$BuildArgs = @(
    'buildx', 'build',
    '--platform', $Platform,
    '--load',
    '--file', $Dockerfile,
    '--build-arg', "SDK_IMAGE=$SdkImage",
    '--build-arg', "RUNTIME_IMAGE=$RuntimeImage",
    '--tag', $TestImage,
    $RepoRoot
)

& docker @BuildArgs
if ($LASTEXITCODE -ne 0) { Write-Error "Hello World image build failed (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Build succeeded.' -ForegroundColor Green

# -- Run the container and capture output -------------------------------------
Write-Host ''
Write-Host 'Running hello-world container...'
Write-Host ('-' * 60)

$Output = & docker run --rm --platform $Platform $TestImage 2>&1
$ExitCode = $LASTEXITCODE

$Output | ForEach-Object { Write-Host "  $_" }
Write-Host ('-' * 60)

# -- Validate output ----------------------------------------------------------
Write-Host ''
if ($ExitCode -ne 0) {
    Write-Host "  [FAIL] Container exited with code $ExitCode" -ForegroundColor Red
    exit 1
}

$OutputText = $Output -join "`n"
$ExpectedPhrases = @(
    'Hello from .NET on RISC-V!',
    'riscv64'
)

$AllPassed = $true
foreach ($Phrase in $ExpectedPhrases) {
    if ($OutputText -match [regex]::Escape($Phrase)) {
        Write-Host "  [PASS] Output contains: '$Phrase'" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Expected output to contain: '$Phrase'" -ForegroundColor Red
        $AllPassed = $false
    }
}

Write-Host ''
Write-Host '============================================================'
if ($AllPassed) {
    Write-Host '  Hello World test PASSED - .NET runs on RISC-V Alpine!' -ForegroundColor Green
} else {
    Write-Host '  Hello World test FAILED' -ForegroundColor Red
    exit 1
}
Write-Host '============================================================'
