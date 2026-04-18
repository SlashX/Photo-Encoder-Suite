#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# photo_check.sh — Analiza completa fisiere foto + export CSV
# ============================================================================
# Analizeaza: EXIF, camera, HDR, Ultra HDR, DJI, GPS, Motion Photo
# Genereaza: CSV cu 50+ campuri + display terminal + recomandari
# Requires: ImageMagick
# Optional: exiftool (recomandat — fara el, analiza e limitata)
# ============================================================================

set -euo pipefail

VERSION="1.0"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'

# ── Paths ────────────────────────────────────────────────────────────────────
INPUT_DIR="/storage/emulated/0/Media/InputPhotos"
OUTPUT_DIR="/storage/emulated/0/Media/OutputPhotos"
CSV_FILE="${OUTPUT_DIR}/photo_check_report.csv"

# ── Defaults ─────────────────────────────────────────────────────────────────
RECURSIVE="true"
VERBOSE="false"
CSV_ONLY="false"

# ── Supported formats ────────────────────────────────────────────────────────
INPUT_EXTENSIONS="jpg jpeg png heic heif avif webp jxl tiff tif bmp gif raw cr2 nef arw dng orf rw2"

# ── Dependency check ─────────────────────────────────────────────────────────
HAS_EXIFTOOL="false"
MAGICK_CMD=""
IDENTIFY_CMD=""

check_dependencies() {
    if command -v magick &>/dev/null; then MAGICK_CMD="magick"; IDENTIFY_CMD="magick identify"
    elif command -v convert &>/dev/null; then MAGICK_CMD="convert"; IDENTIFY_CMD="identify"
    else echo -e "${RED}[ERROR]${NC} ImageMagick not found."; exit 1; fi

    command -v exiftool &>/dev/null && HAS_EXIFTOOL="true" || {
        echo -e "${YELLOW}[WARN]${NC} exiftool not found. Analiza va fi limitata (doar ImageMagick)."
        echo -e "${YELLOW}[WARN]${NC} Install: pkg install exiftool -y"
    }
}

# ── Utility ──────────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}        photo_check.sh v${VERSION}                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${GRAY}        Analiza completa fisiere foto + CSV export           ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    print_header
    cat << 'EOF'
USAGE:
  photo_check.sh -i <input_dir> [-o <output_dir>] [options]

OPTIONS:
  -i, --input <dir>      Input directory (required)
  -o, --output <dir>     Output directory for CSV (default: same as input)
  --no-recursive         Don't scan subdirectories
  --csv-only             Generate CSV only, minimal terminal output
  -v, --verbose          Show all fields per image in terminal
  -h, --help             Show this help

OUTPUT:
  Terminal: rezumat colorat per imagine (format, dimensiuni, HDR, DJI, UHDR)
  CSV:      photo_check_report.csv cu 50+ campuri per imagine

EXAMPLES:
  photo_check.sh -i /sdcard/DCIM/Camera
  photo_check.sh -i /sdcard/DCIM -o /sdcard/Media/OutputPhotos -v
  photo_check.sh -i ./photos --csv-only

EOF
    exit 0
}

is_supported_image() {
    local e="${1##*.}"; e="${e,,}"
    for s in $INPUT_EXTENSIONS; do [[ "$e" == "$s" ]] && return 0; done
    return 1
}

format_size() {
    local b="$1"
    if [[ $b -ge 1048576 ]]; then awk "BEGIN{printf\"%.1f MB\",$b/1048576}"
    elif [[ $b -ge 1024 ]]; then awk "BEGIN{printf\"%.0f KB\",$b/1024}"
    else echo "${b} B"; fi
}

declare -A META=()

