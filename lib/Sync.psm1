Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"
Import-Module "$PSScriptRoot/Manifest.psm1"
Import-Module "$PSScriptRoot/State.psm1"

# Ordinal: a change of case, or of Unicode form, is a change.
function Test-SameText {
  param($A, $B)
  [string]::Equals($A, $B, [StringComparison]::Ordinal)
}

# Decides what sync does with one file from its three versions: repo (placeholders filled in), base (the
# last-applied copy) and live. $null means that version doesn't exist. InRepo is false for a file sync
# applied before that the repo no longer has.
function Get-SyncAction {
  [OutputType([string])]
  param($Repo, $Base, $Live, [bool]$InRepo)
  if ($InRepo) {
    if ($null -eq $Base) {
      if ($null -eq $Live) { return 'WriteRepo' }
      if (Test-SameText $Live $Repo) { return 'RecordBase' }
      return 'Conflict'
    }
    if ($null -eq $Live) { return 'DeletedLocally' }
    if (Test-SameText $Live $Repo) { return 'None' }
    if (Test-SameText $Live $Base) { return 'WriteRepo' }
    if (Test-SameText $Repo $Base) { return 'LocalChange' }
    return 'Merge'
  }
  if ($null -eq $Base) { return 'None' }
  if ($null -eq $Live) { return 'DeletedLocally' }
  if (Test-SameText $Live $Base) { return 'DeleteLive' }
  'RemovedButChanged'
}

# Writes the repo version to the live file, then records it as applied: live first, so a failed write
# leaves the old base and the next sync tries again.
function Write-RepoVersion {
  param([string]$Target, [AllowEmptyString()][string]$Content)
  if (Test-DryRun) {
    Write-Dry "Write $Target"
  } else {
    Write-TextFile $Target $Content
    Write-Ok "Wrote $Target"
  }
  Write-Applied $Target $Content
}

function Invoke-Sync {
  param([switch]$NoPrompt, [switch]$InitialApply)
  $repoDir = Get-RepoDir
  $homeDir = Get-HomeDir
  $result = [ordered]@{}
  foreach ($name in 'Written', 'Merged', 'Conflicts', 'LocalChanges', 'NewLocalFiles', 'Deleted', 'Reported', 'CopiedBack') {
    $result[$name] = [Collections.Generic.List[string]]::new()
  }

  Write-Status 'Syncing dotfiles...'
  $files = @(Get-ManagedFiles $repoDir)

  # Writing through a stow link would edit the repo file instead of a live copy.
  foreach ($file in $files) {
    if (Test-LinkInto $file.Target $repoDir) {
      throw "$($file.Target) is still a stow link — run ./retire.ps1 first"
    }
  }

  $managedTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($file in $files) {
    $repoText = Read-TextFile (Join-Path $repoDir $file.Source)
    if ($null -eq $repoText) { continue }
    [void]$managedTargets.Add($file.Target)
    $target = $file.Target
    $repo = Expand-HomePlaceholder $repoText $homeDir
    $base = Read-Applied $target
    $live = Read-TextFile $target

    switch (Get-SyncAction -Repo $repo -Base $base -Live $live -InRepo $true) {
      'WriteRepo' {
        Write-RepoVersion $target $repo
        $result.Written.Add($target)
      }
      'RecordBase' {
        Write-Applied $target $repo
      }
      'None' {}
      'LocalChange' {
        Write-Warn "Local change: $target"
        $result.LocalChanges.Add($target)
      }
      'DeletedLocally' {
        Write-Warn "Deleted locally, not recreated: $target"
        $result.Reported.Add($target)
      }
      'Merge' {
        Write-Warn "Conflict: $target — changed both here and in the repo; left as it is"
        $result.Conflicts.Add($target)
      }
      'Conflict' {
        if ($InitialApply) {
          $backup = Backup-LiveFile $target
          if (Test-DryRun) {
            Write-Dry "Back up $target to $backup and write the repo version"
            Write-Applied $target $repo
          } else {
            Write-TextFile $target $repo
            Write-Applied $target $repo
            Write-Warn "Backed up $target to $backup and replaced it with the repo version"
          }
          $result.Written.Add($target)
        } else {
          Write-Warn "Conflict: $target — differs from the repo and sync hasn't applied it before; left as it is"
          $result.Conflicts.Add($target)
        }
      }
    }
  }

  # Files sync applied before that the repo no longer has.
  foreach ($target in Get-AppliedTargets) {
    if ($managedTargets.Contains($target)) { continue }
    $base = Read-Applied $target
    $live = Read-TextFile $target
    switch (Get-SyncAction -Repo $null -Base $base -Live $live -InRepo $false) {
      'DeleteLive' {
        if (Test-DryRun) {
          Write-Dry "Delete $target (removed from the repo)"
        } else {
          [IO.File]::Delete($target)
          Write-Ok "Deleted $target (removed from the repo)"
        }
        Remove-Applied $target
        $result.Deleted.Add($target)
      }
      'RemovedButChanged' {
        Write-Warn "Removed from the repo but changed here, so left in place and no longer managed: $target"
        Remove-Applied $target
        $result.Reported.Add($target)
      }
      'DeletedLocally' {
        Write-Skip "Removed from the repo and already deleted here: $target"
        Remove-Applied $target
        $result.Reported.Add($target)
      }
    }
  }

  # Files other tools added to a managed folder.
  foreach ($directory in Get-ManagedDirectories $repoDir) {
    if (-not [IO.Directory]::Exists($directory.Target)) { continue }
    $root = $directory.Target.TrimEnd('/')
    foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
      $target = $item.FullName
      if ($managedTargets.Contains($target)) { continue }
      if (Test-ExcludedPath $target.Substring($root.Length + 1) $directory.Exclude) { continue }
      Write-Warn "New local file: $target"
      $result.NewLocalFiles.Add($target)
    }
  }

  $summary = [ordered]@{}
  foreach ($name in $result.Keys) { $summary[$name] = [string[]]$result[$name].ToArray() }
  [pscustomobject]$summary
}

function Show-SyncSummary {
  param([Parameter(Mandatory)][pscustomobject]$Summary)
  Write-Status 'Sync summary'
  Write-Ok ('{0} written, {1} merged, {2} conflicts, {3} local changes, {4} new local files, {5} deleted, {6} copied back' -f
    $Summary.Written.Count, $Summary.Merged.Count, $Summary.Conflicts.Count, $Summary.LocalChanges.Count,
    $Summary.NewLocalFiles.Count, $Summary.Deleted.Count, $Summary.CopiedBack.Count)
}

Export-ModuleMember -Function Get-SyncAction, Invoke-Sync, Show-SyncSummary
