Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
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

  It "Write-Skip uses the bash scripts' prefix" {
    $out = Write-Skip 'hello' 6>&1 | Out-String
    $out | Should -Match ([regex]::Escape('  - hello'))
  }
}
