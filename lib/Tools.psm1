Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-AptInstalled {
  [OutputType([bool])]
  param([Parameter(Mandatory)][string]$Package)
  if (-not (Get-Command dpkg-query -ErrorAction SilentlyContinue)) { return $false }
  $PSNativeCommandUseErrorActionPreference = $false
  $status = dpkg-query -W -f='${Status}' $Package 2>$null
  [bool]($status -match 'ok installed')
}

Export-ModuleMember -Function Test-AptInstalled
