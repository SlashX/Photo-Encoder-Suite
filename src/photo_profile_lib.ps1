# ============================================================================
# photo_profile_lib.ps1 — Profile schema + validation (PS1 mirror of bash)
# ============================================================================
# Mirrors photo_common.sh sections "v4.8 — PROFILE SCHEMA + VALIDATION".
# Same key list, same enum/regex/intrange constraints. Keep these two files
# in lockstep when adding a new profile key or CLI flag.
#
# Dot-source from photo_encoder.ps1 and from tests/unit/test_profile_*.ps1:
#     . "$PSScriptRoot\photo_profile_lib.ps1"
# ============================================================================

# ── 1) UserProfiles schema ──────────────────────────────────────────────────
# Get-PhotoProfileSchema KEY  ->  "TYPE:CONSTRAINT" or "" if unknown.
# TYPE: enum / bool / int / intrange / regex / string / path
function Get-PhotoProfileSchema {
    param([string]$Key)
    switch ($Key) {
        'Format'                { 'enum:avif,webp,jpeg,heic,png,jxl' }
        'Quality'               { 'intrange:1,100' }
        'Preset'                { 'enum:,web,social,archive,print,max,thumb' }
        'Resize'                { 'regex:^([0-9]+(x[0-9]+)?)?$' }
        'ResizeMode'            { 'enum:,fit,fill,exact' }
        'Crop'                  { 'regex:^([0-9]+:[0-9]+)?$' }
        'MaxSize'               { 'regex:^([0-9]+[kKmMgG]?)?$' }
        'Depth'                 { 'enum:,8,10,16' }
        'HdrMode'               { 'enum:,auto,off,force-sdr,force-hdr' }
        'UHDR'                  { 'enum:,detect,info,strip,extract,decode,convert,convert-preserve,convert-regen' }
        'UHDRGainmapQuality'    { 'intrange:1,100' }
        'DJI'                   { 'enum:,detect,export,privacy-strip,clean' }
        'DJIBurstGroup'         { 'enum:,first,all,skip' }
        'DJILut'                { 'regex:^([A-Za-z0-9_.-]+|auto|none)?$' }
        'DNGPreview'            { 'bool:' }
        'StripExif'             { 'bool:' }
        'SRGB'                  { 'bool:' }
        'NoAutoRotate'          { 'bool:' }
        'WatermarkText'         { 'string:' }
        'WatermarkImage'        { 'path:' }
        'WatermarkPos'          { 'enum:,north,south,east,west,center,northeast,northwest,southeast,southwest' }
        'WatermarkOpacity'      { 'intrange:0,100' }
        'Prefix'                { 'string:' }
        'Suffix'                { 'string:' }
        'NoRecursive'           { 'bool:' }
        'Flat'                  { 'bool:' }
        'MinRes'                { 'regex:^([0-9]+(x[0-9]+)?)?$' }
        'SkipDuplicates'        { 'bool:' }
        'SkipSimilar'           { 'bool:' }
        'SkipSimilarThreshold'  { 'intrange:0,64' }
        'LosslessJpeg'          { 'bool:' }
        'ExtractMotion'         { 'bool:' }
        'MotionOnly'            { 'bool:' }
        'MotionShareable'       { 'bool:' }
        'MotionShareableStrict' { 'bool:' }
        'SkipExisting'          { 'bool:' }
        'Overwrite'             { 'bool:' }
        'Verbose'               { 'bool:' }
        'Compare'               { 'bool:' }
        'InputDir'              { 'path:' }
        'OutputDir'             { 'path:' }
        default                 { '' }
    }
}

