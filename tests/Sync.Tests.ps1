Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  # Pester runs top-level code only while discovering tests; these lines apply strictness to the tests themselves.
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
  Import-Module "$PSScriptRoot/../lib/Sync.psm1" -Force
  Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force

  function Invoke-TestSync {
    param([string[]]$Extra = @())
    Invoke-SyncScript (@('-NoPull', '-NoPrompt') + $Extra)
  }

  function Remove-ManifestEntry {
    param([string]$Source)
    $path = "$env:DOTFILES_REPO/dotfiles.json"
    $manifest = Get-Content -Raw $path | ConvertFrom-Json
    $manifest.entries = @($manifest.entries | Where-Object source -ne $Source)
    Write-FixtureFile $path ($manifest | ConvertTo-Json -Depth 5)
  }

  function Get-TreeHashes {
    param([string[]]$Roots)
    foreach ($root in $Roots) {
      if (-not (Test-Path $root)) { continue }
      Get-ChildItem -LiteralPath $root -Recurse -File -Force |
        Where-Object { $_.FullName -notlike '*/.git/*' } |
        ForEach-Object { "$($_.FullName) $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
    }
  }
}

Describe 'Get-SyncAction' {
  It 'in repo=<InRepo>, repo=<Repo>, base=<Base>, live=<Live> → <Expected>' -ForEach @(
    @{ InRepo = $true; Repo = 'r'; Base = $null; Live = $null; Expected = 'WriteRepo' }
    @{ InRepo = $true; Repo = 'r'; Base = $null; Live = 'r'; Expected = 'RecordBase' }
    @{ InRepo = $true; Repo = 'r'; Base = $null; Live = 'l'; Expected = 'Conflict' }
    @{ InRepo = $true; Repo = 'r'; Base = 'b'; Live = 'r'; Expected = 'None' }
    @{ InRepo = $true; Repo = 'r'; Base = 'b'; Live = $null; Expected = 'DeletedLocally' }
    @{ InRepo = $true; Repo = 'r'; Base = 'b'; Live = 'b'; Expected = 'WriteRepo' }
    @{ InRepo = $true; Repo = 'b'; Base = 'b'; Live = 'l'; Expected = 'LocalChange' }
    @{ InRepo = $true; Repo = 'r'; Base = 'b'; Live = 'l'; Expected = 'Merge' }
    @{ InRepo = $false; Repo = $null; Base = 'b'; Live = $null; Expected = 'DeletedLocally' }
    @{ InRepo = $false; Repo = $null; Base = 'b'; Live = 'b'; Expected = 'DeleteLive' }
    @{ InRepo = $false; Repo = $null; Base = 'b'; Live = 'l'; Expected = 'RemovedButChanged' }
  ) {
    Get-SyncAction -Repo $Repo -Base $Base -Live $Live -InRepo $InRepo | Should -Be $Expected
  }

  It 'treats a change of case as a change' {
    Get-SyncAction -Repo 'b' -Base 'b' -Live 'B' -InRepo $true | Should -Be 'LocalChange'
  }

  It 'treats an empty file as present' {
    Get-SyncAction -Repo '' -Base $null -Live $null -InRepo $true | Should -Be 'WriteRepo'
    Get-SyncAction -Repo '' -Base $null -Live '' -InRepo $true | Should -Be 'RecordBase'
  }
}

