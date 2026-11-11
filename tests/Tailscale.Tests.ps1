Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  Get-Module Common, Manifest, State, Json, Sync, Retire, Tools, Setup, Tailscale | Remove-Module -Force

  Import-Module "$PSScriptRoot/../lib/Common.psm1" -Force
  Import-Module "$PSScriptRoot/../lib/Tailscale.psm1" -Force
  Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force

  function New-FakeCommand {
    param([string]$Name, [string]$Body = 'exit 0')
    Write-FixtureFile "$bin/$Name" "#!/usr/bin/env bash`n$Body`n"
    chmod +x "$bin/$Name"
  }

  function Get-Calls {
    if (Test-Path $log) { @(Get-Content $log) } else { @() }
  }

  function Invoke-Captured {
    param([scriptblock]$Block)
    & $Block 6>&1 | Out-String
  }

  # What 'tailscale status --json' and 'tailscale debug prefs' print; an empty status makes status fail.
  function Set-TailscaleState {
    param([string]$BackendState, [hashtable]$Prefs = @{}, [string]$DNSName = '')
    $status = if ($BackendState) { @{ BackendState = $BackendState; Self = @{ HostName = 'current-name'; DNSName = $DNSName } } | ConvertTo-Json } else { '' }
    Write-FixtureFile "$tmp/status" $status
    Write-FixtureFile "$tmp/prefs" ($Prefs | ConvertTo-Json)
  }

  function Get-MatchingPrefs {
    @{ ControlURL = 'https://controlplane.tailscale.com'; RunSSH = $true; OperatorUser = [Environment]::UserName; Hostname = 'meeg-laptop-wsl'; CorpDNS = $false }
  }

  function Get-AuthKeyFiles {
    @(Get-ChildItem -Path $tmp -Filter 'tailscale-authkey-*')
  }
}

