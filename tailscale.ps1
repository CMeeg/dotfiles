#!/usr/bin/env pwsh

<#
.SYNOPSIS
Opt-in: installs Tailscale on this Linux machine or WSL distro and turns on Tailscale SSH, as described in
tailscale/README.md. Idempotent — safe to run multiple times.

.DESCRIPTION
Installs Tailscale from its apt repo (update.ps1's apt upgrade then keeps it up to date), enables tailscaled,
and logs in with Tailscale SSH on and you as the operator (so 'tailscale serve' works without sudo). In WSL,
DNS is left to Windows. Once logged in, a re-run brings those settings back if they changed.

The first login opens a link to sign in, unless TS_AUTHKEY holds an auth key (e.g. exported from ~/.secrets).

.PARAMETER Hostname
The device's name on your tailnet (e.g. meeg-laptop-wsl). Needed for the first login; on a re-run it renames
the device, and leaving it out keeps the current name.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  # Options = 'None' makes the match case-sensitive: Tailscale lower-cases names, so capitals wouldn't match later.
  [ValidatePattern('^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$', Options = 'None')]
  [string]$Hostname
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:DOTFILES_REPO) { $env:DOTFILES_REPO = $PSScriptRoot }

Import-Module "$PSScriptRoot/lib/Common.psm1"
Import-Module "$PSScriptRoot/lib/Tailscale.psm1"

Set-DryRun ([bool]$WhatIfPreference)
# -WhatIf would otherwise reach the cmdlets inside the modules. The modules check the dry-run flag instead.
$WhatIfPreference = $false

Write-Host ''
Write-Host "`e[1mTailscale setup`e[0m"
if (Test-DryRun) { Write-Host "`e[0;34mDry-run mode — no changes will be made`e[0m" }
Write-Host ''

if (-not $IsLinux) {
  Write-Warn 'This script is for Linux and WSL — on Windows, follow the steps in tailscale/README.md'
  exit 1
}

try {
  Start-SudoKeepAlive
  Invoke-TailscaleSetup $Hostname
} catch {
  Write-StopReason $_
  exit 1
}

Write-Host ''
Write-Host "`e[0;32m✨ `e[1mDone.`e[0m See tailscale/README.md for the admin console and phone steps."
exit 0
