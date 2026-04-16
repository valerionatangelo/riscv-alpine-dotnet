# .NET RISC-V Alpine Docker Build — Notes

Local reproduction of [build.yml](build.yml) targeting a `linux-musl-riscv64`
.NET SDK tarball + custom Alpine riscv64 Docker image, scripted for
**Windows + Docker Desktop + PowerShell**.

---

## Directory layout

```
RiscvDotnet\
├── build.yml                       Reference workflow (read-only)
├── NOTES.md                        This file
├── .gitignore
├── scripts\
│   ├── config.ps1                  Shared variables — edit to customise
│   ├── 00-clean.ps1                Remove previous / failed build state
│   ├── 01-clone.ps1                Clone the dotnet VMR
│   ├── 02-patch.ps1                Apply the linux-musl-riscv64 runtime patch
│   ├── 03-build-sdk.ps1            Run the cross-compilation build in Docker
│   ├── 04-find-artifact.ps1        Locate the produced tarball (used by 05)
│   ├── 05-build-image.ps1          Build the Alpine riscv64 Docker images
│   ├── 06-validate.ps1             Verify dotnet works inside the images
│   └── run-all.ps1                 Run every step end-to-end
├── docker\
│   ├── Dockerfile.sdk              Full SDK image  (dotnet-alpine-riscv64:sdk)
│   └── Dockerfile.runtime          Runtime-only image (dotnet-alpine-riscv64:runtime)
└── dotnet-src\                     Created by 01-clone.ps1  (~435 MB clone, git-ignored)
```

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker Desktop for Windows | 4.x+ with Linux containers mode |
| `docker buildx` | Bundled with Docker Desktop — verify: `docker buildx version` |
| Git | Must be on `PATH` |
| PowerShell | 5.1+ (built into Windows) or PowerShell 7 |
| ~50 GB free disk | Docker Desktop disk image must be large enough |
| Time | The SDK build (step 3) takes **2–8 hours** on a modern PC |
| Windows long-path support | The dotnet VMR contains paths > 260 chars. See below. |

**Windows long-path support (required before cloning)**

Run once in an elevated (Admin) PowerShell:
```powershell
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled -Value 1 -Force
```
No reboot needed — takes effect for new processes immediately. `01-clone.ps1`
checks for this and aborts with instructions if it is not set.

**Execution policy**: if you get a script policy error, run once in an elevated
PowerShell prompt:
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

---

## Quick start

```powershell
cd C:\...\RiscvDotnet

# Run the full pipeline
.\scripts\run-all.ps1

# Or step by step:
.\scripts\01-clone.ps1           # Clone dotnet VMR (~20 GB)
.\scripts\02-patch.ps1           # Apply patch (fast, non-fatal if unneeded)
.\scripts\03-build-sdk.ps1       # *** 2-8 hours — go get a coffee ***
.\scripts\05-build-image.ps1     # Build Alpine Docker images (fast)
.\scripts\06-validate.ps1        # Verify dotnet works
```

---

## Customisation

Edit `scripts\config.ps1` or set environment variables before running:

```powershell
# Different fork / branch
$env:FORK   = "my-github-user"
$env:BRANCH = "release/10.0"
.\scripts\01-clone.ps1

# Release branding
$env:BRANDING = "release"
.\scripts\03-build-sdk.ps1

# Custom image name
$env:IMAGE_NAME    = "my-dotnet"
$env:IMAGE_TAG_SDK = "10-sdk"
.\scripts\05-build-image.ps1
```

---

## How each step maps to build.yml

| build.yml step | Local script |
|---|---|
| `Clone repository` | `01-clone.ps1` |
| `Apply patches` | `02-patch.ps1` |
| `Build` (docker run prereqs image) | `03-build-sdk.ps1` |
| `List assets` / `Upload .NET` | `04-find-artifact.ps1` |
| *(local only)* | `05-build-image.ps1` |
| *(local only)* | `06-validate.ps1` |

The core docker command in `03-build-sdk.ps1` is reproduced verbatim
from build.yml (linux-musl matrix entry):

```
docker run --platform linux/amd64 --rm
  -v <dotnet-src>:/dotnet  -w /dotnet
  -e ROOTFS_DIR=/crossrootfs/riscv64
  mcr.microsoft.com/dotnet-buildtools/prereqs:azurelinux-3.0-net10.0-cross-riscv64-musl
    ./build.sh --clean-while-building --prep -sb
      --os linux-musl --rid linux-musl-riscv64 --arch riscv64
      --branding preview  -p:OfficialBuildId=<YYYYMMDD>.99
```

