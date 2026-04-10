<#
.SYNOPSIS
    photo_encoder.ps1 v4.1.3 — Professional Photo Encoder — Samsung / Google / iPhone / DJI — Ultra HDR
.DESCRIPTION
    Full-featured converter with Ultra HDR (gain map detect/strip/extract/decode),
    classic HDR, tone mapping, quality presets, watermark, crop, motion photo, etc.
    Input:  AVIF/HEIC/JPEG/PNG/WEBP/TIFF/RAW/JXL
    Output: AVIF/WEBP/JPEG/HEIC/PNG/JXL
.EXAMPLE
    .\photo_encoder.ps1 -InputDir ".\photos" -OutputDir ".\web" -Format avif -Preset web
    .\photo_encoder.ps1 -InputDir ".\photos" -OutputDir ".\stripped" -Format jpeg -UHDR strip
    .\photo_encoder.ps1 -InputDir ".\photos" -OutputDir ".\hdr" -Format avif -UHDR decode -Depth 10
#>

param(
    [string]$InputDir = "",
    [string]$OutputDir = "",
    [ValidateSet("avif","webp","jpeg","jpg","heic","png","jxl")][string]$Format = "avif",
    [ValidateRange(1,100)][int]$Quality = 80,
    [ValidateSet("","web","social","archive","print")][string]$Preset = "",
    [string]$MaxSize = "",
    [string]$Resize = "",
    [ValidateSet("fit","fill","exact")][string]$ResizeMode = "fit",
    [string]$Crop = "",
    [ValidateSet("","8","10","16")][string]$Depth = "",
    [switch]$ForceSdr,
    [switch]$ForceHdr,
    [ValidateSet("","detect","info","strip","extract","decode")][string]$UHDR = "",
    [ValidateSet("","detect","export","privacy-strip")][string]$DJI = "",
    [switch]$StripExif,
    [switch]$NoAutoRotate,
    [switch]$SRGB,
    [string]$WatermarkText = "",
    [string]$WatermarkImage = "",
    [string]$WatermarkPos = "SouthEast",
    [int]$WatermarkOpacity = 30,
    [string]$Prefix = "",
    [string]$Suffix = "",
    [int]$MinRes = 0,
    [switch]$LosslessJpeg,
    [switch]$SkipDuplicates,
    [switch]$ExtractMotion,
    [switch]$MotionOnly,
    [switch]$Overwrite,
    [switch]$NoRecursive,
    [switch]$Flat,
    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$SkipExisting,
    [string]$Profile = ""
)

$Version = "4.1.3"
$ErrorActionPreference = "Stop"

# ── Paths ───────────────────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = Get-Location }
$ToolsDir = Join-Path $ScriptDir "tools"
$ProfilesDir = Join-Path $ScriptDir "profiles"
$UserProfilesDir = Join-Path $ScriptDir "UserProfiles"

# ── Launch mode (when no args given on command line) ────────────────────────
$InteractiveMode = $false
if (-not $InputDir -and -not $Profile) {
    Write-Host ""
    Write-Host "  1) Normal      — encode with default settings" -ForegroundColor Green
    Write-Host "  2) Dry-run     — analyze only, no conversion" -ForegroundColor Yellow
    Write-Host "  3) Interactiv  — profile save/load, manual config" -ForegroundColor Cyan
    Write-Host ""
    $launchChoice = Read-Host "  Choose [1-3, default=1]"
    switch ($launchChoice) {
        "2" { $DryRun = $true }
        "3" { $InteractiveMode = $true }
    }

    if (-not $InputDir) {
        Write-Host ""
        $InputDir = Read-Host "  Input folder"
    }
    if (-not $OutputDir) {
        $OutputDir = Read-Host "  Output folder"
    }
}

# ── Interactive UserProfiles/ load (option 3) ──────────────────────────────
if ($InteractiveMode) {
    if (-not (Test-Path $UserProfilesDir)) { New-Item -ItemType Directory -Force -Path $UserProfilesDir | Out-Null }

    $ProfileFiles = Get-ChildItem -Path $UserProfilesDir -Filter "*.conf" -File -ErrorAction SilentlyContinue
    if ($ProfileFiles.Count -gt 0) {
        Write-Host "`n  Saved profiles in UserProfiles\ folder:" -ForegroundColor White
        Write-Host "  ────────────────────────────────────" -ForegroundColor Cyan
        $idx = 0
        foreach ($pf in $ProfileFiles) {
            $idx++
            Write-Host "    $idx) $($pf.BaseName)" -ForegroundColor Green
        }
        Write-Host ""
        Write-Host "    0) Skip — configure manually" -ForegroundColor Gray
        Write-Host ""
        $choice = Read-Host "  Load profile [0-$idx]"
        if ($choice -and $choice -ne "0") {
            $choiceIdx = [int]$choice - 1
            if ($choiceIdx -ge 0 -and $choiceIdx -lt $ProfileFiles.Count) {
                $loadFile = $ProfileFiles[$choiceIdx].FullName
                Write-Host "  Loading: $($ProfileFiles[$choiceIdx].BaseName)" -ForegroundColor Green
                # Generic load (Set-Variable) — zero-maintenance
                Get-Content $loadFile | ForEach-Object {
                    $_ = $_.Trim()
                    if (-not $_ -or $_.StartsWith("#")) { return }
                    if ($_ -match '^([A-Za-z_]\w*)\s*=\s*(.*)$') {
                        Set-Variable -Name $Matches[1] -Value $Matches[2].Trim() -Scope Script
                    }
                }
                # Post-load mapping — type conversions
                if ($Quality)          { $Quality = [int]$Quality }
                if ($WatermarkOpacity) { $WatermarkOpacity = [int]$WatermarkOpacity }
                if ($MinRes)           { $MinRes = [int]$MinRes }
                if ($HdrMode -eq "force-sdr") { $ForceSdr = $true }
                if ($HdrMode -eq "force-hdr") { $ForceHdr = $true }
                foreach ($boolVar in @("StripExif","SRGB","NoAutoRotate","SkipDuplicates",
                    "LosslessJpeg","ExtractMotion","MotionOnly","SkipExisting","Overwrite","NoRecursive","Flat","Verbose")) {
                    if ((Get-Variable -Name $boolVar -ValueOnly -ErrorAction SilentlyContinue) -eq "true") {
                        Set-Variable -Name $boolVar -Value $true -Scope Script
                    }
                }
                if ($MotionOnly -eq $true) { $ExtractMotion = $true }
                # Display loaded settings for confirmation
                Write-Host "  ────────────────────────────────────" -ForegroundColor Cyan
                Write-Host "  Format       : $Format" -ForegroundColor White
                Write-Host "  Quality      : $(if ($Preset) { "$Preset" } else { $Quality })" -ForegroundColor White
                Write-Host "  Input        : $InputDir" -ForegroundColor White
                Write-Host "  Output       : $OutputDir" -ForegroundColor White
                if ($Resize)    { Write-Host "  Resize       : $Resize" -ForegroundColor White }
                if ($Crop)      { Write-Host "  Crop         : $Crop" -ForegroundColor White }
                $hdrDisp = if ($ForceSdr) { "force-sdr" } elseif ($ForceHdr) { "force-hdr" } else { "auto" }
                Write-Host "  HDR          : $hdrDisp" -ForegroundColor White
                if ($UHDR)      { Write-Host "  Ultra HDR    : $UHDR" -ForegroundColor White }
                if ($WatermarkText) { Write-Host "  Watermark    : $WatermarkText" -ForegroundColor White }
                Write-Host "  ────────────────────────────────────" -ForegroundColor Cyan
                $profConfirm = Read-Host "  Lanseaza cu aceste setari? (D/n)"
                if ($profConfirm -ieq "n") {
                    Write-Host "  Profil anulat — continuam cu configurare manuala." -ForegroundColor Yellow
                    # Reset to defaults
                    $Format = "avif"; $Quality = 80; $Preset = ""; $Resize = ""; $Crop = ""
                    $ForceSdr = $false; $ForceHdr = $false; $UHDR = ""; $DJI = ""
                    $StripExif = $false; $SRGB = $false; $WatermarkText = ""
                } else {
                    Write-Host "  Profile loaded.`n" -ForegroundColor Green
                }
            }
        }
    } else {
        Write-Host "  No saved profiles found. Profiles are saved in UserProfiles\ folder." -ForegroundColor Gray
    }
}

