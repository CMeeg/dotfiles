#!/usr/bin/env pwsh
# Applies the repo's dotfiles to this machine and reports local changes. Conflicts and local changes are
# reported, not failures: the exit code is 1 only when sync stops on an error.
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$NoPull,
  [switch]$NoPrompt,
  [switch]$InitialApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/lib/Common.psm1"
Import-Module "$PSScriptRoot/lib/Sync.psm1"

Set-DryRun ([bool]$WhatIfPreference)
if (Test-DryRun) { Write-Host "`e[0;34mDry-run mode — no changes will be made`e[0m" }

try {
  $summary = Invoke-Sync -NoPrompt:$NoPrompt -InitialApply:$InitialApply
  Show-SyncSummary $summary
} catch {
  Write-Warn $_.Exception.Message
  exit 1
}
exit 0
