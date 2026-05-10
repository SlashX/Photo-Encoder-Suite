# Schema lookups: Get-PhotoProfileSchema / Get-PhotoFlagKind / Get-PhotoFlagValueSchema.
. "$PSScriptRoot\..\framework.ps1"

$ProjectRoot = if ($env:PROJECT_ROOT) { $env:PROJECT_ROOT } else { Resolve-Path (Join-Path $PSScriptRoot '..\..') }
$ScriptDir = Join-Path $ProjectRoot 'src'
. (Join-Path $ScriptDir 'photo_profile_lib.ps1')

Assert-Eq -Expected 'enum:avif,webp,jpeg,heic,png,jxl' -Actual (Get-PhotoProfileSchema 'Format') -Msg 'Format enum'
Assert-Eq -Expected 'intrange:1,100' -Actual (Get-PhotoProfileSchema 'Quality') -Msg 'Quality intrange'
Assert-Contains -Haystack (Get-PhotoProfileSchema 'Preset') -Needle 'web' -Msg 'Preset includes web'
Assert-Eq -Expected 'bool:' -Actual (Get-PhotoProfileSchema 'StripExif') -Msg 'StripExif bool'
Assert-Eq -Expected '' -Actual (Get-PhotoProfileSchema 'TOTALLY_BOGUS_KEY_XYZ') -Msg 'unknown key returns empty'
Assert-Eq -Expected 'path:' -Actual (Get-PhotoProfileSchema 'InputDir') -Msg 'InputDir path'

Assert-Eq -Expected 'value' -Actual (Get-PhotoFlagKind '--format') -Msg '--format takes value'
Assert-Eq -Expected 'value' -Actual (Get-PhotoFlagKind '-f') -Msg '-f takes value'
Assert-Eq -Expected 'none' -Actual (Get-PhotoFlagKind '--strip-exif') -Msg '--strip-exif boolean'
Assert-Eq -Expected 'optional-value' -Actual (Get-PhotoFlagKind '--skip-similar') -Msg '--skip-similar optional'
Assert-Eq -Expected '' -Actual (Get-PhotoFlagKind '--no-such-flag') -Msg 'unknown flag'

Assert-Contains -Haystack (Get-PhotoFlagValueSchema '--uhdr') -Needle 'convert-preserve' -Msg '--uhdr accepts convert-preserve'
Assert-Eq -Expected 'enum:8,10,16' -Actual (Get-PhotoFlagValueSchema '--depth') -Msg '--depth enum'

Invoke-TestSummary