Describe 'sync.ps1 apply' {
  BeforeEach {
    $f = New-SyncFixture
    $h = $f.Home
    $r = $f.Repo
    $applied = "$($f.State)/applied"
  }

  AfterEach {
    Remove-SyncFixture
  }

  It 'writes repo files on a fresh machine' {
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly (Read-FixtureFile "$r/plainrc")
    Read-FixtureFile "$h/.otherrc" | Should -BeExactly (Read-FixtureFile "$r/otherrc")
    Read-FixtureFile "$h/.skills/a/SKILL.md" | Should -BeExactly (Read-FixtureFile "$r/skills/a/SKILL.md")
    Read-FixtureFile "$applied/.plainrc" | Should -BeExactly (Read-FixtureFile "$r/plainrc")
    "$applied/.skills/a/SKILL.md" | Should -Exist
  }

  It 'creates missing parent directories' {
    "$h/.config/app" | Should -Not -Exist
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$h/.config/app/app.json" | Should -BeExactly (Read-FixtureFile "$r/cfg/app.json")
  }

  It 'records state when live already matches' {
    Write-FixtureFile "$h/.plainrc" (Read-FixtureFile "$r/plainrc")
    $before = (Get-Item -Force "$h/.plainrc").LastWriteTimeUtc
    Start-Sleep -Milliseconds 20
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$applied/.plainrc" | Should -BeExactly (Read-FixtureFile "$r/plainrc")
    (Get-Item -Force "$h/.plainrc").LastWriteTimeUtc | Should -Be $before
  }

  It 'applies a repo change' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$r/plainrc" "plain`nchanged`n"
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plain`nchanged`n"
    Read-FixtureFile "$applied/.plainrc" | Should -BeExactly "plain`nchanged`n"
  }

  It 'keeps a local change and reports it' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$h/.plainrc" "plain`nlocal`n"
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 0
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plain`nlocal`n"
    $result.Output | Should -Match 'Local change: .*/\.plainrc'
    Read-FixtureFile "$applied/.plainrc" | Should -BeExactly "plain`n"
  }

  It 'local-only entry survives a copy-back that is then discarded' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$h/.plainrc" "plain`nlocal-only`n"
    Write-FixtureFile "$r/plainrc" (Read-FixtureFile "$h/.plainrc")
    Invoke-TestSync | Out-Null
    git -C $r checkout -q -- plainrc
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plain`nlocal-only`n"
  }

  It 'first sight conflict leaves live alone without -InitialApply' {
    Write-FixtureFile "$h/.plainrc" "machine default`n"
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 0
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "machine default`n"
    $result.Output | Should -Match 'Conflict: .*/\.plainrc'
  }

  It '-InitialApply backs up and replaces' {
    Write-FixtureFile "$h/.plainrc" "machine default`n"
    $result = Invoke-TestSync '-InitialApply'
    $result.ExitCode | Should -Be 0
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly (Read-FixtureFile "$r/plainrc")
    $backups = @(Get-ChildItem -Recurse -File -Force "$($f.State)/backup")
    $backups.Count | Should -Be 1
    $backups[0].Name | Should -Be '.plainrc'
    Read-FixtureFile $backups[0].FullName | Should -BeExactly "machine default`n"
    $result.Output | Should -Match "! .*$([regex]::Escape($backups[0].FullName))"
  }

  It "reports a locally deleted file and doesn't recreate it" {
    Invoke-TestSync | Out-Null
    Remove-Item -Force "$h/.otherrc"
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 0
    "$h/.otherrc" | Should -Not -Exist
    $result.Output | Should -Match '/\.otherrc'
  }

  It 'deletes a file removed from the repo when unchanged' {
    Invoke-TestSync | Out-Null
    Remove-ManifestEntry 'otherrc'
    (Invoke-TestSync).ExitCode | Should -Be 0
    "$h/.otherrc" | Should -Not -Exist
    "$applied/.otherrc" | Should -Not -Exist
  }

  It 'reports a removed file that changed locally, once' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$h/.otherrc" "other`nlocal`n"
    Remove-ManifestEntry 'otherrc'
    $first = Invoke-TestSync
    $second = Invoke-TestSync
    Read-FixtureFile "$h/.otherrc" | Should -BeExactly "other`nlocal`n"
    $first.Output | Should -Match '/\.otherrc'
    $second.Output | Should -Not -Match '/\.otherrc'
  }

  It 'reports a new file in a managed directory' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$h/.skills/new/SKILL.md" "new`n"
    (Invoke-TestSync).Output | Should -Match 'New local file: .*/\.skills/new/SKILL\.md'
  }

  It 'ignores excluded files in a managed directory' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$h/.skills/synced/x.md" "synced`n"
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 0 -Because $result.Output
    $result.Output | Should -Not -Match 'synced'
  }

  It 'refuses to write through a link into the repo' {
    New-Item -ItemType SymbolicLink -Path "$h/.plainrc" -Target "$r/plainrc" | Out-Null
    Write-FixtureFile "$r/plainrc" "plain`nrepo edit`n"
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'retire\.ps1'
    Read-FixtureFile "$r/plainrc" | Should -BeExactly "plain`nrepo edit`n"
    "$h/.otherrc" | Should -Not -Exist
  }

  It 'keeps unicode and a missing final newline byte-exact' {
    Write-FixtureFile "$r/plainrc" "glyph  ✓ é"
    (Invoke-TestSync).ExitCode | Should -Be 0
    [IO.File]::ReadAllBytes("$h/.plainrc") | Should -Be ([IO.File]::ReadAllBytes("$r/plainrc"))
  }

  It '-WhatIf changes nothing' {
    Invoke-TestSync | Out-Null
    Write-FixtureFile "$r/plainrc" "plain`nchanged`n"
    $head = git -C $r rev-parse HEAD
    $before = Get-TreeHashes $h, $r, $f.State
    $result = Invoke-TestSync '-WhatIf'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Get-TreeHashes $h, $r, $f.State | Should -Be $before
    git -C $r rev-parse HEAD | Should -Be $head
    $result.Output | Should -Match '~ '
    $result.Output | Should -Not -Match 'What if:'
  }

  It 'fills @HOME@ on apply' {
    Write-FixtureFile "$r/cfg/app.json" '{"p":"@HOME@/x"}'
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$h/.config/app/app.json" | Should -BeExactly "{`"p`":`"$h/x`"}"
  }
}

Describe 'sync.ps1 pull and merge' {
  BeforeEach {
    $f = New-SyncFixture
    $h = $f.Home
    $r = $f.Repo
    $applied = "$($f.State)/applied"
  }

  AfterEach {
    Remove-SyncFixture
  }

  It 'applies an upstream change' {
    (Invoke-SyncScript '-NoPrompt').ExitCode | Should -Be 0
    Set-Upstream 'otherrc' "b`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$h/.otherrc" | Should -BeExactly "b`n"
  }

  It 'merges non-overlapping edits to the same file' {
    Set-Upstream 'plainrc' "1`n2`n3`n4`n5`n"
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Write-FixtureFile "$h/.plainrc" "1 local`n2`n3`n4`n5`n"
    Set-Upstream 'plainrc' "1`n2`n3`n4`n5 upstream`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "1 local`n2`n3`n4`n5 upstream`n"
    $result.Output | Should -Match 'Merged .*/\.plainrc'
    Read-FixtureFile "$applied/.plainrc" | Should -BeExactly "1`n2`n3`n4`n5 upstream`n"
  }

  It 'overlapping edits are a conflict and live is kept' {
    Set-Upstream 'plainrc' "1`n2`n3`n"
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Write-FixtureFile "$h/.plainrc" "1 local`n2`n3`n"
    Set-Upstream 'plainrc' "1 upstream`n2`n3`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "1 local`n2`n3`n"
    $result.Output | Should -Match 'Conflict: .*/\.plainrc'
    Read-FixtureFile "$applied/.plainrc" | Should -BeExactly "1`n2`n3`n"
  }

  It 'a clean merge that breaks JSON is a conflict' {
    Set-Upstream 'cfg/app.json' "{`n  `"a`": 1,`n  `"m`": 0,`n  `"b`": 2`n}`n"
    Invoke-SyncScript '-NoPrompt' | Out-Null
    $local = "{`n  `"a`": 1,`n  `"c`": 3,`n  `"m`": 0,`n  `"b`": 2`n}`n"
    Write-FixtureFile "$h/.config/app/app.json" $local
    Set-Upstream 'cfg/app.json' "{`n  `"a`": 1,`n  `"m`": 0,`n  `"c`": 4,`n  `"b`": 2`n}`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$h/.config/app/app.json" | Should -BeExactly $local
    $result.Output | Should -Match 'Conflict: .*/app\.json'
  }

  It 'merges a clean JSON change' {
    Set-Upstream 'cfg/app.json' "{`n  `"a`": 1,`n  `"m`": 0,`n  `"b`": 2`n}`n"
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Write-FixtureFile "$h/.config/app/app.json" "{`n  `"a`": 1,`n  `"c`": 3,`n  `"m`": 0,`n  `"b`": 2`n}`n"
    Set-Upstream 'cfg/app.json' "{`n  `"a`": 1,`n  `"m`": 0,`n  `"d`": 4,`n  `"b`": 2`n}`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    $live = Read-FixtureFile "$h/.config/app/app.json"
    $live | Should -BeExactly "{`n  `"a`": 1,`n  `"c`": 3,`n  `"m`": 0,`n  `"d`": 4,`n  `"b`": 2`n}`n"
    { $live | ConvertFrom-Json } | Should -Not -Throw
    $result.Output | Should -Match 'Merged .*/app\.json'
  }

  It 'a pull conflict stops before any write' {
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Write-FixtureFile "$r/plainrc" "plain`nmine`n"
    git -C $r commit -q -am 'local change'
    Set-Upstream 'plainrc' "plain`ntheirs`n"
    Set-Upstream 'otherrc' "other`nupstream`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 1
    Read-FixtureFile "$h/.otherrc" | Should -BeExactly "other`n"
    $result.Output | Should -Match 'plainrc'
  }

  It 'refuses to apply while the repo has unresolved git conflicts' {
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Write-FixtureFile "$r/plainrc" "plain`nmine`n"
    git -C $r commit -q -am 'local change'
    Set-Upstream 'plainrc' "plain`ntheirs`n"
    (Invoke-SyncScript '-NoPrompt').ExitCode | Should -Be 1
    Read-FixtureFile "$r/plainrc" | Should -Match '<<<<<<<'
    $result = Invoke-SyncScript '-NoPull', '-NoPrompt'
    $result.ExitCode | Should -Be 1
    $result.Output | Should -Match 'unresolved git conflicts.*plainrc'
    Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plain`n"
  }

  It "-NoPull doesn't touch git" {
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Set-Upstream 'otherrc' "b`n"
    $head = git -C $r rev-parse HEAD
    $result = Invoke-SyncScript '-NoPull', '-NoPrompt'
    $result.ExitCode | Should -Be 0
    git -C $r rev-parse HEAD | Should -Be $head
    Read-FixtureFile "$h/.otherrc" | Should -BeExactly "other`n"
  }

  It 'stashes and restores uncommitted repo changes around the pull' {
    Invoke-SyncScript '-NoPrompt' | Out-Null
    Write-FixtureFile "$r/plainrc" "plain`nuncommitted`n"
    Set-Upstream 'otherrc' "b`n"
    $result = Invoke-SyncScript '-NoPrompt'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$r/plainrc" | Should -BeExactly "plain`nuncommitted`n"
    Read-FixtureFile "$h/.otherrc" | Should -BeExactly "b`n"
    git -C $r stash list | Should -BeNullOrEmpty
  }
}

