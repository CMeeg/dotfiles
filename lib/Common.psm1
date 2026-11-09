Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Paths read from $env:HOME rather than PowerShell's $HOME, which doesn't follow later changes to the variable.

$script:DryRun = $false

function Get-HomeDir {
  [OutputType([string])]
  param()
  $env:HOME
}

# The repo's physical path (links resolved), so it reads the same however the clone was reached; @DOTFILES@
# and the stow-link checks depend on that.
function Get-RepoDir {
  [OutputType([string])]
  param()
  $repo = if ($env:DOTFILES_REPO) { $env:DOTFILES_REPO } else { "$(Get-HomeDir)/.dotfiles" }
  Resolve-PhysicalPath $repo
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
    # The id lets scripts tell this already-reported failure apart (see Write-StopReason).
    Write-Error -Message $message -ErrorId 'StepFailed' -Category InvalidResult -ErrorAction Stop
  }
}

# Prints why a script stopped, unless Invoke-Step already did.
function Write-StopReason {
  param([Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord)
  if ($ErrorRecord.FullyQualifiedErrorId -notlike 'StepFailed*') { Write-Warn $ErrorRecord.Exception.Message }
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

# $Path with every link along it resolved, like realpath. The part from the first missing folder on is kept
# as written.
function Resolve-PhysicalPath {
  [OutputType([string])]
  param([Parameter(Mandatory)][string]$Path, [int]$Depth = 0)
  if ($Depth -gt 40) { throw "Too many levels of symbolic links: $Path" }
  $parts = [IO.Path]::GetFullPath($Path).Split('/', [StringSplitOptions]::RemoveEmptyEntries)
  $current = ''
  for ($i = 0; $i -lt $parts.Count; $i++) {
    $next = "$current/$($parts[$i])"
    $target = Resolve-LinkTarget $next
    if ($target) {
      $next = Resolve-PhysicalPath $target ($Depth + 1)
    } elseif (-not (Test-Path -LiteralPath $next)) {
      return (@($next) + @($parts | Select-Object -Skip ($i + 1))) -join '/'
    }
    $current = $next
  }
  if ($current) { $current } else { '/' }
}

# True if $Path is a symlink that points inside $Directory. Both are compared with links resolved, so a link to
# a linked clone's real path still counts.
function Test-LinkInto {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory)
  $destination = Resolve-LinkTarget $Path
  if (-not $destination) { return $false }
  $prefix = (Resolve-PhysicalPath $Directory).TrimEnd('/') + '/'
  (Resolve-PhysicalPath $destination).StartsWith($prefix, [StringComparison]::Ordinal)
}

# Quotes a value for a bash command line run by Invoke-Step.
function ConvertTo-ShellArgument {
  [OutputType([string])]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
  "'" + $Value.Replace("'", "'\''") + "'"
}

# Asks for the sudo password once, then refreshes the credentials every 60 seconds in the background until
# this PowerShell process exits. Does nothing in dry-run.
function Start-SudoKeepAlive {
  if (Test-DryRun) { return }
  $PSNativeCommandUseErrorActionPreference = $false
  sudo -v
  if ($LASTEXITCODE -ne 0) { throw 'sudo -v failed' }
  $start = [Diagnostics.ProcessStartInfo]::new('bash')
  $start.ArgumentList.Add('-c')
  $start.ArgumentList.Add("while kill -0 $PID 2>/dev/null; do sudo -n true; sleep 60; done >/dev/null 2>&1")
  $start.UseShellExecute = $false
  [void][Diagnostics.Process]::Start($start)
}

# Puts $Directory first on this process's PATH unless it's already there. Installers often put tools in
# folders a fresh login doesn't have on PATH yet, and later steps need to find them.
function Add-PathEntry {
  param([Parameter(Mandatory)][string]$Directory)
  $separator = [IO.Path]::PathSeparator
  if (($env:PATH -split [regex]::Escape($separator)) -ccontains $Directory) { return }
  $env:PATH = "$Directory$separator$env:PATH"
}

function Test-Command {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Name)
  [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Export-ModuleMember -Function Get-HomeDir, Get-RepoDir, Get-StateDir, Resolve-TargetPath, Set-DryRun, Test-DryRun,
  Write-Status, Write-Ok, Write-Skip, Write-Warn, Write-Dry, Invoke-Step, Write-StopReason, Read-TextFile, Write-TextFile, Resolve-LinkTarget, Resolve-PhysicalPath,
  Test-LinkInto, ConvertTo-ShellArgument, Start-SudoKeepAlive, Add-PathEntry, Test-Command
