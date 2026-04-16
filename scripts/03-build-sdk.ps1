#Requires -Version 5.1
# =============================================================================
# 03-build-sdk.ps1 - Build the .NET SDK for linux-musl-riscv64
#
# Reproduces the "Build" step from build.yml verbatim:
#
#   docker run --platform linux/amd64 --rm \
#     -v <dotnet-src>:/dotnet  -w /dotnet \
#     -e ROOTFS_DIR=/crossrootfs/riscv64 \
#     mcr.microsoft.com/dotnet-buildtools/prereqs:azurelinux-3.0-net10.0-cross-riscv64-musl \
#       ./build.sh --clean-while-building --prep -sb \
#         --os linux-musl --rid linux-musl-riscv64 --arch riscv64 \
#         --branding preview  -p:OfficialBuildId=<YYYYMMDD>.99
#
# Notes:
#   - The prereqs image is x86_64 (--platform linux/amd64) and contains the
#     complete RISC-V cross-compilation toolchain + musl sysroot.
#   - -sb = source build (fully offline/reproducible)
#   - --prep generates MSBuild props before the main build
#   - --clean-while-building removes intermediates early to save disk space
#   - Expected time: 2-8 hours.  Required disk: ~50 GB free.
#
# Override: $env:BRANDING = 'release'
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DotnetDir       = Join-Path $RepoRoot $DOTNET_SRC_DIRNAME
$OfficialBuildId = (Get-Date -Format 'yyyyMMdd') + '.99'

Write-Host '============================================================'
Write-Host ' 03-build-sdk.ps1 - Build .NET SDK (linux-musl-riscv64)'
Write-Host '============================================================'
Write-Host "  Source dir      : $DotnetDir"
Write-Host "  Prereqs image   : $PREREQS_IMAGE"
Write-Host "  ROOTFS_DIR      : $ROOTFS_DIR  (inside container)"
Write-Host "  Target RID      : $RID"
Write-Host "  Branding        : $BRANDING"
Write-Host "  OfficialBuildId : $OfficialBuildId"
Write-Host ''
Write-Host '  *** This build typically takes 2-8 hours. ***'
Write-Host '  *** Ensure at least 50 GB of free disk space in Docker Desktop. ***'
Write-Host ''

if (-not (Test-Path (Join-Path $DotnetDir '.git'))) {
    Write-Error "'$DotnetDir' is not a git repo. Run 01-clone.ps1 (and optionally 02-patch.ps1) first."
}

# Docker Desktop on Windows accepts forward-slash paths in -v bindings.
# Resolve-Path is called here (after the existence check) so it doesn't crash
# with a confusing error if the directory hasn't been cloned yet.
$DotnetDirFwd = (Resolve-Path $DotnetDir).Path.Replace('\', '/')

# Pull the prereqs image first so any authentication errors are visible early
Write-Host 'Pulling prereqs image (may take a few minutes on first run)...'
docker pull --platform linux/amd64 $PREREQS_IMAGE
if ($LASTEXITCODE -ne 0) { Write-Error "docker pull failed (exit $LASTEXITCODE)" }
Write-Host ''

Write-Host 'Starting SDK build...'

# Build the argument list as an array to avoid PowerShell quoting issues on Windows.
#
# core.fileMode=false is set before the build because the VMR is on a Windows
# (NTFS) filesystem mounted into Linux: NTFS has no Unix execute bit, so every
# file appears as 100755 to Linux.  Without this flag the source-build
# infrastructure git-checks report false "permission changed" errors for .proj
# files (expected 100644, got 100755) and the build fails.
$BuildScript = (
    # core.fileMode=false must be set GLOBALLY so it is inherited by every git
    # invocation during the build, including those run with GIT_DIR=/dev/null
    # (used by the ApplyPatches MSBuild target in source-build-reference-packages).
    # A repo-local setting on /dotnet is ignored when GIT_DIR=/dev/null bypasses
    # normal git-directory discovery.
    "git config --global core.fileMode false && " +
    "git -C /dotnet config core.fileMode false && " +
    "./build.sh" +
    " --clean-while-building" +
    " --prep" +
    " -sb" +
    " --os $OS_NAME" +
    " --rid $RID" +
    " --arch $ARCH" +
    " --branding $BRANDING" +
    " -p:OfficialBuildId=$OfficialBuildId"
)

$dockerArgs = @(
    'run',
    '--platform', 'linux/amd64',
    '--rm',
    '-v', "${DotnetDirFwd}:/dotnet",
    '-w', '/dotnet',
    '-e', "ROOTFS_DIR=$ROOTFS_DIR",
    $PREREQS_IMAGE,
    'bash', '-c', $BuildScript
)

& docker @dockerArgs

if ($LASTEXITCODE -ne 0) { Write-Error "SDK build failed (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Build finished. Run 05-build-image.ps1 to package the Alpine Docker image.'
