#Requires -Version 5.1
# =============================================================================
# run-all.ps1 — Full end-to-end pipeline
#
# Runs every step in sequence.  You can also run steps individually:
#
#   .\scripts\00-clean.ps1           # Clean previous / failed build state
#   .\scripts\01-clone.ps1           # Clone dotnet VMR
#   .\scripts\02-patch.ps1           # Apply linux-musl-riscv64 patch
#   .\scripts\03-build-sdk.ps1       # *** 2–8 hours — run this and wait ***
#   .\scripts\05-build-image.ps1     # Build Alpine Docker images
#   .\scripts\06-validate.ps1        # Verify dotnet works in the images
#
# (04-find-artifact.ps1 is called internally by 05-build-image.ps1)
#
# Usage:
#   cd C:\...\RiscvDotnet
#   .\scripts\run-all.ps1                     # Normal run
#   .\scripts\run-all.ps1 -Clean              # Wipe artifacts first, keep clone
#   .\scripts\run-all.ps1 -Clean -FullClean   # Wipe everything including clone
#
# Override defaults before running:
#   $env:FORK = "my-fork"; $env:BRANCH = "release/10.0"; $env:BRANDING = "release"
#   .\scripts\run-all.ps1
# =============================================================================
param(
    [switch]$Clean,      # Run 00-clean.ps1 before the pipeline (keeps clone)
    [switch]$FullClean   # Run 00-clean.ps1 -Full -Images before the pipeline
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Header([string]$Title) {
    Write-Host ''
    Write-Host ('#' * 64) -ForegroundColor Cyan
    Write-Host "##  $Title" -ForegroundColor Cyan
    Write-Host ('#' * 64) -ForegroundColor Cyan
    Write-Host ''
}

# ── Optional cleanup ──────────────────────────────────────────────────────────
if ($FullClean) {
    Write-Header 'Pre-step — Full clean (artifacts + clone + images)'
    & "$ScriptDir\00-clean.ps1" -Full -Images
} elseif ($Clean) {
    Write-Header 'Pre-step — Clean artifacts + docker context (clone kept)'
    & "$ScriptDir\00-clean.ps1"
}

# ── Main pipeline ─────────────────────────────────────────────────────────────
Write-Header 'Step 1/5 — Clone dotnet VMR'
& "$ScriptDir\01-clone.ps1"

Write-Header 'Step 2/5 — Apply patches'
& "$ScriptDir\02-patch.ps1"

Write-Header 'Step 3/5 — Build SDK (linux-musl-riscv64)'
& "$ScriptDir\03-build-sdk.ps1"

Write-Header 'Step 4/5 — Build Alpine riscv64 Docker images'
& "$ScriptDir\05-build-image.ps1"

Write-Header 'Step 5/5 — Validate images'
& "$ScriptDir\06-validate.ps1"

Write-Host ''
Write-Host ('#' * 64) -ForegroundColor Green
Write-Host '##  Pipeline complete — all steps finished successfully.'   -ForegroundColor Green
Write-Host ('#' * 64) -ForegroundColor Green
