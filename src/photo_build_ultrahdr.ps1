<#
.SYNOPSIS
    photo_build_ultrahdr.ps1 — Compileaza libultrahdr pe Windows
.DESCRIPTION
    Necesita: Visual Studio 2019+ (cu C++ workload), CMake, Git
    Produce:  ultrahdr_app.exe
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Build libultrahdr — Windows (PowerShell)" -ForegroundColor White
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

# ── Pasul 2: Cloneaza repository ─────────────────────────────────────────────
$BuildDir = Join-Path $env:USERPROFILE "libultrahdr_build"

Write-Host "[2/5] Clonare repository..." -ForegroundColor Green

if (Test-Path (Join-Path $BuildDir "libultrahdr\.git")) {
    Write-Host "  Repository exista, actualizez..." -ForegroundColor Gray
    Set-Location (Join-Path $BuildDir "libultrahdr")
    try {
        & git pull --ff-only 2>$null
    } catch {
        Write-Host "  Pull failed, reclonez..." -ForegroundColor Yellow
        Set-Location $env:USERPROFILE
        Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
        Set-Location $BuildDir
        & git clone https://github.com/google/libultrahdr.git
    }
} else {
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    Set-Location $BuildDir
    & git clone https://github.com/google/libultrahdr.git
}

Set-Location (Join-Path $BuildDir "libultrahdr")
$lastCommit = & git log --oneline -1 2>$null
Write-Host "  OK — $lastCommit" -ForegroundColor Gray
Write-Host ""

# ── Pasul 3: Configureaza build ─────────────────────────────────────────────
Write-Host "[3/5] Configurare CMake..." -ForegroundColor Green

if (Test-Path "build") { Remove-Item "build" -Recurse -Force }
New-Item -ItemType Directory -Force -Path "build" | Out-Null
Set-Location "build"

& cmake -G $VsGenerator `
    -DUHDR_BUILD_DEPS=1 `
    -DUHDR_BUILD_TESTS=0 `
    -DUHDR_BUILD_BENCHMARK=0 `
    -DUHDR_BUILD_FUZZERS=0 `
    .. 2>&1 | Select-String "Configuring|Generating|Build files" | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Write-Host "  OK" -ForegroundColor Gray
Write-Host ""

# ── Pasul 4: Compileaza ─────────────────────────────────────────────────────
Write-Host "[4/5] Compilare... (poate dura 3-10 minute)" -ForegroundColor Green

& cmake --build . --config Release 2>&1 | Select-String "Build succeeded|error|ultrahdr_app" | Select-Object -Last 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

$exePath = Join-Path (Get-Location) "Release\ultrahdr_app.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "[ERROR] Compilare esuata. ultrahdr_app.exe nu exista." -ForegroundColor Red
    Write-Host "  Deschide proiectul in Visual Studio si compileaza manual." -ForegroundColor Yellow
    Read-Host "Apasa Enter pentru a inchide"
    exit 1
}

Write-Host "  OK — ultrahdr_app.exe compilat" -ForegroundColor Gray
Write-Host ""

# ── Pasul 5: Instaleaza ─────────────────────────────────────────────────────
Write-Host "[5/5] Instalare..." -ForegroundColor Green

# Pune langa ffmpeg daca exista, altfel langa script
$InstallDir = $null
if (Test-Path "C:\ffmpeg\bin") { $InstallDir = "C:\ffmpeg\bin" }
if (-not $InstallDir) { $InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $InstallDir) { $InstallDir = Get-Location }

Copy-Item $exePath $InstallDir -Force

$installed = Get-Command "ultrahdr_app" -ErrorAction SilentlyContinue
if ($installed) {
    Write-Host "  OK — ultrahdr_app.exe instalat in $InstallDir" -ForegroundColor Green
} else {
    Write-Host "  ultrahdr_app.exe copiat in $InstallDir" -ForegroundColor Yellow
    Write-Host "  NOTA: Daca nu e in PATH, adauga manual folderul in variabila PATH." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  BUILD COMPLET!" -ForegroundColor Green
Write-Host "  ultrahdr_app.exe: $InstallDir\ultrahdr_app.exe" -ForegroundColor White
Write-Host "  Poti folosi: photo_encoder.ps1 -UHDR decode" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Sursa ramane in: $BuildDir\libultrahdr\" -ForegroundColor Gray
Write-Host "  Pentru stergere: Remove-Item '$BuildDir' -Recurse -Force" -ForegroundColor Gray
Write-Host ""

Read-Host "Apasa Enter pentru a inchide"
