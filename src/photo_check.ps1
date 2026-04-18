<#
.SYNOPSIS
    photo_check.ps1 v1.0 — Analiza completa fisiere foto + export CSV
.DESCRIPTION
    Analizeaza: EXIF, camera, HDR, Ultra HDR, DJI, GPS, Motion Photo
    Genereaza: CSV cu 50+ campuri + display terminal + recomandari
    Requires: ImageMagick
    Optional: exiftool (recomandat)
.EXAMPLE
    .\photo_check.ps1 -InputDir ".\photos"
    .\photo_check.ps1 -InputDir ".\photos" -OutputDir ".\reports" -Verbose
    .\photo_check.ps1 -InputDir ".\DCIM" -CsvOnly
#>

param(
    [string]$InputDir = "",
    [string]$OutputDir = "",
    [switch]$NoRecursive,
    [switch]$CsvOnly,
    [switch]$Verbose
)

$Version = "1.0"
$ErrorActionPreference = "Stop"

# ── Paths ───────────────────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = Get-Location }

$SupportedExtensions = @("*.jpg","*.jpeg","*.png","*.heic","*.heif","*.avif","*.webp","*.jxl","*.tiff","*.tif","*.bmp","*.gif","*.raw","*.cr2","*.nef","*.arw","*.dng","*.orf","*.rw2")
$HasExiftool = [bool](Get-Command "exiftool" -ErrorAction SilentlyContinue)

# ── Validation ───────────────────────────────────────────────────────────────
if (-not (Get-Command "magick" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] ImageMagick not found" -ForegroundColor Red; exit 1
}
if (-not $InputDir) {
    Write-Host "[ERROR] Input directory required (-InputDir)" -ForegroundColor Red
    Write-Host "USAGE: .\photo_check.ps1 -InputDir <dir> [-OutputDir <dir>] [-Verbose] [-CsvOnly] [-NoRecursive]" -ForegroundColor Gray
    exit 1
}
if (-not (Test-Path $InputDir -PathType Container)) {
    Write-Host "[ERROR] Input not found: $InputDir" -ForegroundColor Red; exit 1
}
if (-not $OutputDir) { $OutputDir = $InputDir }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$CsvFile = Join-Path $OutputDir "photo_check_report.csv"
if (-not $HasExiftool) {
    Write-Host "[WARN] exiftool not found. Analiza va fi limitata (doar ImageMagick)." -ForegroundColor Yellow
}

# ── Helpers ──────────────────────────────────────────────────────────────────
function Fmt-Size([long]$B) {
    if ($B -ge 1MB) { "$([math]::Round($B/1MB,1)) MB" }
    elseif ($B -ge 1KB) { "$([math]::Round($B/1KB)) KB" }
    else { "$B B" }
}

$script:Meta = @{}

