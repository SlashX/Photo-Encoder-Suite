# photo_profile_diff.ps1 — predefined + user mode.
. "$PSScriptRoot\..\framework.ps1"

$ProjectRoot = if ($env:PROJECT_ROOT) { $env:PROJECT_ROOT } else { Resolve-Path (Join-Path $PSScriptRoot '..\..') }
$Diff = Join-Path $ProjectRoot 'src\tools\photo_profile_diff.ps1'
if (-not (Test-Path -LiteralPath $Diff)) { Write-Host "tool missing: $Diff"; exit 1 }

$psExe = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $psExe) { $psExe = Get-Command powershell -ErrorAction SilentlyContinue }
if (-not $psExe) { Skip-Test "no pwsh/powershell on PATH" }

function Run-Diff([string[]]$DiffArgs) {
    # Capture child Write-Host output via *> redirection to a temp log file.
    $log = [System.IO.Path]::GetTempFileName()
    try {
        & $psExe.Source -NoProfile -NonInteractive -File $Diff @DiffArgs *> $log
        $rc = $LASTEXITCODE
        $content = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
        if (-not $content) { $content = '' }
        return @{ Out = $content; Rc = $rc }
    }
    finally {
        Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    }
}

# 1) Predefined diff: different
$r = Run-Diff @('-Predefined', '-A', 'instagram', '-B', 'facebook')
Assert-Eq -Expected 1 -Actual $r.Rc -Msg 'predefined diff exit=1'
Assert-Contains -Haystack $r.Out -Needle 'Profile diff (predefined)' -Msg 'header'
Assert-Contains -Haystack $r.Out -Needle 'instagram' -Msg 'mentions instagram'

# 2) Predefined identical
$r = Run-Diff @('-Predefined', '-A', 'instagram', '-B', 'instagram')
Assert-Eq -Expected 0 -Actual $r.Rc -Msg 'predefined identical exit=0'
Assert-Contains -Haystack $r.Out -Needle 'identice' -Msg 'identical message'

# 3) Predefined missing
$r = Run-Diff @('-Predefined', '-A', 'instagram', '-B', 'nonexistent_xyz')
Assert-Eq -Expected 2 -Actual $r.Rc -Msg 'missing predefined exit=2'

# 4) User mode
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("photo_diff_" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    "Format=avif`nQuality=80`nPreset=web`n" | Set-Content -LiteralPath (Join-Path $tmp 'a.conf')
    "Format=jpeg`nQuality=80`nPreset=social`nStripExif=true`n" | Set-Content -LiteralPath (Join-Path $tmp 'b.conf')
    $r = Run-Diff @((Join-Path $tmp 'a.conf'), (Join-Path $tmp 'b.conf'))
    Assert-Eq -Expected 1 -Actual $r.Rc -Msg 'user diff exit=1'
    Assert-Contains -Haystack $r.Out -Needle 'Profile diff (user)' -Msg 'user header'
    Assert-Contains -Haystack $r.Out -Needle 'Format' -Msg 'shows Format'
    Assert-Contains -Haystack $r.Out -Needle 'StripExif' -Msg 'shows StripExif'

    # 5) Identical
    Copy-Item -LiteralPath (Join-Path $tmp 'a.conf') -Destination (Join-Path $tmp 'aa.conf')
    $r = Run-Diff @((Join-Path $tmp 'a.conf'), (Join-Path $tmp 'aa.conf'))
    Assert-Eq -Expected 0 -Actual $r.Rc -Msg 'identical user files exit=0'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Invoke-TestSummary