Describe 'sync.ps1 local changes and copy-back' {
  BeforeEach {
    $f = New-SyncFixture
    $h = $f.Home
    $r = $f.Repo
    $applied = "$($f.State)/applied"
    Invoke-TestSync | Out-Null
  }

  AfterEach {
    Remove-SyncFixture
  }

  It '-CopyBack writes the live change into the repo with placeholders' {
    $before = Read-FixtureFile "$applied/.config/app/app.json"
    Write-FixtureFile "$h/.config/app/app.json" "{`"a`":1,`"q`":`"$h/y`"}`n"
    $result = Invoke-SyncScript '-NoPull', '-CopyBack'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$r/cfg/app.json" | Should -BeExactly "{`"a`":1,`"q`":`"@HOME@/y`"}`n"
    Read-FixtureFile "$applied/.config/app/app.json" | Should -BeExactly $before
  }

  It '-CopyBack adds a new file under a managed directory' {
    Write-FixtureFile "$h/.skills/new/SKILL.md" "new skill`n"
    $result = Invoke-SyncScript '-NoPull', '-CopyBack'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$r/skills/new/SKILL.md" | Should -BeExactly "new skill`n"
  }

  It 'report shows the home path as @HOME@' {
    Write-FixtureFile "$h/.plainrc" "plain`n$h/z`n"
    $result = Invoke-TestSync
    $result.ExitCode | Should -Be 0
    $result.Output | Should -Match ([regex]::Escape('@HOME@/z'))
    $result.Output | Should -Not -Match ([regex]::Escape("$h/z"))
  }

  It "-NoPrompt doesn't copy back" {
    Write-FixtureFile "$h/.plainrc" "plain`nlocal`n"
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$r/plainrc" | Should -BeExactly "plain`n"
  }

  It '-CopyBack -WhatIf changes nothing' {
    Write-FixtureFile "$h/.plainrc" "plain`nlocal`n"
    $result = Invoke-SyncScript '-NoPull', '-CopyBack', '-WhatIf'
    $result.ExitCode | Should -Be 0 -Because $result.Output
    Read-FixtureFile "$r/plainrc" | Should -BeExactly "plain`n"
    $result.Output | Should -Match '~ Copy back'
    $result.Output | Should -Not -Match 'What if:'
  }
}
