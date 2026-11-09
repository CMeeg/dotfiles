Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"

# The last-applied copies mirror target paths relative to home, so targets must be under home.

$script:BackupStamp = $null

function Get-HomeRelativePath {
  param([Parameter(Mandatory)][string]$Target)
  $homeDir = (Get-HomeDir).TrimEnd('/')
  if (-not $Target.StartsWith("$homeDir/", [StringComparison]::Ordinal)) {
    throw "$Target is outside the home folder $homeDir"
  }
  $Target.Substring($homeDir.Length + 1)
}

function Get-AppliedRoot { "$(Get-StateDir)/applied" }

function Get-AppliedPath {
  [OutputType([string])]
  param([Parameter(Mandatory)][string]$Target)
  "$(Get-AppliedRoot)/$(Get-HomeRelativePath $Target)"
}

function Read-Applied {
  param([Parameter(Mandatory)][string]$Target)
  Read-TextFile (Get-AppliedPath $Target)
}

function Write-Applied {
  param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][AllowEmptyString()][string]$Content)
  Write-TextFile (Get-AppliedPath $Target) $Content
}

# Deletes the state file at $Path and any folders it leaves empty, up to $Root.
function Remove-StateFile {
  param([string]$Path, [string]$Root)
  if ([IO.File]::Exists($Path)) { [IO.File]::Delete($Path) }
  $dir = [IO.Path]::GetDirectoryName($Path)
  while ($dir.Length -gt $Root.Length -and [IO.Directory]::Exists($dir) -and
    -not [IO.Directory]::EnumerateFileSystemEntries($dir).GetEnumerator().MoveNext()) {
    [IO.Directory]::Delete($dir)
    $dir = [IO.Path]::GetDirectoryName($dir)
  }
}

# Removes the applied copy and any folders it leaves empty. Does nothing in dry-run.
function Remove-Applied {
  param([Parameter(Mandatory)][string]$Target)
  if (Test-DryRun) { return }
  Remove-StateFile (Get-AppliedPath $Target) (Get-AppliedRoot)
}

function Get-AppliedTargets {
  [OutputType([string[]])]
  param()
  $root = Get-AppliedRoot
  if (-not [IO.Directory]::Exists($root)) { return @() }
  $homeDir = (Get-HomeDir).TrimEnd('/')
  foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
    "$homeDir/$($file.FullName.Substring($root.Length + 1))"
  }
}

# A local change the user chose to ignore is remembered by the hash of the live file, in
# <state>/ignored/<path under home>, until the file changes.
function Get-IgnoredRoot { "$(Get-StateDir)/ignored" }

function Read-IgnoredHash {
  param([Parameter(Mandatory)][string]$Target)
  $text = Read-TextFile "$(Get-IgnoredRoot)/$(Get-HomeRelativePath $Target)"
  if ($null -ne $text) { $text.Trim() }
}

function Write-IgnoredHash {
  param([Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$Hash)
  Write-TextFile "$(Get-IgnoredRoot)/$(Get-HomeRelativePath $Target)" "$Hash`n"
}

# Does nothing in dry-run.
function Remove-IgnoredHash {
  param([Parameter(Mandatory)][string]$Target)
  if (Test-DryRun) { return }
  Remove-StateFile "$(Get-IgnoredRoot)/$(Get-HomeRelativePath $Target)" (Get-IgnoredRoot)
}

function Get-IgnoredTargets {
  [OutputType([string[]])]
  param()
  $root = Get-IgnoredRoot
  if (-not [IO.Directory]::Exists($root)) { return @() }
  $homeDir = (Get-HomeDir).TrimEnd('/')
  foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
    "$homeDir/$($file.FullName.Substring($root.Length + 1))"
  }
}

# Copies the live file to <state>/backup/<run timestamp>/<path under home> and returns that path.
# In dry-run it only returns the path.
function Backup-LiveFile {
  [OutputType([string])]
  param([Parameter(Mandatory)][string]$Target)
  if (-not $script:BackupStamp) { $script:BackupStamp = Get-Date -Format 'yyyyMMdd-HHmmss' }
  $backup = "$(Get-StateDir)/backup/$($script:BackupStamp)/$(Get-HomeRelativePath $Target)"
  if (-not (Test-DryRun)) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
    [IO.File]::Copy($Target, $backup, $true)
  }
  $backup
}

Export-ModuleMember -Function Get-AppliedPath, Read-Applied, Write-Applied, Remove-Applied, Get-AppliedTargets, Backup-LiveFile,
  Read-IgnoredHash, Write-IgnoredHash, Remove-IgnoredHash, Get-IgnoredTargets
