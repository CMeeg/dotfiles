#!/usr/bin/env pwsh

<#
.SYNOPSIS
Automates the Debian setup described in linux/README.md. Idempotent — safe to run multiple times.

.DESCRIPTION
Runs the retire steps, installs the tools, applies the dotfiles with sync.ps1 and runs the setup actions.

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

function Install-Packages {
  Write-Status 'Installing base packages...'
  $packages = 'build-essential', 'curl', 'fonts-jetbrains-mono', 'libnss3-tools', 'jq', 'python-is-python3', 'python3', 'unzip', 'wget'
  # sshd lets the Windows Herdr app reach a WSL distro (see the sshd setup action)
  if (Test-Wsl) { $packages += 'openssh-server' }
  $missing = @($packages | Where-Object { -not (Test-AptInstalled $_) })
  if (-not $missing.Count) {
    Write-Skip 'All base packages are already installed'
    return
  }
  Invoke-Step "sudo apt install -y $($missing -join ' ')"
  Write-Ok 'Base packages installed'
}

function Install-Starship {
  Write-Status 'Installing Starship...'
  if (Test-Command starship) {
    Write-Skip 'Starship is already installed'
    return
  }
  Invoke-Step 'curl -sS https://starship.rs/install.sh | sh -s -- -y'
  Write-Ok 'Starship installed'
}

function Install-Superfile {
  Write-Status 'Installing superfile...'
  if (Test-Command spf) {
    Write-Skip 'superfile is already installed'
    return
  }
  Invoke-Step 'bash -c "$(curl -sLo- https://superfile.dev/install.sh)"'
  Write-Ok "superfile installed (run 'spf' to start)"
}

function Install-Herdr {
  Write-Status 'Installing herdr...'
  if (Test-Command herdr) {
    Write-Skip 'herdr is already installed'
    return
  }
  Invoke-Step 'curl -fsSL https://herdr.dev/install.sh | sh'
  Write-Ok "herdr installed (run 'herdr' to start)"
}

# The Herdr desktop app's runtime. On every Linux machine, not just WSL: any of them can be added as a
# machine in the app.
function Install-HerdrCore {
  Write-Status 'Installing herdr-core...'
  if ([IO.File]::Exists((Get-HerdrCorePath))) {
    Write-Skip 'herdr-core is already installed'
    return
  }
  Invoke-Step 'curl -fsSL https://releases.herdr.dev/core/install.sh | sh'
  Write-Ok 'herdr-core installed'
}

function New-ProjectsDirectory {
  Write-Status 'Creating ~/projects directory...'
  $dir = "$(Get-HomeDir)/projects"
  if ([IO.Directory]::Exists($dir)) {
    Write-Skip '~/projects directory already exists'
    return
  }
  Invoke-Step "mkdir -p $(ConvertTo-ShellArgument $dir)"
  Write-Ok '~/projects directory created'
}

function Install-GitKraken {
  Write-Status 'Installing GitKraken...'
  if (Test-AptInstalled gitkraken) {
    Write-Skip 'GitKraken is already installed'
    return
  }
  Invoke-Step "wget -O /tmp/gitkraken-amd64.deb $GitKrakenDebUrl && sudo apt install -y /tmp/gitkraken-amd64.deb"
  Write-Ok 'GitKraken installed'
  Write-Warn "Run 'gitkraken' and follow setup steps in gitkraken/README.md"
}

function Install-Node {
  Write-Status 'Installing fnm and Node (latest LTS)...'
  if (Test-Command fnm) {
    Write-Skip 'fnm is already installed'
    return
  }
  # --skip-shell: bash/.bashrc (applied by sync) already sets up fnm, so the installer must not append to it
  Invoke-Step 'curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell'
  if (Test-DryRun) {
    Write-Dry 'Add fnm to PATH'
    Write-Dry 'fnm install <latest LTS> && fnm default <latest LTS>'
    Write-Ok 'fnm and Node (latest LTS) installed'
    return
  }
  # This process's PATH doesn't come from .bashrc, so add fnm directly
  $fnmPath = "$(Get-HomeDir)/.local/share/fnm"
  if ([IO.Directory]::Exists($fnmPath)) { $env:PATH = "${fnmPath}:$env:PATH" }
  $lts = Get-LatestNodeLts
  if (-not $lts) {
    Write-Warn "Couldn't find the latest Node LTS — run 'fnm install --lts' later"
    return
  }
  Invoke-Step "fnm install $lts && fnm default $lts"
  Write-Ok "fnm and Node $lts installed"
}

function Install-Chrome {
  Write-Status 'Installing Google Chrome...'
  if (Test-AptInstalled google-chrome-stable) {
    Write-Skip 'Google Chrome is already installed'
    return
  }
  Invoke-Step 'wget -O /tmp/google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo apt install -y /tmp/google-chrome-stable_current_amd64.deb'
  Write-Ok 'Google Chrome installed'
}

function Test-SystemdUnit {
  param([string]$Check, [string]$Unit)
  $PSNativeCommandUseErrorActionPreference = $false
  systemctl $Check --quiet $Unit 2>$null
  $LASTEXITCODE -eq 0
}

