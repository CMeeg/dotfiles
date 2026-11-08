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
  }

  It 'fills @HOME@ on apply' {
    Write-FixtureFile "$r/cfg/app.json" '{"p":"@HOME@/x"}'
    (Invoke-TestSync).ExitCode | Should -Be 0
    Read-FixtureFile "$h/.config/app/app.json" | Should -BeExactly "{`"p`":`"$h/x`"}"
  }
}
