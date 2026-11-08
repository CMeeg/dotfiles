Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Paths read from $env:HOME rather than PowerShell's $HOME, which doesn't follow later changes to the variable.

$script:DryRun = $false

function Get-HomeDir {
  [OutputType([string])]
  param()
  $env:HOME
}

function Get-RepoDir {
  [OutputType([string])]
  param()
  if ($env:DOTFILES_REPO) { return $env:DOTFILES_REPO }
  "$(Get-HomeDir)/.dotfiles"
}

function Get-StateDir {
  [OutputType([string])]
  param()
  if ($env:DOTFILES_STATE) { return $env:DOTFILES_STATE }
  "$(Get-HomeDir)/.local/state/dotfiles"
}

function Resolve-TargetPath {
  [OutputType([string])]
  param([Parameter(Mandatory)][string]$Path)
  if ($Path -eq '~' -or $Path.StartsWith('~/')) {
    $Path = (Get-HomeDir) + $Path.Substring(1)
  }
  [Environment]::ExpandEnvironmentVariables($Path)
}

function Set-DryRun {
  param([Parameter(Mandatory)][bool]$Enabled)
  $script:DryRun = $Enabled
}

function Test-DryRun {
  [OutputType([bool])]
  param()
  $script:DryRun
}

# The same escape codes as the bash scripts (bold yellow has no -ForegroundColor equivalent).
function Write-Coloured {
  param([string]$Code, [string]$Text)
  Write-Host "`e[${Code}m$Text`e[0m"
}

function Write-Status { param([string]$Message) Write-Coloured '0;36' "• $Message" }
function Write-Ok { param([string]$Message) Write-Coloured '0;32' "  ✓ $Message" }
function Write-Skip { param([string]$Message) Write-Coloured '1;33' "  - $Message" }
function Write-Warn { param([string]$Message) Write-Coloured '1;33' "  ! $Message" }
function Write-Dry { param([string]$Message) Write-Coloured '0;34' "  ~ $Message" }

function Invoke-Step {
  param([Parameter(Mandatory)][string]$Command)
  if (Test-DryRun) {
    Write-Dry $Command
    return
  }
  # The exit code is checked below, so a non-zero exit mustn't throw first and skip the warning.
  $PSNativeCommandUseErrorActionPreference = $false
  # pipefail: a failed download in 'curl … | sh' must fail the step, not pass it
  & bash -o pipefail -c $Command
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    $message = "Command failed (exit code $exitCode): $Command"
    Write-Warn $message
    throw $message
  }
}

function Test-Command {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Name)
  [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Export-ModuleMember -Function Get-HomeDir, Get-RepoDir, Get-StateDir, Resolve-TargetPath, Set-DryRun, Test-DryRun,
  Write-Status, Write-Ok, Write-Skip, Write-Warn, Write-Dry, Invoke-Step, Test-Command
