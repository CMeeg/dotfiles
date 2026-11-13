Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/Common.psm1"
Import-Module "$PSScriptRoot/Manifest.psm1"
Import-Module "$PSScriptRoot/State.psm1"
Import-Module "$PSScriptRoot/Tools.psm1"

# Retire steps remove tools and files that this repo no longer installs or manages. Each one is idempotent:
# when there's nothing to remove it prints one skip line and changes nothing. They only remove, never install.

# Symlinks where stow put them (home's top level, and anywhere under ~/.config, ~/.claude and ~/.agents)
# that point into the repo. Unreadable folders are skipped.
function Get-RepoLinks {
  $homeDir = Get-HomeDir
  $repoDir = Get-RepoDir
  $candidates = @(Get-ChildItem -LiteralPath $homeDir -Force -ErrorAction SilentlyContinue)
  foreach ($name in '.config', '.claude', '.agents') {
    $dir = "$homeDir/$name"
    if ([IO.Directory]::Exists($dir)) {
      $candidates += @(Get-ChildItem -LiteralPath $dir -Force -Recurse -ErrorAction SilentlyContinue)
    }
  }
  foreach ($item in $candidates) {
    if ($item.LinkTarget -and (Test-LinkInto $item.FullName $repoDir)) { $item.FullName }
  }
}

function Test-StowLinksPresent {
  [OutputType([bool])]
  param()
  [bool]@(Get-RepoLinks).Count
}

# Removes $Dir and each parent left empty, stopping at home.
function Remove-EmptyParents {
  param([string]$Dir)
  $homeDir = (Get-HomeDir).TrimEnd('/')
  while ($Dir -ne $homeDir -and $Dir -ne '/' -and [IO.Directory]::Exists($Dir) -and
    -not [IO.Directory]::EnumerateFileSystemEntries($Dir).GetEnumerator().MoveNext()) {
    Invoke-Step "rmdir $(ConvertTo-ShellArgument $Dir)"
    $Dir = [IO.Path]::GetDirectoryName($Dir)
  }
}

# Replaces each stow link to a managed file with a real copy and records it as applied, so sync treats it
# as already applied. Deletes links to anything else in the repo (gone, or not in the manifest). Then
# removes stow itself.
function Invoke-RetireStow {
  $homeDir = Get-HomeDir
  $repoDir = Get-RepoDir
  $links = @(Get-RepoLinks)
  $stowInstalled = Test-AptInstalled 'stow'
  if (-not $links.Count -and -not $stowInstalled) {
    Write-Skip 'No stow links, and stow is not installed'
    return
  }

  $managed = @{}
  foreach ($file in Get-ManagedFiles $repoDir) { $managed[$file.Target] = $file }

  $replaced = 0
  $touchedAgents = $false
  foreach ($link in $links) {
    $destination = Resolve-PhysicalPath (Resolve-LinkTarget $link)
    $file = $managed[$link]
    if ($file -and $destination -eq (Resolve-PhysicalPath (Join-Path $repoDir $file.Source)) -and
      [IO.File]::Exists($destination)) {
      $content = Expand-Placeholders (Read-TextFile $destination) $homeDir $repoDir
      if (Test-DryRun) {
        Write-Dry "Replace stow link $link with a copy of $($file.Source)"
      } else {
        [IO.File]::Delete($link)
        Write-TextFile $link $content
      }
      Write-Applied $link $content
      $replaced++
      continue
    }
    # Named one by one: the step runs on every install and update, and a link made by hand would go too.
    $reason = if (Test-Path -LiteralPath $destination) { "isn't in dotfiles.json" } else { 'no longer exists' }
    if (Test-DryRun) {
      Write-Dry "Remove stow link $link ($destination $reason)"
    } else {
      Invoke-Step "rm -f $(ConvertTo-ShellArgument $link)"
      Write-Ok "Removed stow link $link ($destination $reason)"
    }
    if ($link.StartsWith("$homeDir/.agents/", [StringComparison]::Ordinal)) { $touchedAgents = $true }
    if (-not (Test-DryRun)) { Remove-EmptyParents ([IO.Path]::GetDirectoryName($link)) }
  }
  if ($replaced) { Write-Ok "Replaced $replaced stow links with copies of the repo files" }

  # ~/.agents only held repo skills; anything left there came from another tool.
  if (-not (Test-DryRun) -and $touchedAgents -and [IO.Directory]::Exists("$homeDir/.agents")) {
    Write-Warn "~/.agents still has files that aren't from the repo — left in place"
  }

  if ($stowInstalled) {
    Invoke-Step 'sudo apt remove -y stow'
    Write-Ok 'stow removed'
  }
}

