#Requires -Version 5.1
# =============================================================================
# 05-build-image.ps1 - Build Alpine riscv64 Docker images from the SDK tarball
#
# Builds three images in dependency order:
#   1. dotnet-alpine-riscv64:runtime  - CoreCLR only       (~154 MB)
#   2. dotnet-alpine-riscv64:aspnet   - runtime + ASP.NET  (~182 MB)
#   3. dotnet-alpine-riscv64:sdk      - full SDK           (~600 MB+)
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
Write-Host ' 05-build-image.ps1 - Build Alpine riscv64 Docker images'
Write-Host '============================================================'

# -- 1. Locate the SDK tarball ------------------------------------------------
Write-Host ''
Write-Host '[1/6] Locating SDK tarball...'
$SdkTarball = & "$ScriptDir\04-find-artifact.ps1"
if (-not $SdkTarball) { Write-Error '04-find-artifact.ps1 returned nothing.' }
$TarballFilename = Split-Path -Leaf $SdkTarball
Write-Host "  Using: $SdkTarball"

# -- 2. Stage tarball in Docker build context ---------------------------------
Write-Host ''
Write-Host '[2/6] Staging tarball into Docker build context...'
if (-not (Test-Path $DockerContextDir)) {
    New-Item -ItemType Directory -Path $DockerContextDir | Out-Null
}
$DestPath = Join-Path $DockerContextDir $TarballFilename
if (-not (Test-Path $DestPath) -or
    (Get-Item $SdkTarball).LastWriteTime -gt (Get-Item $DestPath).LastWriteTime) {
    Write-Host "  Copying $TarballFilename  (may take a moment)..."
    Copy-Item -Path $SdkTarball -Destination $DestPath -Force
} else {
    Write-Host '  Already up-to-date in context dir - skipping copy.'
}
Write-Host "  Context: $DockerContextDir"

# -- 3. Register QEMU binfmt for riscv64 --------------------------------------
Write-Host ''
Write-Host '[3/6] Registering QEMU binfmt for riscv64...'
docker run --privileged --rm tonistiigi/binfmt --install riscv64
# Non-zero is OK - may already be registered
Write-Host '  binfmt step complete.'

# -- 4. Build runtime image ---------------------------------------------------
Write-Host ''
Write-Host "[4/6] Building runtime image: ${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}  (linux/riscv64)..."
docker buildx build `
    --platform linux/riscv64 `
    --load `
    --build-arg "SDK_TARBALL=$TarballFilename" `
    --build-arg "ALPINE_VERSION=$ALPINE_VERSION" `
    -t "${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}" `
    -f "$DockerDir\Dockerfile.runtime" `
    $DockerContextDir

if ($LASTEXITCODE -ne 0) { Write-Error "Runtime image build failed (exit $LASTEXITCODE)" }

# -- 5. Build aspnet image ----------------------------------------------------
Write-Host ''
Write-Host "[5/6] Building aspnet image: ${IMAGE_NAME}:${IMAGE_TAG_ASPNET}  (linux/riscv64)..."
docker buildx build `
    --platform linux/riscv64 `
    --load `
    --build-arg "SDK_TARBALL=$TarballFilename" `
    --build-arg "ALPINE_VERSION=$ALPINE_VERSION" `
    --build-arg "RUNTIME_IMAGE=${IMAGE_NAME}:${IMAGE_TAG_RUNTIME}" `
    -t "${IMAGE_NAME}:${IMAGE_TAG_ASPNET}" `
    -f "$DockerDir\Dockerfile.aspnet" `
    $DockerContextDir

if ($LASTEXITCODE -ne 0) { Write-Error "Aspnet image build failed (exit $LASTEXITCODE)" }

# -- 6. Build SDK image -------------------------------------------------------
Write-Host ''
Write-Host "[6/6] Building SDK image: ${IMAGE_NAME}:${IMAGE_TAG_SDK}  (linux/riscv64)..."
docker buildx build `
    --platform linux/riscv64 `
    --load `
    --build-arg "SDK_TARBALL=$TarballFilename" `
    --build-arg "ALPINE_VERSION=$ALPINE_VERSION" `
    -t "${IMAGE_NAME}:${IMAGE_TAG_SDK}" `
    -f "$DockerDir\Dockerfile.sdk" `
    $DockerContextDir

if ($LASTEXITCODE -ne 0) { Write-Error "SDK image build failed (exit $LASTEXITCODE)" }

# -- Summary ------------------------------------------------------------------
Write-Host ''
Write-Host '============================================================'
Write-Host ' Images built:' -ForegroundColor Green
docker images --filter "reference=$IMAGE_NAME" --format "  {{.Repository}}:{{.Tag}}  ({{.Size}})"
Write-Host ''
Write-Host ' Run 06-validate.ps1 to verify.'
Write-Host '============================================================'
