Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"
Import-Module "$PSScriptRoot/Tools.psm1"

# Opt-in Tailscale setup for a Linux machine or WSL distro, run by tailscale.ps1 (see tailscale/README.md).
# Each step is idempotent.

function Get-SystemdUnitState {
  param([string]$Check, [string]$Unit)
  $PSNativeCommandUseErrorActionPreference = $false
  "$(systemctl $Check $Unit 2>$null)".Trim()
}

# Parses the JSON a tailscale subcommand prints, or $null if tailscale is missing or the command fails.
function Get-TailscaleJson {
  param([Parameter(Mandatory)][string[]]$Arguments)
  if (-not (Test-Command tailscale)) { return $null }
  $PSNativeCommandUseErrorActionPreference = $false
  $text = (& tailscale @Arguments 2>$null) -join "`n"
  if ($LASTEXITCODE -ne 0 -or -not $text) { return $null }
  try { $text | ConvertFrom-Json } catch { $null }
}

function Get-JsonValue {
  param($Object, [string]$Name)
  if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return $null }
  $Object.$Name
}

# The settings this setup wants, as 'tailscale up' / 'tailscale set' flags. In WSL, DNS is left to Windows:
# WSL tunnels its DNS through the Windows host, whose Tailscale already resolves tailnet names, and
# tailscaled would otherwise rewrite the resolv.conf that WSL generates.
function Get-TailscaleFlags {
  [OutputType([string[]])]
  param([string]$Hostname)
  $flags = @('--ssh', "--operator=$([Environment]::UserName)")
  if ($Hostname) { $flags += "--hostname=$Hostname" }
  if (Test-Wsl) { $flags += '--accept-dns=false' }
  $flags
}

# True when the running prefs already match what Get-TailscaleFlags asks for.
function Test-TailscalePrefsMatch {
  [OutputType([bool])]
  param($Prefs, [string]$Hostname)
  if ($null -eq $Prefs) { return $false }
  if ((Get-JsonValue $Prefs 'RunSSH') -ne $true) { return $false }
  if ((Get-JsonValue $Prefs 'OperatorUser') -cne [Environment]::UserName) { return $false }
  if ($Hostname -and (Get-JsonValue $Prefs 'Hostname') -cne $Hostname) { return $false }
  if ((Test-Wsl) -and (Get-JsonValue $Prefs 'CorpDNS') -ne $false) { return $false }
  $true
}

function Install-Tailscale {
  Write-Status 'Installing Tailscale...'
  if (Test-Command tailscale) {
    Write-Skip 'Tailscale is already installed'
    return
  }
  # Adds Tailscale's apt repo, so update.ps1's 'apt upgrade' keeps it up to date.
  Invoke-Step 'curl -fsSL https://tailscale.com/install.sh | sh'
  Write-Ok 'Tailscale installed'
}

function Start-Tailscaled {
  Write-Status 'Starting tailscaled...'
  if ((Get-SystemdUnitState is-enabled tailscaled) -eq 'enabled' -and (Get-SystemdUnitState is-active tailscaled) -eq 'active') {
    Write-Skip 'tailscaled is already enabled and running'
    return
  }
  Invoke-Step 'sudo systemctl enable --now tailscaled'
  Write-Ok 'tailscaled enabled and running'
}

# The device's name on the tailnet: the first label of its MagicDNS name, or $null before it has one.
function Get-TailscaleDeviceName {
  param($Status)
  $dnsName = Get-JsonValue (Get-JsonValue $Status 'Self') 'DNSName'
  if ($dnsName) { $dnsName.Split('.')[0] } else { $null }
}

# Reports the name the device joined under. When another device already has the name asked for, Tailscale
# adds a number (e.g. meeg-laptop-wsl-1), and that's the name other devices have to use.
function Write-Connected {
  param([Parameter(Mandatory)][string]$Hostname)
  $name = $Hostname
  if (-not (Test-DryRun)) {
    $actual = Get-TailscaleDeviceName (Get-TailscaleJson @('status', '--json'))
    # A rename can take a moment to show in the status, so only a numbered name counts as different.
    if ($actual -match "^$([regex]::Escape($Hostname))-\d+$") { $name = $actual }
  }
  Write-Ok "Connected as $name with Tailscale SSH on"
  if ($name -ne $Hostname) {
    Write-Warn "Tailscale named this device $name, as another device already has the name $Hostname. To change it, use Edit machine name in the admin console"
  }
}

