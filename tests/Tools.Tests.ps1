Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  # Pester runs top-level code only while discovering tests; these lines apply strictness to the tests themselves.
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  Import-Module "$PSScriptRoot/../lib/Tools.psm1" -Force
  Import-Module "$PSScriptRoot/TestHelpers.psm1" -Force
}

Describe 'GitKraken versions' {
  It 'reads the version from the download redirect' {
    Get-GitKrakenVersionFromUrl 'https://release.gitkraken.dev/gkd/production/normal/linux/x64/12.6.2/3LdymkbiGLlvUgLoGwehfDP0Qeo/gitkraken-amd64.deb' |
      Should -Be '12.6.2'
  }

  It 'returns $null for a URL without a version' {
    Get-GitKrakenVersionFromUrl $GitKrakenDebUrl | Should -BeNullOrEmpty
  }

  It 'needs an update when the versions differ' {
    Test-GitKrakenNeedsUpdate '12.6.2' '12.7.0' | Should -BeTrue
  }

  It "doesn't need an update when they match" {
    Test-GitKrakenNeedsUpdate '12.6.2' '12.6.2' | Should -BeFalse
  }

  It 'ignores the Debian revision' {
    Test-GitKrakenNeedsUpdate '12.6.2-1' '12.6.2' | Should -BeFalse
  }
}

Describe 'fnm' {
  BeforeEach {
    $savedPath = $env:PATH
    $bin = Join-Path ([IO.Path]::GetTempPath()) "tools-test-$([guid]::NewGuid())"
    Write-FixtureFile "$bin/fnm" @'
#!/usr/bin/env bash
case "$*" in
  "list-remote --lts") printf 'v24.22.2 (Krypton)\nv26.13.0 (Lithium)\n' ;;
  "list") printf '* v24.16.0\n* v26.13.0 default\n* system\n' ;;
esac
'@
    chmod +x "$bin/fnm"
    $env:PATH = "${bin}:$env:PATH"
  }

  AfterEach {
    $env:PATH = $savedPath
    Remove-Item -Recurse -Force $bin
  }

  It "Get-LatestNodeLts returns the last line's version" {
    Get-LatestNodeLts | Should -Be 'v26.13.0'
  }

  It 'Get-FnmDefault reads the default alias' {
    Get-FnmDefault | Should -Be 'v26.13.0'
  }
}
