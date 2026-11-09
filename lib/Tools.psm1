Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Lookups about installed tools and their latest versions. All are read-only, so they run in dry-run too.

function Test-AptInstalled {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Package)
  if (-not (Get-Command dpkg-query -ErrorAction SilentlyContinue)) { return $false }
  $PSNativeCommandUseErrorActionPreference = $false
  $status = dpkg-query -W -f='${Status}' $Package 2>$null
  [bool]($status -match 'ok installed')
}

# GitKraken's .deb adds no apt repo, so `apt upgrade` never updates it. Its download URL redirects to a
# versioned path (…/linux/x64/<version>/…/gitkraken-amd64.deb), which is how the latest version is found.
# That URL format isn't a documented API, so callers treat a failed lookup as "unknown" and carry on.
$GitKrakenDebUrl = 'https://release.gitkraken.com/linux/gitkraken-amd64.deb'

function Get-GitKrakenVersionFromUrl {
  [OutputType([string])]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Url)
  if ($Url -match '/linux/x64/(\d+(\.\d+)+)/') { return $Matches[1] }
  $null
}

# Reads the latest version from the download redirect without downloading the package; $null on any failure.
function Get-GitKrakenLatestVersion {
  [OutputType([string])]
  param()
  $PSNativeCommandUseErrorActionPreference = $false
  $url = curl -fsSL --max-time 20 -r 0-0 -o /dev/null -w '%{url_effective}' $GitKrakenDebUrl 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $url) { return $null }
  Get-GitKrakenVersionFromUrl ([string]$url)
}

# Ignores a Debian revision suffix on the installed version (12.6.2-1 equals 12.6.2).
function Test-GitKrakenNeedsUpdate {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Installed, [Parameter(Mandatory)][string]$Latest)
  ($Installed -split '-', 2)[0] -ne $Latest
}

# The newest Node LTS version known to fnm (e.g. v26.13.0), or $null.
function Get-LatestNodeLts {
  [OutputType([string])]
  param()
  $PSNativeCommandUseErrorActionPreference = $false
  $lines = @(fnm list-remote --lts 2>$null | Where-Object { $_ -and $_.Trim() })
  if (-not $lines.Count) { return $null }
  ($lines[-1].Trim() -split '\s+')[0]
}

# fnm's default Node version. Not 'fnm current', which follows .node-version files.
function Get-FnmDefault {
  [OutputType([string])]
  param()
  $PSNativeCommandUseErrorActionPreference = $false
  foreach ($line in @(fnm list 2>$null)) {
    $fields = $line.Trim() -split '\s+'
    if ($fields -contains 'default' -and $fields.Count -ge 2) { return $fields[1] }
  }
  $null
}

# Checks WSL's interop file rather than $env:WSL_DISTRO_NAME, which SSH sessions don't have.
function Test-Wsl {
  [OutputType([bool])]
  param()
  [IO.File]::Exists('/proc/sys/fs/binfmt_misc/WSLInterop')
}

# The installer only adds an 'hc' link when no other 'hc' is on PATH, so steps use this path instead.
function Get-HerdrCorePath {
  [OutputType([string])]
  param()
  "$($env:HOME)/.local/bin/herdr-core"
}

# The folders under home that installers put tools in, the same ones bash/.bashrc adds to PATH. Scripts put
# them on their own PATH, because on a fresh machine the shell that started them predates the tools.
function Get-ToolBinDirectories {
  [OutputType([string[]])]
  param()
  $homeDir = $env:HOME
  "$homeDir/.local/bin", "$homeDir/.local/share/fnm", "$homeDir/.opencode/bin", "$homeDir/.aspire/bin"
}

Export-ModuleMember -Function Get-ToolBinDirectories, Test-Wsl, Get-HerdrCorePath, Test-AptInstalled, Get-GitKrakenVersionFromUrl, Get-GitKrakenLatestVersion,
  Test-GitKrakenNeedsUpdate, Get-LatestNodeLts, Get-FnmDefault -Variable GitKrakenDebUrl