# ── Load profile from photo_profiles.conf ────────────────────────────────────
if ($Profile) {
    $ConfFile = Join-Path $ProfilesDir "photo_profiles.conf"
    if (-not (Test-Path $ConfFile)) { $ConfFile = Join-Path $env:USERPROFILE "photo_profiles.conf" }
    if (-not (Test-Path $ConfFile)) {
        Write-Host "[ERROR] photo_profiles.conf not found." -ForegroundColor Red
        Write-Host "  Place it in profiles\ folder next to this script or in $env:USERPROFILE" -ForegroundColor Yellow
        exit 1
    }
    $ProfileFound = $false
    foreach ($line in (Get-Content $ConfFile)) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith("#")) { continue }
        $parts = $line -split "=", 2
        $pName = $parts[0].Trim()
        $pArgs = $parts[1].Trim()
        if ($pName -eq $Profile) {
            $ProfileFound = $true
            Write-Host "[INFO] Loading profile: $Profile = $pArgs" -ForegroundColor Green
            $tokens = $pArgs -split "\s+"
            for ($i = 0; $i -lt $tokens.Count; $i++) {
                switch ($tokens[$i]) {
                    "-f"               { $Format = $tokens[++$i] }
                    "--format"         { $Format = $tokens[++$i] }
                    "-q"               { $Quality = [int]$tokens[++$i] }
                    "--quality"        { $Quality = [int]$tokens[++$i] }
                    "-p"               { $Preset = $tokens[++$i] }
                    "--preset"         { $Preset = $tokens[++$i] }
                    "-r"               { $Resize = $tokens[++$i] }
                    "--resize"         { $Resize = $tokens[++$i] }
                    "--resize-mode"    { $ResizeMode = $tokens[++$i] }
                    "--max-size"       { $MaxSize = $tokens[++$i] }
                    "--crop"           { $Crop = $tokens[++$i] }
                    "--depth"          { $Depth = $tokens[++$i] }
                    "--force-sdr"      { $ForceSdr = $true }
                    "--force-hdr"      { $ForceHdr = $true }
                    "--strip-exif"     { $StripExif = $true }
                    "--keep-exif"      { $StripExif = $false }
                    "--srgb"           { $SRGB = $true }
                    "--no-auto-rotate" { $NoAutoRotate = $true }
                    "--skip-duplicates" { $SkipDuplicates = $true }
                    "--lossless-jpeg"  { $LosslessJpeg = $true }
                    "-m"               { $ExtractMotion = $true }
                    "--extract-motion" { $ExtractMotion = $true }
                    "--motion-only"    { $MotionOnly = $true; $ExtractMotion = $true }
                    "--dji"            { $DJI = $tokens[++$i] }
                    "--uhdr"           { $UHDR = $tokens[++$i] }
                    "--watermark-text" { $WatermarkText = $tokens[++$i] }
                    "--watermark-image" { $WatermarkImage = $tokens[++$i] }
                    "--watermark-pos"  { $WatermarkPos = $tokens[++$i] }
                    "--watermark-opacity" { $WatermarkOpacity = [int]$tokens[++$i] }
                    "--prefix"         { $Prefix = $tokens[++$i] }
                    "--suffix"         { $Suffix = $tokens[++$i] }
                    "--min-res"        { $MinRes = [int]$tokens[++$i] }
                    "--skip-existing"  { $SkipExisting = $true }
                    "--overwrite"      { $Overwrite = $true }
                    "--no-recursive"   { $NoRecursive = $true }
                    "--flat"           { $Flat = $true }
                }
            }
            break
        }
    }
    if (-not $ProfileFound) {
        Write-Host "[ERROR] Profile '$Profile' not found in $ConfFile" -ForegroundColor Red
        Write-Host "  Available profiles:" -ForegroundColor Yellow
        foreach ($line in (Get-Content $ConfFile)) {
            $line = $line.Trim()
            if (-not $line -or $line.StartsWith("#")) { continue }
            $pn = ($line -split "=", 2)[0].Trim()
            Write-Host "    $pn" -ForegroundColor Green
        }
        exit 1
    }
}

if ($Format -eq "jpg") { $Format = "jpeg" }
$OutExt = if ($Format -eq "jpeg") { "jpg" } else { $Format }
$HdrMode = if ($ForceSdr) { "force-sdr" } elseif ($ForceHdr) { "force-hdr" } else { "auto" }
$HdrCapable = @("avif","heic","png","jxl")
$UhdrExts = @(".jpg",".jpeg")

$SupportedExtensions = @("*.jpg","*.jpeg","*.png","*.heic","*.heif","*.avif","*.webp","*.jxl","*.tiff","*.tif","*.bmp","*.gif","*.raw","*.cr2","*.nef","*.arw","*.dng","*.orf","*.rw2")
$MotionExtensions = @(".jpg",".jpeg",".heic",".heif")

$HasExiftool = [bool](Get-Command "exiftool" -ErrorAction SilentlyContinue)
$HasUhdrApp = [bool](Get-Command "ultrahdr_app" -ErrorAction SilentlyContinue)

if ($UHDR -eq "decode" -and -not $HasUhdrApp) {
    Write-Host "[ERROR] ultrahdr_app not found. Required for --uhdr decode." -ForegroundColor Red
    Write-Host "[ERROR] Build from: https://github.com/google/libultrahdr" -ForegroundColor Red
    exit 1
}

$Stats = @{ TotalIn=[long]0; TotalOut=[long]0; Dupes=0; MinResSkip=0; Lossless=0
            HdrDet=0; HdrTM=0; HdrPR=0; UhdrDet=0; UhdrStrip=0; UhdrExtract=0; UhdrDecode=0
            DjiDet=0; DjiExport=0; DjiLive=0; DjiStrip=0; SkipExist=0 }
$CompressionLog = [System.Collections.ArrayList]::new()
$SeenHashes = @{}; $StartTime = Get-Date

