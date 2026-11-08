#!/usr/bin/env pwsh

<#
.SYNOPSIS
Automates the update steps described in linux/README.md. Idempotent — safe to run multiple times.

.DESCRIPTION
Runs the retire steps, updates the tools, pulls and syncs the dotfiles with sync.ps1 and runs the setup
actions.

.PARAMETER SkipRetire
Skips the retire steps, including the move off stow.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$SkipRetire)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/lib/Common.psm1"
Import-Module "$PSScriptRoot/lib/Tools.psm1"
Import-Module "$PSScriptRoot/lib/Retire.psm1"
Import-Module "$PSScriptRoot/lib/Setup.psm1"

Set-DryRun ([bool]$WhatIfPreference)
# -WhatIf would otherwise reach the cmdlets inside the modules. The modules check the dry-run flag instead.
$WhatIfPreference = $false

# ---------- Sections ----------

function Update-System {
  Write-Status 'Updating system packages...'
  Invoke-Step 'sudo apt update'
  Invoke-Step 'sudo apt upgrade -y'
  Write-Ok 'System packages updated'
}

function Update-GitKraken {
  Write-Status 'Updating GitKraken...'
  if (-not (Test-AptInstalled gitkraken)) {
    Write-Skip 'GitKraken is not installed — skipping'
    return
  }
  # Read-only lookup (one small request), so it runs in dry-run too
  $PSNativeCommandUseErrorActionPreference = $false
  $installed = dpkg-query -W -f='${Version}' gitkraken 2>$null
  $latest = Get-GitKrakenLatestVersion
  if (-not $latest) {
    Write-Warn "Couldn't work out the latest GitKraken version — skipping"
    return
  }
  if (-not (Test-GitKrakenNeedsUpdate ([string]$installed) $latest)) {
    Write-Skip "GitKraken is already up to date ($latest)"
    return
  }
  Invoke-Step "wget -O /tmp/gitkraken-amd64.deb $GitKrakenDebUrl && sudo apt install -y /tmp/gitkraken-amd64.deb"
  Write-Ok "GitKraken updated to $latest"
}

function Update-Node {
  Write-Status 'Updating fnm and Node (latest LTS)...'
  if (-not (Test-Command fnm)) {
    Write-Skip 'fnm is not installed — skipping'
    return
  }
  # fnm has no self-update command; re-running the installer updates the binary.
  # --skip-shell: bash/.bashrc (applied by sync) already sets up fnm
  Invoke-Step 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell'
  Write-Ok 'fnm updated'

  # Read-only lookups, so they run in dry-run too
  $lts = Get-LatestNodeLts
  if (-not $lts) {
    Write-Warn "Couldn't find the latest Node LTS — skipping"
    return
  }
  if ((Get-FnmDefault) -eq $lts) {
    Write-Skip "Node $lts (latest LTS) is already the default"
    return
  }
  Invoke-Step "fnm install $lts && fnm default $lts"
  Write-Ok "Node $lts (latest LTS) is now the default — older versions are still installed"
}

function Update-Starship {
  Write-Status 'Updating Starship...'
  if (-not (Test-Command starship)) {
    Write-Skip 'Starship is not installed — skipping'
    return
  }
  Invoke-Step 'curl -sS https://starship.rs/install.sh | sh -s -- -y'
  Write-Ok 'Starship updated'
}

function Update-Superfile {
  Write-Status 'Updating superfile...'
  if (-not (Test-Command spf)) {
    Write-Skip 'superfile is not installed — skipping'
    return
  }
  Invoke-Step 'bash -c "$(curl -sLo- https://superfile.dev/install.sh)"'
  Write-Ok 'superfile updated'
}

function Update-Herdr {
  Write-Status 'Updating herdr...'
  if (-not (Test-Command herdr)) {
    Write-Skip 'herdr is not installed — skipping'
    return
  }
  # herdr refuses to update from inside one of its own sessions
  if ($env:HERDR_PANE_ID) {
    Write-Warn "Running inside a herdr session — skipping (detach and run 'herdr update')"
    return
  }
  Invoke-Step 'herdr update'
  Write-Ok 'herdr updated'
}

function Update-Aspire {
  Write-Status 'Updating Aspire CLI...'
  if (-not [IO.File]::Exists("$(Get-HomeDir)/.aspire/bin/aspire")) {
    Write-Skip 'Aspire CLI is not installed — skipping (run ./install.ps1 to install it)'
    return
  }
  # Re-running the installer fetches the latest stable release
  Invoke-Step 'curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path'
  Write-Ok 'Aspire CLI updated'
}

function Update-Opencode {
  Write-Status 'Updating OpenCode...'
  if (-not (Test-Command opencode)) {
    Write-Skip 'OpenCode is not installed — skipping'
    return
  }
  Invoke-Step 'opencode upgrade'
  Write-Ok 'OpenCode updated'
}

function Update-ClaudeCode {
  Write-Status 'Updating Claude Code...'
  if (-not (Test-Command claude)) {
    Write-Skip 'Claude Code is not installed — skipping'
    return
  }
  Invoke-Step 'claude update'
  Write-Ok 'Claude Code updated'
}

# Pulls and applies the dotfiles. Runs in this terminal, not redirected, so sync can prompt.
function Sync-Dotfiles {
  # A dry run of retire leaves the stow links in place, and sync refuses to write through them.
  if ((Test-DryRun) -and (Test-StowLinksPresent)) {
    Write-Status 'Syncing dotfiles...'
    Write-Skip "Can't preview sync while stow links remain — run ./retire.ps1, then ./sync.ps1 -WhatIf"
    return
  }
  $arguments = @()
  if (Test-DryRun) { $arguments += '-WhatIf' }
  & pwsh -NoProfile -File "$PSScriptRoot/sync.ps1" @arguments
  if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Dotfiles sync stopped — resolve the problem above, then run ./sync.ps1'
  }
}

# ---------- Main ----------

Write-Host ''
Write-Host "`e[1mdotfiles updater`e[0m"
if (Test-DryRun) { Write-Host "`e[0;34mDry-run mode — no changes will be made`e[0m" }
Write-Host ''

try {
  Start-SudoKeepAlive

  if ($SkipRetire) {
    Write-Skip 'Skipping retire steps (-SkipRetire)'
    if (Test-StowLinksPresent) {
      Write-Warn 'Stow links into the repo are still present — sync will stop until ./retire.ps1 has run'
    }
  } else {
    Invoke-RetireSteps
  }
  Update-System
  Update-GitKraken
  Update-Node
  Update-Starship
  Update-Superfile
  Update-Herdr
  Update-Aspire
  Update-Opencode
  Update-ClaudeCode
  Sync-Dotfiles
  Invoke-SetupActions
} catch {
  Write-StopReason $_
  exit 1
}

Write-Host ''
Write-Host "`e[0;32m✨ `e[1mDone.`e[0m"
Write-Host "`e[1m  → Run 'source ~/.bashrc' to reload your shell.`e[0m"
exit 0