# Bulk-load per-file EXIF tags into $script:Meta hashtable
# Reduces exiftool calls from ~30 to ~4 per file
function Load-Meta([string]$File) {
    $script:Meta = @{}
    if (-not $HasExiftool) { return }

    # Pre-seed expected keys with "" so absent tags hit cache (no fallback exiftool call)
    foreach ($t in @("Make","Model","DateTimeOriginal","ISO","ShutterSpeed","FNumber",
                     "FocalLength","ExposureMode","WhiteBalance","Orientation","ProfileDescription",
                     "ColorSpace","BitsPerSample","DigitalZoomRatio","TransferCharacteristics",
                     "ColorPrimaries","MaxContentLightLevel","MaxFrameAverageLightLevel","HDRHeadroom",
                     "MPImageCount","SerialNumber","DNGVersion","DNGBackwardVersion","Compression",
                     "GPSDateTime")) { $script:Meta[$t] = "" }
    foreach ($t in @("XMP-hdrgm:Version","XMP-hdrgm:GainMapMax","XMP-hdrgm:HDRCapacityMax",
                     "XMP-GainMap:Version")) { $script:Meta[$t] = "" }
    foreach ($t in @("N:GPSLatitude","N:GPSLongitude","N:GPSAltitude")) { $script:Meta[$t] = "" }

    # Bulk 1: standard EXIF tags
    try {
        $out = & exiftool -s -S `
            -Make -Model -DateTimeOriginal -ISO -ShutterSpeed -FNumber `
            -FocalLength -ExposureMode -WhiteBalance -Orientation -ProfileDescription `
            -ColorSpace -BitsPerSample -DigitalZoomRatio `
            -TransferCharacteristics -ColorPrimaries `
            -MaxContentLightLevel -MaxFrameAverageLightLevel -HDRHeadroom `
            -MPImageCount -SerialNumber -DNGVersion -DNGBackwardVersion -Compression `
            -GPSDateTime "$File" 2>$null
        foreach ($line in $out) {
            if (-not $line) { continue }
            $idx = $line.IndexOf(":")
            if ($idx -lt 1) { continue }
            $tag = $line.Substring(0,$idx).Trim()
            $val = $line.Substring($idx+1).Trim()
            if ($tag) { $script:Meta[$tag] = $val }
        }
    } catch {}
    # Bulk 2: Ultra HDR hdrgm + ISO GainMap
    try {
        $out = & exiftool -s -S `
            -XMP-hdrgm:Version -XMP-hdrgm:GainMapMax -XMP-hdrgm:HDRCapacityMax `
            -XMP-GainMap:Version "$File" 2>$null
        foreach ($line in $out) {
            if (-not $line) { continue }
            $idx = $line.IndexOf(":")
            if ($idx -lt 1) { continue }
            $tag = $line.Substring(0,$idx).Trim()
            $val = $line.Substring($idx+1).Trim()
            if (-not $tag) { continue }
            if ($tag -eq "Version") { $script:Meta["XMP-hdrgm:Version"] = $val }
            elseif ($tag -eq "GainMapMax") { $script:Meta["XMP-hdrgm:GainMapMax"] = $val }
            elseif ($tag -eq "HDRCapacityMax") { $script:Meta["XMP-hdrgm:HDRCapacityMax"] = $val }
        }
    } catch {}
    # Bulk 3: DJI XMP (only if Make/Model indicates DJI)
    $mk = ($script:Meta["Make"] + "").ToLower()
    $md = ($script:Meta["Model"] + "").ToLower()
    if ($mk -match "dji" -or $md -match "dji|osmo|action|mavic") {
        foreach ($t in @("SpeedX","SpeedY","SpeedZ","GimbalPitchDegree","GimbalYawDegree",
                         "GimbalRollDegree","FlightPitchDegree","FlightYawDegree","FlightRollDegree",
                         "AbsoluteAltitude","RelativeAltitude","CameraSN")) {
            $script:Meta["XMP-drone-dji:$t"] = ""
        }
        try {
            $out = & exiftool -s -S -XMP-drone-dji:all "$File" 2>$null
            foreach ($line in $out) {
                if (-not $line) { continue }
                $idx = $line.IndexOf(":")
                if ($idx -lt 1) { continue }
                $tag = $line.Substring(0,$idx).Trim()
                $val = $line.Substring($idx+1).Trim()
                if ($tag) { $script:Meta["XMP-drone-dji:$tag"] = $val }
            }
        } catch {}
    }
    # Bulk 4: GPS numeric
    try {
        $out = & exiftool -s -S -n -GPSLatitude -GPSLongitude -GPSAltitude "$File" 2>$null
        foreach ($line in $out) {
            if (-not $line) { continue }
            $idx = $line.IndexOf(":")
            if ($idx -lt 1) { continue }
            $tag = $line.Substring(0,$idx).Trim()
            $val = $line.Substring($idx+1).Trim()
            if ($tag) { $script:Meta["N:$tag"] = $val }
        }
    } catch {}
}

function Safe-Exif([string]$File, [string]$Tag) {
    if (-not $HasExiftool) { return "" }
    $key = $Tag.TrimStart("-")
    if ($script:Meta.ContainsKey($key)) { return $script:Meta[$key] }
    try { $val = & exiftool -s3 $Tag "$File" 2>$null; if ($val) { return $val.Trim() } } catch {}
    return ""
}

function Safe-ExifN([string]$File, [string]$Tag) {
    if (-not $HasExiftool) { return "" }
    $key = "N:" + $Tag.TrimStart("-")
    if ($script:Meta.ContainsKey($key)) { return $script:Meta[$key] }
    try { $val = & exiftool -s3 -n $Tag "$File" 2>$null; if ($val) { return $val.Trim() } } catch {}
    return ""
}

function Csv-Escape([string]$Val) {
    '"' + $Val.Replace('"','""') + '"'
}

# ── Header ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  photo_check.ps1 v$Version" -ForegroundColor White
Write-Host "  Analiza completa fisiere foto + CSV export" -ForegroundColor Gray
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Input:    $InputDir" -ForegroundColor White
Write-Host "  Output:   $OutputDir" -ForegroundColor White
Write-Host "  exiftool: $(if($HasExiftool){'available'}else{'not installed'})" -ForegroundColor Gray
Write-Host ""

# ── Collect files ────────────────────────────────────────────────────────────
$Files = @()
foreach ($P in $SupportedExtensions) {
    $Files += Get-ChildItem -Path $InputDir -Filter $P -Recurse:(-not $NoRecursive) -File -ErrorAction SilentlyContinue
}
$Files = $Files | Sort-Object FullName
$Total = $Files.Count

if ($Total -eq 0) { Write-Host "[WARN] No images found" -ForegroundColor Yellow; exit 0 }
Write-Host "[INFO] Found $Total image(s) to analyze" -ForegroundColor Green
Write-Host ""

# ── CSV header ───────────────────────────────────────────────────────────────
"Filename,Extension,Width,Height,Megapixels,BitDepth,Format,FileSize,ColorSpace,Make,Model,DateTime,ISO,ShutterSpeed,FNumber,FocalLength,ExposureMode,WhiteBalance,Orientation,ColorProfile,BitsPerSample,IsHDR,TransferCharacteristics,ColorPrimaries,MaxCLL,MaxFALL,HDRHeadroom,IsUltraHDR,UHDRVersion,GainMapMax,HDRCapacityMax,MPFCount,IsDJI,DJI_SpeedX,DJI_SpeedY,DJI_SpeedZ,DJI_GimbalPitch,DJI_GimbalYaw,DJI_GimbalRoll,DJI_FlightPitch,DJI_FlightYaw,DJI_FlightRoll,DJI_AbsAltitude,DJI_RelAltitude,DJI_SerialNumber,DNGVersion,DNGBackwardVersion,DNGCompression,GPSLatitude,GPSLongitude,GPSAltitude,GPSDateTime,MotionPhoto,Recommendation" | Out-File $CsvFile -Encoding utf8

# ── Counters ─────────────────────────────────────────────────────────────────
$cnt = 0; $cntHdr = 0; $cntUhdr = 0; $cntDji = 0; $cntMotion = 0; $cntGps = 0; $cntDng = 0; $cntDngJxl = 0
$totalSize = [long]0

# ── Analyze each file ────────────────────────────────────────────────────────
foreach ($F in $Files) {
    $cnt++
    $bn = $F.Name
    $ext = $F.Extension.TrimStart(".").ToLower()
    $filePath = $F.FullName
    $fileSize = $F.Length
    $totalSize += $fileSize

    # Bulk-load EXIF tags into $script:Meta cache (1 call vs ~30)
    Load-Meta $filePath

    if (-not $CsvOnly) {
        $pct = [math]::Round($cnt/$Total*100)
        Write-Host "[$pct%] ($cnt/$Total) $bn" -ForegroundColor Blue -NoNewline
        Write-Host ""
    }

    # ── Basic info (ImageMagick) ─────────────────────────────────────
    $imInfo = "0|0|8|UNKNOWN|sRGB"
    try { $imInfo = & magick identify -format "%w|%h|%z|%m|%[colorspace]" "$filePath" 2>$null | Select-Object -First 1 } catch {}
    $parts = $imInfo -split "\|"
    $width = [int]$parts[0]; $height = [int]$parts[1]; $depth = [int]$parts[2]
    $imFormat = $parts[3]; $colorspace = $parts[4]
    $megapixels = [math]::Round($width * $height / 1000000.0, 1)

    # ── EXIF / Camera ────────────────────────────────────────────────
    $make = Safe-Exif $filePath "-Make"
    $model = Safe-Exif $filePath "-Model"
    $datetime = Safe-Exif $filePath "-DateTimeOriginal"
    $iso = Safe-Exif $filePath "-ISO"
    $shutter = Safe-Exif $filePath "-ShutterSpeed"
    $fnum = Safe-Exif $filePath "-FNumber"
    $focal = Safe-Exif $filePath "-FocalLength"
    $exposureMode = Safe-Exif $filePath "-ExposureMode"
    $wb = Safe-Exif $filePath "-WhiteBalance"
    $orientation = Safe-Exif $filePath "-Orientation"
    $colorProfile = Safe-Exif $filePath "-ProfileDescription"
    if (-not $colorProfile) { $colorProfile = Safe-Exif $filePath "-ColorSpace" }
    $bitsPerSample = Safe-Exif $filePath "-BitsPerSample"
    $digitalZoom = Safe-Exif $filePath "-DigitalZoomRatio"

    # ── HDR ───────────────────────────────────────────────────────────
    $isHdr = "no"
    $transferChar = Safe-Exif $filePath "-TransferCharacteristics"
    $colorPrimaries = Safe-Exif $filePath "-ColorPrimaries"
    $maxcll = Safe-Exif $filePath "-MaxContentLightLevel"
    $maxfall = Safe-Exif $filePath "-MaxFrameAverageLightLevel"
    $hdrHeadroom = Safe-Exif $filePath "-HDRHeadroom"

    if ($depth -gt 8) { $isHdr = "yes" }
    if ($transferChar -match "2084|PQ") { $isHdr = "yes (PQ/HDR10)" }
    if ($transferChar -match "HLG|B67") { $isHdr = "yes (HLG)" }
    if ($hdrHeadroom) { $isHdr = "yes (Apple Adaptive)" }
    if ($maxcll) { $isHdr = "yes (HDR10 MaxCLL=$maxcll)" }

    # ── Ultra HDR ────────────────────────────────────────────────────
    $isUhdr = "no"; $uhdrVersion = ""; $gainmapMax = ""; $hdrCapMax = ""; $mpfCount = ""
    if ($HasExiftool -and $ext -in "jpg","jpeg") {
        $uhdrVersion = Safe-Exif $filePath "-XMP-hdrgm:Version"
        if ($uhdrVersion) {
            $isUhdr = "yes (Ultra HDR v$uhdrVersion)"
            $gainmapMax = Safe-Exif $filePath "-XMP-hdrgm:GainMapMax"
            $hdrCapMax = Safe-Exif $filePath "-XMP-hdrgm:HDRCapacityMax"
        } else {
            $isoGm = Safe-Exif $filePath "-XMP-GainMap:Version"
            if ($isoGm) { $isUhdr = "yes (ISO 21496-1)" }
        }
        $mpfCount = Safe-Exif $filePath "-MPImageCount"
        if (-not $mpfCount) { $mpfCount = "1" }
    }

    # ── DJI ──────────────────────────────────────────────────────────
    $isDji = "no"
    $djiSpeedX = ""; $djiSpeedY = ""; $djiSpeedZ = ""
    $djiGimbalP = ""; $djiGimbalY = ""; $djiGimbalR = ""
    $djiFlightP = ""; $djiFlightY = ""; $djiFlightR = ""
    $djiAbsAlt = ""; $djiRelAlt = ""; $djiSerial = ""

    if ($HasExiftool) {
        $makeL = $make.ToLower(); $modelL = $model.ToLower()
        if ($makeL -match "dji" -or $modelL -match "dji|osmo|action|mavic") {
            $isDji = "yes"
            $djiSpeedX = Safe-Exif $filePath "-XMP-drone-dji:SpeedX"
            $djiSpeedY = Safe-Exif $filePath "-XMP-drone-dji:SpeedY"
            $djiSpeedZ = Safe-Exif $filePath "-XMP-drone-dji:SpeedZ"
            $djiGimbalP = Safe-Exif $filePath "-XMP-drone-dji:GimbalPitchDegree"
            $djiGimbalY = Safe-Exif $filePath "-XMP-drone-dji:GimbalYawDegree"
            $djiGimbalR = Safe-Exif $filePath "-XMP-drone-dji:GimbalRollDegree"
            $djiFlightP = Safe-Exif $filePath "-XMP-drone-dji:FlightPitchDegree"
            $djiFlightY = Safe-Exif $filePath "-XMP-drone-dji:FlightYawDegree"
            $djiFlightR = Safe-Exif $filePath "-XMP-drone-dji:FlightRollDegree"
            $djiAbsAlt = Safe-Exif $filePath "-XMP-drone-dji:AbsoluteAltitude"
            $djiRelAlt = Safe-Exif $filePath "-XMP-drone-dji:RelativeAltitude"
            $djiSerial = Safe-Exif $filePath "-SerialNumber"
            if (-not $djiSerial) { $djiSerial = Safe-Exif $filePath "-XMP-drone-dji:CameraSN" }
        }
    }

    # ── DNG version (1.0 -> 1.7.1.0, detects JPEG XL compression) ────
    $dngVersion = ""; $dngBackward = ""; $dngCompression = ""; $dngClass = ""
    if ($ext -eq "dng" -and $HasExiftool) {
        $dngVersion = Safe-Exif $filePath "-DNGVersion"
        $dngBackward = Safe-Exif $filePath "-DNGBackwardVersion"
        $dngCompression = Safe-Exif $filePath "-Compression"
        if ($dngCompression -match "JPEG\s*XL|JXL") {
            $dngClass = "jxl"
        } elseif ($dngVersion -match "^(\d+)\.(\d+)") {
            if ([int]$Matches[2] -ge 7) { $dngClass = "jxl" } else { $dngClass = "legacy" }
        }
    }

    # ── GPS ───────────────────────────────────────────────────────────
    $gpsLat = Safe-ExifN $filePath "-GPSLatitude"
    $gpsLon = Safe-ExifN $filePath "-GPSLongitude"
    $gpsAlt = Safe-ExifN $filePath "-GPSAltitude"
    $gpsDatetime = Safe-Exif $filePath "-GPSDateTime"

    # ── Motion Photo ─────────────────────────────────────────────────
    $motionType = "none"
    $dir = $F.DirectoryName; $stem = [IO.Path]::GetFileNameWithoutExtension($bn)
    foreach ($mext in "MOV","mov") {
        $companion = Join-Path $dir "$stem.$mext"
        if (Test-Path $companion) { $motionType = "iPhone Live Photo"; break }
    }
    if ($motionType -eq "none" -and $ext -in "jpg","jpeg","heic") {
        try {
            $bytes = [IO.File]::ReadAllBytes($filePath)
            $smMarker = [Text.Encoding]::ASCII.GetBytes("MotionPhoto_Data")
            $ftypMarker = [Text.Encoding]::ASCII.GetBytes("ftyp")
            # Samsung check
            $foundSamsung = $false
            for ($i = 0; $i -lt ($bytes.Length - $smMarker.Length); $i++) {
                $match = $true
                for ($j = 0; $j -lt $smMarker.Length; $j++) {
                    if ($bytes[$i+$j] -ne $smMarker[$j]) { $match = $false; break }
                }
                if ($match) { $foundSamsung = $true; break }
            }
            if ($foundSamsung) {
                $motionType = "Samsung Motion Photo"
            } else {
                # Google/DJI ftyp check
                for ($i = 100; $i -lt ($bytes.Length - 4); $i++) {
                    if ($bytes[$i] -eq $ftypMarker[0] -and $bytes[$i+1] -eq $ftypMarker[1] -and $bytes[$i+2] -eq $ftypMarker[2] -and $bytes[$i+3] -eq $ftypMarker[3]) {
                        if ($isDji -eq "yes") { $motionType = "DJI Live Photo" }
                        else { $motionType = "Google Motion Picture" }
                        break
                    }
                }
            }
        } catch {}
    }

    # ── Recommendation ───────────────────────────────────────────────
    $recommendation = ""
    if ($isUhdr -match "^yes") {
        $recommendation = "AVIF (--uhdr decode pt TRUE HDR) sau JPEG (base SDR)"
    } elseif ($isHdr -match "^yes") {
        $recommendation = "AVIF 10-bit (preserve HDR) sau JPEG (tone map SDR)"
    } elseif ($ext -in "heic","heif") {
        $recommendation = "AVIF (mai mic) sau JPEG (universal)"
    } elseif ($ext -eq "dng") {
        if ($dngClass -eq "jxl") {
            $verLabel = if ($dngVersion) { $dngVersion } else { "1.7+" }
            $recommendation = "DNG $verLabel JPEG XL - ImageMagick + LibRaw 0.21+ sau Adobe DNG Converter -> 1.6"
        } elseif ($dngVersion) {
            $recommendation = "DNG $dngVersion -> JPEG/AVIF (quality archive/print)"
        } else {
            $recommendation = "JPEG/AVIF (din RAW, quality archive/print)"
        }
    } elseif ($ext -in "cr2","nef","arw") {
        $recommendation = "JPEG/AVIF (din RAW, quality archive/print)"
    } elseif ($ext -eq "png") {
        $recommendation = "WEBP/AVIF (daca nu e nevoie de lossless)"
    } elseif ($width -gt 4000) {
        $recommendation = "Resize -r 1920 pt web, -r 3840 pt 4K"
    } else {
        $recommendation = "AVIF -p web (cel mai eficient)"
    }
    if ($isDji -eq "yes" -and $djiSerial) {
        $recommendation += " | DJI: --dji privacy-strip pt sharing"
    }

    # ── Stats ────────────────────────────────────────────────────────
    if ($isHdr -match "^yes") { $cntHdr++ }
    if ($isUhdr -match "^yes") { $cntUhdr++ }
    if ($isDji -eq "yes") { $cntDji++ }
    if ($motionType -ne "none") { $cntMotion++ }
    if ($gpsLat) { $cntGps++ }
    if ($dngVersion) { $cntDng++ }
    if ($dngClass -eq "jxl") { $cntDngJxl++ }

    # ── Terminal display ─────────────────────────────────────────────
    if (-not $CsvOnly) {
        Write-Host "  $bn" -ForegroundColor White
        Write-Host "  Format: $imFormat ${width}x${height} (${megapixels}MP) ${depth}-bit | $(Fmt-Size $fileSize)" -ForegroundColor Gray
        if ($make) { Write-Host "  Camera: $make $model | ISO $iso | $shutter | f/$fnum | $focal" -ForegroundColor Gray }
        if ($datetime) { Write-Host "  Date:   $datetime" -ForegroundColor Gray }
        if ($isHdr -match "^yes") {
            Write-Host "  HDR:    $isHdr | $colorspace" -ForegroundColor Magenta
            if ($transferChar) { Write-Host "          Transfer: $transferChar | Primaries: $colorPrimaries" -ForegroundColor Gray }
        }
        if ($isUhdr -match "^yes") {
            Write-Host "  UHDR:   $isUhdr" -ForegroundColor Blue
            if ($gainmapMax) { Write-Host "          GainMax=$gainmapMax HDRCap=$hdrCapMax MPF=$mpfCount" -ForegroundColor Gray }
        }
        if ($isDji -eq "yes") {
            Write-Host "  DJI:    $model" -ForegroundColor Green
            if ($djiGimbalP) { Write-Host "          Gimbal: P=$djiGimbalP Y=$djiGimbalY R=$djiGimbalR" -ForegroundColor Gray }
            if ($djiSpeedX) { Write-Host "          Speed: X=$djiSpeedX Y=$djiSpeedY Z=$djiSpeedZ" -ForegroundColor Gray }
            if ($djiAbsAlt) { Write-Host "          Alt: abs=$djiAbsAlt rel=$djiRelAlt" -ForegroundColor Gray }
            if ($djiSerial) { Write-Host "          SN: $djiSerial" -ForegroundColor Gray }
        }
        if ($dngVersion) {
            $dngColor = if ($dngClass -eq "jxl") { "Yellow" } else { "Magenta" }
            Write-Host "  DNG:    v$dngVersion | Compression: $dngCompression" -ForegroundColor $dngColor
            if ($dngBackward) { Write-Host "          Backward: v$dngBackward" -ForegroundColor Gray }
            if ($dngClass -eq "jxl") { Write-Host "          JPEG XL - may need LibRaw 0.21+ or Adobe DNG Converter" -ForegroundColor Yellow }
        }
        if ($gpsLat) { Write-Host "  GPS:    $gpsLat, $gpsLon | Alt: ${gpsAlt}m" -ForegroundColor Gray }
        if ($motionType -ne "none") { Write-Host "  Motion: $motionType" -ForegroundColor Cyan }
        Write-Host "  Rec:    $recommendation" -ForegroundColor Yellow
        if ($Verbose) {
            Write-Host "  ──────────────────────────────────────────────────" -ForegroundColor Gray
            Write-Host "  ExposureMode: $exposureMode | WB: $wb | Zoom: $digitalZoom" -ForegroundColor Gray
            Write-Host "  BitsPerSample: $bitsPerSample | ColorSpace: $colorspace" -ForegroundColor Gray
            if ($maxcll) { Write-Host "  MaxCLL: $maxcll | MaxFALL: $maxfall" -ForegroundColor Gray }
            if ($hdrHeadroom) { Write-Host "  HDRHeadroom: $hdrHeadroom" -ForegroundColor Gray }
        }
        Write-Host ""
    }

    # ── CSV row ──────────────────────────────────────────────────────
    $row = @(
        (Csv-Escape $bn), (Csv-Escape $ext), (Csv-Escape "$width"), (Csv-Escape "$height"),
        (Csv-Escape "$megapixels"), (Csv-Escape "$depth"), (Csv-Escape $imFormat), (Csv-Escape "$fileSize"),
        (Csv-Escape $colorspace), (Csv-Escape $make), (Csv-Escape $model), (Csv-Escape $datetime),
        (Csv-Escape $iso), (Csv-Escape $shutter), (Csv-Escape $fnum), (Csv-Escape $focal),
        (Csv-Escape $exposureMode), (Csv-Escape $wb), (Csv-Escape $orientation), (Csv-Escape $colorProfile),
        (Csv-Escape $bitsPerSample), (Csv-Escape $isHdr), (Csv-Escape $transferChar), (Csv-Escape $colorPrimaries),
        (Csv-Escape $maxcll), (Csv-Escape $maxfall), (Csv-Escape $hdrHeadroom),
        (Csv-Escape $isUhdr), (Csv-Escape $uhdrVersion), (Csv-Escape $gainmapMax), (Csv-Escape $hdrCapMax), (Csv-Escape $mpfCount),
        (Csv-Escape $isDji), (Csv-Escape $djiSpeedX), (Csv-Escape $djiSpeedY), (Csv-Escape $djiSpeedZ),
        (Csv-Escape $djiGimbalP), (Csv-Escape $djiGimbalY), (Csv-Escape $djiGimbalR),
        (Csv-Escape $djiFlightP), (Csv-Escape $djiFlightY), (Csv-Escape $djiFlightR),
        (Csv-Escape $djiAbsAlt), (Csv-Escape $djiRelAlt), (Csv-Escape $djiSerial),
        (Csv-Escape $dngVersion), (Csv-Escape $dngBackward), (Csv-Escape $dngCompression),
        (Csv-Escape $gpsLat), (Csv-Escape $gpsLon), (Csv-Escape $gpsAlt), (Csv-Escape $gpsDatetime),
        (Csv-Escape $motionType), (Csv-Escape $recommendation)
    ) -join ","
    $row | Out-File $CsvFile -Append -Encoding utf8
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Total images:       $Total" -ForegroundColor White
Write-Host "  Total size:         $(Fmt-Size $totalSize)" -ForegroundColor White
if ($cntHdr -gt 0) { Write-Host "  HDR images:         $cntHdr" -ForegroundColor Magenta }
if ($cntUhdr -gt 0) { Write-Host "  Ultra HDR images:   $cntUhdr" -ForegroundColor Blue }
if ($cntDji -gt 0) { Write-Host "  DJI photos:         $cntDji" -ForegroundColor Green }
if ($cntDng -gt 0) {
    Write-Host "  DNG files:          $cntDng" -ForegroundColor Magenta
    if ($cntDngJxl -gt 0) { Write-Host "    DNG 1.7+ (JXL):   $cntDngJxl" -ForegroundColor Yellow }
}
if ($cntMotion -gt 0) { Write-Host "  Motion/Live Photo:  $cntMotion" -ForegroundColor Cyan }
if ($cntGps -gt 0) { Write-Host "  With GPS:           $cntGps" -ForegroundColor White }
Write-Host "────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
Write-Host "  CSV:  $CsvFile" -ForegroundColor White
Write-Host "        54 campuri per imagine (deschide in Excel/Google Sheets)" -ForegroundColor Gray
Write-Host "================================================================`n" -ForegroundColor Cyan