Describe 'Tailscale setup' {
  BeforeEach {
    $saved = @{ HOME = $env:HOME; PATH = $env:PATH; TS_AUTHKEY = $env:TS_AUTHKEY; TMPDIR = $env:TMPDIR }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "tailscale-test-$([guid]::NewGuid())"
    $h = "$tmp/home"
    $bin = "$tmp/bin"
    $log = "$tmp/calls.log"
    New-Item -ItemType Directory -Path $h, $bin | Out-Null
    $env:HOME = $h
    $env:PATH = "${bin}:/usr/bin:/bin"
    $env:TS_AUTHKEY = $null
    # The auth key file goes in the temp folder, so this puts it where the tests can look for it.
    $env:TMPDIR = $tmp
    $user = [Environment]::UserName

    # sudo logs what it was asked to run, plus the contents and mode of any auth key file it was given.
    # 'tailscale up' fails when $tmp/up-fails exists.
    New-FakeCommand 'sudo' "echo `"`$*`" >>'$log'; for a in `"`$@`"; do case `"`$a`" in --auth-key=file:*) f=`"`${a#--auth-key=file:}`"; echo `"key: `$(cat `"`$f`") (mode `$(stat -c %a `"`$f`"))`" >>'$log' ;; esac; done; if [ `"`$2`" = up ] && [ -e '$tmp/up-fails' ]; then exit 1; fi"
    New-FakeCommand 'curl' "echo `"curl `$*`" >>'$log'"
    New-FakeCommand 'tailscale' "case `"`$1`" in status) s=`$(cat '$tmp/status'); [ -n `"`$s`" ] || exit 1; echo `"`$s`" ;; debug) cat '$tmp/prefs' ;; esac"
    Write-FixtureFile "$tmp/enabled" "enabled`n"
    Write-FixtureFile "$tmp/active" "active`n"
    New-FakeCommand 'systemctl' "case `"`$1`" in is-enabled) cat '$tmp/enabled' ;; is-active) cat '$tmp/active' ;; esac"
    Set-TailscaleState 'NeedsLogin'
    Mock Test-Wsl -ModuleName Tailscale { $true }
    Set-DryRun $false
  }

  AfterEach {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Set-DryRun $false
    Remove-Item -Recurse -Force $tmp
  }

  It 'installs tailscale when it is missing' {
    Mock Test-Command -ModuleName Tailscale -ParameterFilter { $Name -eq 'tailscale' } { $false }
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } | Out-Null
    Get-Calls | Should -Contain 'curl -fsSL https://tailscale.com/install.sh'
  }

  It 'skips the install when tailscale is on PATH' {
    $out = Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' }
    Get-Calls | Should -Not -Contain 'curl -fsSL https://tailscale.com/install.sh'
    $out | Should -Match '  - Tailscale is already installed'
  }

  It "enables tailscaled when it isn't running" {
    Write-FixtureFile "$tmp/active" "inactive`n"
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } | Out-Null
    Get-Calls | Should -Contain 'systemctl enable --now tailscaled'
  }

  It 'skips tailscaled when it is enabled and running' {
    $out = Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' }
    Get-Calls | Should -Not -Contain 'systemctl enable --now tailscaled'
    $out | Should -Match '  - tailscaled is already enabled and running'
  }

  It 'stops with an error when it has never connected and no hostname is given' {
    { Invoke-Captured { Invoke-TailscaleSetup } } | Should -Throw '*Not connected yet — run again with -Hostname*'
    Get-Calls | Should -Not -Match '^tailscale '
  }

  It 'logs in again with the saved name after the login expired' {
    $prefs = Get-MatchingPrefs
    Set-TailscaleState 'NeedsLogin' $prefs
    Invoke-Captured { Invoke-TailscaleSetup } | Out-Null
    Get-Calls | Should -Contain "tailscale up --ssh --operator=$user --hostname=meeg-laptop-wsl --accept-dns=false"
  }

  It "brings a stopped connection back up without repeating settings it already has" {
    Set-TailscaleState 'Stopped' (Get-MatchingPrefs)
    Invoke-Captured { Invoke-TailscaleSetup } | Out-Null
    Get-Calls | Should -Be @('tailscale up')
  }

  It 'sets the settings before bringing a stopped connection back up' {
    $prefs = Get-MatchingPrefs
    $prefs.RunSSH = $false
    Set-TailscaleState 'Stopped' $prefs
    Invoke-Captured { Invoke-TailscaleSetup } | Out-Null
    Get-Calls | Should -Be @("tailscale set --ssh --operator=$user --hostname=meeg-laptop-wsl --accept-dns=false", 'tailscale up')
  }

  It 'logs in with Tailscale SSH, the operator and the hostname, leaving DNS to Windows in WSL' {
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } | Out-Null
    Get-Calls | Should -Contain "tailscale up --ssh --operator=$user --hostname=meeg-laptop-wsl --accept-dns=false"
  }

  It 'keeps Tailscale DNS outside WSL' {
    Mock Test-Wsl -ModuleName Tailscale { $false }
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-server' } | Out-Null
    Get-Calls | Should -Contain "tailscale up --ssh --operator=$user --hostname=meeg-server"
  }

  It 'logs in with TS_AUTHKEY from a file it removes afterwards' {
    $env:TS_AUTHKEY = 'tskey-auth-test'
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } | Out-Null
    $calls = Get-Calls
    $up = @($calls | Where-Object { $_ -like 'tailscale up *' })
    $up.Count | Should -Be 1
    $up[0] | Should -Not -Match 'tskey-auth-test'
    $up[0] -match '--auth-key=file:(\S+)' | Should -BeTrue
    $calls | Should -Contain 'key: tskey-auth-test (mode 600)'
    Get-AuthKeyFiles | Should -BeNullOrEmpty
  }

  It 'removes the auth key file when tailscale up fails' {
    $env:TS_AUTHKEY = 'tskey-auth-test'
    Write-FixtureFile "$tmp/up-fails" ''
    { Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } } | Should -Throw
    Get-Calls | Should -Contain 'key: tskey-auth-test (mode 600)'
    Get-AuthKeyFiles | Should -BeNullOrEmpty
  }

  It 'names the device Tailscale chose when the hostname is taken' {
    Set-TailscaleState 'NeedsLogin' -DNSName 'meeg-laptop-wsl-1.tail1234.ts.net.'
    $out = Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' }
    $out | Should -Match '  ✓ Connected as meeg-laptop-wsl-1 with'
    $out | Should -Match '  ! Tailscale named this device meeg-laptop-wsl-1, as another device already has the name meeg-laptop-wsl\.'
  }

  It 'skips when connected and the settings match' {
    Set-TailscaleState 'Running' (Get-MatchingPrefs) 'meeg-laptop-wsl.tail1234.ts.net.'
    $out = Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' }
    Get-Calls | Should -Not -Match '^tailscale '
    $out | Should -Match '  - Already connected as meeg-laptop-wsl with'
  }

  It 'keeps Tailscale DNS on outside WSL when already connected' {
    Mock Test-Wsl -ModuleName Tailscale { $false }
    $prefs = Get-MatchingPrefs
    $prefs.Hostname = 'meeg-server'
    $prefs.CorpDNS = $true
    Set-TailscaleState 'Running' $prefs
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-server' } | Out-Null
    Get-Calls | Should -Not -Match '^tailscale '
  }

  It 'keeps the current name when connected and no hostname is given' {
    $prefs = Get-MatchingPrefs
    $prefs.Hostname = 'current-name'
    Set-TailscaleState 'Running' $prefs
    $out = Invoke-Captured { Invoke-TailscaleSetup }
    Get-Calls | Should -Not -Match '^tailscale '
    $out | Should -Match '  - Already connected as current-name'
  }

  It 'sets the settings again when Tailscale SSH was turned off' {
    $prefs = Get-MatchingPrefs
    $prefs.RunSSH = $false
    Set-TailscaleState 'Running' $prefs
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } | Out-Null
    Get-Calls | Should -Contain "tailscale set --ssh --operator=$user --hostname=meeg-laptop-wsl --accept-dns=false"
  }

  It 'renames the device when connected under another name' {
    $prefs = Get-MatchingPrefs
    $prefs.Hostname = 'laptop-leo2vfvm-1'
    Set-TailscaleState 'Running' $prefs
    Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' } | Out-Null
    Get-Calls | Should -Contain "tailscale set --ssh --operator=$user --hostname=meeg-laptop-wsl --accept-dns=false"
  }

  It '-WhatIf changes nothing' {
    Mock Test-Command -ModuleName Tailscale -ParameterFilter { $Name -eq 'tailscale' } { $false }
    Write-FixtureFile "$tmp/active" "inactive`n"
    $env:TS_AUTHKEY = 'tskey-auth-test'
    Set-DryRun $true
    $out = Invoke-Captured { Invoke-TailscaleSetup 'meeg-laptop-wsl' }
    Get-Calls | Should -BeNullOrEmpty
    Get-AuthKeyFiles | Should -BeNullOrEmpty
    $out | Should -Match '  ~ curl -fsSL https://tailscale.com/install.sh \| sh'
    $out | Should -Match '  ~ sudo systemctl enable --now tailscaled'
    $out | Should -Match '  ~ sudo tailscale up --ssh'
  }
}

Describe 'tailscale.ps1' {
  It 'rejects a hostname with capitals, which Tailscale would lower-case' {
    $pwsh = (Get-Process -Id $PID).Path
    $out = & $pwsh -NoProfile -File "$PSScriptRoot/../tailscale.ps1" -Hostname 'Meeg-Laptop' -WhatIf 2>&1 | Out-String
    $LASTEXITCODE | Should -Not -Be 0
    $out | Should -Match 'Hostname'
  }
}
