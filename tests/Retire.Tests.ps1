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
  Import-Module "$PSScriptRoot/../lib/State.psm1" -Force
  Import-Module "$PSScriptRoot/../lib/Retire.psm1" -Force
  Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force

  # Puts a bash script called $Name first on PATH.
  function New-FakeCommand {
    param([string]$Name, [string]$Body)
    Write-FixtureFile "$bin/$Name" "#!/usr/bin/env bash`n$Body`n"
    chmod +x "$bin/$Name"
  }

  # A relative link, as stow makes them.
  function New-RepoLink {
    param([string]$Link, [string]$RepoPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Link)) | Out-Null
    $relative = [IO.Path]::GetRelativePath([IO.Path]::GetDirectoryName($Link), "$repo/$RepoPath")
    New-Item -ItemType SymbolicLink -Path $Link -Target $relative | Out-Null
  }

  function Test-IsLink {
    param([string]$Path)
    $item = Get-Item -Force -LiteralPath $Path -ErrorAction SilentlyContinue
    [bool]($item -and $item.LinkTarget)
  }

  function Invoke-Captured {
    param([scriptblock]$Block)
    & $Block 6>&1 | Out-String
  }
}

Describe 'retire steps' {
  BeforeEach {
    $saved = @{ HOME = $env:HOME; DOTFILES_REPO = $env:DOTFILES_REPO; DOTFILES_STATE = $env:DOTFILES_STATE; PATH = $env:PATH }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "retire-test-$([guid]::NewGuid())"
    $h = "$tmp/home"
    $repo = "$tmp/repo"
    $bin = "$tmp/bin"
    $log = "$tmp/calls.log"
    New-Item -ItemType Directory -Path $h, $repo, $bin | Out-Null
    $env:HOME = $h
    $env:DOTFILES_REPO = $repo
    $env:DOTFILES_STATE = "$tmp/state"
    $env:PATH = "${bin}:$env:PATH"
    Write-FixtureFile "$repo/dotfiles.json" @'
{
  "entries": [
    { "source": "plainrc", "linux": "~/.plainrc" },
    { "source": "cfg/app.json", "linux": "~/.config/app/app.json" }
  ]
}
'@
    Write-FixtureFile "$repo/plainrc" "plain`n"
    Write-FixtureFile "$repo/cfg/app.json" "{`"p`":`"@HOME@/x`"}`n"
    # Fakes for everything a retire step might run, so no test touches this machine's packages.
    New-FakeCommand 'sudo' "echo `"sudo `$*`" >>'$log'"
    New-FakeCommand 'dpkg-query' 'echo "unknown ok not-installed"; exit 1'
    New-FakeCommand 'dotnet' "echo `"dotnet `$*`" >>'$log'; echo 'Package Id      Version      Commands'"
    New-FakeCommand 'pgrep' 'exit 1'
    New-FakeCommand 'pkill' "echo `"pkill `$*`" >>'$log'; exit 0"
    Set-DryRun $false
  }

  AfterEach {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Set-DryRun $false
    Remove-Item -Recurse -Force $tmp
  }

  Context 'stow' {
    It 'replaces a managed stow link with a real copy and seeds state' {
      New-RepoLink "$h/.plainrc" 'plainrc'
      Invoke-Captured { Invoke-RetireStow } | Out-Null
      Test-IsLink "$h/.plainrc" | Should -BeFalse
      Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plain`n"
      Read-Applied "$h/.plainrc" | Should -BeExactly "plain`n"
    }

    It 'fills @HOME@ when replacing a link' {
      New-RepoLink "$h/.config/app/app.json" 'cfg/app.json'
      Invoke-Captured { Invoke-RetireStow } | Out-Null
      Read-FixtureFile "$h/.config/app/app.json" | Should -BeExactly "{`"p`":`"$h/x`"}`n"
      Read-Applied "$h/.config/app/app.json" | Should -BeExactly "{`"p`":`"$h/x`"}`n"
    }

    It 'fills @DOTFILES@ when replacing a link' {
      Write-FixtureFile "$repo/plainrc" "plugins=@DOTFILES@/p`n"
      New-RepoLink "$h/.plainrc" 'plainrc'
      Invoke-Captured { Invoke-RetireStow } | Out-Null
      Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plugins=$repo/p`n"
    }

    It 'replaces a link that points at the resolved path of a linked repo' {
      New-Item -ItemType SymbolicLink -Path "$tmp/repo-link" -Target $repo | Out-Null
      $env:DOTFILES_REPO = "$tmp/repo-link"
      New-Item -ItemType SymbolicLink -Path "$h/.plainrc" -Target "$repo/plainrc" | Out-Null
      $out = Invoke-Captured { Invoke-RetireStow }
      Test-IsLink "$h/.plainrc" | Should -BeFalse
      Read-FixtureFile "$h/.plainrc" | Should -BeExactly "plain`n"
      $out | Should -Not -Match 'Removed stow link'
    }

    It 'deletes a link to an unmanaged repo file' {
      Write-FixtureFile "$repo/old/.config/old/x.conf" "old`n"
      New-RepoLink "$h/.config/old/x.conf" 'old/.config/old/x.conf'
      Write-FixtureFile "$h/.config/keep.txt" "keep`n"
      $out = Invoke-Captured { Invoke-RetireStow }
      $out | Should -Match ([regex]::Escape("$h/.config/old/x.conf"))
      Test-IsLink "$h/.config/old/x.conf" | Should -BeFalse
      "$h/.config/old" | Should -Not -Exist
      "$h/.config" | Should -Exist
      Read-FixtureFile "$repo/old/.config/old/x.conf" | Should -BeExactly "old`n"
    }

    It 'deletes a dangling repo link and empty parents' {
      New-RepoLink "$h/.agents/skills/x/SKILL.md" 'agents/.agents/skills/x/SKILL.md'
      $out = Invoke-Captured { Invoke-RetireStow }
      $out | Should -Match ([regex]::Escape("$h/.agents/skills/x/SKILL.md"))
      Test-IsLink "$h/.agents/skills/x/SKILL.md" | Should -BeFalse
      "$h/.agents" | Should -Not -Exist
      $h | Should -Exist
    }

    It 'leaves links outside the repo alone' {
      New-Item -ItemType Directory -Path "$h/.config" | Out-Null
      New-Item -ItemType SymbolicLink -Path "$h/.config/foo" -Target '/nonexistent' | Out-Null
      Invoke-Captured { Invoke-RetireStow } | Out-Null
      Test-IsLink "$h/.config/foo" | Should -BeTrue
    }

    It 'warns when ~/.agents keeps foreign files' {
      New-RepoLink "$h/.agents/skills/x/SKILL.md" 'agents/.agents/skills/x/SKILL.md'
      Write-FixtureFile "$h/.agents/skills/aspire/SKILL.md" "skill`n"
      $out = Invoke-Captured { Invoke-RetireStow }
      "$h/.agents/skills/aspire/SKILL.md" | Should -Exist
      $out | Should -Match 'left in place'
    }

    It 'second run is a no-op' {
      New-RepoLink "$h/.plainrc" 'plainrc'
      New-RepoLink "$h/.agents/skills/x/SKILL.md" 'agents/.agents/skills/x/SKILL.md'
      New-Item -ItemType Directory -Path "$h/.bun", "$h/.opendesign" | Out-Null
      Invoke-Captured { Invoke-RetireSteps } | Out-Null
      $out = Invoke-Captured { Invoke-RetireSteps }
      $out | Should -Match '  - '
      $out | Should -Not -Match '✓|  ! |  ~ '
    }

    It '-WhatIf changes nothing' {
      New-RepoLink "$h/.plainrc" 'plainrc'
      New-RepoLink "$h/.agents/skills/x/SKILL.md" 'agents/.agents/skills/x/SKILL.md'
      $out = & pwsh -NoProfile -File "$PSScriptRoot/../retire.ps1" -WhatIf 2>&1 | Out-String
      $LASTEXITCODE | Should -Be 0 -Because $out
      Test-IsLink "$h/.plainrc" | Should -BeTrue
      Test-IsLink "$h/.agents/skills/x/SKILL.md" | Should -BeTrue
      "$tmp/state" | Should -Not -Exist
      $out | Should -Match '  ~ '
      $out | Should -Not -Match 'What if:'
      $out | Should -Not -Match '✓ Removed stow link'
    }

    It 'removes stow when installed' {
      New-FakeCommand 'dpkg-query' 'echo "install ok installed"'
      Invoke-Captured { Invoke-RetireStow } | Out-Null
      Get-Content $log | Should -Contain 'sudo apt remove -y stow'
    }

    It 'Test-StowLinksPresent' {
      New-RepoLink "$h/.plainrc" 'plainrc'
      Test-StowLinksPresent | Should -BeTrue
      Invoke-Captured { Invoke-RetireStow } | Out-Null
      Test-StowLinksPresent | Should -BeFalse
    }
  }

  Context 'tools' {
    It 'OpenDesign: removes the folder even if pkill finds nothing' {
      New-Item -ItemType Directory -Path "$h/.opendesign/node_modules" | Out-Null
      New-FakeCommand 'pgrep' 'exit 0'
      New-FakeCommand 'pkill' 'exit 1'
      $out = Invoke-Captured { Invoke-RetireOpenDesign }
      "$h/.opendesign" | Should -Not -Exist
      $out | Should -Match '✓ OpenDesign removed'
    }

    It 'OpenDesign: skips when absent' {
      $out = Invoke-Captured { Invoke-RetireOpenDesign }
      $out | Should -Match '  - OpenDesign is not installed'
    }

    It 'Bun: removes the folder' {
      New-Item -ItemType Directory -Path "$h/.bun/bin" | Out-Null
      $out = Invoke-Captured { Invoke-RetireBun }
      "$h/.bun" | Should -Not -Exist
      $out | Should -Match '✓ Bun removed'
    }

    It 'Bun: dry-run keeps the folder' {
      New-Item -ItemType Directory -Path "$h/.bun/bin" | Out-Null
      Set-DryRun $true
      $out = Invoke-Captured { Invoke-RetireBun }
      "$h/.bun" | Should -Exist
      $out | Should -Match '~ rm -rf .*\.bun'
    }

    It 'superpowers clone: removes it and the empty packages folder' {
      New-Item -ItemType Directory -Path "$h/.local/share/opencode/packages/superpowers/.git" | Out-Null
      Invoke-Captured { Invoke-RetireSuperpowersClone } | Out-Null
      "$h/.local/share/opencode/packages" | Should -Not -Exist
      "$h/.local/share/opencode" | Should -Exist
    }

    It 'superpowers clone: keeps other packages' {
      New-Item -ItemType Directory -Path "$h/.local/share/opencode/packages/superpowers/.git", "$h/.local/share/opencode/packages/other" | Out-Null
      Invoke-Captured { Invoke-RetireSuperpowersClone } | Out-Null
      "$h/.local/share/opencode/packages/superpowers" | Should -Not -Exist
      "$h/.local/share/opencode/packages/other" | Should -Exist
    }

    It 'Aspire tool: uninstalls the global tool and installs nothing' {
      New-FakeCommand 'dotnet' "echo `"dotnet `$*`" >>'$log'; if [ `"`$*`" = 'tool list -g' ]; then echo 'Package Id      Version      Commands'; echo 'aspire.cli      13.4.6       aspire'; fi"
      $out = Invoke-Captured { Invoke-RetireAspireDotnetTool }
      Get-Content $log | Should -Contain 'dotnet tool uninstall -g aspire.cli'
      Get-Content $log | Where-Object { $_ -match ' install' } | Should -BeNullOrEmpty
      $out | Should -Match 'run \./install\.ps1'
    }

    It 'Aspire tool: skips when it is not a global tool' {
      $out = Invoke-Captured { Invoke-RetireAspireDotnetTool }
      Get-Content $log | Should -Not -Contain 'dotnet tool uninstall -g aspire.cli'
      $out | Should -Match '  - Aspire is not installed as a \.NET global tool'
    }

    It 'statuslines mods: uninstalls them and removes the marketplace, leaving other plugins' {
      New-FakeCommand 'claude' @"
echo "claude `$*" >>'$log'
case "`$*" in
  'plugin list --json') echo '[{"id":"sub-meter@statuslines"},{"id":"context-bar@statuslines"},{"id":"superpowers@claude-plugins-official"}]' ;;
  'plugin marketplace list --json') echo '[{"name":"statuslines"},{"name":"claude-themes"}]' ;;
esac
"@
      Invoke-Captured { Invoke-RetireStatuslinesMods } | Out-Null
      $calls = Get-Content $log
      $calls | Should -Contain 'claude plugin uninstall sub-meter@statuslines --scope user'
      $calls | Should -Contain 'claude plugin uninstall context-bar@statuslines --scope user'
      $calls | Should -Contain 'claude plugin marketplace remove statuslines'
      $calls | Where-Object { $_ -match 'superpowers|claude-themes' -and $_ -notmatch 'list' } | Should -BeNullOrEmpty
    }

    It 'statuslines mods: skips when none are installed' {
      New-FakeCommand 'claude' @"
echo "claude `$*" >>'$log'
echo '[]'
"@
      $out = Invoke-Captured { Invoke-RetireStatuslinesMods }
      Get-Content $log | Where-Object { $_ -match 'uninstall|remove' } | Should -BeNullOrEmpty
      $out | Should -Match '  - The statuslines mods are not installed'
    }
  }
}
