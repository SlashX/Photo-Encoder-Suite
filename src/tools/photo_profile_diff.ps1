# ═══════════════════════════════════════════════════════════════
#  photo_profile_diff.ps1 — compara doua profile Photo Encoder
# ═══════════════════════════════════════════════════════════════
# Usage:
#   .\photo_profile_diff.ps1 <fileA.conf> <fileB.conf>
#       Diff intre doua UserProfiles (KEY=VALUE).
#
#   .\photo_profile_diff.ps1 -Predefined -A <nameA> -B <nameB> [-File <profiles.conf>]
#       Diff intre doua entries din photo_profiles.conf.
#
# Exit codes: 0 identice, 1 difera, 2 eroare.
# ═══════════════════════════════════════════════════════════════
[CmdletBinding(DefaultParameterSetName='User')]
param(
    [Parameter(ParameterSetName='User', Mandatory=$true, Position=0)][string]$ProfileA,
    [Parameter(ParameterSetName='User', Mandatory=$true, Position=1)][string]$ProfileB,
    [Parameter(ParameterSetName='Predefined', Mandatory=$true)][switch]$Predefined,
    [Parameter(ParameterSetName='Predefined', Mandatory=$true)][string]$A,
    [Parameter(ParameterSetName='Predefined', Mandatory=$true)][string]$B,
    [Parameter(ParameterSetName='Predefined')][string]$File = ""
)

$ErrorActionPreference = 'Stop'
$ToolsDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptDir  = Split-Path -Parent $ToolsDir   # repo/src/

function Read-ConfFile {
    param([string]$Path)
    $map = [ordered]@{}
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"?([^"]*)"?\s*$') {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    return $map
}

# Tokenize "name = flags" line into ordered hashtable of -flag -> value-or-<NONE>
function Get-FlagPairs {
    param([string]$FlagString)
    $tokens = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $inDouble = $false; $inSingle = $false
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

    $map = [ordered]@{}
    $idx = 0
    while ($idx -lt $tokens.Count) {
        $tok = $tokens[$idx]
        if (-not $tok.StartsWith('-')) { $idx++; continue }
        $next = if (($idx + 1) -lt $tokens.Count) { $tokens[$idx+1] } else { '' }
        if (-not $next -or $next.StartsWith('-')) {
            $map[$tok] = '<NONE>'
            $idx++
        } else {
            $map[$tok] = $next
            $idx += 2
        }
    }
    return $map
}

function Get-PredefinedFlags {
    param([string]$Path, [string]$Want)
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        if ($line -match '^\s*([a-zA-Z0-9_-]+)\s*=\s*(.+)$') {
            if ($Matches[1] -eq $Want) { return $Matches[2].TrimEnd() }
        }
    }
    return $null
}

function Show-Diff {
    param(
        [string]$Title,
        [string]$LabelA,
        [string]$LabelB,
        $MapA,
        $MapB,
        [string]$KeyHeader = 'KEY',
        [string]$ValuePrefix = '"',
        [string]$ValueSuffix = '"'
    )

    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "    A: $LabelA" -ForegroundColor White
    Write-Host "    B: $LabelB" -ForegroundColor White
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    $onlyA = @($MapA.Keys | Where-Object { -not $MapB.Contains($_) })
    $onlyB = @($MapB.Keys | Where-Object { -not $MapA.Contains($_) })
    $diff  = @($MapA.Keys | Where-Object { $MapB.Contains($_) -and $MapA[$_] -cne $MapB[$_] })

    if ($onlyA.Count -gt 0) {
        Write-Host ""
        Write-Host "-- Doar in A ($LabelA) --" -ForegroundColor Yellow
        foreach ($k in $onlyA) { "  {0,-25} = {1}{2}{3}" -f $k, $ValuePrefix, $MapA[$k], $ValueSuffix | Write-Host }
    }
    if ($onlyB.Count -gt 0) {
        Write-Host ""
        Write-Host "-- Doar in B ($LabelB) --" -ForegroundColor Yellow
        foreach ($k in $onlyB) { "  {0,-25} = {1}{2}{3}" -f $k, $ValuePrefix, $MapB[$k], $ValueSuffix | Write-Host }
    }
    if ($diff.Count -gt 0) {
        Write-Host ""
        Write-Host "-- Valori diferite --" -ForegroundColor Yellow
        "  {0,-25} {1,-30} {2,-30}" -f $KeyHeader, "A ($LabelA)", "B ($LabelB)" | Write-Host
        "  {0,-25} {1,-30} {2,-30}" -f '---', '---', '---' | Write-Host
        foreach ($k in $diff) {
            "  {0,-25} {1,-30} {2,-30}" -f $k, ($ValuePrefix + $MapA[$k] + $ValueSuffix), ($ValuePrefix + $MapB[$k] + $ValueSuffix) | Write-Host
        }
    }
    if ($onlyA.Count -eq 0 -and $onlyB.Count -eq 0 -and $diff.Count -eq 0) {
        Write-Host ""
        Write-Host "  Profilele sunt identice." -ForegroundColor Green
        return 0
    }
    Write-Host ""
    Write-Host "-- Sumar --" -ForegroundColor Cyan
    Write-Host ("  Doar in A:        {0}" -f $onlyA.Count)
    Write-Host ("  Doar in B:        {0}" -f $onlyB.Count)
    Write-Host ("  Valori diferite:  {0}" -f $diff.Count)
    return 1
}

if ($PSCmdlet.ParameterSetName -eq 'Predefined') {
    if (-not $File) { $File = Join-Path $ScriptDir 'profiles\photo_profiles.conf' }
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        Write-Host "  x Profil inexistent: $File" -ForegroundColor Red; exit 2
    }
    $flagsA = Get-PredefinedFlags -Path $File -Want $A
    $flagsB = Get-PredefinedFlags -Path $File -Want $B
    if (-not $flagsA) { Write-Host "  x Profilul '$A' nu exista in $File" -ForegroundColor Red; exit 2 }
    if (-not $flagsB) { Write-Host "  x Profilul '$B' nu exista in $File" -ForegroundColor Red; exit 2 }
    $mapA = Get-FlagPairs $flagsA
    $mapB = Get-FlagPairs $flagsB
    $rc = Show-Diff -Title 'Profile diff (predefined)' -LabelA $A -LabelB $B `
                    -MapA $mapA -MapB $mapB -KeyHeader 'FLAG' -ValuePrefix '' -ValueSuffix ''
    exit $rc
}

# User mode (KEY=VALUE)
foreach ($p in @($ProfileA, $ProfileB)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Write-Host "  x Fisier inexistent: $p" -ForegroundColor Red; exit 2
    }
}
$mapA = Read-ConfFile -Path $ProfileA
$mapB = Read-ConfFile -Path $ProfileB
$nameA = [System.IO.Path]::GetFileNameWithoutExtension($ProfileA)
$nameB = [System.IO.Path]::GetFileNameWithoutExtension($ProfileB)
$rc = Show-Diff -Title 'Profile diff (user)' -LabelA "$nameA  ($ProfileA)" -LabelB "$nameB  ($ProfileB)" `
                -MapA $mapA -MapB $mapB
exit $rc
