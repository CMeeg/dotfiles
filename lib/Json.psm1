Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Returns the first key that appears twice in the same object, or $null. ConvertFrom-Json accepts duplicate
# keys, so this is checked separately. Skips strings and // and /* */ comments (JSONC); it relies on
# ConvertFrom-Json for the rest of the syntax. Keys are compared as written, without decoding escapes.
function Find-JsonDuplicateKey {
  [OutputType([string])]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  # One entry per open object or array: a key set for an object, $null for an array.
  $stack = [Collections.Generic.Stack[object]]::new()
  $expectKey = $false
  $i = 0
  while ($i -lt $Text.Length) {
    $ch = $Text[$i]
    $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($ch -eq '/' -and $next -eq '/') {
      $end = $Text.IndexOf("`n", $i)
      if ($end -lt 0) { break }
      $i = $end + 1
      continue
    }
    if ($ch -eq '/' -and $next -eq '*') {
      $end = $Text.IndexOf('*/', $i + 2)
      if ($end -lt 0) { break }
      $i = $end + 2
      continue
    }
    if ($ch -eq '"') {
      $end = $i + 1
      while ($end -lt $Text.Length -and $Text[$end] -ne '"') {
        if ($Text[$end] -eq '\') { $end++ }
        $end++
      }
      if ($expectKey) {
        if (-not $stack.Peek().Add($Text.Substring($i + 1, $end - $i - 1))) {
          return $Text.Substring($i + 1, $end - $i - 1)
        }
        $expectKey = $false
      }
      $i = $end + 1
      continue
    }
    switch ($ch) {
      '{' {
        $stack.Push([Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal))
        $expectKey = $true
      }
      '[' {
        $stack.Push($null)
        $expectKey = $false
      }
      { $_ -eq '}' -or $_ -eq ']' } {
        if ($stack.Count) { [void]$stack.Pop() }
        $expectKey = $false
      }
      ',' {
        $expectKey = $stack.Count -gt 0 -and $null -ne $stack.Peek()
      }
    }
    $i++
  }
  $null
}

Export-ModuleMember -Function Find-JsonDuplicateKey
