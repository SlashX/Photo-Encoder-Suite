# Test-PhotoFlagString + Test-PhotoPredefinedProfiles.
. "$PSScriptRoot\..\framework.ps1"

$ProjectRoot = if ($env:PROJECT_ROOT) { $env:PROJECT_ROOT } else { Resolve-Path (Join-Path $PSScriptRoot '..\..') }
$ScriptDir = Join-Path $ProjectRoot 'src'
. (Join-Path $ScriptDir 'photo_profile_lib.ps1')

$builtin = Join-Path $ScriptDir 'profiles\photo_profiles.conf'
Assert-Eq -Expected $true -Actual (Test-PhotoPredefinedProfiles -Path $builtin) -Msg 'built-in photo_profiles.conf valid'

Assert-Eq -Expected $true  -Actual (Test-PhotoFlagString -FlagString "-f jpeg -p social -r 1080 --crop 1:1 --srgb --strip-exif" -Context 'good') -Msg 'valid flag string accepted'
Assert-Eq -Expected $false -Actual (Test-PhotoFlagString -FlagString "-f jpeg --bogus-flag value" -Context 'bad1') -Msg 'unknown flag rejected'
Assert-Eq -Expected $false -Actual (Test-PhotoFlagString -FlagString "-f xyz" -Context 'bad2') -Msg 'bad enum rejected'
Assert-Eq -Expected $false -Actual (Test-PhotoFlagString -FlagString "-q 200" -Context 'bad3') -Msg 'out-of-range quality rejected'
Assert-Eq -Expected $false -Actual (Test-PhotoFlagString -FlagString "-f" -Context 'bad4') -Msg 'missing value rejected'
Assert-Eq -Expected $true  -Actual (Test-PhotoFlagString -FlagString "--skip-similar -p web" -Context 'good2') -Msg '--skip-similar w/o value OK'
Assert-Eq -Expected $true  -Actual (Test-PhotoFlagString -FlagString "--skip-similar 5 -p web" -Context 'good3') -Msg '--skip-similar 5 OK'
Assert-Eq -Expected $true  -Actual (Test-PhotoFlagString -FlagString "-f jpeg -p social --watermark-text `"© COCA`"" -Context 'good4') -Msg 'quoted watermark text OK'

# Bad predefined file
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("photo_pre_" + [System.Guid]::NewGuid().ToString('N') + '.conf')
"demo = -f jpeg --completely-fake-flag x" | Set-Content -LiteralPath $tmp
try {
    Assert-Eq -Expected $false -Actual (Test-PhotoPredefinedProfiles -Path $tmp) -Msg 'bad predefined entry rejected'
} finally {
    Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Invoke-TestSummary
