# ═══════════════════════════════════════════════════════════════
#  generate_samples.ps1 — synth tiny test images via ImageMagick
#  Idempotent (skip-if-exists, override with -Force).
#  Outputs to tests\fixtures\samples\
# ═══════════════════════════════════════════════════════════════
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$SamplesDir = Join-Path $ScriptDir 'samples'
New-Item -ItemType Directory -Force -Path $SamplesDir | Out-Null

$magick = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magick) { $magick = Get-Command convert -ErrorAction SilentlyContinue }
if (-not $magick) {
    Write-Host "  x ImageMagick (magick/convert) negasit." -ForegroundColor Red
    exit 1
}
$MagickExe = $magick.Source

function _Skip([string]$Path) {
    if ($Force) { return $false }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Write-Host ("  ~ exists: {0}" -f (Split-Path -Leaf $Path)) -ForegroundColor Gray
        return $true
    }
    return $false
}

function _SizeKB([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return [math]::Round((Get-Item -LiteralPath $Path).Length / 1KB)
    }
    return 0
}

Write-Host "Generating synthetic samples in: $SamplesDir"

$samples = @(
    @{ File = 'test_256.png';  Args = @('-size','256x256','gradient:blue-yellow') },
    @{ File = 'test_512.png';  Args = @('-size','512x512','plasma:','-fill','white','-gravity','center','-pointsize','36','-annotate','0','PHOTO') },
    @{ File = 'test_256.jpg';  Args = @('-size','256x256','gradient:red-blue','-quality','85') },
    @{ File = 'test_1024.jpg'; Args = @('-size','1024x768','plasma:','-quality','85') }
)

foreach ($s in $samples) {
    $out = Join-Path $SamplesDir $s.File
    if (_Skip $out) { continue }
    & $MagickExe @($s.Args + $out)
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) {
        Write-Host ("  + {0} ({1} KB)" -f $s.File, (_SizeKB $out)) -ForegroundColor Green
    } else {
        Write-Host ("  x failed: {0}" -f $s.File) -ForegroundColor Red
    }
}

# HEIC (best effort)
$heicOut = Join-Path $SamplesDir 'test_256.heic'
if (-not (_Skip $heicOut)) {
    & $MagickExe -size 256x256 'gradient:green-magenta' $heicOut 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $heicOut)) {
        Write-Host ("  + test_256.heic ({0} KB)" -f (_SizeKB $heicOut)) -ForegroundColor Green
    } else {
        if (Test-Path -LiteralPath $heicOut) { Remove-Item -LiteralPath $heicOut -ErrorAction SilentlyContinue }
        Write-Host "  ~ skipped: HEIC (libheif not available in ImageMagick)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Done. Samples directory: $SamplesDir"
Get-ChildItem -LiteralPath $SamplesDir | Select-Object Name, Length