# Writes a file only this user can read. It's created with that mode, so it's never readable by others.
function Write-PrivateFile {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
  $options = [IO.FileStreamOptions]::new()
  $options.Mode = [IO.FileMode]::CreateNew
  $options.Access = [IO.FileAccess]::Write
  $options.UnixCreateMode = [IO.UnixFileMode]'UserRead, UserWrite'
  $writer = [IO.StreamWriter]::new($Path, [Text.UTF8Encoding]::new($false), $options)
  try { $writer.Write($Content) } finally { $writer.Dispose() }
}

# Logs in with 'tailscale up' when the device isn't logged in, turns it back on after 'tailscale down', and
# brings the running settings into line with 'tailscale set'. Without -Hostname, it keeps the name already set.
# An auth key in $env:TS_AUTHKEY (e.g. exported from ~/.secrets) logs in without a browser.
function Connect-Tailscale {
  param([string]$Hostname)
  Write-Status 'Connecting to your tailnet...'
  $status = Get-TailscaleJson @('status', '--json')
  $state = Get-JsonValue $status 'BackendState'
  $prefs = Get-TailscaleJson @('debug', 'prefs')

  if ($state -eq 'Running') {
    if (Test-TailscalePrefsMatch $prefs $Hostname) {
      $candidates = @((Get-TailscaleDeviceName $status), $Hostname, (Get-JsonValue $prefs 'Hostname'), (Get-JsonValue (Get-JsonValue $status 'Self') 'HostName'))
      $name = $candidates | Where-Object { $_ } | Select-Object -First 1
      Write-Skip "Already connected as $name with Tailscale SSH on"
      return
    }
    Invoke-Step "sudo tailscale set $((Get-TailscaleFlags $Hostname) -join ' ')"
    Write-Connected $(if ($Hostname) { $Hostname } else { Get-TailscaleDeviceName $status })
    return
  }

  if (-not $Hostname) { $Hostname = Get-JsonValue $prefs 'Hostname' }
  if (-not $Hostname) {
    throw "Not connected yet — run again with -Hostname <name> (e.g. -Hostname $(hostname | ForEach-Object ToLower)$(if (Test-Wsl) { '-wsl' }))"
  }
  $flags = Get-TailscaleFlags $Hostname

  if ($state -eq 'Stopped') {
    # Logged in but turned off with 'tailscale down'. A bare 'tailscale up' turns it back on as it was; given
    # flags, it would refuse unless they named every setting that differs from the default.
    if (-not (Test-TailscalePrefsMatch $prefs $Hostname)) { Invoke-Step "sudo tailscale set $($flags -join ' ')" }
    Invoke-Step 'sudo tailscale up'
    Write-Connected $Hostname
    return
  }

  $keyFile = $null
  try {
    if ($env:TS_AUTHKEY) {
      # Passed as a file, so the key isn't on the command line where other processes could read it.
      $keyFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), "tailscale-authkey-$([guid]::NewGuid())")
      if (-not (Test-DryRun)) { Write-PrivateFile $keyFile $env:TS_AUTHKEY }
      $flags += "--auth-key=file:$(ConvertTo-ShellArgument $keyFile)"
    } else {
      Write-Host '  Open the link tailscale prints to log in (or put TS_AUTHKEY in ~/.secrets to skip this).'
    }
    Invoke-Step "sudo tailscale up $($flags -join ' ')"
  } finally {
    if ($keyFile -and [IO.File]::Exists($keyFile)) { [IO.File]::Delete($keyFile) }
  }
  Write-Connected $Hostname
}

function Invoke-TailscaleSetup {
  param([string]$Hostname)
  Install-Tailscale
  Start-Tailscaled
  Connect-Tailscale $Hostname
}

Export-ModuleMember -Function Invoke-TailscaleSetup
