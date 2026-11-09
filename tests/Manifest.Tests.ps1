Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  # Pester runs top-level code only while discovering tests; these lines apply strictness to the tests themselves.
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  # Unload the repo's modules first: a module loaded by an earlier test file would stay bound to an older copy of
  # Common (and its dry-run flag) after this file reloads Common with -Force.
  Get-Module Common, Manifest, State, Json, Sync, Retire, Tools, Setup | Remove-Module -Force

  Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
  Import-Module "$PSScriptRoot/../lib/Manifest.psm1" -Force

  # Builds a git repo with the given manifest entries and files (path → content); returns its path.
  function New-TestRepo {
    param([object[]]$Entries, [hashtable]$Files, [string]$GitIgnore = '')
    $repo = Join-Path $tmp 'repo'
    New-Item -ItemType Directory -Path $repo | Out-Null
    git -C $repo init -q
    @{ entries = $Entries } | ConvertTo-Json -Depth 5 | Set-Content -Path "$repo/dotfiles.json"
    if ($GitIgnore) { Set-Content -Path "$repo/.gitignore" -Value $GitIgnore }
    foreach ($path in $Files.Keys) {
      $full = Join-Path $repo $path
      New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
      Set-Content -Path $full -Value $Files[$path]
    }
    $repo
  }
}

Describe 'Get-ManagedFiles' {
  BeforeEach {
    $savedHome = $env:HOME
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $env:HOME = "$tmp/home"
  }

  AfterEach {
    $env:HOME = $savedHome
    Remove-Item -Recurse -Force $tmp
  }

  It 'maps a file entry to its expanded target' {
    $repo = New-TestRepo -Entries @(@{ source = 'bash/.bashrc'; linux = '~/.bashrc' }) -Files @{ 'bash/.bashrc' = 'x' }
    $files = @(Get-ManagedFiles $repo)
    $files.Count | Should -Be 1
    $files[0].Source | Should -Be 'bash/.bashrc'
    $files[0].Target | Should -Be "$tmp/home/.bashrc"
    $files[0].DirectoryEntry | Should -BeNullOrEmpty
  }

  It 'expands a directory entry to its files' {
    $repo = New-TestRepo -Entries @(@{ source = 'skills'; linux = '~/.skills' }) -Files @{
      'skills/a/SKILL.md' = 'a'
      'skills/b/x.md' = 'b'
    }
    git -C $repo add skills/a/SKILL.md
    $files = @(Get-ManagedFiles $repo | Sort-Object Source)
    $files.Source | Should -Be @('skills/a/SKILL.md', 'skills/b/x.md')
    $files.Target | Should -Be @("$tmp/home/.skills/a/SKILL.md", "$tmp/home/.skills/b/x.md")
    $files[0].DirectoryEntry.Source | Should -Be 'skills'
  }

  It 'drops excluded and gitignored files' {
    $repo = New-TestRepo -Entries @(@{ source = 'skills'; linux = '~/.skills'; exclude = @('synced/**') }) -GitIgnore 'skills/tmp.log' -Files @{
      'skills/keep.md' = 'k'
      'skills/synced/s.md' = 's'
      'skills/tmp.log' = 'l'
    }
    @(Get-ManagedFiles $repo).Source | Should -Be @('skills/keep.md')
  }

  It 'skips entries with no key for this OS' {
    $repo = New-TestRepo -Entries @(@{ source = 'win.txt'; windows = '~/win.txt' }) -Files @{ 'win.txt' = 'w' }
    @(Get-ManagedFiles $repo).Count | Should -Be 0
  }

  It 'real manifest covers every stow package file' {
    $repo = Resolve-Path "$PSScriptRoot/.."
    $expected = git -C $repo ls-files bash git starship superfile herdr opencode claude |
      Where-Object { (Test-Path -LiteralPath (Join-Path $repo $_)) -and (Split-Path $_ -Leaf) -ne 'README.md' -and $_ -notlike 'claude/.claude/local-plugins/*' } |
      Sort-Object
    @(Get-ManagedFiles $repo).Source | Sort-Object | Should -Be $expected
  }
}

Describe 'Home placeholder' {
  It 'Expand-HomePlaceholder fills every token' {
    Expand-HomePlaceholder '@HOME@/a @HOME@/b' '/home/u' | Should -Be '/home/u/a /home/u/b'
  }

  It 'ConvertTo-HomePlaceholder replaces the home path before / and "' {
    ConvertTo-HomePlaceholder '"/home/u/x" /home/u' '/home/u' | Should -Be '"@HOME@/x" @HOME@'
  }

  It 'ConvertTo-HomePlaceholder leaves a longer username alone' {
    ConvertTo-HomePlaceholder '/home/u2/x' '/home/u' | Should -Be '/home/u2/x'
  }

  It 'Expand-Placeholders fills @HOME@ and @DOTFILES@' {
    Expand-Placeholders '@DOTFILES@/a @HOME@/b' '/home/u' '/home/u/.dotfiles' | Should -Be '/home/u/.dotfiles/a /home/u/b'
  }

  It 'ConvertTo-Placeholders turns the repo path into @DOTFILES@ before the home path' {
    ConvertTo-Placeholders '"/home/u/.dotfiles/a" /home/u/b' '/home/u' '/home/u/.dotfiles' | Should -Be '"@DOTFILES@/a" @HOME@/b'
  }

  It 'ConvertTo-Placeholders leaves a longer repo folder name alone' {
    ConvertTo-Placeholders '/home/u/.dotfiles2/x' '/home/u' '/home/u/.dotfiles' | Should -Be '@HOME@/.dotfiles2/x'
  }

  It 'both placeholders round-trip' {
    $text = "dirs = `"@DOTFILES@/plugins`"`nhome = '@HOME@/x'"
    ConvertTo-Placeholders (Expand-Placeholders $text '/home/u' '/home/u/.dotfiles') '/home/u' '/home/u/.dotfiles' | Should -Be $text
  }

  It 'placeholder round-trips' {
    $text = "path = `"@HOME@/a`"`nPATH=@HOME@/bin:`$PATH`nhome: '@HOME@'"
    ConvertTo-HomePlaceholder (Expand-HomePlaceholder $text '/home/u') '/home/u' | Should -Be $text
  }
}
