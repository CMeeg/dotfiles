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

$script:Utf8 = [Text.UTF8Encoding]::new($false)

# Reads a file as UTF-8, byte for byte: no BOM stripping, no line-ending changes. $null if the file is missing.
function Read-TextFile {
  param([Parameter(Mandatory)][string]$Path)
  if (-not [IO.File]::Exists($Path)) { return $null }
  $script:Utf8.GetString([IO.File]::ReadAllBytes($Path))
}

# Writes UTF-8 without a BOM, exactly as given, creating parent folders. Does nothing in dry-run, so callers
# print their own dry-run line. An existing file keeps its mode.
function Write-TextFile {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
  if (Test-DryRun) { return }
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
  [IO.File]::WriteAllBytes($Path, $script:Utf8.GetBytes($Content))
}

# The absolute path a symlink points to, resolved against the link's folder (it may not exist), or $null
# if $Path isn't a symlink.
function Resolve-LinkTarget {
  [OutputType([string])]
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.LinkTarget) { return $null }
  $destination = $item.LinkTarget
  if (-not [IO.Path]::IsPathRooted($destination)) {
    $destination = Join-Path ([IO.Path]::GetDirectoryName($Path)) $destination
  }
  [IO.Path]::GetFullPath($destination)
}

# True if $Path is a symlink that points inside $Directory.
function Test-LinkInto {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory)
  $destination = Resolve-LinkTarget $Path
  if (-not $destination) { return $false }
  $prefix = [IO.Path]::GetFullPath($Directory).TrimEnd('/') + '/'
  $destination.StartsWith($prefix, [StringComparison]::Ordinal)
}

# Quotes a value for a bash command line run by Invoke-Step.
function ConvertTo-ShellArgument {
  [OutputType([string])]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
  "'" + $Value.Replace("'", "'\''") + "'"
}

function Test-Command {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Name)
  [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Export-ModuleMember -Function Get-HomeDir, Get-RepoDir, Get-StateDir, Resolve-TargetPath, Set-DryRun, Test-DryRun,
  Write-Status, Write-Ok, Write-Skip, Write-Warn, Write-Dry, Invoke-Step, Read-TextFile, Write-TextFile, Resolve-LinkTarget,
  Test-LinkInto, ConvertTo-ShellArgument, Test-Command
