Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"
Import-Module "$PSScriptRoot/Manifest.psm1"
Import-Module "$PSScriptRoot/State.psm1"
Import-Module "$PSScriptRoot/Json.psm1"

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

function Get-UnmergedFiles {
  param([string]$RepoDir)
  @(git -C $RepoDir diff --name-only --diff-filter=U)
}

# Stashes uncommitted repo changes, pulls with rebase and restores them. Returns $false, after saying why,
# if any step fails or leaves a git conflict, so that sync stops before touching live files.
function Invoke-RepoPull {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$RepoDir)
  Write-Status 'Pulling the dotfiles repo...'
  if (Test-DryRun) {
    Write-Dry 'git pull --rebase (stashing local changes if needed)'
    return $true
  }
  $PSNativeCommandUseErrorActionPreference = $false

  $dirty = git -C $RepoDir status --porcelain --untracked-files=no
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Dotfiles repo not found at $RepoDir"
    return $false
  }
  $stashed = $false
  if ($dirty) {
    git -C $RepoDir stash push --quiet -m sync.ps1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-Warn 'Could not stash local changes — not pulling'
      return $false
    }
    $stashed = $true
  }

  git -C $RepoDir pull --rebase --quiet | Out-Host
  if ($LASTEXITCODE -ne 0) {
    $unmerged = Get-UnmergedFiles $RepoDir
    if ($unmerged) {
      Write-Warn "git pull stopped on a conflict in: $($unmerged -join ', ')"
      Write-Warn "Resolve it in $RepoDir (git status shows how), then run ./sync.ps1"
      if ($stashed) { Write-Warn "Your uncommitted changes are in 'git stash list' — run 'git stash pop' after resolving" }
      return $false
    }
    Write-Warn 'git pull failed'
    if ($stashed) {
      git -C $RepoDir stash pop --quiet | Out-Host
      if ($LASTEXITCODE -ne 0) { Write-Warn "Could not re-apply local changes — they are still in 'git stash list'" }
    }
    return $false
  }

  if ($stashed) {
    git -C $RepoDir stash pop --quiet | Out-Host
    if ($LASTEXITCODE -ne 0) {
      $unmerged = Get-UnmergedFiles $RepoDir
      if ($unmerged) { Write-Warn "Re-applying local changes conflicted in: $($unmerged -join ', ')" }
      Write-Warn "Could not re-apply local changes — they are still in 'git stash list'"
      Write-Warn "Resolve the conflict, run 'git stash drop', then run ./sync.ps1"
      return $false
    }
  }
  Write-Ok 'Pulled the latest changes'
  $true
}

function New-TempDirectory {
  [IO.Directory]::CreateDirectory((Join-Path ([IO.Path]::GetTempPath()) "dotfiles-sync-$([guid]::NewGuid())")).FullName
}

# Temp files are written even in dry-run: they aren't managed files, and the merge result decides what
# the dry run reports.
function Write-TempFile {
  param([string]$Path, [AllowEmptyString()][string]$Content)
  [IO.File]::WriteAllBytes($Path, [Text.UTF8Encoding]::new($false).GetBytes($Content))
}

function Test-ValidJson {
  [OutputType([bool])]
  param([AllowEmptyString()][string]$Text)
  try { $null = $Text | ConvertFrom-Json } catch { return $false }
  $null -eq (Find-JsonDuplicateKey $Text)
}

# Merges live and repo changes against the base with git merge-file. Content holds conflict markers when
# the merge isn't clean. A clean merge of a JSON file that no longer parses, or has a key twice, isn't clean.
function Invoke-ThreeWayMerge {
  param(
    [AllowEmptyString()][string]$Live,
    [AllowEmptyString()][string]$Base,
    [AllowEmptyString()][string]$Repo,
    [string]$Target
  )
  $dir = New-TempDirectory
  try {
    Write-TempFile "$dir/live" $Live
    Write-TempFile "$dir/base" $Base
    Write-TempFile "$dir/repo" $Repo
    # Without -p the result goes into the first file, which keeps its bytes exactly (stdout would be re-split into lines).
    $PSNativeCommandUseErrorActionPreference = $false
    git merge-file -L live -L base -L repo "$dir/live" "$dir/base" "$dir/repo"
    $exitCode = $LASTEXITCODE
    # 0 = clean, 1–127 = number of conflicts, anything else = error.
    if ($exitCode -lt 0 -or $exitCode -gt 127) { throw "git merge-file failed for $Target (exit code $exitCode)" }
    $content = Read-TextFile "$dir/live"
    $clean = $exitCode -eq 0
    if ($clean -and $Target -match '\.jsonc?$') { $clean = Test-ValidJson $content }
    [pscustomobject]@{ Clean = $clean; Content = $content }
  } finally {
    Remove-Item -Recurse -Force -LiteralPath $dir
  }
}