# Bulk-load per-file EXIF tags into META assoc array
# Reduces exiftool calls from ~30 to ~4 per file
load_meta() {
    META=()
    [[ "$HAS_EXIFTOOL" != "true" ]] && return
    local file="$1" line tag val t

    # Pre-seed expected keys with "" so absent tags hit cache (no fallback exiftool call)
    for t in Make Model DateTimeOriginal ISO ShutterSpeed FNumber FocalLength \
             ExposureMode WhiteBalance Orientation ProfileDescription ColorSpace \
             BitsPerSample DigitalZoomRatio TransferCharacteristics ColorPrimaries \
             MaxContentLightLevel MaxFrameAverageLightLevel HDRHeadroom \
             MPImageCount SerialNumber DNGVersion DNGBackwardVersion Compression \
             GPSDateTime; do
        META[$t]=""
    done
    META["XMP-hdrgm:Version"]=""
    META["XMP-hdrgm:GainMapMax"]=""
    META["XMP-hdrgm:HDRCapacityMax"]=""
    META["XMP-GainMap:Version"]=""
    META["N:GPSLatitude"]=""
    META["N:GPSLongitude"]=""
    META["N:GPSAltitude"]=""

    # Bulk 1: standard EXIF tags (no group ambiguity)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tag="${line%%:*}"; val="${line#*:}"
        tag="${tag// /}"; val="${val# }"
        [[ -n "$tag" ]] && META[$tag]="$val"
    done < <(exiftool -s -S \
        -Make -Model -DateTimeOriginal -ISO -ShutterSpeed -FNumber \
        -FocalLength -ExposureMode -WhiteBalance -Orientation -ProfileDescription \
        -ColorSpace -BitsPerSample -DigitalZoomRatio \
        -TransferCharacteristics -ColorPrimaries \
        -MaxContentLightLevel -MaxFrameAverageLightLevel -HDRHeadroom \
        -MPImageCount -SerialNumber -DNGVersion -DNGBackwardVersion -Compression \
        -GPSDateTime "$file" 2>/dev/null)

    # Bulk 2: Ultra HDR hdrgm tags (stored with group prefix)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tag="${line%%:*}"; val="${line#*:}"
        tag="${tag// /}"; val="${val# }"
        [[ -n "$tag" ]] && META["XMP-hdrgm:$tag"]="$val"
    done < <(exiftool -s -S \
        -XMP-hdrgm:Version -XMP-hdrgm:GainMapMax -XMP-hdrgm:HDRCapacityMax \
        "$file" 2>/dev/null)
    local iso_gm; iso_gm=$(exiftool -s3 -XMP-GainMap:Version "$file" 2>/dev/null || echo "")
    [[ -n "$iso_gm" ]] && META["XMP-GainMap:Version"]="$iso_gm"

    # Bulk 3: DJI XMP tags (only if Make/Model indicates DJI)
    local _mk="${META[Make]:-}" _md="${META[Model]:-}"
    _mk="${_mk,,}"; _md="${_md,,}"
    if [[ "$_mk" == *"dji"* || "$_md" == *"dji"* || "$_md" == *"osmo"* || "$_md" == *"action"* || "$_md" == *"mavic"* ]]; then
        for t in SpeedX SpeedY SpeedZ GimbalPitchDegree GimbalYawDegree GimbalRollDegree \
                 FlightPitchDegree FlightYawDegree FlightRollDegree \
                 AbsoluteAltitude RelativeAltitude CameraSN; do
            META["XMP-drone-dji:$t"]=""
        done
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            tag="${line%%:*}"; val="${line#*:}"
            tag="${tag// /}"; val="${val# }"
            [[ -n "$tag" ]] && META["XMP-drone-dji:$tag"]="$val"
        done < <(exiftool -s -S -XMP-drone-dji:all "$file" 2>/dev/null)
    fi

    # Bulk 4: GPS numeric
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        tag="${line%%:*}"; val="${line#*:}"
        tag="${tag// /}"; val="${val# }"
        [[ -n "$tag" ]] && META["N:$tag"]="$val"
    done < <(exiftool -s -S -n -GPSLatitude -GPSLongitude -GPSAltitude "$file" 2>/dev/null)
}

safe_exif() {
    # Get exiftool value from META cache (populated by load_meta), fallback to direct call
    local file="$1" tag="$2"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo ""; return; }
    local key="${tag#-}"
    [[ -n "${META[$key]+x}" ]] && { echo "${META[$key]}"; return; }
    exiftool -s3 "$tag" "$file" 2>/dev/null || echo ""
}

safe_exif_n() {
    # Get exiftool numeric value from META cache
    local file="$1" tag="$2"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo ""; return; }
    local key="N:${tag#-}"
    [[ -n "${META[$key]+x}" ]] && { echo "${META[$key]}"; return; }
    exiftool -s3 -n "$tag" "$file" 2>/dev/null || echo ""
}

