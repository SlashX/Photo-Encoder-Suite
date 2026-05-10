# Sanity test on the PS1 assertion library.
. "$PSScriptRoot\..\framework.ps1"

Assert-Eq -Expected 'abc' -Actual 'abc' -Msg 'string equality'
Assert-Neq -A 'abc' -B 'xyz' -Msg 'string inequality'
Assert-Contains -Haystack 'the quick brown fox' -Needle 'quick' -Msg 'substring'
Assert-NotContains -Haystack 'the quick brown fox' -Needle 'lazy'
Assert-Match -Str 'version 4.8.0' -Pattern '^version [0-9]+'
Assert-Zero 0 -Msg 'exit zero'
Assert-Nonzero 7 -Msg 'exit nonzero'
Assert-DirExists -Path (Join-Path $PSScriptRoot '..')

Invoke-TestSummary