function Test-CanPrompt {
  param([switch]$NoPrompt)
  -not $NoPrompt -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
}

# Offers VS Code's three-way merge editor for a conflict when sync runs in a terminal. Returns $true if the
# user resolved it, after writing the result to live and recording the repo version as applied.
function Resolve-Conflict {
  [OutputType([bool])]
  param(
    [string]$Target,
    [AllowEmptyString()][string]$Base,
    [AllowEmptyString()][string]$Repo,
    [AllowEmptyString()][string]$Merged,
    [switch]$NoPrompt
  )
  if ((Test-DryRun) -or -not (Test-CanPrompt -NoPrompt:$NoPrompt) -or -not (Test-Command code)) {
    Write-Warn "Conflict: $Target — run ./sync.ps1 in a terminal to merge it in VS Code"
    return $false
  }
  $dir = New-TempDirectory
  try {
    Write-TempFile "$dir/repo" $Repo
    Write-TempFile "$dir/base" $Base
    Write-TempFile "$dir/result" $Merged
    Write-Warn "Conflict: $Target — opening VS Code's merge editor with this machine's version and the repo's"
    $PSNativeCommandUseErrorActionPreference = $false
    code --wait --merge $Target "$dir/repo" "$dir/base" "$dir/result" | Out-Host
    $exitCode = $LASTEXITCODE
    $result = Read-TextFile "$dir/result"
    if ($exitCode -ne 0 -or $result -match '(?m)^<<<<<<< ') {
      Write-Warn "Conflict: $Target — not resolved, left as it is"
      return $false
    }
    Write-TextFile $Target $result
    Write-Applied $Target $Repo
    Write-Ok "Merged $Target in VS Code"
    $true
  } finally {
    Remove-Item -Recurse -Force -LiteralPath $dir
  }
}

# Writes the repo and live versions of a local change to temp files, with the home path shown as @HOME@
# as it would be in the repo. A new local file has an empty repo side. Returns the two paths.
function New-LocalChangeFiles {
  param([pscustomobject]$File, [string]$Dir)
  $homeDir = Get-HomeDir
  # The repo path, so the diff header says which file it is (several are called config.toml).
  $name = $File.Source
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName("$Dir/repo/$name")) | Out-Null
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName("$Dir/live/$name")) | Out-Null
  $repoText = if ($null -eq $File.Repo) { '' } else { ConvertTo-HomePlaceholder $File.Repo $homeDir }
  Write-TempFile "$Dir/repo/$name" $repoText
  Write-TempFile "$Dir/live/$name" (ConvertTo-HomePlaceholder $File.Live $homeDir)
  [pscustomobject]@{ Repo = "repo/$name"; Live = "live/$name" }
}

function Show-LocalChange {
  param([Parameter(Mandatory)][pscustomobject]$File)
  $dir = New-TempDirectory
  try {
    $paths = New-LocalChangeFiles $File $dir
    $PSNativeCommandUseErrorActionPreference = $false
    git -C $dir --no-pager diff --no-index --color -- $paths.Repo $paths.Live | Out-Host
    # git diff --no-index exits 1 when the files differ, which is expected here.
    if ($LASTEXITCODE -gt 1) { throw "git diff failed for $($File.Target) (exit code $LASTEXITCODE)" }
  } finally {
    Remove-Item -Recurse -Force -LiteralPath $dir
  }
}

# Asks what to do with one local change; 'd' opens the diff in VS Code and asks again. Enter skips.
function Read-CopyBackChoice {
  [OutputType([bool])]
  param([pscustomobject]$File)
  while ($true) {
    # The VS Code diff shows temp copies, so edits made there don't reach the repo.
    $answer = (Read-Host '  [c]opy back, [s]kip, [d]iff in VS Code (left: repo, right: this machine; view only)').Trim().ToLowerInvariant()
    switch ($answer) {
      'c' { return $true }
      { $_ -in 's', '' } { return $false }
      'd' {
        if (-not (Test-Command code)) {
          Write-Warn 'VS Code (code) is not on PATH'
          continue
        }
        $dir = New-TempDirectory
        try {
          $paths = New-LocalChangeFiles $File $dir
          $PSNativeCommandUseErrorActionPreference = $false
          code --wait --diff "$dir/$($paths.Repo)" "$dir/$($paths.Live)" | Out-Host
        } finally {
          Remove-Item -Recurse -Force -LiteralPath $dir
        }
      }
    }
  }
}