function Invoke-RetireOpenDesign {
  $dir = "$(Get-HomeDir)/.opendesign"
  if (-not (Test-Path -LiteralPath $dir)) {
    Write-Skip 'OpenDesign is not installed'
    return
  }
  $od = "$dir/node_modules/.bin/od"
  if ([IO.File]::Exists($od)) {
    Invoke-Step "$(ConvertTo-ShellArgument $od) daemon stop || true"
  }
  # Match the install path, never a bare "open-design", so nothing else is killed.
  # The bracketed first character stops pkill matching the `bash -c` that runs it.
  $pattern = "[$($dir[0])]$($dir.Substring(1))/"
  if (Test-Command pgrep) {
    $PSNativeCommandUseErrorActionPreference = $false
    pgrep -f $pattern *> $null
    if ($LASTEXITCODE -eq 0) {
      # || true: the daemon may exit between pgrep and pkill, and pkill then exits 1
      Invoke-Step "pkill -f $(ConvertTo-ShellArgument $pattern) || true"
    }
  }
  Invoke-Step "rm -rf $(ConvertTo-ShellArgument $dir)"
  Write-Ok 'OpenDesign removed'
}

function Invoke-RetireBun {
  $dir = "$(Get-HomeDir)/.bun"
  if (-not (Test-Path -LiteralPath $dir)) {
    Write-Skip 'Bun is not installed'
    return
  }
  Invoke-Step "rm -rf $(ConvertTo-ShellArgument $dir)"
  Write-Ok 'Bun removed'
}

# superpowers is now an opencode plugin entry, so the old standalone clone goes.
function Invoke-RetireSuperpowersClone {
  $packages = "$(Get-HomeDir)/.local/share/opencode/packages"
  $clone = "$packages/superpowers"
  if (-not (Test-Path -LiteralPath $clone)) {
    Write-Skip 'superpowers clone for opencode is not present'
    return
  }
  Invoke-Step "rm -rf $(ConvertTo-ShellArgument $clone)"
  if (-not (Test-DryRun) -and -not [IO.Directory]::EnumerateFileSystemEntries($packages).GetEnumerator().MoveNext()) {
    Invoke-Step "rmdir $(ConvertTo-ShellArgument $packages)"
  }
  Write-Ok 'superpowers clone for opencode removed'
}

# Aspire is installed with its own script (~/.aspire/bin) on every machine, so a .NET global tool install
# is removed. install.ps1 puts the script version back.
function Invoke-RetireAspireDotnetTool {
  $installed = $false
  if (Test-Command dotnet) {
    $PSNativeCommandUseErrorActionPreference = $false
    $tools = dotnet tool list -g 2>$null
    $installed = [bool]($tools | Where-Object { ($_ -split '\s+')[0] -eq 'aspire.cli' })
  }
  if (-not $installed) {
    Write-Skip 'Aspire is not installed as a .NET global tool'
    return
  }
  Invoke-Step 'dotnet tool uninstall -g aspire.cli'
  Write-Ok "Aspire .NET global tool removed — run ./install.ps1 to reinstall it with Aspire's install script"
}

# The statuslines marketplace's sub-meter and context-bar mods are replaced by the session-status local plugin.
# Dropping them from settings.json isn't enough: an installed plugin with no enabledPlugins entry starts enabled.
function Invoke-RetireStatuslinesMods {
  $plugins = @()
  $hasMarketplace = $false
  if (Test-Command claude) {
    $PSNativeCommandUseErrorActionPreference = $false
    try {
      $installed = (claude plugin list --json 2>$null) -join "`n" | ConvertFrom-Json
      $plugins = @($installed | Where-Object { $_.id -in 'sub-meter@statuslines', 'context-bar@statuslines' } |
          ForEach-Object { $_.id })
      $marketplaces = (claude plugin marketplace list --json 2>$null) -join "`n" | ConvertFrom-Json
      $hasMarketplace = [bool]($marketplaces | Where-Object { $_.name -eq 'statuslines' })
    } catch {
      Write-Warn "Couldn't list Claude Code's plugins, so sub-meter and context-bar were left as they are"
      return
    }
  }
  if (-not $plugins.Count -and -not $hasMarketplace) {
    Write-Skip 'The statuslines mods are not installed'
    return
  }
  foreach ($id in $plugins) { Invoke-Step "claude plugin uninstall $id --scope user" }
  if ($hasMarketplace) { Invoke-Step 'claude plugin marketplace remove statuslines' }
  Write-Ok 'statuslines mods and marketplace removed — the session-status local plugin replaces them'
}

function Invoke-RetireSteps {
  Write-Status 'Retiring removed tools...'
  Invoke-RetireStow
  Invoke-RetireOpenDesign
  Invoke-RetireBun
  Invoke-RetireSuperpowersClone
  Invoke-RetireAspireDotnetTool
  Invoke-RetireStatuslinesMods
}

Export-ModuleMember -Function Invoke-RetireStow, Invoke-RetireOpenDesign, Invoke-RetireBun, Invoke-RetireSuperpowersClone,
  Invoke-RetireAspireDotnetTool, Invoke-RetireStatuslinesMods, Invoke-RetireSteps, Test-StowLinksPresent