function Install-Caddy {
  Write-Status 'Installing Caddy...'
  $justInstalled = $false
  if (Test-AptInstalled caddy) {
    Write-Skip 'Caddy is already installed'
  } else {
    # Adds Caddy's apt repo so 'apt upgrade' keeps it updated
    Invoke-Step 'sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl'
    Invoke-Step "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg"
    Invoke-Step "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null"
    Invoke-Step 'sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list'
    Invoke-Step 'sudo apt update'
    Invoke-Step 'sudo apt install -y caddy'
    Write-Ok 'Caddy installed'
    $justInstalled = $true
  }

  # The package starts a 'caddy' systemd service serving a default page on :80,
  # which blocks projects running 'caddy run' themselves. Upgrades keep it disabled.
  if ($justInstalled -or (Test-SystemdUnit is-enabled caddy) -or (Test-SystemdUnit is-active caddy)) {
    Invoke-Step 'sudo systemctl disable --now caddy'
    Write-Ok 'Caddy systemd service disabled'
  } else {
    Write-Skip 'Caddy systemd service is already disabled'
  }
}

function Enable-UnprivilegedLowPorts {
  Write-Status 'Allowing unprivileged processes to bind ports 80 and above...'
  # Lets 'caddy run' (or any dev server) bind 80/443 without root. Unlike setcap,
  # this survives binary upgrades. Fine for a dev machine.
  $conf = '/etc/sysctl.d/50-unprivileged-ports.conf'
  $setting = 'net.ipv4.ip_unprivileged_port_start=80'
  if ([IO.File]::Exists($conf) -and ([IO.File]::ReadAllLines($conf) -ccontains $setting)) {
    Write-Skip 'Unprivileged port start is already set to 80'
    return
  }
  Invoke-Step "echo '$setting' | sudo tee $conf >/dev/null"
  Invoke-Step 'sudo sysctl --system >/dev/null'
  Write-Ok 'Unprivileged port start set to 80'
}

function Install-Aspire {
  Write-Status 'Installing Aspire CLI...'
  # Only the install script's location counts, so every machine installs Aspire the same way
  # (a .NET global tool install is removed by the retire steps)
  if ([IO.File]::Exists("$(Get-HomeDir)/.aspire/bin/aspire")) {
    Write-Skip 'Aspire CLI is already installed'
    return
  }
  # --skip-path: ~/.bashrc is managed by sync, so PATH is set there instead of letting the installer append to it
  Invoke-Step 'curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path'
  Write-Ok 'Aspire CLI installed'
}

function Test-OpencodeV2 {
  if (-not (Test-Command opencode)) { return $false }
  $PSNativeCommandUseErrorActionPreference = $false
  # Anchored to the start of the version ("opencode v2.2.6"), so the "2." in "v1.12.0" doesn't count
  [bool]((opencode --version 2>$null) -match '(^|\s)v?2\.')
}

function Install-Opencode {
  Write-Status 'Installing opencode...'
  if (Test-OpencodeV2) {
    Write-Skip 'opencode v2 is already installed'
    return
  }
  if (Test-Command opencode) {
    Write-Warn 'opencode v1 detected — the installer will replace it with v2'
  }
  Invoke-Step 'curl -fsSL https://opencode.ai/v2/install | bash'
  Write-Ok 'opencode installed'
}

function Install-ClaudeCode {
  Write-Status 'Installing Claude Code...'
  if (Test-Command claude) {
    Write-Skip 'Claude Code is already installed'
    return
  }
  Invoke-Step 'curl -fsSL https://claude.ai/install.sh | bash'
  Write-Ok 'Claude Code installed'
  Write-Warn "Run 'claude' and follow the sign-in steps — see claude/README.md"
}

# Runs in this terminal, not redirected, so sync can prompt. With no state yet, the first apply backs up
# files that differ from the repo (e.g. Debian's default ~/.bashrc) and replaces them.
function Sync-Dotfiles {
  # A dry run of retire leaves the stow links in place, and sync refuses to write through them.
  if ((Test-DryRun) -and (Test-StowLinksPresent)) {
    Write-Status 'Syncing dotfiles...'
    Write-Skip "Can't preview sync while stow links remain — run ./retire.ps1, then ./sync.ps1 -WhatIf"
    return
  }
  $arguments = @('-NoPull')
  if (-not [IO.Directory]::Exists((Get-StateDir))) { $arguments += '-InitialApply' }
  if (Test-DryRun) { $arguments += '-WhatIf' }
  & pwsh -NoProfile -File "$PSScriptRoot/sync.ps1" @arguments
  if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Dotfiles sync stopped — resolve the problem above, then run ./sync.ps1'
  }
}

# ---------- Main ----------

Write-Host ''
Write-Host "`e[1mdotfiles installer`e[0m"
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
  Install-Packages
  Install-Starship
  Install-Superfile
  Install-Herdr
  Install-HerdrCore
  New-ProjectsDirectory
  Install-GitKraken
  Install-Node
  Install-Chrome
  Install-Caddy
  Enable-UnprivilegedLowPorts
  Install-Aspire
  Install-Opencode
  Install-ClaudeCode
  Sync-Dotfiles
  Invoke-SetupActions
} catch {
  Write-StopReason $_
  exit 1
}

Write-Host ''
Write-Host "`e[0;32m✨ `e[1mDone.`e[0m"
# This script's environment doesn't reach the user's shell, so they reload it to pick up aliases, fnm PATH,
# starship, etc.
Write-Host "`e[1m  → Run 'source ~/.bashrc' to reload your shell.`e[0m"
exit 0
