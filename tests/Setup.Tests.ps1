Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  # Pester runs top-level code only while discovering tests; these lines apply strictness to the tests themselves.
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
  Import-Module "$PSScriptRoot/../lib/Setup.psm1" -Force
  Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force

  function New-FakeCommand {
    param([string]$Name, [string]$Body = 'exit 0')
    Write-FixtureFile "$bin/$Name" "#!/usr/bin/env bash`n$Body`n"
    chmod +x "$bin/$Name"
  }

  # A fake herdr that prints $Status for 'integration status' and logs every call.
  function New-FakeHerdr {
    param([string]$Status)
    Write-FixtureFile "$tmp/herdr-status" $Status
    New-FakeCommand 'herdr' "echo `"herdr `$*`" >>'$log'; if [ `"`$*`" = 'integration status' ]; then cat '$tmp/herdr-status'; fi"
  }

  function Get-Calls {
    if (Test-Path $log) { @(Get-Content $log) } else { @() }
  }

  function Invoke-Captured {
    param([scriptblock]$Block)
    & $Block 6>&1 | Out-String
  }
}

Describe 'herdr integrations' {
  BeforeEach {
    $saved = @{ HOME = $env:HOME; PATH = $env:PATH }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "setup-test-$([guid]::NewGuid())"
    $h = "$tmp/home"
    $bin = "$tmp/bin"
    $log = "$tmp/calls.log"
    New-Item -ItemType Directory -Path $h, $bin | Out-Null
    $env:HOME = $h
    # Only the fakes and system folders, so this machine's real herdr, claude and opencode aren't found.
    $env:PATH = "${bin}:/usr/bin:/bin"
    New-FakeCommand 'claude'
    New-FakeCommand 'opencode'
    Set-DryRun $false
  }

  AfterEach {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -Recurse -Force $tmp
  }

  It 'skips when herdr is current and the hook is in settings' {
    New-FakeHerdr "claude: current (v11) ($h/.claude/hooks/herdr-agent-state.sh)`n"
    Write-FixtureFile "$h/.claude/settings.json" '{"hooks":{"SessionStart":[{"hooks":[{"command":"bash \"/x/.claude/hooks/herdr-agent-state.sh\" session"}]}]}}'
    $out = Invoke-Captured { Invoke-HerdrIntegration claude }
    Get-Calls | Should -Not -Contain 'herdr integration install claude'
    $out | Should -Match '  - '
  }

  It 'reinstalls when the settings file lacks the hook' {
    New-FakeHerdr "claude: current (v11) ($h/.claude/hooks/herdr-agent-state.sh)`n"
    Write-FixtureFile "$h/.claude/settings.json" '{"permissions":{}}'
    Invoke-Captured { Invoke-HerdrIntegration claude } | Out-Null
    Get-Calls | Should -Contain 'herdr integration install claude'
  }

  It 'installs when herdr reports not installed' {
    New-FakeHerdr "claude: not installed ($h/.claude/hooks/herdr-agent-state.sh)`n"
    Write-FixtureFile "$h/.claude/settings.json" '{"permissions":{}}'
    Invoke-Captured { Invoke-HerdrIntegration claude } | Out-Null
    Get-Calls | Should -Contain 'herdr integration install claude'
  }

  It 'opencode: skips when current and cli.json references herdr' {
    New-FakeHerdr "opencode: current (v13) ($h/.config/opencode/plugins/herdr-agent-state.js)`n"
    Write-FixtureFile "$h/.config/opencode/cli.json" '{"plugin":["./herdr-opencode"]}'
    Invoke-Captured { Invoke-HerdrIntegration opencode } | Out-Null
    Get-Calls | Should -Not -Contain 'herdr integration install opencode'
  }

  It 'opencode: installs when cli.json lacks the herdr plugin' {
    New-FakeHerdr "opencode: current (v13) ($h/.config/opencode/plugins/herdr-agent-state.js)`n"
    Write-FixtureFile "$h/.config/opencode/cli.json" '{"plugin":[]}'
    Invoke-Captured { Invoke-HerdrIntegration opencode } | Out-Null
    Get-Calls | Should -Contain 'herdr integration install opencode'
  }

  It "skips an agent that isn't installed" {
    New-FakeHerdr "opencode: not installed`n"
    Remove-Item "$bin/opencode"
    $out = Invoke-Captured { Invoke-HerdrIntegration opencode }
    Get-Calls | Should -Not -Contain 'herdr integration install opencode'
    $out | Should -Match '  - .*opencode'
  }

  It 'skips when herdr is missing' {
    $out = Invoke-Captured { Invoke-HerdrIntegration claude }
    $out | Should -Match '  - .*herdr'
  }
}