csv_escape() {
    # Escape value for CSV (wrap in quotes, escape existing quotes)
    local val="$1"
    val="${val//\"/\"\"}"
    echo "\"$val\""
}

# ══════════════════════════════════════════════════════════════════════════════
# ANALYZE SINGLE IMAGE
# ══════════════════════════════════════════════════════════════════════════════

analyze_image() {
    local file="$1"
    local bn="${file##*/}"
    local ext="${bn##*.}"; ext="${ext,,}"

    # Bulk-load EXIF tags into META cache (1 call vs ~30)
    load_meta "$file"

    # ── Basic info (ImageMagick) ──────────────────────────────────────
    local im_info
    im_info=$($IDENTIFY_CMD -format "%w|%h|%z|%m|%[colorspace]" "$file" 2>/dev/null | head -1 || echo "0|0|8|UNKNOWN|sRGB")
    local width height depth im_format colorspace
    IFS='|' read -r width height depth im_format colorspace <<< "$im_info"

    local file_size
    file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
    local megapixels
    megapixels=$(awk "BEGIN{printf\"%.1f\",$width*$height/1000000}")

    # ── EXIF / Camera ─────────────────────────────────────────────────
    local make model datetime iso shutter fnum focal exposure_mode wb
    local orientation color_profile bits_per_sample digital_zoom
    make=$(safe_exif "$file" "-Make")
    model=$(safe_exif "$file" "-Model")
    datetime=$(safe_exif "$file" "-DateTimeOriginal")
    iso=$(safe_exif "$file" "-ISO")
    shutter=$(safe_exif "$file" "-ShutterSpeed")
    fnum=$(safe_exif "$file" "-FNumber")
    focal=$(safe_exif "$file" "-FocalLength")
    exposure_mode=$(safe_exif "$file" "-ExposureMode")
    wb=$(safe_exif "$file" "-WhiteBalance")
    orientation=$(safe_exif "$file" "-Orientation")
    color_profile=$(safe_exif "$file" "-ProfileDescription")
    [[ -z "$color_profile" ]] && color_profile=$(safe_exif "$file" "-ColorSpace")
    bits_per_sample=$(safe_exif "$file" "-BitsPerSample")
    digital_zoom=$(safe_exif "$file" "-DigitalZoomRatio")

    # ── HDR ────────────────────────────────────────────────────────────
    # ── HDR (these are read by caller for stats — NOT local) ─────────
    is_hdr="no"
    local transfer_char color_primaries maxcll maxfall hdr_headroom
    transfer_char=$(safe_exif "$file" "-TransferCharacteristics")
    color_primaries=$(safe_exif "$file" "-ColorPrimaries")
    maxcll=$(safe_exif "$file" "-MaxContentLightLevel")
    maxfall=$(safe_exif "$file" "-MaxFrameAverageLightLevel")
    hdr_headroom=$(safe_exif "$file" "-HDRHeadroom")

    [[ "$depth" -gt 8 ]] && is_hdr="yes"
    [[ "$transfer_char" == *"2084"* || "$transfer_char" == *"PQ"* ]] && is_hdr="yes (PQ/HDR10)"
    [[ "$transfer_char" == *"HLG"* || "$transfer_char" == *"B67"* ]] && is_hdr="yes (HLG)"
    [[ -n "$hdr_headroom" ]] && is_hdr="yes (Apple Adaptive)"
    [[ -n "$maxcll" ]] && is_hdr="yes (HDR10 MaxCLL=$maxcll)"

    # ── Ultra HDR ──────────────────────────────────────────────────────
    is_uhdr="no"
    local uhdr_version="" gainmap_max="" hdr_cap_max="" mpf_count=""
    if [[ "$HAS_EXIFTOOL" == "true" && ( "$ext" == "jpg" || "$ext" == "jpeg" ) ]]; then
        uhdr_version=$(safe_exif "$file" "-XMP-hdrgm:Version")
        if [[ -n "$uhdr_version" ]]; then
            is_uhdr="yes (Ultra HDR v$uhdr_version)"
            gainmap_max=$(safe_exif "$file" "-XMP-hdrgm:GainMapMax")
            hdr_cap_max=$(safe_exif "$file" "-XMP-hdrgm:HDRCapacityMax")
        else
            local iso_gm; iso_gm=$(safe_exif "$file" "-XMP-GainMap:Version")
            [[ -n "$iso_gm" ]] && is_uhdr="yes (ISO 21496-1)"
        fi
        mpf_count=$(safe_exif "$file" "-MPImageCount")
        [[ -z "$mpf_count" ]] && mpf_count="1"
    fi

    # ── DJI ────────────────────────────────────────────────────────────
    is_dji="no"
    local dji_speed_x="" dji_speed_y="" dji_speed_z=""
    local dji_gimbal_p="" dji_gimbal_y="" dji_gimbal_r=""
    local dji_flight_p="" dji_flight_y="" dji_flight_r=""
    local dji_abs_alt="" dji_rel_alt="" dji_serial=""

    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        if [[ "${make,,}" == *"dji"* || "${model,,}" == *"dji"* || "${model,,}" == *"osmo"* || "${model,,}" == *"action"* || "${model,,}" == *"mavic"* ]]; then
            is_dji="yes"
            dji_speed_x=$(safe_exif "$file" "-XMP-drone-dji:SpeedX")
            dji_speed_y=$(safe_exif "$file" "-XMP-drone-dji:SpeedY")
            dji_speed_z=$(safe_exif "$file" "-XMP-drone-dji:SpeedZ")
            dji_gimbal_p=$(safe_exif "$file" "-XMP-drone-dji:GimbalPitchDegree")
            dji_gimbal_y=$(safe_exif "$file" "-XMP-drone-dji:GimbalYawDegree")
            dji_gimbal_r=$(safe_exif "$file" "-XMP-drone-dji:GimbalRollDegree")
            dji_flight_p=$(safe_exif "$file" "-XMP-drone-dji:FlightPitchDegree")
            dji_flight_y=$(safe_exif "$file" "-XMP-drone-dji:FlightYawDegree")
            dji_flight_r=$(safe_exif "$file" "-XMP-drone-dji:FlightRollDegree")
            dji_abs_alt=$(safe_exif "$file" "-XMP-drone-dji:AbsoluteAltitude")
            dji_rel_alt=$(safe_exif "$file" "-XMP-drone-dji:RelativeAltitude")
            dji_serial=$(safe_exif "$file" "-SerialNumber")
            [[ -z "$dji_serial" ]] && dji_serial=$(safe_exif "$file" "-XMP-drone-dji:CameraSN")
        fi
    fi

    # ── DNG version (1.0 → 1.7.1.0, detects JPEG XL compression) ──────
    dng_version=""
    dng_backward=""
    dng_compression=""
    dng_class=""
    if [[ "$ext" == "dng" && "$HAS_EXIFTOOL" == "true" ]]; then
        dng_version=$(safe_exif "$file" "-DNGVersion")
        dng_backward=$(safe_exif "$file" "-DNGBackwardVersion")
        dng_compression=$(safe_exif "$file" "-Compression")
        if [[ "$dng_compression" == *"JPEG XL"* || "$dng_compression" == *"JXL"* ]]; then
            dng_class="jxl"
        elif [[ -n "$dng_version" ]]; then
            local _dmin; _dmin=$(echo "$dng_version" | cut -d. -f2 2>/dev/null)
            if [[ "$_dmin" =~ ^[0-9]+$ && "$_dmin" -ge 7 ]]; then dng_class="jxl"; else dng_class="legacy"; fi
        fi
    fi

    # ── GPS ────────────────────────────────────────────────────────────
    gps_lat=""
    local gps_lon gps_alt gps_datetime
    gps_lat=$(safe_exif_n "$file" "-GPSLatitude")
    gps_lon=$(safe_exif_n "$file" "-GPSLongitude")
    gps_alt=$(safe_exif_n "$file" "-GPSAltitude")
    gps_datetime=$(safe_exif "$file" "-GPSDateTime")

    # ── Motion Photo ──────────────────────────────────────────────────
    motion_type="none"

    # Check for iPhone Live Photo companion MOV
    local dir; dir=$(dirname "$file"); local stem="${bn%.*}"
    for mext in MOV mov; do
        [[ -f "${dir}/${stem}.${mext}" ]] && { motion_type="iPhone Live Photo"; break; }
    done

    # Check for Samsung/Google/DJI embedded
    if [[ "$motion_type" == "none" && ( "$ext" == "jpg" || "$ext" == "jpeg" || "$ext" == "heic" ) ]]; then
        if grep -aqm1 "MotionPhoto_Data" "$file" 2>/dev/null; then
            motion_type="Samsung Motion Photo"
        elif [[ "$is_dji" == "yes" ]]; then
            # Check for DJI Live Photo (ftyp after JPEG data)
            local ftyp_check
            ftyp_check=$(grep -aob "ftyp" "$file" 2>/dev/null | cut -d: -f1 | while read pos; do [[ $pos -gt 100 ]] && echo "found" && break; done || true)
            [[ "$ftyp_check" == "found" ]] && motion_type="DJI Live Photo"
        else
            local ftyp_check
            ftyp_check=$(grep -aob "ftyp" "$file" 2>/dev/null | cut -d: -f1 | while read pos; do [[ $pos -gt 100 ]] && echo "found" && break; done || true)
            [[ "$ftyp_check" == "found" ]] && motion_type="Google Motion Picture"
        fi
    fi

    # ── Recomandare ────────────────────────────────────────────────────
    local recommendation=""
    if [[ "$is_uhdr" == yes* ]]; then
        recommendation="AVIF (--uhdr decode pt TRUE HDR) sau JPEG (base SDR)"
    elif [[ "$is_hdr" == yes* ]]; then
        recommendation="AVIF 10-bit (preserve HDR) sau JPEG (tone map SDR)"
    elif [[ "$ext" == "heic" || "$ext" == "heif" ]]; then
        recommendation="AVIF (mai mic) sau JPEG (universal)"
    elif [[ "$ext" == "dng" ]]; then
        if [[ "$dng_class" == "jxl" ]]; then
            recommendation="DNG ${dng_version:-1.7+} JPEG XL — ImageMagick + LibRaw 0.21+ sau Adobe DNG Converter -> 1.6"
        elif [[ -n "$dng_version" ]]; then
            recommendation="DNG ${dng_version} -> JPEG/AVIF (quality archive/print)"
        else
            recommendation="JPEG/AVIF (din RAW, quality archive/print)"
        fi
    elif [[ "$ext" == "cr2" || "$ext" == "nef" || "$ext" == "arw" ]]; then
        recommendation="JPEG/AVIF (din RAW, quality archive/print)"
    elif [[ "$ext" == "png" ]]; then
        recommendation="WEBP/AVIF (daca nu e nevoie de lossless)"
    elif [[ $width -gt 4000 ]]; then
        recommendation="Resize -r 1920 pt web, -r 3840 pt 4K"
    else
        recommendation="AVIF -p web (cel mai eficient)"
    fi

    if [[ "$is_dji" == "yes" && -n "$dji_serial" ]]; then
        recommendation="$recommendation | DJI: --dji privacy-strip pt sharing"
    fi

    # ── Terminal display ──────────────────────────────────────────────
    if [[ "$CSV_ONLY" != "true" ]]; then
        echo -e "${WHITE}${bn}${NC}"
        echo -e "  ${GRAY}Format:${NC} ${im_format} ${width}x${height} (${megapixels}MP) ${depth}-bit | $(format_size $file_size)"

        [[ -n "$make" ]] && echo -e "  ${GRAY}Camera:${NC} ${make} ${model} | ISO ${iso} | ${shutter} | f/${fnum} | ${focal}"
        [[ -n "$datetime" ]] && echo -e "  ${GRAY}Date:${NC}   ${datetime}"

        # HDR
        if [[ "$is_hdr" == yes* ]]; then
            echo -e "  ${MAGENTA}HDR:${NC}    ${is_hdr} | ${colorspace}"
            [[ -n "$transfer_char" ]] && echo -e "          Transfer: ${transfer_char} | Primaries: ${color_primaries}"
        fi

        # Ultra HDR
        if [[ "$is_uhdr" == yes* ]]; then
            echo -e "  ${BLUE}UHDR:${NC}   ${is_uhdr}"
            [[ -n "$gainmap_max" ]] && echo -e "          GainMax=${gainmap_max} HDRCap=${hdr_cap_max} MPF=${mpf_count}"
        fi

        # DJI
        if [[ "$is_dji" == "yes" ]]; then
            echo -e "  ${GREEN}DJI:${NC}    ${model}"
            [[ -n "$dji_gimbal_p" ]] && echo -e "          Gimbal: P=${dji_gimbal_p} Y=${dji_gimbal_y} R=${dji_gimbal_r}"
            [[ -n "$dji_speed_x" ]] && echo -e "          Speed: X=${dji_speed_x} Y=${dji_speed_y} Z=${dji_speed_z}"
            [[ -n "$dji_abs_alt" ]] && echo -e "          Alt: abs=${dji_abs_alt} rel=${dji_rel_alt}"
            [[ -n "$dji_serial" ]] && echo -e "          SN: ${dji_serial}"
        fi

        # DNG version
        if [[ -n "$dng_version" ]]; then
            local _dc="${MAGENTA}"; [[ "$dng_class" == "jxl" ]] && _dc="${YELLOW}"
            echo -e "  ${_dc}DNG:${NC}    v${dng_version} | Compression: ${dng_compression:-?}"
            [[ -n "$dng_backward" ]] && echo -e "          Backward: v${dng_backward}"
            [[ "$dng_class" == "jxl" ]] && echo -e "          ${YELLOW}JPEG XL — may need LibRaw 0.21+ or Adobe DNG Converter${NC}"
        fi

        # GPS
        [[ -n "$gps_lat" ]] && echo -e "  ${GRAY}GPS:${NC}    ${gps_lat}, ${gps_lon} | Alt: ${gps_alt}m"

        # Motion Photo
        [[ "$motion_type" != "none" ]] && echo -e "  ${CYAN}Motion:${NC} ${motion_type}"

        # Color profile
        [[ -n "$color_profile" ]] && echo -e "  ${GRAY}Color:${NC}  ${color_profile} | Orientation: ${orientation}"

        # Recommendation
        echo -e "  ${YELLOW}Rec:${NC}    ${recommendation}"

        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "  ${GRAY}──────────────────────────────────────────────────${NC}"
            echo -e "  ${GRAY}ExposureMode: ${exposure_mode} | WB: ${wb} | Zoom: ${digital_zoom}${NC}"
            echo -e "  ${GRAY}BitsPerSample: ${bits_per_sample} | ColorSpace: ${colorspace}${NC}"
            [[ -n "$maxcll" ]] && echo -e "  ${GRAY}MaxCLL: ${maxcll} | MaxFALL: ${maxfall}${NC}"
            [[ -n "$hdr_headroom" ]] && echo -e "  ${GRAY}HDRHeadroom: ${hdr_headroom}${NC}"
        fi
        echo ""
    fi

    # ── CSV row ───────────────────────────────────────────────────────
    CSV_ROW=""
    CSV_ROW+="$(csv_escape "$bn"),"
    CSV_ROW+="$(csv_escape "$ext"),"
    CSV_ROW+="$(csv_escape "$width"),"
    CSV_ROW+="$(csv_escape "$height"),"
    CSV_ROW+="$(csv_escape "$megapixels"),"
    CSV_ROW+="$(csv_escape "$depth"),"
    CSV_ROW+="$(csv_escape "$im_format"),"
    CSV_ROW+="$(csv_escape "$file_size"),"
    CSV_ROW+="$(csv_escape "$colorspace"),"
    CSV_ROW+="$(csv_escape "$make"),"
    CSV_ROW+="$(csv_escape "$model"),"
    CSV_ROW+="$(csv_escape "$datetime"),"
    CSV_ROW+="$(csv_escape "$iso"),"
    CSV_ROW+="$(csv_escape "$shutter"),"
    CSV_ROW+="$(csv_escape "$fnum"),"
    CSV_ROW+="$(csv_escape "$focal"),"
    CSV_ROW+="$(csv_escape "$exposure_mode"),"
    CSV_ROW+="$(csv_escape "$wb"),"
    CSV_ROW+="$(csv_escape "$orientation"),"
    CSV_ROW+="$(csv_escape "$color_profile"),"
    CSV_ROW+="$(csv_escape "$bits_per_sample"),"
    CSV_ROW+="$(csv_escape "$is_hdr"),"
    CSV_ROW+="$(csv_escape "$transfer_char"),"
    CSV_ROW+="$(csv_escape "$color_primaries"),"
    CSV_ROW+="$(csv_escape "$maxcll"),"
    CSV_ROW+="$(csv_escape "$maxfall"),"
    CSV_ROW+="$(csv_escape "$hdr_headroom"),"
    CSV_ROW+="$(csv_escape "$is_uhdr"),"
    CSV_ROW+="$(csv_escape "$uhdr_version"),"
    CSV_ROW+="$(csv_escape "$gainmap_max"),"
    CSV_ROW+="$(csv_escape "$hdr_cap_max"),"
    CSV_ROW+="$(csv_escape "$mpf_count"),"
    CSV_ROW+="$(csv_escape "$is_dji"),"
    CSV_ROW+="$(csv_escape "$dji_speed_x"),"
    CSV_ROW+="$(csv_escape "$dji_speed_y"),"
    CSV_ROW+="$(csv_escape "$dji_speed_z"),"
    CSV_ROW+="$(csv_escape "$dji_gimbal_p"),"
    CSV_ROW+="$(csv_escape "$dji_gimbal_y"),"
    CSV_ROW+="$(csv_escape "$dji_gimbal_r"),"
    CSV_ROW+="$(csv_escape "$dji_flight_p"),"
    CSV_ROW+="$(csv_escape "$dji_flight_y"),"
    CSV_ROW+="$(csv_escape "$dji_flight_r"),"
    CSV_ROW+="$(csv_escape "$dji_abs_alt"),"
    CSV_ROW+="$(csv_escape "$dji_rel_alt"),"
    CSV_ROW+="$(csv_escape "$dji_serial"),"
    CSV_ROW+="$(csv_escape "$dng_version"),"
    CSV_ROW+="$(csv_escape "$dng_backward"),"
    CSV_ROW+="$(csv_escape "$dng_compression"),"
    CSV_ROW+="$(csv_escape "$gps_lat"),"
    CSV_ROW+="$(csv_escape "$gps_lon"),"
    CSV_ROW+="$(csv_escape "$gps_alt"),"
    CSV_ROW+="$(csv_escape "$gps_datetime"),"
    CSV_ROW+="$(csv_escape "$motion_type"),"
    CSV_ROW+="$(csv_escape "$recommendation")"
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)       INPUT_DIR="$2"; shift 2 ;;
            -o|--output)      OUTPUT_DIR="$2"; shift 2 ;;
            --no-recursive)   RECURSIVE="false"; shift ;;
            --csv-only)       CSV_ONLY="true"; shift ;;
            -v|--verbose)     VERBOSE="true"; shift ;;
            -h|--help)        usage ;;
            --version)        echo "photo_check.sh v${VERSION}"; exit 0 ;;
            *)                echo -e "${RED}[ERROR]${NC} Unknown: $1"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"
    print_header
    check_dependencies

    [[ ! -d "$INPUT_DIR" ]] && { echo -e "${RED}[ERROR]${NC} Not found: $INPUT_DIR"; exit 1; }
    mkdir -p "$OUTPUT_DIR"
    CSV_FILE="${OUTPUT_DIR}/photo_check_report.csv"

    echo -e "  Input:    ${WHITE}${INPUT_DIR}${NC}"
    echo -e "  Output:   ${WHITE}${OUTPUT_DIR}${NC}"
    echo -e "  exiftool: $(if [[ "$HAS_EXIFTOOL" == "true" ]]; then echo -e "${GREEN}available${NC}"; else echo -e "${GRAY}not installed${NC}"; fi)"
    echo ""

    # Collect files
    local files=() fd=()
    [[ "$RECURSIVE" != "true" ]] && fd=(-maxdepth 1)
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$INPUT_DIR" "${fd[@]}" -type f -print0 2>/dev/null | sort -z)

    local image_files=()
    for f in "${files[@]}"; do is_supported_image "$f" && image_files+=("$f"); done
    local total=${#image_files[@]}

    [[ $total -eq 0 ]] && { echo -e "${YELLOW}[WARN]${NC} No images found"; exit 0; }

    echo -e "${GREEN}[INFO]${NC} Found $total image(s) to analyze"
    echo ""

    # CSV header
    echo "Filename,Extension,Width,Height,Megapixels,BitDepth,Format,FileSize,ColorSpace,Make,Model,DateTime,ISO,ShutterSpeed,FNumber,FocalLength,ExposureMode,WhiteBalance,Orientation,ColorProfile,BitsPerSample,IsHDR,TransferCharacteristics,ColorPrimaries,MaxCLL,MaxFALL,HDRHeadroom,IsUltraHDR,UHDRVersion,GainMapMax,HDRCapacityMax,MPFCount,IsDJI,DJI_SpeedX,DJI_SpeedY,DJI_SpeedZ,DJI_GimbalPitch,DJI_GimbalYaw,DJI_GimbalRoll,DJI_FlightPitch,DJI_FlightYaw,DJI_FlightRoll,DJI_AbsAltitude,DJI_RelAltitude,DJI_SerialNumber,DNGVersion,DNGBackwardVersion,DNGCompression,GPSLatitude,GPSLongitude,GPSAltitude,GPSDateTime,MotionPhoto,Recommendation" > "$CSV_FILE"

    # Counters
    local count=0
    local cnt_hdr=0 cnt_uhdr=0 cnt_dji=0 cnt_motion=0 cnt_gps=0
    local cnt_dng=0 cnt_dng_jxl=0
    local total_size=0

    for file in "${image_files[@]}"; do
        count=$((count + 1))

        [[ "$CSV_ONLY" != "true" ]] && printf "\r${GRAY}[%d/%d]${NC} Analyzing..." "$count" "$total"

        analyze_image "$file"
        echo "$CSV_ROW" >> "$CSV_FILE"

        # Count stats from last analysis
        local fsz; fsz=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
        total_size=$((total_size + fsz))

        # Read back from CSV_ROW is messy — use the variables still in scope
        # (analyze_image sets them as locals but they persist in this scope)
        [[ "$is_hdr" == yes* ]] && cnt_hdr=$((cnt_hdr + 1))
        [[ "$is_uhdr" == yes* ]] && cnt_uhdr=$((cnt_uhdr + 1))
        [[ "$is_dji" == "yes" ]] && cnt_dji=$((cnt_dji + 1))
        [[ "$motion_type" != "none" ]] && cnt_motion=$((cnt_motion + 1))
        [[ -n "$gps_lat" ]] && cnt_gps=$((cnt_gps + 1))
        [[ -n "$dng_version" ]] && cnt_dng=$((cnt_dng + 1))
        [[ "$dng_class" == "jxl" ]] && cnt_dng_jxl=$((cnt_dng_jxl + 1))
    done

    # ── Summary ───────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Summary${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Total images:       ${WHITE}${total}${NC}"
    echo -e "  Total size:         ${WHITE}$(format_size $total_size)${NC}"
    [[ $cnt_hdr -gt 0 ]]    && echo -e "  HDR images:         ${MAGENTA}${cnt_hdr}${NC}"
    [[ $cnt_uhdr -gt 0 ]]   && echo -e "  Ultra HDR images:   ${BLUE}${cnt_uhdr}${NC}"
    [[ $cnt_dji -gt 0 ]]    && echo -e "  DJI photos:         ${GREEN}${cnt_dji}${NC}"
    [[ $cnt_dng -gt 0 ]]    && { echo -e "  DNG files:          ${MAGENTA}${cnt_dng}${NC}"; [[ $cnt_dng_jxl -gt 0 ]] && echo -e "    DNG 1.7+ (JXL):   ${YELLOW}${cnt_dng_jxl}${NC}"; }
    [[ $cnt_motion -gt 0 ]] && echo -e "  Motion/Live Photo:  ${CYAN}${cnt_motion}${NC}"
    [[ $cnt_gps -gt 0 ]]    && echo -e "  With GPS:           ${WHITE}${cnt_gps}${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "  CSV:  ${WHITE}${CSV_FILE}${NC}"
    echo -e "        ${GRAY}54 campuri per imagine (deschide in Excel/Google Sheets)${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