# Writes the live content, with the home path turned back into @HOME@, into the repo working tree for the
# user to review and commit. Leaves the last-applied copy alone, so a copy-back that's later discarded
# shows up as a local change again instead of looking like a repo deletion.
function Invoke-CopyBack {
  param([Parameter(Mandatory)][pscustomobject]$File)
  if (Test-DryRun) {
    Write-Dry "Copy back $($File.Target) → $($File.Source)"
    return
  }
  Write-TextFile (Join-Path (Get-RepoDir) $File.Source) (ConvertTo-HomePlaceholder $File.Live (Get-HomeDir))
  Write-Ok "Copied back $($File.Target) → $($File.Source)"
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
  param([switch]$NoPrompt, [switch]$InitialApply, [switch]$CopyBack)
  $repoDir = Get-RepoDir
  $homeDir = Get-HomeDir
  $result = [ordered]@{}
  foreach ($name in 'Written', 'Merged', 'Conflicts', 'LocalChanges', 'NewLocalFiles', 'Deleted', 'Reported', 'CopiedBack') {
    $result[$name] = [Collections.Generic.List[string]]::new()
  }
  # Live files that differ from the repo, reported with a diff once everything is applied.
  $localFiles = [Collections.Generic.List[object]]::new()

  Write-Status 'Syncing dotfiles...'
  # A pull or stash pop that stopped on a conflict leaves conflict markers in the working tree.
  $unmerged = Get-UnmergedFiles $repoDir
  if ($unmerged) {
    throw "The dotfiles repo has unresolved git conflicts in: $($unmerged -join ', ') — resolve them in $repoDir, then run ./sync.ps1"
  }
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
        $localFiles.Add([pscustomobject]@{ Target = $target; Source = $file.Source; Repo = $repo; Live = $live })
        $result.LocalChanges.Add($target)
      }
      'DeletedLocally' {
        Write-Warn "Deleted locally, not recreated: $target"
        $result.Reported.Add($target)
      }
      'Merge' {
        $merge = Invoke-ThreeWayMerge -Live $live -Base $base -Repo $repo -Target $target
        if ($merge.Clean) {
          if (Test-DryRun) {
            Write-Dry "Merge $target (changed here and in the repo; merges cleanly)"
          } else {
            Write-TextFile $target $merge.Content
            Write-Ok "Merged $target"
          }
          # The repo version, not the merge: the local part stays a local change on later syncs.
          Write-Applied $target $repo
          $result.Merged.Add($target)
        } elseif (Resolve-Conflict -Target $target -Base $base -Repo $repo -Merged $merge.Content -NoPrompt:$NoPrompt) {
          $result.Merged.Add($target)
        } else {
          $result.Conflicts.Add($target)
        }
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
          # First sight: no base yet, so the merge editor starts from an empty one.
          $merge = Invoke-ThreeWayMerge -Live $live -Base '' -Repo $repo -Target $target
          if (Resolve-Conflict -Target $target -Base '' -Repo $repo -Merged $merge.Content -NoPrompt:$NoPrompt) {
            $result.Merged.Add($target)
          } else {
            $result.Conflicts.Add($target)
          }
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
      $relative = $target.Substring($root.Length + 1)
      if (Test-ExcludedPath $relative $directory.Exclude) { continue }
      $source = "$($directory.Source.TrimEnd('/'))/$relative"
      $localFiles.Add([pscustomobject]@{ Target = $target; Source = $source; Repo = $null; Live = Read-TextFile $target })
      $result.NewLocalFiles.Add($target)
    }
  }

  if ($localFiles.Count) {
    Write-Status 'Local changes (this machine vs the repo)...'
    $canPrompt = -not $CopyBack -and (Test-CanPrompt -NoPrompt:$NoPrompt)
    foreach ($localFile in $localFiles) {
      Write-Warn "$(if ($null -eq $localFile.Repo) { 'New local file' } else { 'Local change' }): $($localFile.Target)"
      Show-LocalChange $localFile
      $copy = if ($CopyBack) { $true } elseif ($canPrompt) { Read-CopyBackChoice $localFile } else { $false }
      if ($copy) {
        Invoke-CopyBack $localFile
        $result.CopiedBack.Add($localFile.Target)
      }
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
  if ($Summary.CopiedBack.Count -and -not (Test-DryRun)) {
    Write-Warn "Review with 'git diff' in $(Get-RepoDir), stage what you want, then commit and push"
  }
}

Export-ModuleMember -Function Get-SyncAction, Invoke-RepoPull, Invoke-ThreeWayMerge, Show-LocalChange, Invoke-CopyBack,
  Invoke-Sync, Show-SyncSummary