# ── Helpers ──────────────────────────────────────────────────────────────────
function Get-PresetQ($p,$f) {
    @{ web=@{avif=40;webp=75;jpeg=82;heic=50;jxl=45;png=95}; social=@{avif=35;webp=70;jpeg=78;heic=45;jxl=40;png=95}
       archive=@{avif=60;webp=90;jpeg=95;heic=70;jxl=65;png=95}; print=@{avif=65;webp=92;jpeg=97;heic=75;jxl=70;png=95} }[$p][$f]
}
$EffQ = if ($Preset) { Get-PresetQ $Preset $Format } else { $Quality }

function Fmt-Size([long]$B) { if($B -ge 1MB){"$([math]::Round($B/1MB,1)) MB"}elseif($B -ge 1KB){"$([math]::Round($B/1KB)) KB"}else{"$B B"} }
function Fmt-Dur([TimeSpan]$D) { if($D.TotalHours -ge 1){"$([int]$D.TotalHours)h $($D.Minutes)m"}elseif($D.TotalMinutes -ge 1){"$([int]$D.TotalMinutes)m $($D.Seconds)s"}else{"$([int]$D.TotalSeconds)s"} }
function Parse-SizeB([string]$S) { if($S -match '^([\d.]+)\s*(k|kb|m|mb)?$'){$n=[double]$Matches[1]; switch($Matches[2]){{$_ -in "k","kb"}{[long]($n*1KB)}{$_ -in "m","mb"}{[long]($n*1MB)}default{[long]$n}}}else{0} }

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  photo_encoder.ps1 v$Version" -ForegroundColor White
Write-Host "  Professional Batch Photo Encoder + HDR + Ultra HDR" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan

if (-not $InputDir) { Write-Host "[ERROR] Input directory required (-InputDir)" -ForegroundColor Red; exit 1 }
if (-not $OutputDir) { Write-Host "[ERROR] Output directory required (-OutputDir)" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $InputDir -PathType Container)) { Write-Host "[ERROR] Input not found: $InputDir" -ForegroundColor Red; exit 1 }
if (-not (Get-Command "magick" -ErrorAction SilentlyContinue)) { Write-Host "[ERROR] ImageMagick not found" -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# ── HEIC/JXL output support check ───────────────────────────────────────────
if ($Format -eq "heic") {
    $testFile = Join-Path $env:TEMP "heic_test_$PID.heic"
    try { & magick -size 1x1 xc:black "$testFile" 2>$null } catch {}
    if (-not (Test-Path $testFile)) {
        Write-Host "[WARN] ImageMagick cannot write HEIC. libheif may be missing." -ForegroundColor Yellow
        Write-Host "[WARN] Falling back to AVIF format." -ForegroundColor Yellow
        $Format = "avif"; $OutExt = "avif"
    }
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
}
if ($Format -eq "jxl") {
    $testFile = Join-Path $env:TEMP "jxl_test_$PID.jxl"
    try { & magick -size 1x1 xc:black "$testFile" 2>$null } catch {}
    if (-not (Test-Path $testFile)) {
        Write-Host "[WARN] ImageMagick cannot write JPEG XL. libjxl may be missing." -ForegroundColor Yellow
        Write-Host "[WARN] Falling back to AVIF format." -ForegroundColor Yellow
        $Format = "avif"; $OutExt = "avif"
    }
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
}

Write-Host "  Format: $($Format.ToUpper()) | $(if($Preset){"Preset: $Preset (q$EffQ)"}else{"Quality: $Quality"}) | HDR: $HdrMode" -ForegroundColor White
if ($UHDR) { Write-Host "  Ultra HDR: $UHDR" -ForegroundColor Blue } else { Write-Host "  Ultra HDR: auto-detect" -ForegroundColor White }
Write-Host "  libultrahdr: $(if($HasUhdrApp){'available'}else{'not installed'}) | exiftool: $(if($HasExiftool){'available'}else{'not installed'})" -ForegroundColor Gray
Write-Host "  Input: $InputDir -> Output: $OutputDir`n" -ForegroundColor White

# ══════════════════════════════════════════════════════════════════════════════
# ULTRA HDR FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Detect-UHDR([string]$Path) {
    if (-not $HasExiftool) { return "unknown" }
    $hdrgm = & exiftool -s3 "-XMP-hdrgm:Version" "$Path" 2>$null
    if ($hdrgm) { return "uhdr" }
    $iso = & exiftool -s3 "-XMP-GainMap:Version" "$Path" 2>$null
    if ($iso) { return "iso21496" }
    $mpfc = & exiftool -s3 -MPImageCount "$Path" 2>$null
    if ($mpfc -and [int]$mpfc -gt 1) {
        $hh = & exiftool -s3 -HDRHeadroom "$Path" 2>$null
        if ($hh) { return "adaptive" }
        return "mpf_possible"
    }
    return "none"
}

function Get-UHDRInfo([string]$Path) {
    if (-not $HasExiftool) { return "exiftool required" }
    $info = @()
    $v = & exiftool -s3 "-XMP-hdrgm:Version" "$Path" 2>$null; if($v){$info+="UHDR v$v"}
    $gmax = & exiftool -s3 "-XMP-hdrgm:GainMapMax" "$Path" 2>$null; if($gmax){$info+="GainMax=$gmax"}
    $hcap = & exiftool -s3 "-XMP-hdrgm:HDRCapacityMax" "$Path" 2>$null; if($hcap){$info+="HDRCap=$hcap"}
    $mpc = & exiftool -s3 -MPImageCount "$Path" 2>$null; if($mpc){$info+="MPF=$mpc images"}
    $mpl = & exiftool -s3 -MPImageLength "$Path" 2>$null; if($mpl){$sz=$mpl -split "`n"|Select-Object -Last 1; $info+="GainMap=$(Fmt-Size ([long]$sz))"}
    return ($info -join ", ")
}

function Strip-UHDRGainmap([string]$In, [string]$Out) {
    if (-not $HasExiftool) { Write-Host "[WARN] exiftool required" -ForegroundColor Yellow; return $false }
    if ($DryRun) { Write-Host "[DRY] Strip UHDR: $([IO.Path]::GetFileName($In))" -ForegroundColor Cyan; return $true }
    Copy-Item $In $Out -Force
    & exiftool -overwrite_original "-XMP-hdrgm:all=" "-XMP-GainMap:all=" "-MPF:all=" "$Out" 2>$null | Out-Null
    $inSz = (Get-Item $In).Length; $outSz = (Get-Item $Out).Length; $saved = $inSz - $outSz
    if ($saved -gt 0) {
        $sp = [math]::Round($saved/$inSz*100, 1)
        Write-Host "[UHDR] Stripped: $([IO.Path]::GetFileName($In)) ($(Fmt-Size $inSz) -> $(Fmt-Size $outSz), saved ${sp}%)" -ForegroundColor Blue
        $Stats.UhdrStrip++
    }
    return $true
}

