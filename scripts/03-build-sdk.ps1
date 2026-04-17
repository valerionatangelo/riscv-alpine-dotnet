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
# Windows filesystem note:
#   NuGet extracts .nupkg files (including DLL assemblies) to package caches
#   during the build.  When the cache lives on a Windows (NTFS) bind-mount,
#   Windows Defender or NTFS security policies silently drop the DLL files,
#   leaving only XML docs.  This causes CS0246 "type not found" errors when
#   the compiler tries to reference those assemblies.
#
#   Fix: the two NuGet package cache directories (.packages and
#   src/source-build-reference-packages/artifacts/.packages) are mounted as
#   Docker named volumes (true Linux ext4 filesystem) so DLLs are preserved.
#   The final SDK tarball in artifacts/assets/... is still on the Windows
#   bind-mount so it remains accessible from Windows after the build.
#
# Override: $env:BRANDING = 'release'
# =============================================================================
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
. "$ScriptDir\config.ps1"

$DotnetDir       = Join-Path $RepoRoot $DOTNET_SRC_DIRNAME
$OfficialBuildId = (Get-Date -Format 'yyyyMMdd') + '.99'

# Docker named volumes for NuGet package caches.
# Using the image name as a prefix keeps volumes associated with this project.
#
# Only the NuGet caches need a real Linux volume.  The bootstrap SDK (.dotnet/)
# is installed via tar (not NuGet), works fine on the Windows bind-mount, and
# must NOT be a Docker volume: an empty volume creates an empty .dotnet/ dir,
# which tricks prep-source-build.sh into running .dotnet/dotnet before it is
# installed, crashing with exit 127.
$VolPackages     = "${IMAGE_NAME}-dotnet-packages"
$VolSbrpPackages = "${IMAGE_NAME}-sbrp-packages"

Write-Host '============================================================'
Write-Host ' 03-build-sdk.ps1 - Build .NET SDK (linux-musl-riscv64)'
Write-Host '============================================================'
Write-Host "  Source dir      : $DotnetDir"
Write-Host "  Prereqs image   : $PREREQS_IMAGE"
Write-Host "  ROOTFS_DIR      : $ROOTFS_DIR  (inside container)"
Write-Host "  Target RID      : $RID"
Write-Host "  Branding        : $BRANDING"
Write-Host "  OfficialBuildId : $OfficialBuildId"
Write-Host "  Vol (.packages) : $VolPackages"
Write-Host "  Vol (sbrp pkgs) : $VolSbrpPackages"
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

# Pre-build script run inside the container before invoking build.sh:
#
# 1. git config --global core.fileMode false
#    Must be GLOBAL so all git invocations inherit it, including those that run
#    with GIT_DIR=/dev/null (ApplyPatches in source-build-reference-packages).
#    NTFS has no Unix execute bit, so every file appears as 100755; without
#    this flag the source-build patch-apply step fails with "expected 100644".
#
# 2. git -C /dotnet config core.fileMode false
#    Belt-and-suspenders: also set on the repo itself.
#
# 3. Pre-create the package cache directories inside the Docker volumes so they
#    exist before the bind-mount of /dotnet (which might create empty dirs on
#    the Windows side).  This is defensive; Docker usually handles this.
$BuildScript = (
    # If .dotnet/ exists but has no dotnet binary, remove it.
    # Docker creates an empty directory on the Windows bind-mount as a mount-point
    # when a named volume was previously attached there; after that volume is
    # removed the empty dir remains.  prep-source-build.sh checks [ -d .dotnet ]
    # and immediately tries to run .dotnet/dotnet without verifying the binary
    # exists, causing exit 127.  Deleting the empty dir lets the prep script
    # install the SDK from scratch as intended.
    "( [ -d /dotnet/.dotnet ] && [ ! -f /dotnet/.dotnet/dotnet ] && rm -rf /dotnet/.dotnet ) ; " +
    # Several repos (nuget-client, templating, roslyn, aspnetcore, sdk, ...) enforce
    # IDE0055 (Fix formatting) as a build error.  Source files were checked out on
    # Windows with CRLF line endings; the Roslyn formatter on Linux sees \r as
    # trailing whitespace and fails.  Strip \r from all C#/F#/VB source files
    # across the entire source tree once before the build starts.
    # xargs -P4 runs 4 sed processes in parallel to keep this under ~2 minutes.
    "echo 'Stripping CRLF from all source files (one-time, may take ~2 min)...' && " +
    "find /dotnet/src -name '*.cs' -o -name '*.fs' -o -name '*.vb' | xargs -P4 -r sed -i 's/\r//' 2>/dev/null ; " +
    "echo 'CRLF strip done.' && " +
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

# Volume mounts:
#   /dotnet                    - Windows bind-mount (source + final tarball)
#   /dotnet/.packages          - Docker volume (NuGet global cache, needs real Linux FS for DLL extraction)
#   /dotnet/.dotnet            - Docker volume (bootstrapped SDK, needs real Linux FS)
#   /dotnet/src/source-build-reference-packages/artifacts/.packages
#                              - Docker volume (SBRP NuGet cache, same reason)
$dockerArgs = @(
    'run',
    '--platform', 'linux/amd64',
    '--rm',
    '-v', "${DotnetDirFwd}:/dotnet",
    '-v', "${VolPackages}:/dotnet/.packages",
    '-v', "${VolSbrpPackages}:/dotnet/src/source-build-reference-packages/artifacts/.packages",
    '-w', '/dotnet',
    '-e', "ROOTFS_DIR=$ROOTFS_DIR",
    $PREREQS_IMAGE,
    'bash', '-c', $BuildScript
)

& docker @dockerArgs

if ($LASTEXITCODE -ne 0) { Write-Error "SDK build failed (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Build finished. Next steps:'
Write-Host '  .\scripts\04-find-artifact.ps1   # locate and verify the SDK tarball'
Write-Host '  .\scripts\05-build-image.ps1     # build the Alpine riscv64 Docker image'
