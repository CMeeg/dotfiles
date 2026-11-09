#!/usr/bin/env pwsh
# Applies the repo's dotfiles to this machine and reports local changes. Conflicts and local changes are
# reported, not failures: the exit code is 1 only when sync stops on an error.
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$NoPull,
  [switch]$NoPrompt,
  [switch]$InitialApply,
  # Copies every local change and new local file back into the repo without asking.
  [switch]$CopyBack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The repo is this script's own clone unless DOTFILES_REPO says otherwise; the modules read it from there.
if (-not $env:DOTFILES_REPO) { $env:DOTFILES_REPO = $PSScriptRoot }

Import-Module "$PSScriptRoot/lib/Common.psm1"
Import-Module "$PSScriptRoot/lib/Sync.psm1"

Set-DryRun ([bool]$WhatIfPreference)
# -WhatIf would otherwise reach the cmdlets inside the modules, skipping temp-file cleanup and printing
# "What if:" lines. The modules check the dry-run flag instead.
$WhatIfPreference = $false
if (Test-DryRun) { Write-Host "`e[0;34mDry-run mode — no changes will be made`e[0m" }

try {
  $repoDir = Get-RepoDir
  if (-not (Test-Path -LiteralPath (Join-Path $repoDir '.git'))) {
    Write-Warn "Dotfiles repo not found at $repoDir"
    exit 1
  }
  # A pull that fails or leaves a git conflict stops sync before any live file is touched.
  if (-not $NoPull) {
    Update-CommittedBases
    if (-not (Invoke-RepoPull (Get-RepoDir))) { exit 1 }
  }
  $summary = Invoke-Sync -NoPrompt:$NoPrompt -InitialApply:$InitialApply -CopyBack:$CopyBack
  Show-SyncSummary $summary
} catch {
  Write-StopReason $_
  exit 1
}
exit 0
