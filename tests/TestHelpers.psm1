Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A throwaway machine for sync tests: a temp home, a bare remote, this machine's clone and another machine's clone.

$script:FixtureEnvNames = @(
  'HOME', 'DOTFILES_REPO', 'DOTFILES_STATE', 'XDG_CACHE_HOME', 'GIT_CONFIG_NOSYSTEM',
  'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL'
)
$script:SavedEnv = $null
$script:Fixture = $null

$script:SeedManifest = @'
{
  "entries": [
    { "source": "plainrc", "linux": "~/.plainrc" },
    { "source": "otherrc", "linux": "~/.otherrc" },
    { "source": "cfg/app.json", "linux": "~/.config/app/app.json" },
    { "source": "skills", "linux": "~/.skills", "exclude": ["synced/**"] }
  ]
}

'@

# Takes plain $args so git options such as -A aren't bound as PowerShell parameters.
function Invoke-FixtureGit {
  $dir, $gitArgs = $args
  $output = & git -C $dir @gitArgs 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') failed in ${dir}: $output" }
}

# Writes UTF-8 without a BOM, exactly as given, creating parent folders.
function Write-FixtureFile {
  param([string]$Path, [AllowEmptyString()][string]$Content)
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
  [IO.File]::WriteAllBytes($Path, [Text.UTF8Encoding]::new($false).GetBytes($Content))
}

function Read-FixtureFile {
  param([string]$Path)
  [Text.UTF8Encoding]::new($false).GetString([IO.File]::ReadAllBytes($Path))
}

function New-SyncFixture {
  $root = Join-Path ([IO.Path]::GetTempPath()) "sync-test-$([guid]::NewGuid())"
  $fixture = [pscustomobject]@{
    Root = $root
    Home = "$root/home"
    Repo = "$root/repo"
    State = "$root/state"
    Remote = "$root/remote.git"
    Other = "$root/other"
  }
  # Set before any setup step, so Remove-SyncFixture cleans up after a setup that fails partway.
  $script:Fixture = $fixture

  $script:SavedEnv = @{}
  foreach ($name in $script:FixtureEnvNames) { $script:SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name) }
  $env:HOME = $fixture.Home
  $env:DOTFILES_REPO = $fixture.Repo
  $env:DOTFILES_STATE = $fixture.State
  # pwsh writes a startup cache under ~/.cache; keeping it out of the temp home leaves only sync's writes there.
  $env:XDG_CACHE_HOME = "$root/cache"
  $env:GIT_CONFIG_NOSYSTEM = '1'
  $env:GIT_AUTHOR_NAME = 'Sync Test'
  $env:GIT_AUTHOR_EMAIL = 'sync-test@example.invalid'
  $env:GIT_COMMITTER_NAME = 'Sync Test'
  $env:GIT_COMMITTER_EMAIL = 'sync-test@example.invalid'

  New-Item -ItemType Directory -Path $fixture.Home | Out-Null
  & git init -q --bare -b main $fixture.Remote
  if ($LASTEXITCODE -ne 0) { throw 'git init --bare failed' }

  $seed = "$root/seed"
  & git init -q -b main $seed
  if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
  Write-FixtureFile "$seed/dotfiles.json" $script:SeedManifest
  Write-FixtureFile "$seed/plainrc" "plain`n"
  Write-FixtureFile "$seed/otherrc" "other`n"
  Write-FixtureFile "$seed/cfg/app.json" "{`"a`":1}`n"
  Write-FixtureFile "$seed/skills/a/SKILL.md" "skill a`n"
  Invoke-FixtureGit $seed add -A
  Invoke-FixtureGit $seed commit -q -m seed
  Invoke-FixtureGit $seed remote add origin $fixture.Remote
  Invoke-FixtureGit $seed push -q origin main
  Remove-Item -Recurse -Force $seed

  & git clone -q $fixture.Remote $fixture.Repo 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
  & git clone -q $fixture.Remote $fixture.Other 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }

  $fixture
}

function Remove-SyncFixture {
  if ($script:SavedEnv) {
    foreach ($name in $script:SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $script:SavedEnv[$name]) }
    $script:SavedEnv = $null
  }
  if ($script:Fixture) {
    if (Test-Path $script:Fixture.Root) { Remove-Item -Recurse -Force $script:Fixture.Root }
    $script:Fixture = $null
  }
}

# Runs sync.ps1 in a child process, so its output is redirected as in a non-interactive run.
function Invoke-SyncScript {
  param([string[]]$Arguments = @())
  $script = Join-Path $PSScriptRoot '../sync.ps1'
  $output = & pwsh -NoProfile -File $script @Arguments 2>&1 | Out-String
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

# Commits and pushes a change from the other machine's clone.
function Set-Upstream {
  param([string]$Path, [AllowEmptyString()][string]$Content)
  $other = $script:Fixture.Other
  Write-FixtureFile (Join-Path $other $Path) $Content
  Invoke-FixtureGit $other add -A
  Invoke-FixtureGit $other commit -q -m "upstream: $Path"
  Invoke-FixtureGit $other push -q origin main
}

Export-ModuleMember -Function New-SyncFixture, Remove-SyncFixture, Invoke-SyncScript, Set-Upstream, Write-FixtureFile, Read-FixtureFile