**Why `linux/amd64` for the build container?**
The prereqs image is an x86_64 Azure Linux container that bundles the RISC-V
cross-compilation toolchain and a musl sysroot at `/crossrootfs/riscv64`. No
QEMU emulation is needed for the *build itself* — the cross-compiler produces
riscv64 binaries while running natively on x86_64. QEMU is only needed later
to *run* the resulting Alpine image on your x86 host.

---

## The patch (02-patch.ps1)

build.yml applies am11/runtime@fa6e00a to `src/runtime` inside the VMR.
Comment in build.yml: *"needed for .NET 10 linux-musl-riscv64, remove it
once we move on from .NET 10"*.

The script mirrors the `|| true` behaviour from build.yml — a failed apply is
a warning, not an error, because the fix may already be merged upstream.

---

## The Docker images

### `dotnet-alpine-riscv64:sdk`
- Base: `alpine:edge` (riscv64, via QEMU on x86 host)
- Deps: `libssl3  libgcc  libstdc++  zlib  icu-libs`
- Full .NET SDK extracted to `/opt/dotnet`
- `DOTNET_ROOT=/opt/dotnet`, `/opt/dotnet` in `PATH`

### `dotnet-alpine-riscv64:runtime`
- Same base + deps
- Two-stage build: only copies `dotnet` binary and `shared/` runtime frameworks
- Noticeably smaller than the SDK image
- Use for running compiled apps, not building them

---

## Validation output

A passing `06-validate.ps1` run looks like:

```
  > Architecture  (uname -m)
  riscv64
  [PASS]

  > dotnet --version
  10.0.100-preview.5.xxxxx
  [PASS]

  > dotnet --info
  .NET SDK:
   Version: 10.0.100-preview.5...
  ...
  [PASS]
```

---

## Cleaning up / Retrying a failed build

Use `00-clean.ps1` to remove stale build state before retrying.  Three levels:

```powershell
# Default — remove build artifacts + docker context, keep the clone
# (fastest retry: avoids re-downloading the 435 MB VMR)
.\scripts\00-clean.ps1

# Also remove the dotnet-src clone (re-clone on next run)
.\scripts\00-clean.ps1 -Full

# Also remove the built Docker images from the local daemon
.\scripts\00-clean.ps1 -Images

# Nuclear option — everything gone, truly fresh start
.\scripts\00-clean.ps1 -Full -Images
```

What each level removes:

| Flag(s) | What is removed |
|---|---|
| *(none)* | `dotnet-src\artifacts\`, `dotnet-src\.packages\`, `dotnet-src\.dotnet\`, `docker\context\` |
| `-Full` | Everything above **+** the `dotnet-src\` clone itself |
| `-Images` | Everything above **+** `dotnet-alpine-riscv64:sdk` and `:runtime` images |
| `-Full -Images` | Complete reset |

You can also pass flags to `run-all.ps1` to clean before the pipeline runs:

```powershell
# Wipe artifacts first, then run the full pipeline (clone is kept)
.\scripts\run-all.ps1 -Clean

# Wipe everything including the clone, then run the full pipeline
.\scripts\run-all.ps1 -FullClean
```

---

## Troubleshooting

**`Filename too long` / `error: unable to create file` during clone (exit 128)**
The dotnet VMR contains file paths exceeding Windows' default 260-character
limit.  Fix with one admin command (no reboot needed):
```powershell
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled -Value 1 -Force
```
Then remove the partial clone and retry:
```powershell
Remove-Item -Recurse -Force dotnet-src
.\scripts\01-clone.ps1
```
`01-clone.ps1` now checks this automatically and aborts early if the key is not
set, so you will see a clear error message before any download starts.

**Script execution policy error**
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**"no space left on device" during build**
Increase the Docker Desktop disk image size:
Docker Desktop > Settings > Resources > Disk image size > at least 80 GB.

**`docker buildx build` fails with "exec format error"**
QEMU is not registered. Run manually:
```powershell
docker run --privileged --rm tonistiigi/binfmt --install riscv64
```

**`dotnet --info` prints globalization/ICU errors**
Ensure `icu-libs` is installed in the image (it is by default).
If you removed it, set `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true` at runtime:
```powershell
docker run --rm --platform linux/riscv64 `
  -e DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true `
  dotnet-alpine-riscv64:sdk dotnet --info
```

**Patch fails to apply**
Expected if already merged upstream. The script continues (matching
build.yml's `|| true`).

**Pre-pulling the prereqs image manually**
```powershell
docker pull --platform linux/amd64 `
  mcr.microsoft.com/dotnet-buildtools/prereqs:azurelinux-3.0-net10.0-cross-riscv64-musl
```