function Extract-UHDRGainmap([string]$In, [string]$OutDir) {
    if (-not $HasExiftool) { Write-Host "[WARN] exiftool required" -ForegroundColor Yellow; return $false }
    $name = [IO.Path]::GetFileNameWithoutExtension($In)
    $gmOut = Join-Path $OutDir "${name}_gainmap.jpg"
    if ((Test-Path $gmOut) -and -not $Overwrite) { return $false }
    if ($DryRun) { Write-Host "[DRY] Extract gain map: $([IO.Path]::GetFileName($In))" -ForegroundColor Cyan; return $true }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    # Try MPImage2 extraction
    & exiftool -b -MPImage2 "$In" > "$gmOut" 2>$null
    if (-not (Test-Path $gmOut) -or (Get-Item $gmOut).Length -lt 100) {
        # Fallback: find second JPEG SOI marker
        Remove-Item $gmOut -Force -ErrorAction SilentlyContinue
        $bytes = [IO.File]::ReadAllBytes($In)
        $soi = @(0xFF, 0xD8, 0xFF)
        $count = 0; $offset = -1
        for ($i = 0; $i -lt ($bytes.Length - 3); $i++) {
            if ($bytes[$i] -eq $soi[0] -and $bytes[$i+1] -eq $soi[1] -and $bytes[$i+2] -eq $soi[2]) {
                $count++
                if ($count -eq 2) { $offset = $i; break }
            }
        }
        if ($offset -gt 100) {
            $gm = New-Object byte[] ($bytes.Length - $offset)
            [Array]::Copy($bytes, $offset, $gm, 0, $gm.Length)
            [IO.File]::WriteAllBytes($gmOut, $gm)
        }
    }

    if ((Test-Path $gmOut) -and (Get-Item $gmOut).Length -gt 100) {
        $sz = (Get-Item $gmOut).Length
        Write-Host "[UHDR] Gain map: $([IO.Path]::GetFileName($In)) -> ${name}_gainmap.jpg ($(Fmt-Size $sz))" -ForegroundColor Blue
        $Stats.UhdrExtract++
        return $true
    }
    Remove-Item $gmOut -Force -ErrorAction SilentlyContinue
    return $false
}

function Decode-UHDRFull([string]$In, [string]$Out) {
    if (-not $HasUhdrApp) { Write-Host "[ERROR] ultrahdr_app required" -ForegroundColor Red; return $false }
    if ($DryRun) { Write-Host "[DRY] UHDR decode: $([IO.Path]::GetFileName($In)) -> $([IO.Path]::GetFileName($Out))" -ForegroundColor Cyan; return $true }

    $name = [IO.Path]::GetFileNameWithoutExtension($In)
    $tmpDir = Join-Path $env:TEMP "uhdr_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $rawHdr = Join-Path $tmpDir "${name}_hdr.raw"

    $dims = & magick identify -format "%wx%h" "$In" 2>$null | Select-Object -First 1
    if ($dims -notmatch '^(\d+)x(\d+)$') { Remove-Item $tmpDir -Recurse -Force; return $false }
    $w = $Matches[1]; $h = $Matches[2]

    & ultrahdr_app -m 1 -j "$In" -z "$rawHdr" -o 2 -O 5 2>$null
    if (-not (Test-Path $rawHdr) -or (Get-Item $rawHdr).Length -lt 100) {
        Write-Host "[FAIL] UHDR decode failed: $([IO.Path]::GetFileName($In))" -ForegroundColor Red
        Remove-Item $tmpDir -Recurse -Force; return $false
    }

    $d = if ($Depth) { $Depth } else { "10" }
    $outDir2 = [IO.Path]::GetDirectoryName($Out)
    New-Item -ItemType Directory -Force -Path $outDir2 | Out-Null

    & magick -size "${w}x${h}" -depth 10 "RGBA:$rawHdr" -depth $d -quality $EffQ "$Out" 2>$null
    Remove-Item $tmpDir -Recurse -Force

    if (Test-Path $Out) {
        $inSz = (Get-Item $In).Length; $outSz = (Get-Item $Out).Length
        $Stats.TotalIn += $inSz; $Stats.TotalOut += $outSz; $Stats.UhdrDecode++
        Write-Host "[UHDR] Decoded: $([IO.Path]::GetFileName($In)) -> $([IO.Path]::GetFileName($Out)) ($(Fmt-Size $inSz) -> $(Fmt-Size $outSz), ${d}-bit HDR)" -ForegroundColor Blue
        return $true
    }
    return $false
}

# ══════════════════════════════════════════════════════════════════════════════
# DJI PHOTO FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Detect-DJIPhoto([string]$Path) {
    if (-not $HasExiftool) { return $false }
    $make = & exiftool -s3 -Make "$Path" 2>$null
    if ($make -and $make.ToLower() -match "dji") { return $true }
    $model = & exiftool -s3 -Model "$Path" 2>$null
    if ($model -and $model.ToLower() -match "dji|osmo|action|mavic|phantom|mini") { return $true }
    $xmp = & exiftool -s3 "-XMP-drone-dji:SpeedX" "$Path" 2>$null
    if ($xmp) { return $true }
    return $false
}

function Get-DJIInfo([string]$Path) {
    if (-not $HasExiftool) { return "exiftool required" }
    $i = @()
    $m = & exiftool -s3 -Model "$Path" 2>$null; if($m){$i+=$m}
    $lat = & exiftool -s3 -GPSLatitude "$Path" 2>$null; $lon = & exiftool -s3 -GPSLongitude "$Path" 2>$null
    if($lat){$i+="GPS: $lat, $lon"}
    $iso = & exiftool -s3 -ISO "$Path" 2>$null; $sh = & exiftool -s3 -ShutterSpeed "$Path" 2>$null
    $fn = & exiftool -s3 -FNumber "$Path" 2>$null
    if($iso){$i+="ISO=$iso $sh f/$fn"}
    $sn = & exiftool -s3 -SerialNumber "$Path" 2>$null; if($sn){$i+="SN:$sn"}
    return ($i -join " | ")
}

