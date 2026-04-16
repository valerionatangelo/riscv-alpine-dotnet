# =============================================================================
# config.ps1 - Shared configuration for the .NET RISC-V build pipeline
#
# Dot-source this file from every other script:
#   . "$PSScriptRoot\config.ps1"
#
# Override any variable by setting the matching environment variable BEFORE
# running a script:
#   $env:FORK = "my-fork"; $env:BRANCH = "release/10.0"
#   .\scripts\01-clone.ps1
# =============================================================================

# -- Upstream repo ------------------------------------------------------------
$FORK     = if ($env:FORK)     { $env:FORK }     else { 'dotnet' }
$BRANCH   = if ($env:BRANCH)   { $env:BRANCH }   else { 'main' }
$BRANDING = if ($env:BRANDING) { $env:BRANDING } else { 'preview' }

# -- Build target -------------------------------------------------------------
$OS_NAME = 'linux-musl'        # Alpine uses musl libc
$ARCH    = 'riscv64'
$RID     = "$OS_NAME-$ARCH"    # linux-musl-riscv64

# -- Build prereqs container (mirrors build.yml linux-musl matrix entry) ------
# Runs as linux/amd64; contains the RISC-V cross-toolchain + musl sysroot
$BUILD_PREREQS_TAG = 'azurelinux-3.0-net10.0-cross-riscv64-musl'
$PREREQS_IMAGE     = "mcr.microsoft.com/dotnet-buildtools/prereqs:$BUILD_PREREQS_TAG"

# Path inside the prereqs container (not on the Windows host)
$ROOTFS_DIR = '/crossrootfs/riscv64'

# -- Local directories --------------------------------------------------------
$DOTNET_SRC_DIRNAME = 'dotnet-src'   # cloned under the repo root

# -- Final Docker images ------------------------------------------------------
$ALPINE_VERSION    = if ($env:ALPINE_VERSION)    { $env:ALPINE_VERSION }    else { 'edge' }
$IMAGE_NAME        = if ($env:IMAGE_NAME)        { $env:IMAGE_NAME }        else { 'dotnet-alpine-riscv64' }
$IMAGE_TAG_SDK     = if ($env:IMAGE_TAG_SDK)     { $env:IMAGE_TAG_SDK }     else { 'sdk' }
$IMAGE_TAG_RUNTIME = if ($env:IMAGE_TAG_RUNTIME) { $env:IMAGE_TAG_RUNTIME } else { 'runtime' }
