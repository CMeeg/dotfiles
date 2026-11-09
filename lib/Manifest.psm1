Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"

# The manifest key that holds this OS's target path.
function Get-OsKey {
  if ($IsWindows) { return 'windows' }
  if ($IsMacOS) { return 'macos' }
  'linux'
}

# Manifest entries that have a target for this OS, with the target resolved.
function Get-ManifestEntries {
  param([Parameter(Mandatory)][string]$RepoDir)
  $manifest = Get-Content -Raw -Path (Join-Path $RepoDir 'dotfiles.json') | ConvertFrom-Json
  $osKey = Get-OsKey
  foreach ($entry in $manifest.entries) {
    $target = $entry.PSObject.Properties[$osKey]
    if (-not $target) { continue }
    $exclude = $entry.PSObject.Properties['exclude']
    [pscustomobject]@{
      Source = $entry.source
      Target = Resolve-TargetPath $target.Value
      Exclude = [string[]]@(if ($exclude) { $exclude.Value })
      IsDirectory = Test-Path -PathType Container -Path (Join-Path $RepoDir $entry.source)
    }
  }
}

function Get-ManagedDirectories {
  param([Parameter(Mandatory)][string]$RepoDir)
  foreach ($entry in Get-ManifestEntries $RepoDir) {
    if ($entry.IsDirectory) {
      [pscustomobject]@{ Source = $entry.Source; Target = $entry.Target; Exclude = $entry.Exclude }
    }
  }
}

function Get-ManagedFiles {
  param([Parameter(Mandatory)][string]$RepoDir)
  foreach ($entry in Get-ManifestEntries $RepoDir) {
    if (-not $entry.IsDirectory) {
      [pscustomobject]@{ Source = $entry.Source; Target = $entry.Target; DirectoryEntry = $null }
      continue
    }
    $directory = [pscustomobject]@{ Source = $entry.Source; Target = $entry.Target; Exclude = $entry.Exclude }
    # Tracked plus untracked-not-ignored, so .gitignore applies; -z keeps non-ASCII names unquoted.
    $listing = git -C $RepoDir ls-files -z -co --exclude-standard -- $entry.Source
    if ($LASTEXITCODE -ne 0) { throw "git ls-files failed for $($entry.Source) (exit code $LASTEXITCODE)" }
    $sources = ($listing -join '') -split "`0" | Where-Object { $_ } | Sort-Object -Unique
    foreach ($source in $sources) {
      # A tracked file deleted from the working tree is still listed; sync works from the working tree.
      if (-not (Test-Path -PathType Leaf -Path (Join-Path $RepoDir $source))) { continue }
      $relative = $source.Substring($entry.Source.TrimEnd('/').Length + 1)
      if (Test-ExcludedPath $relative $entry.Exclude) { continue }
      [pscustomobject]@{ Source = $source; Target = "$($entry.Target.TrimEnd('/'))/$relative"; DirectoryEntry = $directory }
    }
  }
}

function Test-ExcludedPath {
  [OutputType([bool])]
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [AllowEmptyCollection()][string[]]$Patterns = @()
  )
  foreach ($pattern in $Patterns) {
    $regex = [regex]::Escape($pattern) -replace '\\\*\\\*/', '(.*/)?' -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '[^/]'
    if ($RelativePath -match "^$regex\z") { return $true }
  }
  $false
}

function Expand-HomePlaceholder {
  [OutputType([string])]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$HomeDir)
  $Text.Replace('@HOME@', $HomeDir)
}

# Replaces $Path with $Token only where it's a whole path, followed by /, a quote, whitespace, : or the end of
# the text: /home/u2 stays as written when the path is /home/u.
function ConvertTo-PathToken {
  param([AllowEmptyString()][string]$Text, [string]$Path, [string]$Token)
  [regex]::Replace($Text, [regex]::Escape($Path.TrimEnd('/')) + '(?=[/"''\s:]|\z)', $Token.Replace('$', '$$'))
}

function ConvertTo-HomePlaceholder {
  [OutputType([string])]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$HomeDir)
  ConvertTo-PathToken $Text $HomeDir '@HOME@'
}

# @DOTFILES@ is the clone's own path, for config that points into the repo (e.g. local plugin folders).
function Expand-Placeholders {
  [OutputType([string])]
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$HomeDir,
    [Parameter(Mandatory)][string]$RepoDir
  )
  Expand-HomePlaceholder ($Text.Replace('@DOTFILES@', $RepoDir.TrimEnd('/'))) $HomeDir
}

# The repo path is converted first: the clone is usually under home, and its path should become @DOTFILES@,
# not @HOME@/.dotfiles.
function ConvertTo-Placeholders {
  [OutputType([string])]
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][string]$HomeDir,
    [Parameter(Mandatory)][string]$RepoDir
  )
  ConvertTo-HomePlaceholder (ConvertTo-PathToken $Text $RepoDir '@DOTFILES@') $HomeDir
}

Export-ModuleMember -Function Get-ManagedFiles, Get-ManagedDirectories, Test-ExcludedPath, Expand-HomePlaceholder,
  ConvertTo-HomePlaceholder, Expand-Placeholders, ConvertTo-Placeholders