function Export-DJIMetadata([string]$InDir, [string]$OutDir) {
    if (-not $HasExiftool) { Write-Host "[ERROR] exiftool required" -ForegroundColor Red; return }
    $csv = Join-Path $OutDir "dji_photo_metadata.csv"
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    "Filename,Make,Model,DateTime,GPSLatitude,GPSLongitude,GPSAltitude,ISO,ShutterSpeed,FNumber,FocalLength,SpeedX,SpeedY,SpeedZ,GimbalPitch,GimbalYaw,GimbalRoll,SerialNumber" | Out-File $csv -Encoding utf8
    $cnt = 0
    foreach($F in $Files) {
        if (-not (Detect-DJIPhoto $F.FullName)) { continue }
        $cnt++; $n = $F.Name
        $fields = @("-Make","-Model","-DateTimeOriginal","-n -GPSLatitude","-n -GPSLongitude","-n -GPSAltitude","-ISO","-ShutterSpeed","-FNumber","-FocalLength")
        $vals = @($n)
        foreach($tag in "Make","Model","DateTimeOriginal") { $v = & exiftool -s3 "-$tag" $F.FullName 2>$null; $vals += "`"$v`"" }
        foreach($tag in "GPSLatitude","GPSLongitude","GPSAltitude") { $v = & exiftool -s3 -n "-$tag" $F.FullName 2>$null; $vals += "`"$v`"" }
        foreach($tag in "ISO","ShutterSpeed","FNumber","FocalLength") { $v = & exiftool -s3 "-$tag" $F.FullName 2>$null; $vals += "`"$v`"" }
        foreach($tag in "XMP-drone-dji:SpeedX","XMP-drone-dji:SpeedY","XMP-drone-dji:SpeedZ","XMP-drone-dji:GimbalPitchDegree","XMP-drone-dji:GimbalYawDegree","XMP-drone-dji:GimbalRollDegree") { $v = & exiftool -s3 "-$tag" $F.FullName 2>$null; $vals += "`"$v`"" }
        $sn = & exiftool -s3 -SerialNumber $F.FullName 2>$null; $vals += "`"$sn`""
        "`"$($vals -join '","')`"" | Out-File $csv -Append -Encoding utf8
        Write-Host "[DJI] Exported: $n" -ForegroundColor Green
        $Stats.DjiExport++
    }
    if ($cnt -gt 0) { Write-Host "[INFO] DJI metadata: $cnt photos -> $csv" -ForegroundColor Green }
    else { Write-Host "[WARN] No DJI photos found" -ForegroundColor Yellow; Remove-Item $csv -Force -ErrorAction SilentlyContinue }
}

function Strip-DJIPrivacy([string]$In, [string]$Out) {
    if (-not $HasExiftool) { Write-Host "[WARN] exiftool required" -ForegroundColor Yellow; return $false }
    if ($DryRun) { Write-Host "[DRY] DJI privacy strip: $([IO.Path]::GetFileName($In))" -ForegroundColor Cyan; return $true }
    Copy-Item $In $Out -Force
    & exiftool -overwrite_original "-GPS:all=" "-SerialNumber=" "-XMP-drone-dji:all=" "-Make=" "-Model=" "-HostComputer=" "$Out" 2>$null | Out-Null
    $Stats.DjiStrip++
    Write-Host "[DJI] Privacy stripped: $([IO.Path]::GetFileName($In))" -ForegroundColor Green
    return $true
}

function Extract-DJILivePhoto([string]$In, [string]$OutDir) {
    $name = [IO.Path]::GetFileNameWithoutExtension($In)
    $vidOut = Join-Path $OutDir "${name}_dji_live.mp4"
    if ((Test-Path $vidOut) -and -not $Overwrite) { return $false }
    $bytes = [IO.File]::ReadAllBytes($In)
    $ftyp = [Text.Encoding]::ASCII.GetBytes("ftyp")
    $offset = -1
    for ($i = 100; $i -lt ($bytes.Length - 4); $i++) {
        if ($bytes[$i] -eq $ftyp[0] -and $bytes[$i+1] -eq $ftyp[1] -and $bytes[$i+2] -eq $ftyp[2] -and $bytes[$i+3] -eq $ftyp[3]) {
            $offset = $i - 4; break
        }
    }
    if ($offset -le 0) { return $false }
    $vidSize = $bytes.Length - $offset
    if ($vidSize -lt 5000) { return $false }
    if ($DryRun) { Write-Host "[DRY] DJI Live Photo: $([IO.Path]::GetFileName($In))" -ForegroundColor Cyan; return $true }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $vid = New-Object byte[] $vidSize
    [Array]::Copy($bytes, $offset, $vid, 0, $vidSize)
    [IO.File]::WriteAllBytes($vidOut, $vid)
    $Stats.DjiLive++
    $mb = [math]::Round($vidSize/1MB, 1)
    Write-Host "[DJI] Live Photo: $([IO.Path]::GetFileName($In)) -> ${name}_dji_live.mp4 ($mb MB)" -ForegroundColor Green
    return $true
}

# ══════════════════════════════════════════════════════════════════════════════
# HDR DETECTION
# ══════════════════════════════════════════════════════════════════════════════

function Detect-HDR([string]$P) {
    $h = $false
    try { $d = & magick identify -format "%z" "$P" 2>$null | Select-Object -First 1; if([int]$d -gt 8){$h=$true} } catch {}
    if ($HasExiftool) {
        $t = & exiftool -s3 -MaxContentLightLevel -TransferCharacteristics -ColorPrimaries -HDRHeadroom "$P" 2>$null
        if (($t -join "|") -match "2084|PQ|HLG|2020|HDRHeadroom") { $h = $true }
    }
    return $h
}

function Resolve-HDR([bool]$IsHdr,[string]$Fmt) {
    if (-not $IsHdr) { return "pass" }
    if ($HdrMode -eq "force-sdr") { return "tonemap" }
    if ($HdrMode -eq "force-hdr") { return "preserve" }
    if ($HdrCapable -contains $Fmt) { return "preserve" } else { return "tonemap" }
}

function Get-TgtDepth([string]$Act,[string]$Fmt) {
    if ($Depth) { return $Depth }
    switch($Act) { "tonemap" {"8"} "preserve" { switch($Fmt){"avif"{"10"}"heic"{"10"}"jxl"{"10"}"png"{"16"}default{""}} } default { if($Fmt -in "jpeg","webp"){"8"}else{""} } }
}

# ══════════════════════════════════════════════════════════════════════════════
# MOTION / LIVE PHOTO
# ══════════════════════════════════════════════════════════════════════════════

function Find-LiveMOV([string]$P) {
    $d=[IO.Path]::GetDirectoryName($P); $s=[IO.Path]::GetFileNameWithoutExtension($P)
    foreach($e in ".MOV",".mov",".Mov"){$c=Join-Path $d "$s$e";if(Test-Path $c){$sz=(Get-Item $c).Length;if($sz -gt 0 -and $sz -lt 50MB){return $c}}}; return $null
}
function Do-ExtractLive([string]$Ph,[string]$Mv,[string]$Od) {
    $n=[IO.Path]::GetFileNameWithoutExtension($Ph);$o=Join-Path $Od "${n}_live.mov"
    if((Test-Path $o)-and -not $Overwrite){return $false}
    if($DryRun){Write-Host "[DRY] iPhone: $([IO.Path]::GetFileName($Ph))" -ForegroundColor Cyan;return $true}
    New-Item -ItemType Directory -Force -Path $Od|Out-Null;Copy-Item $Mv $o -Force
    Write-Host "[LIVE] iPhone: $([IO.Path]::GetFileName($Ph)) -> ${n}_live.mov" -ForegroundColor Green;return $true
}
function Do-ExtractEmbedded([string]$Fp,[string]$Od) {
    $n=[IO.Path]::GetFileNameWithoutExtension($Fp);$o=Join-Path $Od "${n}_motion.mp4"
    if((Test-Path $o)-and -not $Overwrite){return $false}
    $b=[IO.File]::ReadAllBytes($Fp);$off=-1;$src=""
    $sm=[Text.Encoding]::ASCII.GetBytes("MotionPhoto_Data");$ft=[Text.Encoding]::ASCII.GetBytes("ftyp")
    for($i=0;$i -lt($b.Length-$sm.Length);$i++){$m=$true;for($j=0;$j -lt $sm.Length;$j++){if($b[$i+$j]-ne$sm[$j]){$m=$false;break}};if($m){$off=$i+$sm.Length;$src="Samsung";break}}
    if($off -lt 0){for($i=100;$i -lt($b.Length-4);$i++){if($b[$i]-eq$ft[0]-and$b[$i+1]-eq$ft[1]-and$b[$i+2]-eq$ft[2]-and$b[$i+3]-eq$ft[3]){$off=$i-4;$src="Google";break}}}
    if($off -le 0){return $false};$vs=$b.Length-$off;if($vs -lt 1000){return $false}
    if($DryRun){Write-Host "[DRY] $src: $([IO.Path]::GetFileName($Fp))" -ForegroundColor Cyan;return $true}
    New-Item -ItemType Directory -Force -Path $Od|Out-Null
    $v=New-Object byte[] $vs;[Array]::Copy($b,$off,$v,0,$vs);[IO.File]::WriteAllBytes($o,$v)
    Write-Host "[MOTION] $src: $([IO.Path]::GetFileName($Fp)) -> ${n}_motion.mp4" -ForegroundColor Green;return $true
}

# ══════════════════════════════════════════════════════════════════════════════
# CONVERT
# ══════════════════════════════════════════════════════════════════════════════

function Convert-Photo([string]$In,[string]$Out,[int]$Q,[string]$HdrAct,[string]$TgtD) {
    if((Test-Path $Out)-and -not $Overwrite){return "skipped"}
    if($DryRun){Write-Host "[DRY] $([IO.Path]::GetFileName($In)) -> $([IO.Path]::GetFileName($Out)) (q$Q)" -ForegroundColor Cyan;return "dry"}

    # ── Lossless JPEG optimization ────────────────────────────────────
    if ($LosslessJpeg -and $Format -eq "jpeg") {
        $inExt = [IO.Path]::GetExtension($In).ToLower()
        if ($inExt -in ".jpg",".jpeg") {
            $od2 = [IO.Path]::GetDirectoryName($Out)
            New-Item -ItemType Directory -Force -Path $od2 | Out-Null
            $hasJpegtran = [bool](Get-Command "jpegtran" -ErrorAction SilentlyContinue)
            if ($hasJpegtran) {
                & jpegtran -copy none -optimize -progressive -outfile "$Out" "$In" 2>&1 | Out-Null
            } else {
                & magick "$In" -strip "$Out" 2>&1 | Out-Null
            }
            if (Test-Path $Out) {
                $isz = (Get-Item $In).Length; $osz = (Get-Item $Out).Length
                $Stats.TotalIn += $isz; $Stats.TotalOut += $osz; $Stats.Lossless++
                $r = [math]::Round(($osz/$isz)*100)
                Write-Host "[LOSSLESS] $([IO.Path]::GetFileName($In))  ($(Fmt-Size $isz) -> $(Fmt-Size $osz), ${r}%)" -ForegroundColor Green
                $script:CompressionLog.Add([PSCustomObject]@{Name=[IO.Path]::GetFileName($In);InSize=$isz;OutSize=$osz;Ratio=$r}) | Out-Null
                return "ok"
            }
        }
    }

    $a=@($In)
    if(-not $NoAutoRotate){$a+="-auto-orient"}
    if($HdrAct -eq "tonemap"){$a+=@("-colorspace","sRGB","-depth","8")}
    elseif($HdrAct -eq "preserve" -and $TgtD -and $TgtD -ne "8"){$a+=@("-depth",$TgtD)}
    elseif($Depth){$a+=@("-depth",$Depth)}
    if($SRGB -and $HdrAct -ne "tonemap"){$a+=@("-colorspace","sRGB")}

    if($Crop -and $Crop -match '^(\d+):(\d+)$'){
        $cw=[int]$Matches[1];$ch=[int]$Matches[2]
        $dims=& magick identify -format "%wx%h" $In 2>$null|Select-Object -First 1
        if($dims -match '^(\d+)x(\d+)$'){$iw=[int]$Matches[1];$ih=[int]$Matches[2];$tr=$cw/$ch;$cr=$iw/$ih
            if($cr -gt $tr){$nw=[math]::Floor($ih*$tr/2)*2;$nh=$ih}else{$nw=$iw;$nh=[math]::Floor($iw/$tr/2)*2}
            $a+=@("-gravity","Center","-crop","${nw}x${nh}+0+0","+repage")}}

    if($Resize){$rs=if($Resize -notmatch "x"){"${Resize}x"}else{$Resize}
        switch($ResizeMode){"fit"{$a+=@("-resize",$rs)}"fill"{$a+=@("-resize","${rs}^","-gravity","center","-extent",$Resize)}"exact"{$a+=@("-resize","${rs}!")}}}

    $a+=@("-quality",$Q.ToString())
    if($Format -eq "jpeg"){$s=if($Q -ge 90){"4:4:4"}else{"4:2:0"};$a+=@("-sampling-factor",$s)}
    if($StripExif){$a+="-strip"}
    if($WatermarkText){$a+=@("-gravity",$WatermarkPos,"-fill","white","-stroke","black","-strokewidth","1","-pointsize","36","-annotate","+20+20",$WatermarkText)}
    $a+=$Out

    $od=[IO.Path]::GetDirectoryName($Out);New-Item -ItemType Directory -Force -Path $od|Out-Null
    try {
        & magick @a 2>&1|Out-Null
        if($LASTEXITCODE -ne 0){throw "magick exit $LASTEXITCODE"}
        if($WatermarkImage -and (Test-Path $WatermarkImage)){
            $d2=& magick identify -format "%w" $Out 2>$null|Select-Object -First 1;$ww=[math]::Max(50,[int]([int]$d2*0.15))
            $tmp="$Out.wm";& magick composite -dissolve $WatermarkOpacity -gravity $WatermarkPos -geometry "${ww}x+20+20" $WatermarkImage $Out $tmp 2>&1|Out-Null
            if(Test-Path $tmp){Move-Item $tmp $Out -Force}}
        if(-not $StripExif -and $HasExiftool){
            & exiftool -TagsFromFile $In -overwrite_original $Out 2>&1|Out-Null
            if($HdrAct -eq "preserve"){& exiftool -TagsFromFile $In -MaxContentLightLevel -MaxFrameAverageLightLevel -ColorPrimaries -TransferCharacteristics -overwrite_original $Out 2>&1|Out-Null}}
        $isz=(Get-Item $In).Length;$osz=(Get-Item $Out).Length;$Stats.TotalIn+=$isz;$Stats.TotalOut+=$osz
        $r=[math]::Round(($osz/$isz)*100);$c=if($r -le 100){"Green"}else{"Yellow"}
        Write-Host "[OK] $([IO.Path]::GetFileName($In)) -> $([IO.Path]::GetFileName($Out))  ($(Fmt-Size $isz) -> $(Fmt-Size $osz), ${r}%)" -ForegroundColor $c
        $script:CompressionLog.Add([PSCustomObject]@{Name=[IO.Path]::GetFileName($In);InSize=$isz;OutSize=$osz;Ratio=$r}) | Out-Null
        return "ok"
    } catch { Write-Host "[FAIL] $([IO.Path]::GetFileName($In)): $_" -ForegroundColor Red; return "fail" }
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

$Files=@(); foreach($P in $SupportedExtensions){$Files+=Get-ChildItem -Path $InputDir -Filter $P -Recurse:(-not $NoRecursive) -File -ErrorAction SilentlyContinue}
$Files=$Files|Sort-Object FullName; $Total=$Files.Count
$Conv=0;$MoEx=0;$LiEx=0;$Skip=0;$Fail=0
if($Total -eq 0){Write-Host "[WARN] No images" -ForegroundColor Yellow;exit 0}
Write-Host "[INFO] Found $Total image(s)" -ForegroundColor Green

# Pre-scan UHDR
if ($HasExiftool) {
    $uc=0; foreach($F in $Files){ if($UhdrExts -contains $F.Extension.ToLower()){ $ut=Detect-UHDR $F.FullName; if($ut -notin "none","unknown"){$uc++} } }
    if($uc -gt 0){Write-Host "[INFO] Detected $uc Ultra HDR image(s)" -ForegroundColor Blue}
}
Write-Host ""

# DJI batch export (before per-file loop)
if ($DJI -eq "export") {
    Export-DJIMetadata $InputDir $OutputDir
    exit 0
}

$MaxB=if($MaxSize){Parse-SizeB $MaxSize}else{0}; $Cnt=0


foreach($F in $Files){
    $Cnt++; $Pct=[math]::Round($Cnt/$Total*100)
    $barW=40; $filled=[math]::Floor($Pct*$barW/100); $empty=$barW-$filled
    $bar = ("█" * $filled) + ("░" * $empty)
    Write-Host "[$bar] $Pct% ($Cnt/$Total) $($F.Name)" -ForegroundColor Blue

    # Skip duplicates
    if($SkipDuplicates){$h=(Get-FileHash $F.FullName -Algorithm SHA256).Hash;if($SeenHashes.ContainsKey($h)){$Stats.Dupes++;$Skip++;continue};$SeenHashes[$h]=$F.Name}
    # Min resolution
    if($MinRes -gt 0){try{$w=& magick identify -format "%w" $F.FullName 2>$null|Select-Object -First 1;if([int]$w -lt $MinRes){$Stats.MinResSkip++;$Skip++;continue}}catch{}}

    # Motion / Live Photo
    if($ExtractMotion -or $MotionOnly){
        if($MotionExtensions -contains $F.Extension.ToLower()){
            $rd=$F.DirectoryName.Replace($InputDir,"").TrimStart("\");$md=if($Flat -or -not $rd){Join-Path $OutputDir "motion_videos"}else{Join-Path $OutputDir(Join-Path $rd "motion_videos")}
            $cm=Find-LiveMOV $F.FullName;if($cm){if(Do-ExtractLive $F.FullName $cm $md){$LiEx++}}else{if(Do-ExtractEmbedded $F.FullName $md){$MoEx++}}}}
    if($MotionOnly){continue}

    # ── UHDR handling ─────────────────────────────────────────────────
    $isUhdr = $false
    if ($UhdrExts -contains $F.Extension.ToLower()) {
        $uhdrType = Detect-UHDR $F.FullName
        if ($uhdrType -notin "none","unknown") {
            $isUhdr = $true; $Stats.UhdrDet++
            $uhdrInfo = if($Verbose -or $UHDR -in "info","detect"){Get-UHDRInfo $F.FullName}else{""}

            switch ($UHDR) {
                "detect" { Write-Host "[UHDR] $($F.Name): $uhdrType ($uhdrInfo)" -ForegroundColor Blue; continue }
                "info"   { Write-Host "[UHDR] $($F.Name): $uhdrType ($uhdrInfo)" -ForegroundColor Blue; continue }
                "strip"  {
                    $rd=$F.DirectoryName.Replace($InputDir,"").TrimStart("\")
                    $od=if($Flat -or -not $rd){$OutputDir}else{Join-Path $OutputDir $rd}
                    $of=Join-Path $od "$($Prefix)$([IO.Path]::GetFileNameWithoutExtension($F.Name))$($Suffix).$OutExt"
                    Strip-UHDRGainmap $F.FullName $of; $Conv++; continue
                }
                "extract" {
                    $rd=$F.DirectoryName.Replace($InputDir,"").TrimStart("\")
                    $od=if($Flat -or -not $rd){$OutputDir}else{Join-Path $OutputDir $rd}
                    Extract-UHDRGainmap $F.FullName (Join-Path $od "gainmaps")
                    # Fall through to normal conversion
                }
                "decode" {
                    $rd=$F.DirectoryName.Replace($InputDir,"").TrimStart("\")
                    $od=if($Flat -or -not $rd){$OutputDir}else{Join-Path $OutputDir $rd}
                    $of=Join-Path $od "$($Prefix)$([IO.Path]::GetFileNameWithoutExtension($F.Name))$($Suffix).$OutExt"
                    if(Decode-UHDRFull $F.FullName $of){$Conv++}else{$Fail++}; continue
                }
                default {
                    Write-Host "[UHDR] $($F.Name): Ultra HDR detected ($uhdrType) - converting base SDR" -ForegroundColor Blue
                }
            }
        }
    }

    # ── DJI handling ─────────────────────────────────────────────────
    if ($HasExiftool -and (Detect-DJIPhoto $F.FullName)) {
        $Stats.DjiDet++
        switch ($DJI) {
            "detect" { $di = Get-DJIInfo $F.FullName; Write-Host "[DJI] $($F.Name): $di" -ForegroundColor Green; continue }
            "privacy-strip" {
                $rd2=$F.DirectoryName.Replace($InputDir,"").TrimStart("\")
                $od2=if($Flat -or -not $rd2){$OutputDir}else{Join-Path $OutputDir $rd2}
                $of2=Join-Path $od2 "$($Prefix)$([IO.Path]::GetFileNameWithoutExtension($F.Name))$($Suffix).$OutExt"
                if(Strip-DJIPrivacy $F.FullName $of2){$Conv++}; continue
            }
        }
        # DJI Live Photo extraction (when -m is enabled)
        if ($ExtractMotion -or $MotionOnly) {
            $rd3=$F.DirectoryName.Replace($InputDir,"").TrimStart("\")
            $md3=if($Flat -or -not $rd3){Join-Path $OutputDir "motion_videos"}else{Join-Path $OutputDir(Join-Path $rd3 "motion_videos")}
            Extract-DJILivePhoto $F.FullName $md3 | Out-Null
        }
    }

    # ── HDR detection ─────────────────────────────────────────────────
    $isHdr = Detect-HDR $F.FullName; $hdrAct = Resolve-HDR $isHdr $Format; $tgtD = Get-TgtDepth $hdrAct $Format
    if($isHdr){$Stats.HdrDet++
        if($hdrAct -eq "tonemap"){Write-Host "[HDR] $($F.Name): tone map SDR" -ForegroundColor Magenta;$Stats.HdrTM++}
        elseif($hdrAct -eq "preserve"){Write-Host "[HDR] $($F.Name): preserve ${tgtD}-bit" -ForegroundColor Magenta;$Stats.HdrPR++}}

    # ── Build output path ─────────────────────────────────────────────
    $rp=$F.FullName.Replace($InputDir,"").TrimStart("\");$rd=[IO.Path]::GetDirectoryName($rp);$st=[IO.Path]::GetFileNameWithoutExtension($F.Name)
    $od=if($Flat -or -not $rd){$OutputDir}else{Join-Path $OutputDir $rd}
    $on="${Prefix}${st}${Suffix}.${OutExt}";$of=Join-Path $od $on

    # ── Skip existing (resume) ────────────────────────────────────────
    if ($SkipExisting -and (Test-Path $of)) {
        $existSz = (Get-Item $of).Length
        if ($existSz -gt 0) {
            $Skip++; $Stats.SkipExist++
            if ($Verbose) { Write-Host "[SKIP] Already converted: $on ($(Fmt-Size $existSz))" -ForegroundColor Gray }
            continue
        }
    }

    # ── Convert ───────────────────────────────────────────────────────
    if($MaxB -gt 0){
        $curQ=$EffQ
        for($att=0;$att -lt 8;$att++){
            $r=Convert-Photo $F.FullName $of $curQ $hdrAct $tgtD
            if($r -ne "ok" -or -not(Test-Path $of)){break}
            $osz=(Get-Item $of).Length;if($osz -le $MaxB){break}
            $Stats.TotalIn-=(Get-Item $F.FullName).Length;$Stats.TotalOut-=$osz
            $ratio=$MaxB/$osz;$red=[math]::Max(5,[int]($curQ*(1-$ratio)));$curQ=[math]::Max(10,$curQ-$red);Remove-Item $of -Force
        }
        switch($r){"ok"{$Conv++}"skipped"{$Skip++}"fail"{$Fail++}}
    }else{
        $r=Convert-Photo $F.FullName $of $EffQ $hdrAct $tgtD
        switch($r){"ok"{$Conv++}"skipped"{$Skip++}"fail"{$Fail++}}
    }
}

# ── Save Profile Option (interactive only, not dry-run) ─────────────────────
if ($InteractiveMode -and -not $DryRun) {
    Write-Host ""
    $saveChoice = Read-Host "  Save this configuration as profile? (Y/N) [N]"
    if ($saveChoice -eq "Y" -or $saveChoice -eq "y") {
        if (-not (Test-Path $UserProfilesDir)) { New-Item -ItemType Directory -Force -Path $UserProfilesDir | Out-Null }
        $saveName = Read-Host "  Profile name"
        if ($saveName) {
            $saveFile = Join-Path $UserProfilesDir "$saveName.conf"
            $hdrModeVal = if ($ForceSdr) { "force-sdr" } elseif ($ForceHdr) { "force-hdr" } else { "auto" }
            @(
                "# Photo Encoder Profile: $saveName"
                "# Saved: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                "InputDir=$InputDir"
                "OutputDir=$OutputDir"
                "Format=$Format"
                "Quality=$Quality"
                "Preset=$Preset"
                "Resize=$Resize"
                "ResizeMode=$ResizeMode"
                "Crop=$Crop"
                "MaxSize=$MaxSize"
                "Depth=$Depth"
                "HdrMode=$hdrModeVal"
                "UHDR=$UHDR"
                "DJI=$DJI"
                "StripExif=$($StripExif.ToString().ToLower())"
                "SRGB=$($SRGB.ToString().ToLower())"
                "NoAutoRotate=$($NoAutoRotate.ToString().ToLower())"
                "WatermarkText=$WatermarkText"
                "WatermarkImage=$WatermarkImage"
                "WatermarkPos=$WatermarkPos"
                "WatermarkOpacity=$WatermarkOpacity"
                "NoRecursive=$($NoRecursive.ToString().ToLower())"
                "Flat=$($Flat.ToString().ToLower())"
                "Prefix=$Prefix"
                "Suffix=$Suffix"
                "MinRes=$MinRes"
                "SkipDuplicates=$($SkipDuplicates.ToString().ToLower())"
                "LosslessJpeg=$($LosslessJpeg.ToString().ToLower())"
                "ExtractMotion=$($ExtractMotion.ToString().ToLower())"
                "MotionOnly=$($MotionOnly.ToString().ToLower())"
                "SkipExisting=$($SkipExisting.ToString().ToLower())"
                "Overwrite=$($Overwrite.ToString().ToLower())"
                "Verbose=$($Verbose.ToString().ToLower())"
            ) | Out-File $saveFile -Encoding utf8
            Write-Host "  Saved: $saveFile" -ForegroundColor Green
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

$Dur=(Get-Date)-$StartTime; $TM=$MoEx+$LiEx
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Total: $Total | Converted: $Conv | Skipped: $Skip | Failed: $Fail"
if($Stats.Dupes -gt 0){Write-Host "    Duplicates: $($Stats.Dupes)" -ForegroundColor Gray}
if($Stats.MinResSkip -gt 0){Write-Host "    Below min-res: $($Stats.MinResSkip)" -ForegroundColor Gray}
if($Stats.SkipExist -gt 0){Write-Host "    Already converted: $($Stats.SkipExist)" -ForegroundColor Gray}
if($Stats.Lossless -gt 0){Write-Host "  Lossless optimized: $($Stats.Lossless)" -ForegroundColor Green}
if($TM -gt 0){Write-Host "  Motion videos: $TM (Samsung/Google: $MoEx, iPhone: $LiEx)" -ForegroundColor Green}
if($Stats.UhdrDet -gt 0){
    Write-Host "  Ultra HDR: $($Stats.UhdrDet) detected" -ForegroundColor Blue
    if($Stats.UhdrStrip -gt 0){Write-Host "    Stripped: $($Stats.UhdrStrip)"}
    if($Stats.UhdrExtract -gt 0){Write-Host "    Gain maps: $($Stats.UhdrExtract)"}
    if($Stats.UhdrDecode -gt 0){Write-Host "    Decoded HDR: $($Stats.UhdrDecode)"}
}
if($Stats.HdrDet -gt 0){Write-Host "  Classic HDR: $($Stats.HdrDet) (tonemapped: $($Stats.HdrTM), preserved: $($Stats.HdrPR))" -ForegroundColor Magenta}
if($Stats.DjiDet -gt 0){
    Write-Host "  DJI photos: $($Stats.DjiDet)" -ForegroundColor Green
    if($Stats.DjiExport -gt 0){Write-Host "    Exported: $($Stats.DjiExport)"}
    if($Stats.DjiLive -gt 0){Write-Host "    Live Photo: $($Stats.DjiLive)"}
    if($Stats.DjiStrip -gt 0){Write-Host "    Privacy stripped: $($Stats.DjiStrip)"}
}
Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
if(-not $DryRun -and -not $MotionOnly -and $Stats.TotalIn -gt 0){
    $saved=$Stats.TotalIn-$Stats.TotalOut
    Write-Host "  Size: $(Fmt-Size $Stats.TotalIn) -> $(Fmt-Size $Stats.TotalOut) $(if($saved -gt 0){"(saved $(Fmt-Size $saved))"})"
    # Compression Report
    if ($CompressionLog.Count -gt 0) {
        Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
        Write-Host "  Compression Report" -ForegroundColor White
        $best = $CompressionLog | Sort-Object Ratio | Select-Object -First 5
        $worst = $CompressionLog | Sort-Object Ratio -Descending | Select-Object -First 5
        Write-Host "  Top 5 most compressed:" -ForegroundColor Green
        foreach ($e in $best) {
            $sv = $e.InSize - $e.OutSize
            Write-Host "    $($e.Ratio)% $($e.Name) ($(Fmt-Size $e.InSize) -> $(Fmt-Size $e.OutSize), saved $(Fmt-Size $sv))" -ForegroundColor Green
        }
        Write-Host "  Top 5 least compressed:" -ForegroundColor Yellow
        foreach ($e in $worst) {
            $fc = if ($e.Ratio -gt 100) { "Red" } else { "Yellow" }
            Write-Host "    $($e.Ratio)% $($e.Name) ($(Fmt-Size $e.InSize) -> $(Fmt-Size $e.OutSize))" -ForegroundColor $fc
        }
    }
}
Write-Host "  Time: $(Fmt-Dur $Dur) | HDR: $HdrMode | UHDR: $(if($UHDR){$UHDR}else{'auto'})"
Write-Host "================================================================`n" -ForegroundColor Cyan