# Test-PhotoUserProfile <FilePath>
# Echoes errors (line-numbered) to error stream. Returns:
#   $true  if all keys are valid (or only unknown-key warnings)
#   $false on any validation failure (also writes "x ..." to stderr).
function Test-PhotoUserProfile {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host "  x Profil inexistent: $Path" -ForegroundColor Red
        return $false
    }
    $errors = 0
    $lineno = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineno++
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"?([^"]*)"?\s*$') {
            $key = $Matches[1]
            $value = $Matches[2]
            $schema = Get-PhotoProfileSchema $key
            if (-not $schema) {
                Write-Host "  ! [linia $lineno] cheie necunoscuta: $key (ignor)" -ForegroundColor Yellow
                continue
            }
            $stype = ($schema -split ':',2)[0]
            $sconstraint = ($schema -split ':',2)[1]
            switch ($stype) {
                'enum' {
                    $allowed = @($sconstraint -split ',')
                    if ($allowed -notcontains $value) {
                        Write-Host "  x [linia $lineno] $key=`"$value`" -- valori permise: $sconstraint" -ForegroundColor Red
                        $errors++
                    }
                }
                'bool' {
                    if ($value -ne '' -and $value -ne 'true' -and $value -ne 'false') {
                        Write-Host "  x [linia $lineno] $key=`"$value`" -- astept true/false" -ForegroundColor Red
                        $errors++
                    }
                }
                'int' {
                    if ($value -ne '' -and $value -notmatch '^[0-9]+$') {
                        Write-Host "  x [linia $lineno] $key=`"$value`" -- astept intreg" -ForegroundColor Red
                        $errors++
                    }
                }
                'intrange' {
                    $rmin,$rmax = $sconstraint -split ',',2
                    if ($value -ne '') {
                        if ($value -notmatch '^[0-9]+$' -or [int]$value -lt [int]$rmin -or [int]$value -gt [int]$rmax) {
                            Write-Host "  x [linia $lineno] $key=`"$value`" -- astept $rmin..$rmax" -ForegroundColor Red
                            $errors++
                        }
                    }
                }
                'regex' {
                    if ($value -notmatch $sconstraint) {
                        Write-Host "  x [linia $lineno] $key=`"$value`" -- nu corespunde pattern: $sconstraint" -ForegroundColor Red
                        $errors++
                    }
                }
                # 'path' / 'string' -> no validation here
            }
        }
    }
    return ($errors -eq 0)
}

# ── 2) Predefined profiles (CLI flag bundles) ───────────────────────────────
# Get-PhotoFlagKind <flag>  ->  "none" | "value" | "optional-value" | ""
function Get-PhotoFlagKind {
    param([string]$Flag)
    switch -CaseSensitive ($Flag) {
        '--force-sdr'        { 'none' }
        '--force-hdr'        { 'none' }
        '--strip-exif'       { 'none' }
        '--keep-exif'        { 'none' }
        '--srgb'             { 'none' }
        '--auto-rotate'      { 'none' }
        '--no-auto-rotate'   { 'none' }
        '--skip-duplicates'  { 'none' }
        '--lossless-jpeg'    { 'none' }
        '--dng-preview'      { 'none' }
        '--skip-existing'    { 'none' }
        '--overwrite'        { 'none' }
        '--no-recursive'     { 'none' }
        '--flat'             { 'none' }
        '--compare'          { 'none' }
        '-m'                 { 'none' }
        '--extract-motion'   { 'none' }
        '--motion-only'      { 'none' }
        '--motion-shareable' { 'none' }
        '--motion-shareable-strict' { 'none' }
        '-f'                 { 'value' }
        '--format'           { 'value' }
        '-q'                 { 'value' }
        '--quality'          { 'value' }
        '-p'                 { 'value' }
        '--preset'           { 'value' }
        '-r'                 { 'value' }
        '--resize'           { 'value' }
        '--max-size'         { 'value' }
        '--resize-mode'      { 'value' }
        '--crop'             { 'value' }
        '--depth'            { 'value' }
        '--watermark-text'   { 'value' }
        '--watermark-image'  { 'value' }
        '--watermark-pos'    { 'value' }
        '--watermark-opacity' { 'value' }
        '--prefix'           { 'value' }
        '--suffix'           { 'value' }
        '--min-res'          { 'value' }
        '--dji'              { 'value' }
        '--dji-burst-group'  { 'value' }
        '--dji-lut'          { 'value' }
        '--uhdr'             { 'value' }
        '--uhdr-gainmap-quality' { 'value' }
        '--skip-similar'     { 'optional-value' }
        default              { '' }
    }
}

# Get-PhotoFlagValueSchema <flag>  ->  "TYPE:CONSTRAINT" or ""
function Get-PhotoFlagValueSchema {
    param([string]$Flag)
    switch -CaseSensitive ($Flag) {
        '-f'                    { 'enum:avif,webp,jpeg,heic,png,jxl' }
        '--format'              { 'enum:avif,webp,jpeg,heic,png,jxl' }
        '-q'                    { 'intrange:1,100' }
        '--quality'             { 'intrange:1,100' }
        '-p'                    { 'enum:web,social,archive,print,max,thumb' }
        '--preset'              { 'enum:web,social,archive,print,max,thumb' }
        '-r'                    { 'regex:^[0-9]+(x[0-9]+)?$' }
        '--resize'              { 'regex:^[0-9]+(x[0-9]+)?$' }
        '--max-size'            { 'regex:^[0-9]+[kKmMgG]?$' }
        '--resize-mode'         { 'enum:fit,fill,exact' }
        '--crop'                { 'regex:^[0-9]+:[0-9]+$' }
        '--depth'               { 'enum:8,10,16' }
        '--watermark-pos'       { 'enum:north,south,east,west,center,northeast,northwest,southeast,southwest' }
        '--watermark-opacity'   { 'intrange:0,100' }
        '--min-res'             { 'regex:^[0-9]+(x[0-9]+)?$' }
        '--dji'                 { 'enum:detect,export,privacy-strip,clean' }
        '--dji-burst-group'     { 'enum:first,all,skip' }
        '--dji-lut'             { 'regex:^[A-Za-z0-9_.-]+$' }
        '--uhdr'                { 'enum:detect,info,strip,extract,decode,convert,convert-preserve,convert-regen' }
        '--uhdr-gainmap-quality' { 'intrange:1,100' }
        '--skip-similar'        { 'intrange:0,64' }
        '--watermark-text'      { 'string:' }
        '--watermark-image'     { 'string:' }
        '--prefix'              { 'string:' }
        '--suffix'              { 'string:' }
        default                 { '' }
    }
}

# Internal: tokenize a CLI flag string honouring "quoted values" and 'singles'.
function _Get-PhotoFlagTokens {
    param([string]$FlagString)
    $tokens = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $inDouble = $false
    $inSingle = $false
    for ($i = 0; $i -lt $FlagString.Length; $i++) {
        $ch = $FlagString[$i]
        if ($ch -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($ch -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($ch -eq ' ' -and -not $inDouble -and -not $inSingle) {
            if ($cur.Length -gt 0) { $tokens.Add($cur.ToString()) | Out-Null; $cur.Clear() | Out-Null }
            continue
        }
        $cur.Append($ch) | Out-Null
    }
    if ($cur.Length -gt 0) { $tokens.Add($cur.ToString()) | Out-Null }
    if ($inDouble -or $inSingle) { return $null }   # unbalanced quotes
    return ,$tokens.ToArray()
}

# Test-PhotoFlagString <flagString> [<contextLabel>]
function Test-PhotoFlagString {
    param(
        [Parameter(Mandatory=$true)][string]$FlagString,
        [string]$Context = 'flags'
    )
    $tokens = _Get-PhotoFlagTokens $FlagString
    if ($null -eq $tokens) {
        Write-Host "  x [$Context] tokenizare esuata (quoting invalid?): $FlagString" -ForegroundColor Red
        return $false
    }
    $errors = 0
    $i = 0
    $n = $tokens.Length
    while ($i -lt $n) {
        $tok = $tokens[$i]
        $kind = Get-PhotoFlagKind $tok
        if (-not $kind) {
            Write-Host "  x [$Context] flag necunoscut: $tok" -ForegroundColor Red
            $errors++
            $i++
            continue
        }
        if ($kind -eq 'none') { $i++; continue }
        $nextIdx = $i + 1
        if ($nextIdx -ge $n) {
            if ($kind -eq 'value') {
                Write-Host "  x [$Context] $tok cere o valoare (lipseste)" -ForegroundColor Red
                $errors++
            }
            $i++
            continue
        }
        $nextTok = $tokens[$nextIdx]
        if ($kind -eq 'optional-value' -and $nextTok.StartsWith('-')) { $i++; continue }
        $val = $nextTok
        $schema = Get-PhotoFlagValueSchema $tok
        if ($schema) {
            $stype = ($schema -split ':',2)[0]
            $sconstraint = ($schema -split ':',2)[1]
            switch ($stype) {
                'enum' {
                    $allowed = @($sconstraint -split ',')
                    if ($allowed -notcontains $val) {
                        Write-Host "  x [$Context] $tok `"$val`" -- valori permise: $sconstraint" -ForegroundColor Red
                        $errors++
                    }
                }
                'regex' {
                    if ($val -notmatch $sconstraint) {
                        Write-Host "  x [$Context] $tok `"$val`" -- nu corespunde: $sconstraint" -ForegroundColor Red
                        $errors++
                    }
                }
                'intrange' {
                    $rmin,$rmax = $sconstraint -split ',',2
                    if ($val -notmatch '^[0-9]+$' -or [int]$val -lt [int]$rmin -or [int]$val -gt [int]$rmax) {
                        Write-Host "  x [$Context] $tok `"$val`" -- astept $rmin..$rmax" -ForegroundColor Red
                        $errors++
                    }
                }
                # 'string' / 'path' -> no constraint
            }
        }
        $i += 2
    }
    return ($errors -eq 0)
}

# Test-PhotoPredefinedProfiles <FilePath>
function Test-PhotoPredefinedProfiles {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host "  x Profil inexistent: $Path" -ForegroundColor Red
        return $false
    }
    $errors = 0
    $lineno = 0
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $lineno++
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*([a-zA-Z0-9_-]+)\s*=\s*(.+)$') {
            $name  = $Matches[1]
            $flags = $Matches[2].TrimEnd()
            if (-not (Test-PhotoFlagString -FlagString $flags -Context "linia $lineno`: $name")) {
                $errors++
            }
        } else {
            Write-Host "  x [linia $lineno] format invalid (astept 'name = flags'): $line" -ForegroundColor Red
            $errors++
        }
    }
    return ($errors -eq 0)
}
