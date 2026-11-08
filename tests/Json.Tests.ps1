Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
  # Pester runs top-level code only while discovering tests; these lines apply strictness to the tests themselves.
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  Import-Module "$PSScriptRoot/../lib/Json.psm1" -Force
}

Describe 'Find-JsonDuplicateKey' {
  It 'finds a key repeated in one object' {
    Find-JsonDuplicateKey "{`n  `"a`": 1,`n  `"c`": 3,`n  `"m`": 0,`n  `"c`": 4`n}" | Should -Be 'c'
  }

  It 'finds a repeat in a nested object' {
    Find-JsonDuplicateKey '{"o": {"x": 1, "y": [1, {"z": 1}], "x": 2}}' | Should -Be 'x'
  }

  It 'allows the same key in different objects' {
    Find-JsonDuplicateKey '{"a": {"k": 1}, "b": {"k": 2}, "c": [{"k": 1}, {"k": 2}]}' | Should -BeNullOrEmpty
  }

  It 'ignores keys inside strings and comments' {
    $text = @'
{
  // "a": 0,
  /* "a": 0, */
  "a": "\"a\": 1, {\"a\": 2}",
  "b": "a"
}
'@
    Find-JsonDuplicateKey $text | Should -BeNullOrEmpty
  }

  It 'returns $null for an empty object' {
    Find-JsonDuplicateKey '{}' | Should -BeNullOrEmpty
  }
}
