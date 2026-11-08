Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"

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

function Invoke-SetupActions {
  Write-Status 'Running setup actions...'
  Invoke-HerdrIntegration claude
  Invoke-HerdrIntegration opencode
}

Export-ModuleMember -Function Invoke-HerdrIntegration, Invoke-SetupActions
