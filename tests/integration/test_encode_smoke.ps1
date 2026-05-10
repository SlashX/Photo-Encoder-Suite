# Encode 1 sample (PNG -> AVIF) end-to-end via photo_encoder.ps1.
. "$PSScriptRoot\..\framework.ps1"

$ProjectRoot = if ($env:PROJECT_ROOT) { $env:PROJECT_ROOT } else { Resolve-Path (Join-Path $PSScriptRoot '..\..') }
$Encoder = Join-Path $ProjectRoot 'src\photo_encoder.ps1'
$Fixtures = Join-Path $ProjectRoot 'tests\fixtures\samples'

if (-not (Test-Path -LiteralPath $Encoder)) { Write-Host "encoder missing: $Encoder"; exit 1 }
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) { Skip-Test 'ImageMagick not installed' }

$Sample = Join-Path $Fixtures 'test_256.png'
if (-not (Test-Path -LiteralPath $Sample)) {
    Skip-Test 'sample PNG missing - run tests\fixtures\generate_samples.ps1 first'
}

$psExe = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $psExe) { $psExe = Get-Command powershell -ErrorAction SilentlyContinue }
if (-not $psExe) { Skip-Test 'no pwsh/powershell' }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("photo_enc_" + [System.Guid]::NewGuid().ToString('N'))
$indir = Join-Path $work 'in'
$outdir = Join-Path $work 'out'
New-Item -ItemType Directory -Force -Path $indir, $outdir | Out-Null
Copy-Item -LiteralPath $Sample -Destination $indir
$log = Join-Path $work 'encoder.log'

try {
    & $psExe.Source -NoProfile -NonInteractive -File $Encoder -InputDir $indir -OutputDir $outdir -Format avif -Preset web -Quality 70 *> $log
    $rc = $LASTEXITCODE

    $logContent = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    if (-not $logContent) { $logContent = '' }

    if ($rc -ne 0 -and $logContent -match '(no encode delegate|delegate.*avif|cannot write)') {
        Skip-Test 'ImageMagick lacks AVIF write support'
    }

    Assert-Zero $rc -Msg 'encoder exit 0'

    $produced = Get-ChildItem -LiteralPath $outdir -Recurse -Filter '*.avif' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($produced) {
        Assert-FileExists -Path $produced.FullName -Msg 'AVIF output produced'
        if ($produced.Length -gt 100) { _pass } else { _fail "AVIF output too small: $($produced.Length) bytes" }
    } else {
        _fail 'no AVIF found in output dir'
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Invoke-TestSummary
