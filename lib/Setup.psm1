Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"
Import-Module "$PSScriptRoot/Tools.psm1"

# Setup actions: configuration that tools write themselves, run after sync by install.ps1 and update.ps1.
# Each one is idempotent.

# The live config file each agent's herdr integration writes to, and the text that shows it's there.
# herdr's own status only checks its plugin files, so a config that lost its entry (e.g. replaced by
# sync) still reports "current".
$script:HerdrAgentConfig = @{
  claude = @{ Path = '.claude/settings.json'; Marker = 'herdr-agent-state.sh' }
  opencode = @{ Path = '.config/opencode/cli.json'; Marker = 'herdr-opencode' }
}

function Invoke-HerdrIntegration {
  param([Parameter(Mandatory)][ValidateSet('claude', 'opencode')][string]$Agent)
  if (-not (Test-Command herdr)) {
    Write-Skip "herdr is not installed — skipping its $Agent integration"
    return
  }
  if (-not (Test-Command $Agent)) {
    Write-Skip "$Agent is not installed — skipping its herdr integration"
    return
  }

  $PSNativeCommandUseErrorActionPreference = $false
  $status = @(herdr integration status 2>$null)
  $current = [bool]($status | Where-Object { $_ -match "^${Agent}: current\b" })
  $config = $script:HerdrAgentConfig[$Agent]
  $configText = Read-TextFile "$(Get-HomeDir)/$($config.Path)"
  $referenced = $null -ne $configText -and $configText.Contains($config.Marker)
  if ($current -and $referenced) {
    Write-Skip "herdr's $Agent integration is already installed"
    return
  }
  Invoke-Step "herdr integration install $Agent"
  Write-Ok "herdr's $Agent integration installed"
}

function Get-SystemdState {
  param([string]$Check, [string]$Unit)
  $PSNativeCommandUseErrorActionPreference = $false
  "$(systemctl $Check $Unit 2>$null)".Trim()
}

# Runs sshd on 127.0.0.1:2222 so the Windows Herdr app can reach this WSL distro. A failure warns instead
# of throwing: WSL distros share one network, so a second distro can't take the port, and install or
# update should carry on. A config that fails 'sshd -t' is never loaded.
function Invoke-WslSshd {
  param(
    [string]$ConfigDir = '/etc/ssh/sshd_config.d',
    [string]$SshdPath = '/usr/sbin/sshd'
  )
  if (-not (Test-Wsl)) {
    Write-Skip 'Not WSL — skipping sshd for the Herdr app'
    return
  }
  if (-not [IO.File]::Exists($SshdPath)) {
    Write-Warn "openssh-server isn't installed — run ./install.ps1"
    return
  }

  $source = "$(Get-RepoDir)/linux/sshd_config.d/herdr-wsl.conf"
  $target = "$ConfigDir/herdr-wsl.conf"
  $installed = Read-TextFile $target
  if ($null -ne $installed -and $installed -ceq (Read-TextFile $source) -and
    (Get-SystemdState is-enabled ssh) -eq 'enabled' -and (Get-SystemdState is-active ssh) -eq 'active') {
    Write-Skip 'sshd for the Herdr app is already set up'
  } else {
    try {
      Invoke-Step "sudo install -m 644 $(ConvertTo-ShellArgument $source) $(ConvertTo-ShellArgument $target)"
      Invoke-Step 'sudo sshd -t'
      Invoke-Step 'sudo systemctl enable ssh'
      Invoke-Step 'sudo systemctl restart ssh'
    } catch {
      Write-Warn "sshd setup failed — check 'sudo journalctl -u ssh -n 20'; port 2222 may be used by another WSL distro (they share one network)"
      return
    }
    Write-Ok 'sshd for the Herdr app set up on 127.0.0.1:2222'
  }

  $keys = Read-TextFile "$(Get-HomeDir)/.ssh/authorized_keys"
  if ($null -eq $keys -or $keys -notmatch '(?m)^ssh-') {
    Write-Warn 'No keys in ~/.ssh/authorized_keys — add the Windows key (see windows/README.md)'
  }
}

function Invoke-SetupActions {
  Write-Status 'Running setup actions...'
  Invoke-HerdrIntegration claude
  Invoke-HerdrIntegration opencode
  Invoke-WslSshd
}

Export-ModuleMember -Function Invoke-HerdrIntegration, Invoke-WslSshd, Invoke-SetupActions
