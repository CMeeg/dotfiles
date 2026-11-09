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
}

Describe 'Common' {
  BeforeEach {
    $savedHome = $env:HOME
    $savedState = $env:DOTFILES_STATE
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Set-DryRun $false
  }

  AfterEach {
    $env:HOME = $savedHome
    $env:DOTFILES_STATE = $savedState
    Set-DryRun $false
    Remove-Item -Recurse -Force $tmp
  }

  It 'Resolve-TargetPath expands a leading tilde from $env:HOME' {
    $env:HOME = '/tmp/h'
    Resolve-TargetPath '~/.bashrc' | Should -Be '/tmp/h/.bashrc'
  }

  It 'Get-StateDir honours DOTFILES_STATE' {
    $env:HOME = '/tmp/h'
    $env:DOTFILES_STATE = '/tmp/state'
    Get-StateDir | Should -Be '/tmp/state'
    $env:DOTFILES_STATE = $null
    Get-StateDir | Should -Be '/tmp/h/.local/state/dotfiles'
  }

  It 'Invoke-Step prints a dry line and runs nothing in dry-run' {
    Set-DryRun $true
    $out = Invoke-Step "touch $tmp/x" 6>&1 | Out-String
    "$tmp/x" | Should -Not -Exist
    $out | Should -Match '~ touch'
  }

  It 'Invoke-Step fails a pipeline whose first command fails' {
    $out = & {
      try { Invoke-Step 'false | cat' } catch { 'threw' }
    } 6>&1 | Out-String
    $out | Should -Match 'threw'
    $out | Should -Match ([regex]::Escape('Command failed (exit code 1)'))
  }

  It 'Invoke-Step runs a succeeding command' {
    Invoke-Step "touch $tmp/x"
    "$tmp/x" | Should -Exist
  }

  It 'Add-PathEntry puts a folder first on PATH once' {
    $savedPath = $env:PATH
    try {
      $env:PATH = '/usr/bin:/bin'
      Add-PathEntry '/tmp/h/.local/bin'
      Add-PathEntry '/tmp/h/.local/bin'
      $env:PATH | Should -Be '/tmp/h/.local/bin:/usr/bin:/bin'
    } finally {
      $env:PATH = $savedPath
    }
  }

  It 'Resolve-PhysicalPath follows links anywhere in the path' {
    New-Item -ItemType Directory -Path "$tmp/real/sub" | Out-Null
    New-Item -ItemType SymbolicLink -Path "$tmp/link" -Target "$tmp/real" | Out-Null
    Resolve-PhysicalPath "$tmp/link/sub/file.txt" | Should -Be "$tmp/real/sub/file.txt"
    Resolve-PhysicalPath "$tmp/link/" | Should -Be "$tmp/real"
    Resolve-PhysicalPath "$tmp/real/missing/x" | Should -Be "$tmp/real/missing/x"
  }

  It "Write-Skip uses the bash scripts' prefix" {
    $out = Write-Skip 'hello' 6>&1 | Out-String
    $out | Should -Match ([regex]::Escape('  - hello'))
  }
}
