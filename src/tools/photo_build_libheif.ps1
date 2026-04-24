<#
.SYNOPSIS
    photo_build_libheif.ps1 — Compileaza libheif pe Windows (vcpkg)
.DESCRIPTION
    Necesita: Visual Studio 2019+ (cu C++ workload), CMake, Git
    Produce:  heif-convert.exe, heif-info.exe, libheif.dll

    vcpkg e cea mai simpla ruta pe Windows — gestioneaza automat dependintele
    (libde265 pentru HEVC decode, libaom pentru AV1, x265 pentru HEIC write).

    Alternativa rapida:
      winget install strukturag.libheif
    (nu garanteaza heif-convert in PATH — verifica dupa instalare)
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Build libheif — Windows (vcpkg)" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# ── Pasul 1: Verifica dependinte ─────────────────────────────────────────────
Write-Host "[1/5] Verificare dependinte..." -ForegroundColor Green

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Git nu e instalat." -ForegroundColor Red
    Write-Host "  Download: https://git-scm.com/download/win" -ForegroundColor Yellow
    Read-Host "Apasa Enter pentru a inchide"
    exit 1
}

if (-not (Get-Command "cmake" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] CMake nu e instalat." -ForegroundColor Red
    Write-Host "  Download: https://cmake.org/download/" -ForegroundColor Yellow
    Read-Host "Apasa Enter pentru a inchide"
    exit 1
}

# Detecteaza Visual Studio
$VsGenerator = $null
$VsPaths = @(
    "C:\Program Files\Microsoft Visual Studio\2022",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022",
    "C:\Program Files\Microsoft Visual Studio\2019",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019"
)
foreach ($p in $VsPaths) {
    if (Test-Path $p) {
        if ($p -match "2022") { $VsGenerator = "Visual Studio 17 2022" }
        else { $VsGenerator = "Visual Studio 16 2019" }
        break
    }
}

if (-not $VsGenerator) {
    Write-Host "[ERROR] Visual Studio 2019 sau 2022 nu e instalat." -ForegroundColor Red
    Write-Host "  Download: https://visualstudio.microsoft.com/downloads/" -ForegroundColor Yellow
    Write-Host '  Selecteaza "Desktop development with C++" la instalare.' -ForegroundColor Yellow
    Read-Host "Apasa Enter pentru a inchide"
    exit 1
}

Write-Host "  Git: OK" -ForegroundColor Gray
Write-Host "  CMake: OK" -ForegroundColor Gray
Write-Host "  Visual Studio: $VsGenerator" -ForegroundColor Gray
Write-Host ""

# ── Pasul 2: Setup vcpkg ─────────────────────────────────────────────────────
$VcpkgDir = Join-Path $env:USERPROFILE "vcpkg"

Write-Host "[2/5] Setup vcpkg..." -ForegroundColor Green

if (-not (Test-Path (Join-Path $VcpkgDir ".git"))) {
    Write-Host "  Clonare vcpkg in $VcpkgDir..." -ForegroundColor Gray
    Set-Location $env:USERPROFILE
    & git clone https://github.com/microsoft/vcpkg.git
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] git clone vcpkg esuat" -ForegroundColor Red
        Read-Host "Apasa Enter pentru a inchide"
        exit 1
    }
} else {
    Write-Host "  vcpkg exista — actualizez..." -ForegroundColor Gray
    Set-Location $VcpkgDir
    & git pull --ff-only 2>$null
}

Set-Location $VcpkgDir
if (-not (Test-Path (Join-Path $VcpkgDir "vcpkg.exe"))) {
    Write-Host "  Bootstrap vcpkg..." -ForegroundColor Gray
    & .\bootstrap-vcpkg.bat -disableMetrics
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] bootstrap-vcpkg esuat" -ForegroundColor Red
        Read-Host "Apasa Enter pentru a inchide"
        exit 1
    }
}

Write-Host "  vcpkg: OK" -ForegroundColor Gray
Write-Host ""

# ── Pasul 3: Instalare libheif + tools ───────────────────────────────────────
Write-Host "[3/5] Instalare libheif (poate dura 10-30 min la prima rulare)..." -ForegroundColor Green

& .\vcpkg.exe install "libheif[core,hevc,aom]:x64-windows" --recurse
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] vcpkg install libheif esuat" -ForegroundColor Red
    Read-Host "Apasa Enter pentru a inchide"
    exit 1
}

Write-Host ""

# ── Pasul 4: Localizare binare ───────────────────────────────────────────────
Write-Host "[4/5] Localizare heif-convert.exe..." -ForegroundColor Green

$BinDir = Join-Path $VcpkgDir "installed\x64-windows\tools\libheif"
$HeifConvert = Join-Path $BinDir "heif-convert.exe"
$HeifInfo    = Join-Path $BinDir "heif-info.exe"

if (-not (Test-Path $HeifConvert)) {
    # vcpkg may place tools under installed\x64-windows\bin
    $AltBin = Join-Path $VcpkgDir "installed\x64-windows\bin"
    if (Test-Path (Join-Path $AltBin "heif-convert.exe")) {
        $BinDir = $AltBin
        $HeifConvert = Join-Path $BinDir "heif-convert.exe"
        $HeifInfo    = Join-Path $BinDir "heif-info.exe"
    }
}

if (-not (Test-Path $HeifConvert)) {
    Write-Host "[ERROR] heif-convert.exe nu a fost gasit dupa build." -ForegroundColor Red
    Write-Host "  Cauta manual in: $VcpkgDir\installed\x64-windows\" -ForegroundColor Yellow
    Read-Host "Apasa Enter pentru a inchide"
    exit 1
}

Write-Host "  heif-convert.exe: $HeifConvert" -ForegroundColor Gray
Write-Host ""

# ── Pasul 5: Copiere langa photo_encoder.ps1 ─────────────────────────────────
Write-Host "[5/5] Copiere binare langa photo_encoder.ps1..." -ForegroundColor Green

$ScriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$TargetDir = $ScriptDir

Copy-Item $HeifConvert -Destination $TargetDir -Force
if (Test-Path $HeifInfo) { Copy-Item $HeifInfo -Destination $TargetDir -Force }

# Copy required DLLs (libheif + codec deps)
$DllDir = Join-Path $VcpkgDir "installed\x64-windows\bin"
if (Test-Path $DllDir) {
    Get-ChildItem -Path $DllDir -Filter "*.dll" | Where-Object {
        $_.Name -match "^(heif|de265|aom|x265|dav1d|sharpyuv)"
    } | ForEach-Object {
        Copy-Item $_.FullName -Destination $TargetDir -Force
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  [DONE] libheif instalat cu succes!" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  heif-convert.exe + DLLs -> $TargetDir" -ForegroundColor Gray
Write-Host ""
Write-Host "  Test:" -ForegroundColor White
Write-Host "    .\heif-convert.exe --version" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Folosire in photo_encoder.ps1:" -ForegroundColor White
Write-Host "    .\photo_encoder.ps1 -i InputHEIC\ -o OutputUHDR\ -UHDR convert" -ForegroundColor Cyan
Write-Host ""

Read-Host "Apasa Enter pentru a inchide"
