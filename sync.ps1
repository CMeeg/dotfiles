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

Import-Module "$PSScriptRoot/lib/Common.psm1"
Import-Module "$PSScriptRoot/lib/Sync.psm1"

Set-DryRun ([bool]$WhatIfPreference)
# -WhatIf would otherwise reach the cmdlets inside the modules, skipping temp-file cleanup and printing
# "What if:" lines. The modules check the dry-run flag instead.
$WhatIfPreference = $false
if (Test-DryRun) { Write-Host "`e[0;34mDry-run mode — no changes will be made`e[0m" }

try {
  # A pull that fails or leaves a git conflict stops sync before any live file is touched.
  if (-not $NoPull -and -not (Invoke-RepoPull (Get-RepoDir))) { exit 1 }
  $summary = Invoke-Sync -NoPrompt:$NoPrompt -InitialApply:$InitialApply -CopyBack:$CopyBack
  Show-SyncSummary $summary
} catch {
  Write-Warn $_.Exception.Message
  exit 1
}
exit 0
