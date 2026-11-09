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
# applied before that the repo no longer has. RepoCommitted says the repo file has no uncommitted changes:
# a committed copy-back becomes the base, but an uncommitted one doesn't, so discarding it still leaves a
# local change.
function Get-SyncAction {
  [OutputType([string])]
  param($Repo, $Base, $Live, [bool]$InRepo, [bool]$RepoCommitted)
  if ($InRepo) {
    if ($null -eq $Base) {
      if ($null -eq $Live) { return 'WriteRepo' }
      if (Test-SameText $Live $Repo) { return 'RecordBase' }
      return 'Conflict'
    }
    if ($null -eq $Live) { return 'DeletedLocally' }
    if (Test-SameText $Live $Repo) {
      if ($RepoCommitted -and -not (Test-SameText $Repo $Base)) { return 'RecordBase' }
      return 'None'
    }
    if (Test-SameText $Live $Base) { return 'WriteRepo' }
    if (Test-SameText $Repo $Base) { return 'LocalChange' }
    return 'Merge'
  }
  if ($null -eq $Base) { return 'None' }
  if ($null -eq $Live) { return 'DeletedLocally' }
  if (Test-SameText $Live $Base) { return 'DeleteLive' }
  'RemovedButChanged'
}

# True if $Target, or a folder between it and home, is a link into the repo, as stow makes them. Writing
# through one would edit the repo file instead of a live copy.
function Test-StowLinked {
  [OutputType([bool])]
  param([string]$Target, [string]$RepoDir)
  $stop = (Get-HomeDir).TrimEnd('/')
  $path = $Target
  while ($path -and $path.Length -gt $stop.Length) {
    if (Test-LinkInto $path $RepoDir) { return $true }
    $path = [IO.Path]::GetDirectoryName($path)
  }
  $false
}

# True if the repo file has no uncommitted changes and is tracked (git status lists neither).
function Test-RepoFileCommitted {
  [OutputType([bool])]
  param([string]$RepoDir, [string]$Source)
  $PSNativeCommandUseErrorActionPreference = $false
  # git status lists neither ignored files nor, with status.showUntrackedFiles=no, untracked ones.
  git -C $RepoDir ls-files --error-unmatch -- $Source *> $null
  if ($LASTEXITCODE -ne 0) { return $false }
  $status = git -C $RepoDir status --porcelain -- $Source
  if ($LASTEXITCODE -ne 0) { throw "git status failed for $Source in $RepoDir (exit code $LASTEXITCODE)" }
  -not $status
}

# Whether a file whose live copy matches the repo should have the repo version recorded as last applied.
# git is only asked when the base is out of date, which is rare.
function Test-RecordCommittedBase {
  [OutputType([bool])]
  param([string]$RepoDir, [string]$Source, $Repo, $Base, $Live)
  $null -ne $Base -and (Test-SameText $Live $Repo) -and -not (Test-SameText $Repo $Base) -and
    (Test-RepoFileCommitted $RepoDir $Source)
}

# Records committed copy-backs as last applied before a pull. The pull can bring in a newer version of the
# same lines, and against the old base that would look like a conflict.
function Update-CommittedBases {
  $repoDir = Get-RepoDir
  $homeDir = Get-HomeDir
  foreach ($file in Get-ManagedFiles $repoDir) {
    # Invoke-Sync refuses stow links; nothing to record for them.
    if (Test-StowLinked $file.Target $repoDir) { continue }
    $repoText = Read-TextFile (Join-Path $repoDir $file.Source)
    if ($null -eq $repoText) { continue }
    $repo = Expand-Placeholders $repoText $homeDir $repoDir
    if (Test-RecordCommittedBase $repoDir $file.Source $repo (Read-Applied $file.Target) (Read-TextFile $file.Target)) {
      Write-Applied $file.Target $repo
    }
  }
}

