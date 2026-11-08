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

Describe 'sshd for the Herdr app' {
  BeforeEach {
    $saved = @{ HOME = $env:HOME; PATH = $env:PATH; DOTFILES_REPO = $env:DOTFILES_REPO }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "setup-test-$([guid]::NewGuid())"
    $h = "$tmp/home"
    $bin = "$tmp/bin"
    $log = "$tmp/calls.log"
    $configDir = "$tmp/sshd_config.d"
    $sshd = "$tmp/sshd"
    New-Item -ItemType Directory -Path $h, $bin, $configDir | Out-Null
    Write-FixtureFile $sshd ''
    $env:HOME = $h
    $env:DOTFILES_REPO = (Resolve-Path "$PSScriptRoot/..").Path
    $env:PATH = "${bin}:/usr/bin:/bin"
    $repoConfig = "$env:DOTFILES_REPO/linux/sshd_config.d/herdr-wsl.conf"
    # sudo logs what it was asked to run and fails when that contains the text in $tmp/fail.
    Write-FixtureFile "$tmp/fail" ''
    New-FakeCommand 'sudo' "echo `"`$*`" >>'$log'; fail=`$(cat '$tmp/fail'); if [ -n `"`$fail`" ] && [[ `"`$*`" == *`"`$fail`"* ]]; then exit 1; fi"
    Write-FixtureFile "$tmp/enabled" 'disabled'
    Write-FixtureFile "$tmp/active" 'inactive'
    New-FakeCommand 'systemctl' "case `"`$1`" in is-enabled) cat '$tmp/enabled' ;; is-active) cat '$tmp/active' ;; esac"
    Mock Test-Wsl -ModuleName Setup { $true }
    Set-DryRun $false
  }

  AfterEach {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Set-DryRun $false
    Remove-Item -Recurse -Force $tmp
  }

  It 'sshd: skips when not WSL' {
    Mock Test-Wsl -ModuleName Setup { $false }
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    Get-Calls | Should -BeNullOrEmpty
    $out | Should -Match '  - Not WSL'
  }

  It 'sshd: warns when openssh-server is missing' {
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath "$tmp/missing" }
    Get-Calls | Should -BeNullOrEmpty
    $out | Should -Match "  ! openssh-server isn't installed"
  }

  It 'sshd: skips when the config matches and ssh is running' {
    Copy-Item $repoConfig "$configDir/herdr-wsl.conf"
    Write-FixtureFile "$tmp/enabled" "enabled`n"
    Write-FixtureFile "$tmp/active" "active`n"
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    Get-Calls | Should -BeNullOrEmpty
    $out | Should -Match '  - sshd for the Herdr app is already set up'
  }

  It 'sshd: installs the config and restarts ssh when it differs' {
    Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd } | Out-Null
    $calls = Get-Calls
    $calls.Count | Should -Be 4
    $calls[0] | Should -Be "install -m 644 $repoConfig $configDir/herdr-wsl.conf"
    $calls[1] | Should -Be 'sshd -t'
    $calls[2] | Should -Be 'systemctl enable ssh'
    $calls[3] | Should -Be 'systemctl restart ssh'
  }

  It "sshd: doesn't restart when sshd -t fails" {
    Write-FixtureFile "$tmp/fail" 'sshd -t'
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    Get-Calls | Should -Not -Contain 'systemctl restart ssh'
    $out | Should -Match 'sshd setup failed'
  }

  It "sshd: a failed restart warns and doesn't throw" {
    Write-FixtureFile "$tmp/fail" 'restart'
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    $out | Should -Match '  ! sshd setup failed.*2222'
  }

  It 'sshd: warns when authorized_keys has no key' {
    Write-FixtureFile "$h/.ssh/authorized_keys" ''
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    $out | Should -Match '  ! No keys in ~/\.ssh/authorized_keys'
  }

  It "sshd: doesn't warn when authorized_keys has a key" {
    Write-FixtureFile "$h/.ssh/authorized_keys" "ssh-ed25519 AAAAC3Nz windows`n"
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    $out | Should -Not -Match 'authorized_keys'
  }

  It 'sshd: -WhatIf changes nothing' {
    Set-DryRun $true
    $out = Invoke-Captured { Invoke-WslSshd -ConfigDir $configDir -SshdPath $sshd }
    Get-Calls | Should -BeNullOrEmpty
    $out | Should -Match '  ~ sudo install -m 644'
    $out | Should -Match '  ~ sudo systemctl restart ssh'
  }
}
