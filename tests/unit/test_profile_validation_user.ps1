# Test-PhotoUserProfile — accepts valid, rejects bad enum/regex/intrange.
. "$PSScriptRoot\..\framework.ps1"

$ProjectRoot = if ($env:PROJECT_ROOT) { $env:PROJECT_ROOT } else { Resolve-Path (Join-Path $PSScriptRoot '..\..') }
$ScriptDir = Join-Path $ProjectRoot 'src'
. (Join-Path $ScriptDir 'photo_profile_lib.ps1')

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("photo_test_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # 1) Valid
    @"
Format=avif
Quality=80
Preset=web
SkipDuplicates=true
WatermarkOpacity=30
"@ | Set-Content -LiteralPath (Join-Path $tmp 'valid.conf')
    $rc = Test-PhotoUserProfile -Path (Join-Path $tmp 'valid.conf') 2>$null
    Assert-Eq -Expected $true -Actual $rc -Msg 'valid profile passes'

    # 2) Bad enum
    "Format=avi" | Set-Content -LiteralPath (Join-Path $tmp 'bad_enum.conf')
    $rc = Test-PhotoUserProfile -Path (Join-Path $tmp 'bad_enum.conf') 2>$null
    Assert-Eq -Expected $false -Actual $rc -Msg 'bad enum fails'

    # 3) Out of range
    "Quality=200" | Set-Content -LiteralPath (Join-Path $tmp 'bad_range.conf')
    $rc = Test-PhotoUserProfile -Path (Join-Path $tmp 'bad_range.conf') 2>$null
    Assert-Eq -Expected $false -Actual $rc -Msg 'out-of-range int fails'

    # 4) Bad bool
    "StripExif=yes" | Set-Content -LiteralPath (Join-Path $tmp 'bad_bool.conf')
    $rc = Test-PhotoUserProfile -Path (Join-Path $tmp 'bad_bool.conf') 2>$null
    Assert-Eq -Expected $false -Actual $rc -Msg 'non-bool rejected'

    # 5) Unknown key - warning only
    @"
Format=avif
SOME_FUTURE_FIELD=value
"@ | Set-Content -LiteralPath (Join-Path $tmp 'unknown.conf')
    $rc = Test-PhotoUserProfile -Path (Join-Path $tmp 'unknown.conf') 2>$null
    Assert-Eq -Expected $true -Actual $rc -Msg 'unknown key not blocking'

    # 6) Missing file
    $rc = Test-PhotoUserProfile -Path (Join-Path $tmp 'nope.conf') 2>$null
    Assert-Eq -Expected $false -Actual $rc -Msg 'missing file fails'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Invoke-TestSummary