function Get-UnmergedFiles {
  param([string]$RepoDir)
  $PSNativeCommandUseErrorActionPreference = $false
  $files = @(git -C $RepoDir diff --name-only --diff-filter=U)
  if ($LASTEXITCODE -ne 0) { throw "git diff failed in $RepoDir (exit code $LASTEXITCODE)" }
  $files
}

# For messages after a git step already failed: a second failure is reported, not thrown, so the warnings that
# follow (e.g. where the stashed changes are) still print.
function Get-UnmergedFilesOrWarn {
  param([string]$RepoDir)
  try { Get-UnmergedFiles $RepoDir } catch { Write-Warn $_.Exception.Message }
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

  if (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) {
    Write-Warn "Dotfiles repo not found at $RepoDir"
    return $false
  }
  $dirty = git -C $RepoDir status --porcelain --untracked-files=no
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "git status failed in $RepoDir (exit code $LASTEXITCODE) — see git's message above"
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
    $unmerged = Get-UnmergedFilesOrWarn $RepoDir
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
      $unmerged = Get-UnmergedFilesOrWarn $RepoDir
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

function Get-TextHash {
  [OutputType([string])]
  param([AllowEmptyString()][string]$Text)
  [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Text)))
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
    if ($Target -match '\.jsonc?$' -and -not (Test-ValidJson $result)) {
      Write-Warn "Conflict: $Target — the merge result isn't valid JSON (or has a key twice), left as it is"
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
  $repoText = if ($null -eq $File.Repo) { '' } else { ConvertTo-Placeholders $File.Repo $homeDir (Get-RepoDir) }
  Write-TempFile "$Dir/repo/$name" $repoText
  Write-TempFile "$Dir/live/$name" (ConvertTo-Placeholders $File.Live $homeDir (Get-RepoDir))
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

# Asks what to do with one local change: 'copy', 'skip' (this run only) or 'ignore' (until the file
# changes). 'd' opens the diff in VS Code and asks again. Enter skips.
function Read-CopyBackChoice {
  [OutputType([string])]
  param([pscustomobject]$File)
  while ($true) {
    # The VS Code diff shows temp copies, so edits made there don't reach the repo.
    $answer = (Read-Host '  [c]opy back, [s]kip, [i]gnore until it changes, [d]iff in VS Code (left: repo, right: this machine; view only)').Trim().ToLowerInvariant()
    switch ($answer) {
      'c' { return 'copy' }
      { $_ -in 's', '' } { return 'skip' }
      'i' { return 'ignore' }
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
  Write-TextFile (Join-Path (Get-RepoDir) $File.Source) (ConvertTo-Placeholders $File.Live (Get-HomeDir) (Get-RepoDir))
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

# An ignored file is counted as ignored, not also as a local change or new local file.
function Move-ToIgnored {
  param($Result, [string]$Target)
  [void]$Result.LocalChanges.Remove($Target)
  [void]$Result.NewLocalFiles.Remove($Target)
  $Result.Ignored.Add($Target)
}

# A merge keeps this machine's edits, so a merged file that still differs from the repo goes into this run's
# local-changes report too, rather than only showing up on the next sync.
function Add-MergedLocalChange {
  param($LocalFiles, $Result, [string]$Source, [string]$Target, [AllowEmptyString()][string]$Repo, $Merged)
  if ($null -eq $Merged -or (Test-SameText $Merged $Repo)) { return }
  $LocalFiles.Add([pscustomobject]@{ Target = $Target; Source = $Source; Repo = $Repo; Live = $Merged })
  $Result.LocalChanges.Add($Target)
}

function Invoke-Sync {
  param([switch]$NoPrompt, [switch]$InitialApply, [switch]$CopyBack)
  $repoDir = Get-RepoDir
  $homeDir = Get-HomeDir
  $result = [ordered]@{}
  foreach ($name in 'Written', 'Merged', 'Conflicts', 'LocalChanges', 'NewLocalFiles', 'Ignored', 'Deleted', 'Reported', 'CopiedBack') {
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

  foreach ($file in $files) {
    if (Test-StowLinked $file.Target $repoDir) {
      throw "$($file.Target) is still a stow link into the repo — run ./retire.ps1 first"
    }
  }

  $managedTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($file in $files) {
    $repoText = Read-TextFile (Join-Path $repoDir $file.Source)
    if ($null -eq $repoText) { continue }
    [void]$managedTargets.Add($file.Target)
    $target = $file.Target
    $repo = Expand-Placeholders $repoText $homeDir $repoDir
    $base = Read-Applied $target
    $live = Read-TextFile $target

    $committed = Test-RecordCommittedBase $repoDir $file.Source $repo $base $live
    switch (Get-SyncAction -Repo $repo -Base $base -Live $live -InRepo $true -RepoCommitted $committed) {
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
          Add-MergedLocalChange $localFiles $result $file.Source $target $repo $merge.Content
        } elseif (Resolve-Conflict -Target $target -Base $base -Repo $repo -Merged $merge.Content -NoPrompt:$NoPrompt) {
          $result.Merged.Add($target)
          Add-MergedLocalChange $localFiles $result $file.Source $target $repo (Read-TextFile $target)
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
            Add-MergedLocalChange $localFiles $result $file.Source $target $repo (Read-TextFile $target)
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

  # Ignores still in force this run; any other stored ignore is for a file that changed or no longer differs.
  $keepIgnored = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  if ($localFiles.Count) {
    Write-Status 'Local changes (this machine vs the repo)...'
    $canPrompt = -not $CopyBack -and (Test-CanPrompt -NoPrompt:$NoPrompt)
    foreach ($localFile in $localFiles) {
      $target = $localFile.Target
      $hash = Get-TextHash $localFile.Live
      if ((Read-IgnoredHash $target) -ceq $hash) {
        Write-Skip "Local change ignored until it changes: $target"
        [void]$keepIgnored.Add($target)
        Move-ToIgnored $result $target
        continue
      }
      Write-Warn "$(if ($null -eq $localFile.Repo) { 'New local file' } else { 'Local change' }): $target"
      Show-LocalChange $localFile
      $choice = if ($CopyBack) { 'copy' } elseif ($canPrompt) { Read-CopyBackChoice $localFile } else { 'skip' }
      switch ($choice) {
        'copy' {
          Invoke-CopyBack $localFile
          $result.CopiedBack.Add($target)
        }
        'ignore' {
          Write-IgnoredHash $target $hash
          [void]$keepIgnored.Add($target)
          Move-ToIgnored $result $target
          if (Test-DryRun) {
            Write-Dry "Ignore $target until it changes"
          } else {
            Write-Skip "Ignoring this local change until it changes: $target"
          }
        }
      }
    }
  }
  foreach ($target in Get-IgnoredTargets) {
    if (-not $keepIgnored.Contains($target)) { Remove-IgnoredHash $target }
  }

  $summary = [ordered]@{}
  foreach ($name in $result.Keys) { $summary[$name] = [string[]]$result[$name].ToArray() }
  [pscustomobject]$summary
}

function Show-SyncSummary {
  param([Parameter(Mandatory)][pscustomobject]$Summary)
  Write-Status 'Sync summary'
  Write-Ok ('{0} written, {1} merged, {2} conflicts, {3} local changes, {4} new local files, {5} ignored, {6} deleted, {7} copied back' -f
    $Summary.Written.Count, $Summary.Merged.Count, $Summary.Conflicts.Count, $Summary.LocalChanges.Count,
    $Summary.NewLocalFiles.Count, $Summary.Ignored.Count, $Summary.Deleted.Count, $Summary.CopiedBack.Count)
  if ($Summary.CopiedBack.Count -and -not (Test-DryRun)) {
    Write-Warn "Review with 'git diff' in $(Get-RepoDir), stage what you want, then commit and push"
  }
}

Export-ModuleMember -Function Get-SyncAction, Update-CommittedBases, Invoke-RepoPull, Invoke-ThreeWayMerge, Show-LocalChange, Invoke-CopyBack,
  Invoke-Sync, Show-SyncSummary
