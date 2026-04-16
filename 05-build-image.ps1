#Requires -Version 5.1
# =============================================================================
# 05-build-image.ps1 — Build Alpine riscv64 Docker images from the SDK tarball
#
# Steps:
#   1. Locate the SDK tarball (calls 04-find-artifact.ps1)
#   2. Stage it into docker\context\
#   3. Register QEMU binfmt for riscv64 (needed to run the final image on x86)
#   4. Build the SDK image    (dotnet-alpine-riscv64:sdk)
#   5. Build the runtime image (dotnet-alpine-riscv64:runtime)
#
# Note: The SDK *build* (step 3) runs as linux/amd64 (no QEMU needed).
#       QEMU is only needed to RUN the final riscv64 Alpine image on an x86 host.
#
# Override: $env:IMAGE_NAME = "my-dotnet";  $env:ALPINE_VERSION = "3.21"
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DockerDir        = Join-Path $RepoRoot 'docker'
$DockerContextDir = Join-Path $DockerDir 'context'

Write-Host '============================================================'
Write-Host ' 05-build-image.ps1 — Build Alpine riscv64 Docker images'
Write-Host '============================================================'

# ── 1. Locate the SDK tarball ──────────────────────────────────────────────
Write-Host ''
Write-Host '[1/5] Locating SDK tarball…'
$SdkTarball = & "$ScriptDir\04-find-artifact.ps1"
if (-not $SdkTarball) { Write-Error '04-find-artifact.ps1 returned nothing.' }
$TarballFilename = Split-Path -Leaf $SdkTarball
Write-Host "  Using: $SdkTarball"

# ── 2. Stage tarball in Docker build context ───────────────────────────────
Write-Host ''
Write-Host '[2/5] Staging tarball into Docker build context…'
if (-not (Test-Path $DockerContextDir)) {
    New-Item -ItemType Directory -Path $DockerContextDir | Out-Null
}
$DestPath = Join-Path $DockerContextDir $TarballFilename
if (-not (Test-Path $DestPath) -or
    (Get-Item $SdkTarball).LastWriteTime -gt (Get-Item $DestPath).LastWriteTime) {
    Write-Host "  Copying $TarballFilename  (may take a moment)…"
    Copy-Item -Path $SdkTarball -Destination $DestPath -Force
} else {
    Write-Host '  Already up-to-date in context dir — skipping copy.'
}
Write-Host "  Context: $DockerContextDir"

# ── 3. Register QEMU binfmt for riscv64 ───────────────────────────────────
Write-Host ''
Write-Host '[3/5] Registering QEMU binfmt for riscv64…'
docker run --privileged --rm tonistiigi/binfmt --install riscv64
# Non-zero is OK — may already be registered
Write-Host '  binfmt step complete.'

# ── 4. Build SDK image ─────────────────────────────────────────────────────
Write-Host ''
Write-Host "[4/5] Building SDK image: ${IMAGE_NAME}:${IMAGE_TAG_SDK}  (linux/riscv64)…"
docker buildx build `
    --platform linux/riscv64 `
    --load `
    --build-arg "SDK_TARBALL=$TarballFilename" `
    --build-arg "ALPINE_VERSION=$ALPINE_VERSION" `
    -t "${IMAGE_NAME}:${IMAGE_TAG_SDK}" `
    -f "$DockerDir\Dockerfile.sdk" `
    $DockerContextDir

if ($LASTEXITCODE -ne 0) { Write-Error "SDK image build failed (exit $LASTEXITCODE)" }

# ── 5. Build runtime image ─────────────────────────────────────────────────
Write-Host ''
Write-Host "[5/5] Building runtime image: ${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}  (linux/riscv64)…"
docker buildx build `
    --platform linux/riscv64 `
    --load `
    --build-arg "SDK_TARBALL=$TarballFilename" `
    --build-arg "ALPINE_VERSION=$ALPINE_VERSION" `
    -t "${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}" `
    -f "$DockerDir\Dockerfile.runtime" `
    $DockerContextDir

if ($LASTEXITCODE -ne 0) { Write-Error "Runtime image build failed (exit $LASTEXITCODE)" }

# ── Summary ────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '============================================================'
Write-Host ' Images built:' -ForegroundColor Green
docker images --filter "reference=$IMAGE_NAME" --format "  {{.Repository}}:{{.Tag}}  ({{.Size}})"
Write-Host ''
Write-Host ' Run 06-validate.ps1 to verify.'
Write-Host '============================================================'
