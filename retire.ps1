#!/usr/bin/env pwsh
# Removes tools and files this repo no longer installs or manages, including the move off stow. Safe to run
# again: each step skips when there's nothing to remove.
[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/lib/Common.psm1"
Import-Module "$PSScriptRoot/lib/Retire.psm1"

Set-DryRun ([bool]$WhatIfPreference)
# -WhatIf would otherwise reach the cmdlets inside the modules. The modules check the dry-run flag instead.
$WhatIfPreference = $false
if (Test-DryRun) { Write-Host "`e[0;34mDry-run mode — no changes will be made`e[0m" }

try {
  Invoke-RetireSteps
} catch {
  Write-Warn $_.Exception.Message
  exit 1
}
exit 0
