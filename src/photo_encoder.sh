#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# photo_encoder.sh v4.3 — Professional Batch Photo Encoder
# ============================================================================
# Formats:  AVIF/HEIC/JPEG/PNG/WEBP/TIFF/RAW/DNG/JXL → AVIF/WEBP/JPEG/HEIC/PNG/JXL
# Motion:   Samsung Motion Photo + Google Motion Picture + iPhone Live Photo
#           + DJI 4K Live Photo
# HDR:      Auto detect, tone map HDR→SDR, preserve HDR, bit depth (8/10/16)
# UHDR:     Ultra HDR / Super HDR / Adaptive HDR (gain map)
# DJI:      Photo detection, metadata export, privacy strip, 4K Live Photo
# Requires: ImageMagick
# Optional: exiftool, jpegtran/mozjpeg, libultrahdr (ultrahdr_app)
# ============================================================================

set -euo pipefail

VERSION="4.3"

# ── Paths ───────────────────────────────────────────────────────────────────
INPUT_DIR="/storage/emulated/0/Media/InputPhotos"
OUTPUT_DIR="/storage/emulated/0/Media/OutputPhotos"
TOOLS_DIR="/storage/emulated/0/Media/Scripts/tools"
PROFILES_DIR="/storage/emulated/0/Media/Scripts/profiles"
USER_PROFILES_DIR="/storage/emulated/0/Media/UserProfiles"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
OUTPUT_FORMAT="avif"; QUALITY=80; QUALITY_PRESET=""; MAX_FILE_SIZE=""
RESIZE=""; RESIZE_MODE="fit"; CROP_RATIO=""
STRIP_EXIF="false"; AUTO_ROTATE="true"; SRGB_CONVERT="false"
WATERMARK_TEXT=""; WATERMARK_IMAGE=""; WATERMARK_POSITION="SouthEast"; WATERMARK_OPACITY=30
OUTPUT_PREFIX=""; OUTPUT_SUFFIX=""; MIN_RESOLUTION=0
LOSSLESS_JPEG="false"; SKIP_DUPLICATES="false"
PRESERVE_STRUCTURE="true"; OVERWRITE="false"; RECURSIVE="true"
EXTRACT_MOTION="false"; MOTION_ONLY="false"
DRY_RUN="false"; VERBOSE="false"; COMPARE="false"

# ── Batch / Watch ───────────────────────────────────────────────────────────
PARALLEL_JOBS=1               # 1 = sequential (default), 2-8 = parallel
SKIP_EXISTING="false"         # skip if output file exists and >0 bytes (resume)
PROFILE=""                    # named profile from photo_profiles.conf
WATCH_MODE="false"            # watch input dir for new files
WATCH_INTERVAL=5              # seconds between scans in watch mode

# ── HDR ──────────────────────────────────────────────────────────────────────
HDR_MODE="auto"               # auto | force-sdr | force-hdr
BIT_DEPTH=""                  # "" (auto) | 8 | 10 | 16

# ── Ultra HDR (UHDR) ────────────────────────────────────────────────────────
UHDR_ACTION=""                # "" (auto-detect+warn) | detect | strip | extract | decode | info
HAS_ULTRAHDR_APP="false"     # set in check_dependencies

HAS_EXIFTOOL="false"

# ── DJI ──────────────────────────────────────────────────────────────────────
DJI_ACTION=""                 # "" | detect | export | privacy-strip

# ── DNG ──────────────────────────────────────────────────────────────────────
DNG_PREVIEW_MODE="false"      # true = extract embedded preview JPEG (fast, skip demosaic)

# ── Supported formats ────────────────────────────────────────────────────────
INPUT_EXTENSIONS="jpg jpeg png heic heif avif webp jxl tiff tif bmp gif raw cr2 nef arw dng orf rw2"
MOTION_EXTENSIONS="jpg jpeg heic heif"
HDR_CAPABLE_FORMATS="avif heic png jxl"
UHDR_EXTENSIONS="jpg jpeg"    # Ultra HDR only exists in JPEG containers

# ── Tracking ─────────────────────────────────────────────────────────────────
declare -A LIVE_PHOTO_PAIRED=() SEEN_HASHES=()
declare -A DJI_DETECT_CACHE=() UHDR_DETECT_CACHE=()
STATS_TOTAL_IN_SIZE=0; STATS_TOTAL_OUT_SIZE=0; STATS_START_TIME=0
declare -A FORMAT_COUNTS=()
STATS_DUPLICATES_SKIPPED=0; STATS_MINRES_SKIPPED=0; STATS_LOSSLESS_OPTIMIZED=0
STATS_HDR_DETECTED=0; STATS_HDR_TONEMAPPED=0; STATS_HDR_PRESERVED=0
STATS_UHDR_DETECTED=0; STATS_UHDR_STRIPPED=0; STATS_UHDR_EXTRACTED=0; STATS_UHDR_DECODED=0
STATS_DJI_DETECTED=0; STATS_DJI_EXPORTED=0; STATS_DJI_LIVEPHOTO=0; STATS_DJI_STRIPPED=0
STATS_DNG_DETECTED=0; STATS_DNG_JXL=0; STATS_DNG_FAILED=0; STATS_DNG_PREVIEW=0
STATS_SKIPPED_EXISTING=0
# Compression tracking: "filename|in_size|out_size|ratio" per converted file
COMPRESSION_LOG=""

# ══════════════════════════════════════════════════════════════════════════════
# QUALITY PRESETS
# ══════════════════════════════════════════════════════════════════════════════

get_preset_quality() {
    local p="$1" f="$2"
    case "$p" in
        web)     case "$f" in avif) echo 40;; webp) echo 75;; jpeg) echo 82;; heic) echo 50;; jxl) echo 45;; png) echo 95;; esac ;;
        social)  case "$f" in avif) echo 35;; webp) echo 70;; jpeg) echo 78;; heic) echo 45;; jxl) echo 40;; png) echo 95;; esac ;;
        archive) case "$f" in avif) echo 60;; webp) echo 90;; jpeg) echo 95;; heic) echo 70;; jxl) echo 65;; png) echo 95;; esac ;;
        print)   case "$f" in avif) echo 65;; webp) echo 92;; jpeg) echo 97;; heic) echo 75;; jxl) echo 70;; png) echo 95;; esac ;;
        max)     case "$f" in avif) echo 80;; webp) echo 95;; jpeg) echo 98;; heic) echo 85;; jxl) echo 80;; png) echo 95;; esac ;;
        thumb)   case "$f" in avif) echo 25;; webp) echo 50;; jpeg) echo 60;; heic) echo 30;; jxl) echo 25;; png) echo 95;; esac ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# LOGGING & UTILITY
# ══════════════════════════════════════════════════════════════════════════════

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}        photo_encoder.sh v${VERSION}                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${GRAY}        Professional Batch Photo Encoder + HDR + UHDR         ${CYAN}║${NC}"
    echo -e "${CYAN}║${GRAY}        Samsung / Google / iPhone / DJI • Ultra HDR         ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

usage() {
    print_header
    cat << 'USAGE_EOF'
USAGE:
  photo_encoder.sh -i <input_dir> -o <output_dir> [options]

FORMAT & QUALITY:
  -f, --format <fmt>       avif, webp, jpeg, heic, png, jxl (default: avif)
  -q, --quality <1-100>    Manual quality (default: 80)
  -p, --preset <name>      web | social | archive | print
  --max-size <size>        Target max file size (e.g. 500k, 2m)

HDR & BIT DEPTH:
  --depth <8|10|16>        Output bit depth (default: auto)
  --force-sdr              Force tone map to SDR 8-bit (all formats)
  --force-hdr              Preserve HDR even on JPEG/WEBP
  (default: auto — tone map on JPEG/WEBP, preserve on AVIF/HEIC/PNG)

ULTRA HDR (gain map JPEG — Samsung Super HDR / Google Ultra HDR / Apple Adaptive HDR):
  --uhdr detect            Detect UHDR files and show info (no conversion)
  --uhdr strip             Strip gain map from UHDR JPEGs (smaller file, SDR only)
  --uhdr extract           Extract gain map as separate image (<name>_gainmap.jpg)
  --uhdr decode            Full HDR decode via libultrahdr → encode to AVIF/HEIC 10-bit
                            (requires ultrahdr_app in PATH — see setup instructions)
  --uhdr info              Show detailed UHDR metadata per file (verbose)
  (default without --uhdr: auto-detect UHDR, show warning, convert base SDR normally)

  Note: --uhdr decode produces TRUE HDR output by applying the gain map
  to reconstruct the full HDR image. This is the highest quality option.
  Requires libultrahdr compiled and ultrahdr_app in PATH.

RESIZE & CROP:
  -r, --resize <WxH|W>     Resize (e.g. 1920x1080, 1920)
  --resize-mode <mode>     fit | fill | exact
  --crop <ratio>           16:9, 4:3, 1:1, 9:16, 3:2

WATERMARK:
  --watermark-text <text>  --watermark-image <path>
  --watermark-pos <pos>    --watermark-opacity <0-100>

METADATA & COLOR:
  --strip-exif / --keep-exif   --srgb   --auto-rotate / --no-auto-rotate

DNG:
  --dng-preview            Extract embedded preview JPEG from DNG (fast path,
                           skip demosaic). Auto-fallback for DNG 1.7+ that
                           ImageMagick cannot decode. Requires ExifTool.

OUTPUT NAMING:     --prefix <text>  --suffix <text>
FILTERS:           --min-res <px>   --skip-duplicates   --lossless-jpeg
MOTION/LIVE PHOTO: -m / --motion-only
PROCESSING:        --overwrite  --no-recursive  --flat  --dry-run  -v

EXAMPLES:
  # Auto: detect UHDR, convert base SDR to AVIF
  photo_encoder.sh -i /sdcard/DCIM -o ./web -f avif -p web

  # Strip gain map from UHDR JPEGs (smaller files)
  photo_encoder.sh -i /sdcard/DCIM -o ./stripped -f jpeg --uhdr strip

  # Extract gain maps as separate images
  photo_encoder.sh -i /sdcard/DCIM -o ./maps --uhdr extract

  # Full UHDR decode → true HDR AVIF 10-bit (requires libultrahdr)
  photo_encoder.sh -i /sdcard/DCIM -o ./hdr -f avif --uhdr decode --depth 10

  # Just detect and show UHDR info (no conversion)
  photo_encoder.sh -i /sdcard/DCIM -o /dev/null --uhdr detect

  # Force all to SDR regardless of UHDR/HDR
  photo_encoder.sh -i /sdcard/DCIM -o ./sdr -f jpeg --force-sdr --uhdr strip

USAGE_EOF
    exit 0
}

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${GRAY}[VERB]${NC} $*" || true; }
log_dry()     { echo -e "${CYAN}[DRY]${NC} $*"; }
log_hdr()     { echo -e "${MAGENTA}[HDR]${NC} $*"; }
log_uhdr()    { echo -e "${BLUE}[UHDR]${NC} $*"; }

parse_size_bytes() { local i="${1,,}" n="${1//[^0-9.]/}" u="${1//[0-9.]/}"; u="${u,,}"; case "$u" in k|kb) awk "BEGIN{printf\"%.0f\",$n*1024}";; m|mb) awk "BEGIN{printf\"%.0f\",$n*1048576}";; *) echo "$n";; esac; }
format_size() { local b="$1"; if [[ $b -ge 1048576 ]]; then awk "BEGIN{printf\"%.1f MB\",$b/1048576}"; elif [[ $b -ge 1024 ]]; then awk "BEGIN{printf\"%.0f KB\",$b/1024}"; else echo "${b} B"; fi; }
format_duration() { local s="$1"; if [[ $s -ge 3600 ]]; then printf "%dh %dm %ds" $((s/3600)) $(((s%3600)/60)) $((s%60)); elif [[ $s -ge 60 ]]; then printf "%dm %ds" $((s/60)) $((s%60)); else printf "%ds" "$s"; fi; }

show_progress() {
    local c="$1" t="$2" n="$3" w=40 pct=$((${1}*100/${2}))
    local f=$((pct*w/100)) e=$((w-f)) bar=""
    for ((i=0;i<f;i++)); do bar+="█"; done; for ((i=0;i<e;i++)); do bar+="░"; done
    printf "\r${BLUE}[%s]${NC} %3d%% (%d/%d) %s\n" "$bar" "$pct" "$c" "$t" "$n"
}

is_supported_image() { local e="${1##*.}"; e="${e,,}"; for s in $INPUT_EXTENSIONS; do [[ "$e" == "$s" ]] && return 0; done; return 1; }
is_motion_candidate() { local e="${1##*.}"; e="${e,,}"; for m in $MOTION_EXTENSIONS; do [[ "$e" == "$m" ]] && return 0; done; return 1; }
is_hdr_capable() { for f in $HDR_CAPABLE_FORMATS; do [[ "$1" == "$f" ]] && return 0; done; return 1; }
is_uhdr_candidate() { local e="${1##*.}"; e="${e,,}"; for u in $UHDR_EXTENSIONS; do [[ "$e" == "$u" ]] && return 0; done; return 1; }

# ══════════════════════════════════════════════════════════════════════════════
# DEPENDENCY CHECK
# ══════════════════════════════════════════════════════════════════════════════

check_dependencies() {
    if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
        log_error "ImageMagick not found. Install: pkg install imagemagick"; exit 1
    fi
    command -v magick &>/dev/null && MAGICK_CMD="magick" || MAGICK_CMD="convert"
    IDENTIFY_CMD="${MAGICK_CMD/convert/identify}"
    [[ "$MAGICK_CMD" == "magick" ]] && IDENTIFY_CMD="magick identify"

    command -v exiftool &>/dev/null && HAS_EXIFTOOL="true" || {
        log_warn "exiftool not found. UHDR detection and EXIF transfer limited."
        log_warn "Install: pkg install exiftool -y"
    }

    command -v ultrahdr_app &>/dev/null && HAS_ULTRAHDR_APP="true" || {
        if [[ "$UHDR_ACTION" == "decode" ]]; then
            log_error "ultrahdr_app not found. Required for --uhdr decode."
            log_error "Build from: https://github.com/google/libultrahdr"
            log_error "After build, copy ultrahdr_app to PATH."
            exit 1
        fi
        [[ -n "$UHDR_ACTION" ]] && log_warn "libultrahdr not found. Advanced UHDR decode disabled."
    }

    if [[ "$SKIP_DUPLICATES" == "true" ]]; then
        command -v sha256sum &>/dev/null && HASH_CMD="sha256sum" || \
        { command -v shasum &>/dev/null && HASH_CMD="shasum -a 256" || { log_warn "sha256sum not found."; SKIP_DUPLICATES="false"; }; }
    fi
}

get_magick_cmd() { echo "$MAGICK_CMD"; }
get_image_width() { $IDENTIFY_CMD -format "%w" "$1" 2>/dev/null | head -1 || echo "0"; }
get_image_dimensions() { $IDENTIFY_CMD -format "%wx%h" "$1" 2>/dev/null | head -1 || echo "0x0"; }
get_file_hash() { $HASH_CMD "$1" 2>/dev/null | cut -d' ' -f1 || echo ""; }

# ══════════════════════════════════════════════════════════════════════════════
# PROFILES — Named presets from photo_profiles.conf
# ══════════════════════════════════════════════════════════════════════════════

# Profile format (photo_profiles.conf):
#   profilename = -f avif -p web -r 1920 --srgb --strip-exif
# One profile per line. Lines starting with # are comments.

load_profile() {
    local profile_name="$1"
    local conf_file="${PROFILES_DIR}/photo_profiles.conf"

    # Also check home as fallback
    [[ ! -f "$conf_file" ]] && conf_file="$HOME/photo_profiles.conf"

    if [[ ! -f "$conf_file" ]]; then
        log_error "photo_profiles.conf not found. Create it with profiles."
        log_info "Example: echo 'instagram = -f jpeg -p social -r 1080 --crop 1:1 --srgb' > $PROFILES_DIR/photo_profiles.conf"
        exit 1
    fi

    local profile_args=""
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local pname="${line%%=*}"; pname="${pname// /}"
        local pargs="${line#*=}"; pargs="${pargs# }"
        if [[ "$pname" == "$profile_name" ]]; then
            profile_args="$pargs"
            break
        fi
    done < "$conf_file"

    if [[ -z "$profile_args" ]]; then
        log_error "Profile '$profile_name' not found in $conf_file"
        log_info "Available profiles:"
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            local pn="${line%%=*}"; pn="${pn// /}"
            echo -e "  ${GREEN}${pn}${NC}"
        done < "$conf_file"
        exit 1
    fi

    log_info "Loading profile: ${profile_name} → ${profile_args}"
    # Re-parse with profile args (they get injected before user args)
    eval "set -- $profile_args"
    parse_profile_args "$@"
}

# Parse profile args (subset — only conversion flags, not -i/-o)
# Used by load_profile() for photo_profiles.conf (CLI flags format)
parse_profile_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--format)          OUTPUT_FORMAT="${2,,}"; shift 2 ;;
            -q|--quality)         QUALITY="$2"; shift 2 ;;
            -p|--preset)          QUALITY_PRESET="${2,,}"; shift 2 ;;
            --max-size)           MAX_FILE_SIZE="$2"; shift 2 ;;
            -r|--resize)          RESIZE="$2"; shift 2 ;;
            --resize-mode)        RESIZE_MODE="$2"; shift 2 ;;
            --crop)               CROP_RATIO="$2"; shift 2 ;;
            --depth)              BIT_DEPTH="$2"; shift 2 ;;
            --force-sdr)          HDR_MODE="force-sdr"; shift ;;
            --force-hdr)          HDR_MODE="force-hdr"; shift ;;
            --strip-exif)         STRIP_EXIF="true"; shift ;;
            --keep-exif)          STRIP_EXIF="false"; shift ;;
            --srgb)               SRGB_CONVERT="true"; shift ;;
            --no-auto-rotate)     AUTO_ROTATE="false"; shift ;;
            --watermark-text)     WATERMARK_TEXT="$2"; shift 2 ;;
            --watermark-image)    WATERMARK_IMAGE="$2"; shift 2 ;;
            --watermark-pos)      WATERMARK_POSITION="$2"; shift 2 ;;
            --watermark-opacity)  WATERMARK_OPACITY="$2"; shift 2 ;;
            --prefix)             OUTPUT_PREFIX="$2"; shift 2 ;;
            --suffix)             OUTPUT_SUFFIX="$2"; shift 2 ;;
            --min-res)            MIN_RESOLUTION="$2"; shift 2 ;;
            --skip-duplicates)    SKIP_DUPLICATES="true"; shift ;;
            --lossless-jpeg)      LOSSLESS_JPEG="true"; shift ;;
            -m|--extract-motion)  EXTRACT_MOTION="true"; shift ;;
            --motion-only)        MOTION_ONLY="true"; EXTRACT_MOTION="true"; shift ;;
            --dji)                DJI_ACTION="${2,,}"; shift 2 ;;
            --uhdr)               UHDR_ACTION="${2,,}"; shift 2 ;;
            --dng-preview)        DNG_PREVIEW_MODE="true"; shift ;;
            --skip-existing)      SKIP_EXISTING="true"; shift ;;
            --overwrite)          OVERWRITE="true"; shift ;;
            --no-recursive)       RECURSIVE="false"; shift ;;
            --flat)               PRESERVE_STRUCTURE="false"; shift ;;
            --compare)            COMPARE="true"; shift ;;
            *)                    shift ;;  # skip unknown profile args
        esac
    done
}

# Load profile from profiles/*.conf (KEY=VALUE format, generic eval)
# Used by interactive mode (profiles/ folder)
# NOTE: Uses case/esac whitelist instead of generic eval for bash security.
# Trade-off: new parameters must be added manually here AND in save_profile_conf().
# PS1 uses Set-Variable (zero-maintenance) because PowerShell scope is safer.
load_profile_conf() {
    local conf_file="$1"
    while IFS= read -r line; do
        line="${line## }"; line="${line%% }"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            val="${val## }"; val="${val%% }"
            # Safety: only set known variables
            case "$key" in
                InputDir)         INPUT_DIR="$val" ;;
                OutputDir)        OUTPUT_DIR="$val" ;;
                Format)           OUTPUT_FORMAT="${val,,}" ;;
                Quality)          QUALITY="$val" ;;
                Preset)           [[ -n "$val" ]] && QUALITY_PRESET="${val,,}" ;;
                Resize)           [[ -n "$val" ]] && RESIZE="$val" ;;
                ResizeMode)       RESIZE_MODE="$val" ;;
                Crop)             [[ -n "$val" ]] && CROP_RATIO="$val" ;;
                MaxSize)          [[ -n "$val" ]] && MAX_FILE_SIZE="$val" ;;
                Depth)            [[ -n "$val" ]] && BIT_DEPTH="$val" ;;
                HdrMode)          [[ -n "$val" ]] && HDR_MODE="$val" ;;
                UHDR)             [[ -n "$val" ]] && UHDR_ACTION="$val" ;;
                DJI)              [[ -n "$val" ]] && DJI_ACTION="$val" ;;
                DNGPreview)       [[ "$val" == "true" ]] && DNG_PREVIEW_MODE="true" ;;
                StripExif)        [[ "$val" == "true" ]] && STRIP_EXIF="true" ;;
                SRGB)             [[ "$val" == "true" ]] && SRGB_CONVERT="true" ;;
                NoAutoRotate)     [[ "$val" == "true" ]] && AUTO_ROTATE="false" ;;
                WatermarkText)    [[ -n "$val" ]] && WATERMARK_TEXT="$val" ;;
                WatermarkImage)   [[ -n "$val" ]] && WATERMARK_IMAGE="$val" ;;
                WatermarkPos)     WATERMARK_POSITION="$val" ;;
                WatermarkOpacity) WATERMARK_OPACITY="$val" ;;
                NoRecursive)      [[ "$val" == "true" ]] && RECURSIVE="false" ;;
                Flat)             [[ "$val" == "true" ]] && PRESERVE_STRUCTURE="false" ;;
                Prefix)           [[ -n "$val" ]] && OUTPUT_PREFIX="$val" ;;
                Suffix)           [[ -n "$val" ]] && OUTPUT_SUFFIX="$val" ;;
                MinRes)           MIN_RESOLUTION="$val" ;;
                SkipDuplicates)   [[ "$val" == "true" ]] && SKIP_DUPLICATES="true" ;;
                LosslessJpeg)     [[ "$val" == "true" ]] && LOSSLESS_JPEG="true" ;;
                ExtractMotion)    [[ "$val" == "true" ]] && EXTRACT_MOTION="true" ;;
                MotionOnly)       [[ "$val" == "true" ]] && { MOTION_ONLY="true"; EXTRACT_MOTION="true"; } ;;
                SkipExisting)     [[ "$val" == "true" ]] && SKIP_EXISTING="true" ;;
                Overwrite)        [[ "$val" == "true" ]] && OVERWRITE="true" ;;
                Verbose)          [[ "$val" == "true" ]] && VERBOSE="true" ;;
                Compare)          [[ "$val" == "true" ]] && COMPARE="true" ;;
            esac
        fi
    done < "$conf_file"
}

# Save current configuration to UserProfiles/*.conf (KEY=VALUE format)
save_profile_conf() {
    mkdir -p "$USER_PROFILES_DIR"

    echo ""
    read -p "  Salvezi configuratia ca profil? (d/N) [N]: " save_choice
    if [[ "${save_choice,,}" == "d" ]]; then
        read -p "  Nume profil: " prof_name
        if [[ -n "$prof_name" ]]; then
            local prof_file="${USER_PROFILES_DIR}/${prof_name}.conf"
            local hdr_val="$HDR_MODE"
            cat > "$prof_file" << EOF
# Photo Encoder Profile: ${prof_name}
# Saved: $(date '+%Y-%m-%d %H:%M:%S')
InputDir=${INPUT_DIR}
OutputDir=${OUTPUT_DIR}
Format=${OUTPUT_FORMAT}
Quality=${QUALITY}
Preset=${QUALITY_PRESET}
Resize=${RESIZE}
ResizeMode=${RESIZE_MODE}
Crop=${CROP_RATIO}
MaxSize=${MAX_FILE_SIZE}
Depth=${BIT_DEPTH}
HdrMode=${hdr_val}
UHDR=${UHDR_ACTION}
DJI=${DJI_ACTION}
DNGPreview=${DNG_PREVIEW_MODE}
StripExif=${STRIP_EXIF}
SRGB=${SRGB_CONVERT}
NoAutoRotate=$([[ "$AUTO_ROTATE" == "false" ]] && echo "true" || echo "false")
WatermarkText=${WATERMARK_TEXT}
WatermarkImage=${WATERMARK_IMAGE}
WatermarkPos=${WATERMARK_POSITION}
WatermarkOpacity=${WATERMARK_OPACITY}
NoRecursive=$([[ "$RECURSIVE" == "false" ]] && echo "true" || echo "false")
Flat=$([[ "$PRESERVE_STRUCTURE" == "false" ]] && echo "true" || echo "false")
Prefix=${OUTPUT_PREFIX}
Suffix=${OUTPUT_SUFFIX}
MinRes=${MIN_RESOLUTION}
SkipDuplicates=${SKIP_DUPLICATES}
LosslessJpeg=${LOSSLESS_JPEG}
ExtractMotion=${EXTRACT_MOTION}
MotionOnly=${MOTION_ONLY}
SkipExisting=${SKIP_EXISTING}
Overwrite=${OVERWRITE}
Verbose=${VERBOSE}
Compare=${COMPARE}
EOF
            log_info "Profil salvat: ${prof_file}"
        fi
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# HEIC OUTPUT CHECK
# ══════════════════════════════════════════════════════════════════════════════

check_heic_output_support() {
    if [[ "$OUTPUT_FORMAT" == "heic" ]]; then
        # Test if ImageMagick can write HEIC
        local test_file="/tmp/heic_test_$$.heic"
        $MAGICK_CMD -size 1x1 xc:black "$test_file" 2>/dev/null || {
            log_warn "ImageMagick cannot write HEIC. libheif may be missing."
            log_warn "Termux: pkg install libheif -y"
            log_warn "Falling back to AVIF format."
            OUTPUT_FORMAT="avif"
        }
        rm -f "$test_file"
    fi
    if [[ "$OUTPUT_FORMAT" == "jxl" ]]; then
        # Test if ImageMagick can write JXL
        local test_file="/tmp/jxl_test_$$.jxl"
        $MAGICK_CMD -size 1x1 xc:black "$test_file" 2>/dev/null || {
            log_warn "ImageMagick cannot write JPEG XL. libjxl may be missing."
            log_warn "Termux: pkg install libjxl -y"
            log_warn "Falling back to AVIF format."
            OUTPUT_FORMAT="avif"
        }
        rm -f "$test_file"
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# COMPRESSION REPORT — Before/After Top 5
# ══════════════════════════════════════════════════════════════════════════════

log_compression() {
    local filename="$1" in_size="$2" out_size="$3"
    local ratio; ratio=$(awk "BEGIN{printf\"%.1f\",($out_size/$in_size)*100}")
    COMPRESSION_LOG="${COMPRESSION_LOG}${filename}|${in_size}|${out_size}|${ratio}\n"
}

print_compression_report() {
    [[ -z "$COMPRESSION_LOG" ]] && return

    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Compression Report${NC}"

    # Best compressed (lowest ratio = most savings)
    echo -e "  ${GREEN}Top 5 most compressed:${NC}"
    echo -e "$COMPRESSION_LOG" | sort -t'|' -k4 -n | head -5 | while IFS='|' read -r name isz osz ratio; do
        [[ -z "$name" ]] && continue
        local saved=$((isz - osz))
        echo -e "    ${GREEN}${ratio}%${NC} ${name} ${GRAY}($(format_size $isz) → $(format_size $osz), saved $(format_size $saved))${NC}"
    done

    # Least compressed (highest ratio = least savings or grew)
    echo -e "  ${YELLOW}Top 5 least compressed:${NC}"
    echo -e "$COMPRESSION_LOG" | sort -t'|' -k4 -rn | head -5 | while IFS='|' read -r name isz osz ratio; do
        [[ -z "$name" ]] && continue
        local c="${YELLOW}"; [[ $(awk "BEGIN{print($ratio>100)}") -eq 1 ]] && c="${RED}"
        echo -e "    ${c}${ratio}%${NC} ${name} ${GRAY}($(format_size $isz) → $(format_size $osz))${NC}"
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# WATCH MODE — Monitor input dir for new files
# ══════════════════════════════════════════════════════════════════════════════

run_watch_mode() {
    local input_dir="$1" output_dir="$2"
    declare -A processed_files=()
    local find_opts=()
    [[ "$RECURSIVE" == "false" ]] && find_opts=(-maxdepth 1)

    log_info "Watch mode started. Monitoring: $input_dir"
    log_info "Interval: ${WATCH_INTERVAL}s. Press Ctrl+C to stop."
    echo ""

    # Initial scan — mark existing files as processed
    while IFS= read -r -d '' f; do
        is_supported_image "$f" && processed_files["$f"]=1
    done < <(find "$input_dir" "${find_opts[@]}" -type f -print0 2>/dev/null)

    local initial_count=${#processed_files[@]}
    log_info "Skipped $initial_count existing files. Waiting for new files..."

    while true; do
        sleep "$WATCH_INTERVAL"
        local new_count=0

        while IFS= read -r -d '' f; do
            is_supported_image "$f" || continue
            [[ -n "${processed_files[$f]+x}" ]] && continue

            # New file found
            new_count=$((new_count + 1))
            processed_files["$f"]=1
            local bn="${f##*/}"

            # Wait for file to finish writing (size stable for 2 seconds)
            local prev_size=0 curr_size=1
            while [[ $prev_size -ne $curr_size ]]; do
                prev_size=$curr_size
                sleep 2
                curr_size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
            done

            log_info "New file: $bn"
            local nm="${bn%.*}"
            local on; on=$(build_output_filename "$bn")
            local of="${output_dir}/${on}"
            mkdir -p "$output_dir"

            convert_image "$f" "$of" || log_error "Failed: $bn"
        done < <(find "$input_dir" "${find_opts[@]}" -type f -print0 2>/dev/null)

        [[ $new_count -gt 0 ]] && log_info "Processed $new_count new file(s). Watching..."
    done
}

# Detect if JPEG contains Ultra HDR gain map
# Checks: XMP hdrgm: namespace, MPF secondary image, Apple HDR gain map
detect_uhdr() {
    local file="$1"
    [[ -n "${UHDR_DETECT_CACHE[$file]+x}" ]] && { echo "${UHDR_DETECT_CACHE[$file]}"; return; }
    [[ "$HAS_EXIFTOOL" != "true" ]] && { UHDR_DETECT_CACHE[$file]="unknown"; echo "unknown"; return; }

    # Check for Ultra HDR / Super HDR XMP namespace (hdrgm:)
    local xmp_check
    xmp_check=$(exiftool -s3 -XMP-hdrgm:all "$file" 2>/dev/null | head -5 || echo "")
    if [[ -n "$xmp_check" ]]; then
        UHDR_DETECT_CACHE[$file]="uhdr"; echo "uhdr"  # Google Ultra HDR / Samsung Super HDR
        return
    fi

    # Check for ISO 21496-1 gain map metadata
    local iso_check
    iso_check=$(exiftool -s3 -XMP-GainMap:all "$file" 2>/dev/null | head -5 || echo "")
    if [[ -n "$iso_check" ]]; then
        UHDR_DETECT_CACHE[$file]="iso21496"; echo "iso21496"  # ISO 21496-1 (Apple Adaptive HDR or Android 15+)
        return
    fi

    # Check MPF (Multi-Picture Format) for secondary images
    local mpf_count
    mpf_count=$(exiftool -s3 -MPImageCount "$file" 2>/dev/null || echo "")
    if [[ -n "$mpf_count" && "$mpf_count" -gt 1 ]]; then
        # Has multiple images — could be gain map
        # Check for HDR-related XMP
        local hdr_xmp
        hdr_xmp=$(exiftool -s3 -HDRPMakerNote -HDRHeadroom "$file" 2>/dev/null | head -5 || echo "")
        if [[ -n "$hdr_xmp" ]]; then
            UHDR_DETECT_CACHE[$file]="adaptive"; echo "adaptive"  # Apple Adaptive HDR
            return
        fi
        # MPF with multiple images but no HDR XMP — could still be UHDR
        UHDR_DETECT_CACHE[$file]="mpf_possible"; echo "mpf_possible"
        return
    fi

    UHDR_DETECT_CACHE[$file]="none"; echo "none"
}

# Get UHDR metadata details
get_uhdr_info() {
    local file="$1"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo "exiftool required"; return; }

    local info=""

    # Ultra HDR v1 (hdrgm:) metadata
    local version gainmap_min gainmap_max gamma hdr_cap_min hdr_cap_max
    version=$(exiftool -s3 -XMP-hdrgm:Version "$file" 2>/dev/null || echo "")
    gainmap_min=$(exiftool -s3 -XMP-hdrgm:GainMapMin "$file" 2>/dev/null || echo "")
    gainmap_max=$(exiftool -s3 -XMP-hdrgm:GainMapMax "$file" 2>/dev/null || echo "")
    gamma=$(exiftool -s3 -XMP-hdrgm:Gamma "$file" 2>/dev/null || echo "")
    hdr_cap_min=$(exiftool -s3 -XMP-hdrgm:HDRCapacityMin "$file" 2>/dev/null || echo "")
    hdr_cap_max=$(exiftool -s3 -XMP-hdrgm:HDRCapacityMax "$file" 2>/dev/null || echo "")

    [[ -n "$version" ]] && info="UHDR v${version}"
    [[ -n "$gainmap_max" ]] && info="$info, GainMax=$gainmap_max"
    [[ -n "$hdr_cap_max" ]] && info="$info, HDRCapMax=$hdr_cap_max"
    [[ -n "$gamma" ]] && info="$info, Gamma=$gamma"

    # MPF info
    local mpf_count
    mpf_count=$(exiftool -s3 -MPImageCount "$file" 2>/dev/null || echo "1")
    info="$info, MPF images=$mpf_count"

    # File size of gain map (secondary image)
    local mpf_size
    mpf_size=$(exiftool -s3 -MPImageLength "$file" 2>/dev/null | tail -1 || echo "")
    [[ -n "$mpf_size" ]] && info="$info, GainMap=$(format_size $mpf_size)"

    echo "$info"
}

# Extract gain map image from UHDR JPEG
extract_uhdr_gainmap() {
    local input="$1" output_dir="$2"
    local name="${input##*/}"; name="${name%.*}"
    local gainmap_out="${output_dir}/${name}_gainmap.jpg"

    [[ -f "$gainmap_out" && "$OVERWRITE" != "true" ]] && { log_verbose "Skip (exists): $gainmap_out"; return 0; }
    [[ "$HAS_EXIFTOOL" != "true" ]] && { log_warn "exiftool required for gain map extraction"; return 1; }

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would extract gain map: ${input##*/} → ${name}_gainmap.jpg"
        return 0
    fi

    # Extract all MPF images — gain map is typically image #2
    local tmpdir="${output_dir}/.uhdr_tmp_$$"
    mkdir -p "$tmpdir"

    exiftool -mpf:all -b "$input" > "${tmpdir}/mpf_raw" 2>/dev/null || true

    # Alternative: extract using trailer/preview tags
    if [[ ! -s "${tmpdir}/mpf_raw" ]]; then
        # Try extracting secondary JPEG by finding SOI marker after primary
        local primary_end
        # Use exiftool to get MPF offsets
        exiftool -v3 -MPF "$input" 2>/dev/null | grep -i "offset\|length" > "${tmpdir}/mpf_info" || true

        # Fallback: extract using exiftool -b -PreviewImage or -MPImage2
        exiftool -b -MPImage2 "$input" > "${tmpdir}/gainmap.jpg" 2>/dev/null || true

        if [[ -s "${tmpdir}/gainmap.jpg" ]]; then
            cp "${tmpdir}/gainmap.jpg" "$gainmap_out"
        fi
    fi

    # If MPImage2 extraction didn't work, try binary extraction
    if [[ ! -s "$gainmap_out" ]]; then
        # Find the second JPEG SOI (FF D8) after the first one
        local offsets
        offsets=$(grep -aob $'\xff\xd8\xff' "$input" 2>/dev/null | cut -d: -f1 || true)
        local count=0
        local second_offset=""
        for off in $offsets; do
            count=$((count + 1))
            if [[ $count -eq 2 ]]; then
                second_offset=$off
                break
            fi
        done

        if [[ -n "$second_offset" && "$second_offset" -gt 100 ]]; then
            dd if="$input" of="$gainmap_out" bs=1 skip="$second_offset" 2>/dev/null
            # Verify it's a valid JPEG
            if ! file "$gainmap_out" 2>/dev/null | grep -qi "jpeg\|jfif"; then
                rm -f "$gainmap_out"
            fi
        fi
    fi

    rm -rf "$tmpdir"

    if [[ -f "$gainmap_out" ]]; then
        local gm_size; gm_size=$(stat -c%s "$gainmap_out" 2>/dev/null || stat -f%z "$gainmap_out" 2>/dev/null)
        log_uhdr "Extracted gain map: ${input##*/} → ${name}_gainmap.jpg ($(format_size $gm_size))"
        STATS_UHDR_EXTRACTED=$((STATS_UHDR_EXTRACTED + 1))
        return 0
    else
        log_verbose "Could not extract gain map from: ${input##*/}"
        return 1
    fi
}

# Strip gain map from UHDR JPEG (keep only base SDR)
strip_uhdr_gainmap() {
    local input="$1" output="$2"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { log_warn "exiftool required for gain map stripping"; return 1; }

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would strip UHDR gain map: ${input##*/}"
        return 0
    fi

    # Copy file then remove UHDR-specific data
    cp "$input" "$output"

    # Remove XMP hdrgm namespace, GainMap namespace, and MPF secondary images
    exiftool -overwrite_original \
        -XMP-hdrgm:all= \
        -XMP-GainMap:all= \
        -MPF:all= \
        "$output" 2>/dev/null || true

    # Verify size reduction
    local in_size out_size
    in_size=$(stat -c%s "$input" 2>/dev/null || stat -f%z "$input" 2>/dev/null)
    out_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)
    local saved=$((in_size - out_size))

    if [[ $saved -gt 0 ]]; then
        local sp; sp=$(awk "BEGIN {printf \"%.1f\", ($saved/$in_size)*100}")
        log_uhdr "Stripped gain map: ${input##*/} ($(format_size $in_size) → $(format_size $out_size), saved ${sp}%)"
        STATS_UHDR_STRIPPED=$((STATS_UHDR_STRIPPED + 1))
    else
        log_verbose "No gain map data removed (file unchanged): ${input##*/}"
    fi
    return 0
}

# Full UHDR decode via libultrahdr → raw HDR → encode to target format
decode_uhdr_full() {
    local input="$1" output="$2"
    [[ "$HAS_ULTRAHDR_APP" != "true" ]] && { log_error "ultrahdr_app required for UHDR decode"; return 1; }

    local name="${input##*/}"; name="${name%.*}"
    local tmpdir="/tmp/uhdr_decode_$$"
    mkdir -p "$tmpdir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would UHDR decode: ${input##*/} → HDR → $(basename "$output")"
        return 0
    fi

    # Decode UHDR JPEG to raw HDR (RGBA1010102 or P010)
    # -m 1 = decode mode
    # -j = input JPEG
    # -o 2 = PQ transfer function (HDR10)
    # -O 5 = output format RGBA1010102
    local raw_hdr="${tmpdir}/${name}_hdr.raw"
    local decode_log="${tmpdir}/decode.log"

    # Get dimensions first
    local dims; dims=$(get_image_dimensions "$input")
    local w="${dims%%x*}" h="${dims##*x}"

    ultrahdr_app -m 1 -j "$input" -z "$raw_hdr" -o 2 -O 5 > "$decode_log" 2>&1 || {
        log_error "UHDR decode failed for: ${input##*/}"
        [[ "$VERBOSE" == "true" ]] && cat "$decode_log"
        rm -rf "$tmpdir"
        return 1
    }

    if [[ -s "$raw_hdr" ]]; then
        # Convert raw HDR to target format via ImageMagick
        local cmd; cmd=$(get_magick_cmd)
        local depth="10"
        [[ -n "$BIT_DEPTH" ]] && depth="$BIT_DEPTH"

        $cmd -size "${w}x${h}" -depth 10 RGBA:"$raw_hdr" \
            -depth "$depth" \
            -quality "$(get_effective_quality)" \
            "$output" 2>/dev/null || {
            log_error "HDR encode failed for: ${input##*/}"
            rm -rf "$tmpdir"
            return 1
        }

        local in_size out_size
        in_size=$(stat -c%s "$input" 2>/dev/null || stat -f%z "$input" 2>/dev/null)
        out_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)
        STATS_TOTAL_IN_SIZE=$((STATS_TOTAL_IN_SIZE + in_size))
        STATS_TOTAL_OUT_SIZE=$((STATS_TOTAL_OUT_SIZE + out_size))
        STATS_UHDR_DECODED=$((STATS_UHDR_DECODED + 1))
        log_uhdr "UHDR decode: ${input##*/} → $(basename "$output") ($(format_size $in_size) → $(format_size $out_size), ${depth}-bit HDR)"
    else
        log_error "UHDR decode produced empty output: ${input##*/}"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"
    return 0
}

get_effective_quality() {
    local q="$QUALITY"
    [[ -n "$QUALITY_PRESET" ]] && q=$(get_preset_quality "$QUALITY_PRESET" "$OUTPUT_FORMAT")
    echo "$q"
}

# ══════════════════════════════════════════════════════════════════════════════
# DJI PHOTO DETECTION & HANDLING
# ══════════════════════════════════════════════════════════════════════════════

# Detect if image is from a DJI camera
# Returns: "dji" or "none"
detect_dji_photo() {
    local file="$1"
    [[ -n "${DJI_DETECT_CACHE[$file]+x}" ]] && { echo "${DJI_DETECT_CACHE[$file]}"; return; }

    # Method 1: Check EXIF Make field
    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        local make
        make=$(exiftool -s3 -Make "$file" 2>/dev/null || echo "")
        if [[ "${make,,}" == *"dji"* ]]; then
            DJI_DETECT_CACHE[$file]="dji"; echo "dji"
            return
        fi

        # Method 2: Check for DJI-specific XMP tags (SpeedX, AbsoluteAltitude, etc.)
        local dji_xmp
        dji_xmp=$(exiftool -s3 -XMP-drone-dji:all "$file" 2>/dev/null | head -3 || echo "")
        if [[ -n "$dji_xmp" ]]; then
            DJI_DETECT_CACHE[$file]="dji"; echo "dji"
            return
        fi

        # Method 3: Check Software/Model for DJI
        local model
        model=$(exiftool -s3 -Model "$file" 2>/dev/null || echo "")
        if [[ "${model,,}" == *"dji"* || "${model,,}" == *"osmo"* || "${model,,}" == *"action"* || "${model,,}" == *"mavic"* || "${model,,}" == *"phantom"* || "${model,,}" == *"mini"* ]]; then
            DJI_DETECT_CACHE[$file]="dji"; echo "dji"
            return
        fi
    fi

    DJI_DETECT_CACHE[$file]="none"; echo "none"
}

# Get DJI photo metadata summary
get_dji_info() {
    local file="$1"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo "exiftool required"; return; }

    local info=""
    local model make
    make=$(exiftool -s3 -Make "$file" 2>/dev/null || echo "")
    model=$(exiftool -s3 -Model "$file" 2>/dev/null || echo "")
    [[ -n "$model" ]] && info="$model" || info="$make"

    # GPS
    local lat lon alt
    lat=$(exiftool -s3 -GPSLatitude "$file" 2>/dev/null || echo "")
    lon=$(exiftool -s3 -GPSLongitude "$file" 2>/dev/null || echo "")
    alt=$(exiftool -s3 -GPSAltitude "$file" 2>/dev/null || echo "")
    [[ -n "$lat" ]] && info="$info | GPS: $lat, $lon"
    [[ -n "$alt" ]] && info="$info, Alt: $alt"

    # DJI-specific: Speed, Orientation
    local speed_x speed_y pitch yaw roll
    speed_x=$(exiftool -s3 -XMP-drone-dji:SpeedX "$file" 2>/dev/null || echo "")
    speed_y=$(exiftool -s3 -XMP-drone-dji:SpeedY "$file" 2>/dev/null || echo "")
    pitch=$(exiftool -s3 -XMP-drone-dji:GimbalPitchDegree "$file" 2>/dev/null || echo "")
    yaw=$(exiftool -s3 -XMP-drone-dji:GimbalYawDegree "$file" 2>/dev/null || echo "")

    [[ -n "$speed_x" ]] && info="$info | Speed: X=$speed_x Y=$speed_y"
    [[ -n "$pitch" ]] && info="$info | Gimbal: P=$pitch Y=$yaw"

    # Camera settings
    local iso shutter fnum
    iso=$(exiftool -s3 -ISO "$file" 2>/dev/null || echo "")
    shutter=$(exiftool -s3 -ShutterSpeed "$file" 2>/dev/null || echo "")
    fnum=$(exiftool -s3 -FNumber "$file" 2>/dev/null || echo "")
    [[ -n "$iso" ]] && info="$info | ISO=$iso"
    [[ -n "$shutter" ]] && info="$info Shutter=$shutter"
    [[ -n "$fnum" ]] && info="$info f/$fnum"

    # Serial number
    local serial
    serial=$(exiftool -s3 -SerialNumber "$file" 2>/dev/null || echo "")
    [[ -z "$serial" ]] && serial=$(exiftool -s3 -XMP-drone-dji:CameraSN "$file" 2>/dev/null || echo "")
    [[ -n "$serial" ]] && info="$info | SN: $serial"

    echo "$info"
}

# Export DJI metadata to CSV
export_dji_metadata() {
    local input_dir="$1" output_dir="$2"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { log_error "exiftool required for DJI metadata export"; return 1; }

    local csv_file="${output_dir}/dji_photo_metadata.csv"
    mkdir -p "$output_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would export DJI metadata to: $csv_file"
        return 0
    fi

    # CSV header
    echo "Filename,Make,Model,DateTime,GPSLatitude,GPSLongitude,GPSAltitude,ISO,ShutterSpeed,FNumber,FocalLength,SpeedX,SpeedY,SpeedZ,GimbalPitch,GimbalYaw,GimbalRoll,FlightPitch,FlightYaw,FlightRoll,AbsoluteAltitude,RelativeAltitude,SerialNumber,FirmwareVersion" > "$csv_file"

    local count=0
    local find_depth=()
    [[ "$RECURSIVE" != "true" ]] && find_depth=(-maxdepth 1)

    while IFS= read -r -d '' file; do
        is_supported_image "$file" || continue
        local is_dji; is_dji=$(detect_dji_photo "$file")
        [[ "$is_dji" != "dji" ]] && continue

        count=$((count + 1))
        local bn="${file##*/}"

        # Extract all fields
        local make model dt lat lon alt iso shutter fnum fl
        local sx sy sz gp gy gr fp fy fr absalt relalt sn fw
        make=$(exiftool -s3 -Make "$file" 2>/dev/null || echo "")
        model=$(exiftool -s3 -Model "$file" 2>/dev/null || echo "")
        dt=$(exiftool -s3 -DateTimeOriginal "$file" 2>/dev/null || echo "")
        lat=$(exiftool -s3 -n -GPSLatitude "$file" 2>/dev/null || echo "")
        lon=$(exiftool -s3 -n -GPSLongitude "$file" 2>/dev/null || echo "")
        alt=$(exiftool -s3 -n -GPSAltitude "$file" 2>/dev/null || echo "")
        iso=$(exiftool -s3 -ISO "$file" 2>/dev/null || echo "")
        shutter=$(exiftool -s3 -ShutterSpeed "$file" 2>/dev/null || echo "")
        fnum=$(exiftool -s3 -FNumber "$file" 2>/dev/null || echo "")
        fl=$(exiftool -s3 -FocalLength "$file" 2>/dev/null || echo "")
        sx=$(exiftool -s3 -XMP-drone-dji:SpeedX "$file" 2>/dev/null || echo "")
        sy=$(exiftool -s3 -XMP-drone-dji:SpeedY "$file" 2>/dev/null || echo "")
        sz=$(exiftool -s3 -XMP-drone-dji:SpeedZ "$file" 2>/dev/null || echo "")
        gp=$(exiftool -s3 -XMP-drone-dji:GimbalPitchDegree "$file" 2>/dev/null || echo "")
        gy=$(exiftool -s3 -XMP-drone-dji:GimbalYawDegree "$file" 2>/dev/null || echo "")
        gr=$(exiftool -s3 -XMP-drone-dji:GimbalRollDegree "$file" 2>/dev/null || echo "")
        fp=$(exiftool -s3 -XMP-drone-dji:FlightPitchDegree "$file" 2>/dev/null || echo "")
        fy=$(exiftool -s3 -XMP-drone-dji:FlightYawDegree "$file" 2>/dev/null || echo "")
        fr=$(exiftool -s3 -XMP-drone-dji:FlightRollDegree "$file" 2>/dev/null || echo "")
        absalt=$(exiftool -s3 -XMP-drone-dji:AbsoluteAltitude "$file" 2>/dev/null || echo "")
        relalt=$(exiftool -s3 -XMP-drone-dji:RelativeAltitude "$file" 2>/dev/null || echo "")
        sn=$(exiftool -s3 -SerialNumber "$file" 2>/dev/null || echo "")
        [[ -z "$sn" ]] && sn=$(exiftool -s3 -XMP-drone-dji:CameraSN "$file" 2>/dev/null || echo "")
        fw=$(exiftool -s3 -Software "$file" 2>/dev/null || echo "")

        echo "\"$bn\",\"$make\",\"$model\",\"$dt\",\"$lat\",\"$lon\",\"$alt\",\"$iso\",\"$shutter\",\"$fnum\",\"$fl\",\"$sx\",\"$sy\",\"$sz\",\"$gp\",\"$gy\",\"$gr\",\"$fp\",\"$fy\",\"$fr\",\"$absalt\",\"$relalt\",\"$sn\",\"$fw\"" >> "$csv_file"
        STATS_DJI_EXPORTED=$((STATS_DJI_EXPORTED + 1))

        echo -e "${GREEN}[DJI]${NC} Exported: $bn"
    done < <(find "$input_dir" "${find_depth[@]}" -type f -print0 2>/dev/null | sort -z)

    if [[ $count -gt 0 ]]; then
        log_info "DJI metadata exported: $count photos → $csv_file"
    else
        log_warn "No DJI photos found in: $input_dir"
        rm -f "$csv_file"
    fi
}

# Strip DJI privacy-sensitive data (serial number, GPS, device info)
strip_dji_privacy() {
    local input="$1" output="$2"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { log_warn "exiftool required for DJI privacy strip"; return 1; }

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "Would strip DJI privacy: ${input##*/}"
        return 0
    fi

    cp "$input" "$output"

    # Remove: GPS, serial number, DJI XMP drone data, device identifiers
    exiftool -overwrite_original \
        -GPS:all= \
        -SerialNumber= \
        -XMP-drone-dji:all= \
        -XMP-tiff:Software= \
        -Make= \
        -Model= \
        -HostComputer= \
        -CameraSerialNumber= \
        "$output" 2>/dev/null || true

    local in_size out_size
    in_size=$(stat -c%s "$input" 2>/dev/null || stat -f%z "$input" 2>/dev/null)
    out_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)

    STATS_DJI_STRIPPED=$((STATS_DJI_STRIPPED + 1))
    echo -e "${GREEN}[DJI]${NC} Privacy stripped: ${input##*/} ($(format_size $in_size) → $(format_size $out_size))"
    return 0
}

# Extract DJI 4K Live Photo video
# DJI Live Photo: JPEG with embedded MP4 (similar to Samsung Motion Photo)
# DJI uses a similar approach — short video clip appended after JPEG data
extract_dji_live_photo() {
    local input="$1" output_dir="$2"
    local bn="${input##*/}" name="${input##*/}"; name="${name%.*}"
    local video_out="${output_dir}/${name}_dji_live.mp4"

    [[ -f "$video_out" && "$OVERWRITE" != "true" ]] && return 0

    # DJI Live Photo embeds MP4 similar to Samsung — search for ftyp box
    local offset=""
    local ftyp_offsets
    ftyp_offsets=$(grep -aob "ftyp" "$input" 2>/dev/null | cut -d: -f1 || true)
    for ftyp_pos in $ftyp_offsets; do
        local mp4_start=$((ftyp_pos - 4))
        if [[ $mp4_start -gt 100 ]]; then
            offset=$mp4_start
            break
        fi
    done

    [[ -z "$offset" || "$offset" -le 0 ]] && return 1

    local file_size; file_size=$(stat -c%s "$input" 2>/dev/null || stat -f%z "$input" 2>/dev/null)
    local video_size=$((file_size - offset))
    [[ $video_size -lt 5000 ]] && return 1  # DJI 4K Live Photo should be larger than basic motion

    local size_mb; size_mb=$(awk "BEGIN{printf\"%.1f\",$video_size/1048576}")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry "DJI Live Photo: $bn → ${name}_dji_live.mp4 ($size_mb MB)"
        return 0
    fi

    dd if="$input" of="$video_out" bs=1 skip="$offset" 2>/dev/null

    if file "$video_out" 2>/dev/null | grep -qi "mp4\|video\|iso media"; then
        STATS_DJI_LIVEPHOTO=$((STATS_DJI_LIVEPHOTO + 1))
        echo -e "${GREEN}[DJI]${NC} Live Photo: $bn → ${name}_dji_live.mp4 ($size_mb MB)"
        return 0
    else
        rm -f "$video_out"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# HDR DETECTION (non-UHDR — classic 10-bit HDR)
# ══════════════════════════════════════════════════════════════════════════════

detect_hdr() {
    local file="$1" is_hdr="false"
    local depth; depth=$($IDENTIFY_CMD -format "%z" "$file" 2>/dev/null | head -1 || echo "8")
    [[ "$depth" -gt 8 ]] && is_hdr="true"

    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        local tags; tags=$(exiftool -s3 -MaxContentLightLevel -TransferCharacteristics -ColorPrimaries -HDRHeadroom "$file" 2>/dev/null | tr '\n' '|' || echo "")
        [[ "$tags" == *"2084"* || "$tags" == *"PQ"* || "$tags" == *"HLG"* || "$tags" == *"2020"* || "$tags" == *"HDRHeadroom"* ]] && is_hdr="true"
    fi
    [[ "$is_hdr" == "true" ]] && echo "hdr" || echo "sdr"
}

resolve_hdr_action() {
    local hdr="$1" fmt="$2"
    [[ "$hdr" == "sdr" ]] && { echo "passthrough"; return; }
    case "$HDR_MODE" in force-sdr) echo "tonemap"; return;; force-hdr) echo "preserve"; return;; esac
    is_hdr_capable "$fmt" && echo "preserve" || echo "tonemap"
}

get_target_depth() {
    local act="$1" fmt="$2"
    [[ -n "$BIT_DEPTH" ]] && { echo "$BIT_DEPTH"; return; }
    case "$act" in
        tonemap) echo "8" ;;
        preserve) case "$fmt" in avif) echo "10";; heic) echo "10";; jxl) echo "10";; png) echo "16";; *) echo "";; esac ;;
        *) case "$fmt" in jpeg|webp) echo "8";; *) echo "";; esac ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# DNG VERSION DETECTION (DNG 1.0 → 1.7.1.0, JPEG XL compression)
# ══════════════════════════════════════════════════════════════════════════════

# Returns DNG version (e.g. "1.7.1.0") or empty. Requires exiftool.
detect_dng_version() {
    local file="$1"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo ""; return; }
    exiftool -s3 -DNGVersion "$file" 2>/dev/null || echo ""
}

detect_dng_backward_version() {
    local file="$1"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo ""; return; }
    exiftool -s3 -DNGBackwardVersion "$file" 2>/dev/null || echo ""
}

detect_dng_compression() {
    local file="$1"
    [[ "$HAS_EXIFTOOL" != "true" ]] && { echo ""; return; }
    exiftool -s3 -Compression "$file" 2>/dev/null || echo ""
}

# Returns "jxl" if DNG uses JPEG XL compression (DNG 1.7+), else "legacy" or "unknown".
classify_dng() {
    local ver="$1" comp="$2"
    [[ "$comp" == *"JPEG XL"* || "$comp" == *"JXL"* ]] && { echo "jxl"; return; }
    if [[ -n "$ver" ]]; then
        local minor; minor=$(echo "$ver" | cut -d. -f2 2>/dev/null)
        [[ "$minor" =~ ^[0-9]+$ && "$minor" -ge 7 ]] && { echo "jxl"; return; }
        echo "legacy"; return
    fi
    echo "unknown"
}

# Extract embedded preview JPEG from DNG (skip demosaic for fast path).
# Tries JpgFromRaw → PreviewImage → OtherImage in order. Returns tag name on success.
# Usage: extract_dng_preview <input.dng> <output.jpg>
extract_dng_preview() {
    local input="$1" output="$2"
    [[ "$HAS_EXIFTOOL" != "true" ]] && return 1
    local tag
    for tag in JpgFromRaw PreviewImage OtherImage; do
        if exiftool -b -"$tag" "$input" > "$output" 2>/dev/null && [[ -s "$output" ]]; then
            echo "$tag"
            return 0
        fi
    done
    rm -f "$output" 2>/dev/null
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# MOTION / LIVE PHOTO
# ══════════════════════════════════════════════════════════════════════════════

find_iphone_live_photo() {
    local f="$1" d; d=$(dirname "$f"); local s="${f##*/}"; s="${s%.*}"
    for e in MOV mov Mov; do local c="${d}/${s}.${e}"; [[ -f "$c" ]] && { local z; z=$(stat -c%s "$c" 2>/dev/null || stat -f%z "$c" 2>/dev/null); [[ $z -gt 0 && $z -lt 52428800 ]] && { echo "$c"; return 0; }; }; done
    local sl="${s,,}"; [[ "$sl" != "$s" ]] && { for e in MOV mov; do local c="${d}/${sl}.${e}"; [[ -f "$c" ]] && { local z; z=$(stat -c%s "$c" 2>/dev/null || stat -f%z "$c" 2>/dev/null); [[ $z -gt 0 && $z -lt 52428800 ]] && { echo "$c"; return 0; }; }; done; }
    return 1
}

extract_iphone_live() {
    local f="$1" m="$2" od="$3"; local n="${f##*/}"; n="${n%.*}"; local o="${od}/${n}_live.mov"
    [[ -f "$o" && "$OVERWRITE" != "true" ]] && return 0
    local z; z=$(stat -c%s "$m" 2>/dev/null || stat -f%z "$m" 2>/dev/null); local mb; mb=$(awk "BEGIN{printf\"%.1f\",$z/1048576}")
    [[ "$DRY_RUN" == "true" ]] && { log_dry "iPhone: ${f##*/} → ${n}_live.mov ($mb MB)"; return 0; }
    cp "$m" "$o"; echo -e "${GREEN}[LIVE]${NC} iPhone: ${f##*/} → ${n}_live.mov ($mb MB)"; return 0
}

extract_embedded_motion() {
    local f="$1" od="$2"; local bn="${f##*/}" n="${f##*/}"; n="${n%.*}"; local o="${od}/${n}_motion.mp4"
    [[ -f "$o" && "$OVERWRITE" != "true" ]] && return 0
    local off="" src=""
    local so; so=$(grep -aob "MotionPhoto_Data" "$f" 2>/dev/null | head -1 | cut -d: -f1 || true)
    [[ -n "$so" ]] && { off=$((so + 16)); src="Samsung"; }
    if [[ -z "$off" ]]; then local fo; fo=$(grep -aob "ftyp" "$f" 2>/dev/null | cut -d: -f1 || true); for fp in $fo; do local ms=$((fp-4)); [[ $ms -gt 100 ]] && { off=$ms; src="Google"; break; }; done; fi
    [[ -z "$off" || "$off" -le 0 ]] && return 1
    local fz; fz=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null); local vz=$((fz-off)); [[ $vz -lt 1000 ]] && return 1
    local mb; mb=$(awk "BEGIN{printf\"%.1f\",$vz/1048576}")
    [[ "$DRY_RUN" == "true" ]] && { log_dry "$src: $bn → ${n}_motion.mp4 ($mb MB)"; return 0; }
    dd if="$f" of="$o" bs=1 skip="$off" 2>/dev/null
    file "$o" 2>/dev/null | grep -qi "mp4\|video\|iso media" && { echo -e "${GREEN}[MOTION]${NC} $src: $bn → ${n}_motion.mp4 ($mb MB)"; return 0; } || { rm -f "$o"; return 1; }
}

# ══════════════════════════════════════════════════════════════════════════════
# IMAGE CONVERSION (standard — non-UHDR-decode path)
# ══════════════════════════════════════════════════════════════════════════════

build_output_filename() {
    local n="$1" s="${1%.*}" ext; case "$OUTPUT_FORMAT" in jpeg|jpg) ext="jpg";; *) ext="$OUTPUT_FORMAT";; esac
    echo "${OUTPUT_PREFIX}${s}${OUTPUT_SUFFIX}.${ext}"
}

build_magick_args() {
    local input="$1" output="$2" qval="$3" hdr_act="$4" tgt_d="$5"
    MAGICK_ARGS=("$input")
    [[ "$AUTO_ROTATE" == "true" ]] && MAGICK_ARGS+=("-auto-orient")
    if [[ "$hdr_act" == "tonemap" ]]; then MAGICK_ARGS+=("-colorspace" "sRGB" "-depth" "8")
    elif [[ "$hdr_act" == "preserve" && -n "$tgt_d" && "$tgt_d" != "8" ]]; then MAGICK_ARGS+=("-depth" "$tgt_d")
    elif [[ -n "$BIT_DEPTH" ]]; then MAGICK_ARGS+=("-depth" "$BIT_DEPTH"); fi
    [[ "$SRGB_CONVERT" == "true" && "$hdr_act" != "tonemap" ]] && MAGICK_ARGS+=("-colorspace" "sRGB")
    if [[ -n "$CROP_RATIO" ]]; then
        local cw="${CROP_RATIO%%:*}" ch="${CROP_RATIO##*:}" dims; dims=$(get_image_dimensions "$input")
        local iw="${dims%%x*}" ih="${dims##*x}"
        if [[ $iw -gt 0 && $ih -gt 0 ]]; then
            local tr; tr=$(awk "BEGIN{printf\"%.6f\",$cw/$ch}"); local cr; cr=$(awk "BEGIN{printf\"%.6f\",$iw/$ih}")
            local nw nh; if awk "BEGIN{exit!($cr>$tr)}"; then nh=$ih; nw=$(awk "BEGIN{printf\"%.0f\",$ih*$tr}"); nw=$(((nw/2)*2)); else nw=$iw; nh=$(awk "BEGIN{printf\"%.0f\",$iw/$tr}"); nh=$(((nh/2)*2)); fi
            MAGICK_ARGS+=("-gravity" "Center" "-crop" "${nw}x${nh}+0+0" "+repage")
        fi
    fi
    if [[ -n "$RESIZE" ]]; then local rs="$RESIZE"; [[ "$rs" != *x* ]] && rs="${rs}x"
        case "$RESIZE_MODE" in fit) MAGICK_ARGS+=("-resize" "$rs");; fill) MAGICK_ARGS+=("-resize" "${rs}^" "-gravity" "center" "-extent" "$RESIZE");; exact) MAGICK_ARGS+=("-resize" "${rs}!");; esac; fi
    case "$OUTPUT_FORMAT" in avif|webp|heic|jxl) MAGICK_ARGS+=("-quality" "$qval");; jpeg|jpg) MAGICK_ARGS+=("-quality" "$qval"); [[ $qval -ge 90 ]] && MAGICK_ARGS+=("-sampling-factor" "4:4:4") || MAGICK_ARGS+=("-sampling-factor" "4:2:0");; png) MAGICK_ARGS+=("-quality" "95");; esac
    [[ "$STRIP_EXIF" == "true" ]] && MAGICK_ARGS+=("-strip")
    [[ -n "$WATERMARK_TEXT" ]] && MAGICK_ARGS+=("-gravity" "$WATERMARK_POSITION" "-fill" "white" "-stroke" "black" "-strokewidth" "1" "-pointsize" "36" "-annotate" "+20+20" "$WATERMARK_TEXT")
    MAGICK_ARGS+=("$output")
}

apply_image_watermark() {
    local t="$1" w="$2"; [[ ! -f "$w" ]] && return 1; local cmd; cmd=$(get_magick_cmd)
    local dims; dims=$(get_image_dimensions "$t"); local iw="${dims%%x*}"; local ww=$((iw*15/100)); [[ $ww -lt 50 ]] && ww=50
    local tmp="${t}.wm"; $cmd composite -dissolve "$WATERMARK_OPACITY" -gravity "$WATERMARK_POSITION" -geometry "${ww}x+20+20" "$w" "$t" "$tmp" 2>/dev/null
    [[ -f "$tmp" ]] && { mv "$tmp" "$t"; return 0; }; return 1
}

convert_image() {
    local input="$1" output="$2"
    local qval; qval=$(get_effective_quality)

    # ── UHDR handling ─────────────────────────────────────────────────
    if is_uhdr_candidate "$input"; then
        local uhdr_type; uhdr_type=$(detect_uhdr "$input")

        if [[ "$uhdr_type" != "none" && "$uhdr_type" != "unknown" ]]; then
            STATS_UHDR_DETECTED=$((STATS_UHDR_DETECTED + 1))
            local uhdr_info=""; [[ "$VERBOSE" == "true" || "$UHDR_ACTION" == "info" || "$UHDR_ACTION" == "detect" ]] && uhdr_info=$(get_uhdr_info "$input")

            case "$UHDR_ACTION" in
                detect|info)
                    log_uhdr "${input##*/}: $uhdr_type ($uhdr_info)"
                    return 0  # detect-only, no conversion
                    ;;
                strip)
                    strip_uhdr_gainmap "$input" "$output"
                    return $?
                    ;;
                extract)
                    local edir; edir=$(dirname "$output")
                    extract_uhdr_gainmap "$input" "${edir}/gainmaps"
                    # Continue with normal conversion below
                    ;;
                decode)
                    decode_uhdr_full "$input" "$output"
                    return $?
                    ;;
                *)
                    # Default: warn and convert base SDR
                    log_uhdr "${input##*/}: Ultra HDR detected ($uhdr_type) — converting base SDR"
                    [[ -n "$uhdr_info" ]] && log_verbose "  UHDR info: $uhdr_info"
                    ;;
            esac
        fi
    fi

    # ── DJI Photo handling ────────────────────────────────────────────
    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        local is_dji; is_dji=$(detect_dji_photo "$input")
        if [[ "$is_dji" == "dji" ]]; then
            STATS_DJI_DETECTED=$((STATS_DJI_DETECTED + 1))

            case "$DJI_ACTION" in
                detect)
                    local dji_info; dji_info=$(get_dji_info "$input")
                    echo -e "${GREEN}[DJI]${NC} ${input##*/}: $dji_info"
                    return 0  # detect-only
                    ;;
                export)
                    # Export is handled at batch level in process_files, not per-image
                    # Just log detection here, continue with conversion
                    log_verbose "DJI photo: ${input##*/} (export handled at batch level)"
                    ;;
                privacy-strip)
                    strip_dji_privacy "$input" "$output"
                    return $?
                    ;;
                *)
                    # Default: log DJI detection, continue normal conversion
                    log_verbose "DJI photo detected: ${input##*/}"
                    ;;
            esac

            # Try DJI 4K Live Photo extraction if motion extraction enabled
            if [[ "$EXTRACT_MOTION" == "true" || "$MOTION_ONLY" == "true" ]]; then
                local motion_dir; motion_dir=$(dirname "$output")/motion_videos
                mkdir -p "$motion_dir"
                extract_dji_live_photo "$input" "$motion_dir" || true
            fi
        fi
    fi

    # ── DNG version detection (supports DNG 1.0 → 1.7.1.0) ────────────
    local _ie="${input##*.}"; _ie="${_ie,,}"
    local dng_preview_tmp=""
    local orig_input="$input"
    if [[ "$_ie" == "dng" ]]; then
        STATS_DNG_DETECTED=$((STATS_DNG_DETECTED + 1))
        local dng_ver dng_bwd dng_comp dng_class
        dng_ver=$(detect_dng_version "$input")
        dng_bwd=$(detect_dng_backward_version "$input")
        dng_comp=$(detect_dng_compression "$input")
        dng_class=$(classify_dng "$dng_ver" "$dng_comp")

        if [[ -n "$dng_ver" ]]; then
            log_verbose "DNG ${dng_ver} (backward: ${dng_bwd:-?}) | Compression: ${dng_comp:-?}"
        fi

        # Preview extraction path: --dng-preview flag OR auto-fallback for unsupported DNG 1.7+
        local try_preview="false" dng_reason=""
        if [[ "$DNG_PREVIEW_MODE" == "true" ]]; then
            try_preview="true"; dng_reason="fast-mode"
        elif [[ "$dng_class" == "jxl" ]]; then
            STATS_DNG_JXL=$((STATS_DNG_JXL + 1))
            echo -e "${MAGENTA}[DNG]${NC} ${input##*/}: DNG ${dng_ver:-1.7+} (${dng_comp:-JPEG XL})"
            if ! $IDENTIFY_CMD -format "%w" "$input" &>/dev/null; then
                try_preview="true"; dng_reason="auto-fallback"
            fi
        elif [[ -n "$dng_ver" ]]; then
            log_verbose "DNG ${dng_ver} — legacy compression, well supported"
        fi

        if [[ "$try_preview" == "true" ]]; then
            dng_preview_tmp="${TMPDIR:-/tmp}/dng_preview_$$_$(date +%s%N).jpg"
            local preview_tag
            if preview_tag=$(extract_dng_preview "$input" "$dng_preview_tmp"); then
                STATS_DNG_PREVIEW=$((STATS_DNG_PREVIEW + 1))
                echo -e "${MAGENTA}[DNG]${NC} Preview extras (${preview_tag}, ${dng_reason}): $(basename "$input")"
                input="$dng_preview_tmp"
            else
                rm -f "$dng_preview_tmp" 2>/dev/null; dng_preview_tmp=""
                if [[ "$dng_reason" == "auto-fallback" ]]; then
                    STATS_DNG_FAILED=$((STATS_DNG_FAILED + 1))
                    echo -e "${RED}[DNG]${NC} ImageMagick nu poate decoda DNG ${dng_ver:-1.7+} si nu exista preview embedded"
                    echo -e "${YELLOW}[DNG]${NC} Solutii:"
                    echo -e "${YELLOW}[DNG]${NC}   1) Actualizeaza ImageMagick + LibRaw 0.21+ (suport JPEG XL)"
                    echo -e "${YELLOW}[DNG]${NC}   2) Converteste cu Adobe DNG Converter la DNG 1.6 (backward compat)"
                    echo -e "${YELLOW}[DNG]${NC}   3) Foloseste Lightroom / ACR pentru export TIFF/JPEG intermediar"
                    return 1
                else
                    log_verbose "DNG preview extraction esuata, continua cu RAW normal"
                fi
            fi
        fi
    fi

    # ── Classic HDR detection ─────────────────────────────────────────
    local is_hdr="sdr" hdr_action="passthrough" target_depth=""
    is_hdr=$(detect_hdr "$input")
    if [[ "$is_hdr" == "hdr" ]]; then
        STATS_HDR_DETECTED=$((STATS_HDR_DETECTED + 1))
        hdr_action=$(resolve_hdr_action "$is_hdr" "$OUTPUT_FORMAT")
        target_depth=$(get_target_depth "$hdr_action" "$OUTPUT_FORMAT")
        case "$hdr_action" in
            tonemap)  log_hdr "$(basename "$orig_input"): HDR → tone map SDR"; STATS_HDR_TONEMAPPED=$((STATS_HDR_TONEMAPPED + 1)) ;;
            preserve) log_hdr "$(basename "$orig_input"): HDR → preserve ${target_depth}-bit"; STATS_HDR_PRESERVED=$((STATS_HDR_PRESERVED + 1)) ;;
        esac
    else
        target_depth=$(get_target_depth "passthrough" "$OUTPUT_FORMAT")
    fi

    # ── Lossless JPEG ─────────────────────────────────────────────────
    if [[ "$LOSSLESS_JPEG" == "true" && "$OUTPUT_FORMAT" == "jpeg" ]]; then
        local ie="${input##*.}"; ie="${ie,,}"
        if [[ "$ie" == "jpg" || "$ie" == "jpeg" ]]; then
            [[ "$DRY_RUN" == "true" ]] && { log_dry "Lossless: $(basename "$orig_input")"; return 0; }
            local cmd; cmd=$(get_magick_cmd)
            if command -v jpegtran &>/dev/null; then
                jpegtran -copy none -optimize -progressive -outfile "$output" "$input" 2>/dev/null
            else
                $cmd "$input" -strip "$output" 2>/dev/null
            fi
            if [[ -f "$output" ]]; then
                local isz osz; isz=$(stat -c%s "$orig_input" 2>/dev/null || stat -f%z "$orig_input" 2>/dev/null); osz=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)
                STATS_TOTAL_IN_SIZE=$((STATS_TOTAL_IN_SIZE + isz)); STATS_TOTAL_OUT_SIZE=$((STATS_TOTAL_OUT_SIZE + osz)); STATS_LOSSLESS_OPTIMIZED=$((STATS_LOSSLESS_OPTIMIZED + 1))
                echo -e "${GREEN}[LOSSLESS]${NC} $(basename "$orig_input") ${GRAY}($(format_size $isz) → $(format_size $osz))${NC}"
                return 0
            fi
        fi
    fi

    # ── Standard conversion ───────────────────────────────────────────
    [[ "$DRY_RUN" == "true" ]] && { log_dry "Convert: $(basename "$orig_input") → $(basename "$output") (q$qval, $hdr_action)"; return 0; }

    local cmd; cmd=$(get_magick_cmd)

    if [[ -n "$MAX_FILE_SIZE" ]]; then
        local mb; mb=$(parse_size_bytes "$MAX_FILE_SIZE"); local cq=$qval
        for ((att=0; att<8; att++)); do
            build_magick_args "$input" "$output" "$cq" "$hdr_action" "$target_depth"
            $cmd "${MAGICK_ARGS[@]}" 2>/dev/null; [[ ! -f "$output" ]] && return 1
            local osz; osz=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)
            [[ $osz -le $mb ]] && break
            local red; red=$(awk "BEGIN{r=int($cq*(1-$mb/$osz));if(r<5)r=5;print r}"); cq=$((cq-red)); [[ $cq -lt 10 ]] && cq=10
            rm -f "$output"
        done
    else
        build_magick_args "$input" "$output" "$qval" "$hdr_action" "$target_depth"
        $cmd "${MAGICK_ARGS[@]}" 2>/dev/null
    fi

    if [[ -f "$output" ]]; then
        [[ -n "$WATERMARK_IMAGE" ]] && apply_image_watermark "$output" "$WATERMARK_IMAGE"
        if [[ "$STRIP_EXIF" == "false" && "$HAS_EXIFTOOL" == "true" ]]; then
            exiftool -TagsFromFile "$input" -overwrite_original "$output" 2>/dev/null || true
            if [[ "$hdr_action" == "preserve" ]]; then
                exiftool -TagsFromFile "$input" -MaxContentLightLevel -MaxFrameAverageLightLevel -ColorPrimaries -TransferCharacteristics -overwrite_original "$output" 2>/dev/null || true
            fi
        fi
        local isz osz; isz=$(stat -c%s "$orig_input" 2>/dev/null || stat -f%z "$orig_input" 2>/dev/null); osz=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null)
        STATS_TOTAL_IN_SIZE=$((STATS_TOTAL_IN_SIZE + isz)); STATS_TOTAL_OUT_SIZE=$((STATS_TOTAL_OUT_SIZE + osz))
        local ratio; ratio=$(awk "BEGIN{printf\"%.0f\",($osz/$isz)*100}"); local c="${GREEN}"; [[ $ratio -gt 100 ]] && c="${YELLOW}"
        echo -e "${c}[OK]${NC} $(basename "$orig_input") → $(basename "$output") ${GRAY}($(format_size $isz) → $(format_size $osz), ${ratio}%)${NC}"
        log_compression "$(basename "$orig_input")" "$isz" "$osz"
        if [[ "$COMPARE" == "true" ]]; then
            local saved=$((isz - osz)); local sp; sp=$(awk "BEGIN{printf\"%.1f\",($saved/$isz)*100}")
            echo -e "  ${CYAN}[COMPARE]${NC} $(format_size $isz) → $(format_size $osz) ${GRAY}(${ratio}%, saved $(format_size $saved) / ${sp}%)${NC}"
        fi
        [[ -n "$dng_preview_tmp" && -f "$dng_preview_tmp" ]] && rm -f "$dng_preview_tmp"
        return 0
    else
        [[ -n "$dng_preview_tmp" && -f "$dng_preview_tmp" ]] && rm -f "$dng_preview_tmp"
        log_error "Failed: $(basename "$orig_input")"; return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN PROCESSING
# ══════════════════════════════════════════════════════════════════════════════

process_files() {
    local input_dir="$1" output_dir="$2"
    local total=0 converted=0 motion_ext=0 live_ext=0 skipped=0 failed=0
    STATS_START_TIME=$(date +%s)

    local files=() fd=(); [[ "$RECURSIVE" != "true" ]] && fd=(-maxdepth 1)
    while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$input_dir" "${fd[@]}" -type f -print0 2>/dev/null | sort -z)
    local image_files=(); for f in "${files[@]}"; do is_supported_image "$f" && image_files+=("$f"); done
    total=${#image_files[@]}
    [[ $total -eq 0 ]] && { log_warn "No images found"; return 0; }
    log_info "Found $total image(s)"

    # Pre-scan
    if [[ "$EXTRACT_MOTION" == "true" || "$MOTION_ONLY" == "true" ]]; then
        local lc=0; for f in "${image_files[@]}"; do is_motion_candidate "$f" && { local c; c=$(find_iphone_live_photo "$f" 2>/dev/null || true); [[ -n "$c" ]] && lc=$((lc+1)); }; done
        [[ $lc -gt 0 ]] && log_info "Detected $lc iPhone Live Photo(s)"
    fi

    # Pre-scan UHDR
    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        local uc=0; for f in "${image_files[@]}"; do is_uhdr_candidate "$f" && { local ut; ut=$(detect_uhdr "$f"); [[ "$ut" != "none" && "$ut" != "unknown" ]] && uc=$((uc+1)); }; done
        [[ $uc -gt 0 ]] && log_info "Detected $uc Ultra HDR image(s)"
    fi

    # Pre-scan DJI
    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        local dc=0; for f in "${image_files[@]}"; do local dj; dj=$(detect_dji_photo "$f"); [[ "$dj" == "dji" ]] && dc=$((dc+1)); done
        [[ $dc -gt 0 ]] && log_info "Detected $dc DJI photo(s)"
    fi

    # Pre-scan DNG
    if [[ "$HAS_EXIFTOOL" == "true" ]]; then
        local nc=0 njxl=0
        for f in "${image_files[@]}"; do
            local ne="${f##*.}"; ne="${ne,,}"
            if [[ "$ne" == "dng" ]]; then
                nc=$((nc+1))
                local nv nco ncl
                nv=$(detect_dng_version "$f"); nco=$(detect_dng_compression "$f")
                ncl=$(classify_dng "$nv" "$nco")
                [[ "$ncl" == "jxl" ]] && njxl=$((njxl+1))
            fi
        done
        if [[ $nc -gt 0 ]]; then
            if [[ $njxl -gt 0 ]]; then
                log_info "Detected $nc DNG file(s) — $njxl with DNG 1.7+ (JPEG XL)"
            else
                log_info "Detected $nc DNG file(s)"
            fi
        fi
    fi

    # DJI batch export (runs once before per-file loop, then exits)
    if [[ "$DJI_ACTION" == "export" ]]; then
        export_dji_metadata "$input_dir" "$output_dir"
        return 0
    fi

    echo ""

    local count=0
    for file in "${image_files[@]}"; do
        count=$((count + 1))
        local bn="${file##*/}" nm="${file##*/}"; nm="${nm%.*}"
        local rp="${file#$input_dir/}" rd; rd=$(dirname "$rp")
        local od="$output_dir"; [[ "$PRESERVE_STRUCTURE" == "true" && "$rd" != "." ]] && od="${output_dir}/${rd}"; mkdir -p "$od"

        show_progress "$count" "$total" "$bn"

        # Track input format distribution
        local ext="${bn##*.}"; ext="${ext,,}"
        FORMAT_COUNTS["$ext"]=$(( ${FORMAT_COUNTS["$ext"]:-0} + 1 ))

        # Skip duplicates
        if [[ "$SKIP_DUPLICATES" == "true" ]]; then
            local h; h=$(get_file_hash "$file")
            [[ -n "$h" && -n "${SEEN_HASHES[$h]+x}" ]] && { STATS_DUPLICATES_SKIPPED=$((STATS_DUPLICATES_SKIPPED+1)); skipped=$((skipped+1)); continue; }
            [[ -n "$h" ]] && SEEN_HASHES["$h"]="$bn"
        fi

        # Min resolution
        [[ $MIN_RESOLUTION -gt 0 ]] && { local w; w=$(get_image_width "$file"); [[ $w -lt $MIN_RESOLUTION ]] && { STATS_MINRES_SKIPPED=$((STATS_MINRES_SKIPPED+1)); skipped=$((skipped+1)); continue; }; }

        # Motion / Live Photo
        if [[ "$EXTRACT_MOTION" == "true" || "$MOTION_ONLY" == "true" ]]; then
            if is_motion_candidate "$file"; then
                local md="${od}/motion_videos"; mkdir -p "$md"
                local cm; cm=$(find_iphone_live_photo "$file" 2>/dev/null || true)
                if [[ -n "$cm" ]]; then LIVE_PHOTO_PAIRED["$cm"]=1; extract_iphone_live "$file" "$cm" "$md" && live_ext=$((live_ext+1))
                else extract_embedded_motion "$file" "$md" && motion_ext=$((motion_ext+1)); fi
            fi
        fi
        [[ "$MOTION_ONLY" == "true" ]] && continue

        local on; on=$(build_output_filename "$bn"); local of="${od}/${on}"
        [[ -f "$of" && "$OVERWRITE" != "true" ]] && { skipped=$((skipped+1)); continue; }

        # Skip existing (resume mode)
        if [[ "$SKIP_EXISTING" == "true" && -f "$of" ]]; then
            local existing_size; existing_size=$(stat -c%s "$of" 2>/dev/null || stat -f%z "$of" 2>/dev/null || echo 0)
            if [[ $existing_size -gt 0 ]]; then
                STATS_SKIPPED_EXISTING=$((STATS_SKIPPED_EXISTING + 1))
                skipped=$((skipped+1))
                log_verbose "Skip existing: $on ($(format_size $existing_size))"
                continue
            fi
        fi

        if convert_image "$file" "$of"; then converted=$((converted+1)); else failed=$((failed+1)); fi
    done

    # ── Summary ───────────────────────────────────────────────────────
    local et; et=$(date +%s); local dur=$((et - STATS_START_TIME)); local tm=$((motion_ext + live_ext))
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Summary${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "  Total images:             ${WHITE}${total}${NC}"
    if [[ "$MOTION_ONLY" != "true" && "$UHDR_ACTION" != "detect" && "$UHDR_ACTION" != "info" ]]; then
        echo -e "  Converted:                ${GREEN}${converted}${NC}"
        echo -e "  Skipped:                  ${YELLOW}${skipped}${NC}"
        [[ $STATS_DUPLICATES_SKIPPED -gt 0 ]] && echo -e "    Duplicates:             ${GRAY}${STATS_DUPLICATES_SKIPPED}${NC}"
        [[ $STATS_MINRES_SKIPPED -gt 0 ]]    && echo -e "    Below min-res:          ${GRAY}${STATS_MINRES_SKIPPED}${NC}"
        [[ $STATS_SKIPPED_EXISTING -gt 0 ]]  && echo -e "    Already converted:      ${GRAY}${STATS_SKIPPED_EXISTING}${NC}"
        echo -e "  Failed:                   ${RED}${failed}${NC}"
        [[ $STATS_LOSSLESS_OPTIMIZED -gt 0 ]] && echo -e "  Lossless optimized:       ${GREEN}${STATS_LOSSLESS_OPTIMIZED}${NC}"
    fi
    [[ $tm -gt 0 ]] && { echo -e "  Motion videos:            ${GREEN}${tm}${NC}"; [[ $motion_ext -gt 0 ]] && echo -e "    Samsung/Google:         ${WHITE}${motion_ext}${NC}"; [[ $live_ext -gt 0 ]] && echo -e "    iPhone Live Photo:      ${WHITE}${live_ext}${NC}"; }

    if [[ $STATS_UHDR_DETECTED -gt 0 ]]; then
        echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
        echo -e "  ${BLUE}Ultra HDR images:         ${WHITE}${STATS_UHDR_DETECTED}${NC}"
        [[ $STATS_UHDR_STRIPPED -gt 0 ]]   && echo -e "    Gain maps stripped:   ${WHITE}${STATS_UHDR_STRIPPED}${NC}"
        [[ $STATS_UHDR_EXTRACTED -gt 0 ]]  && echo -e "    Gain maps extracted:  ${WHITE}${STATS_UHDR_EXTRACTED}${NC}"
        [[ $STATS_UHDR_DECODED -gt 0 ]]    && echo -e "    Full HDR decoded:     ${WHITE}${STATS_UHDR_DECODED}${NC}"
    fi
    if [[ $STATS_HDR_DETECTED -gt 0 ]]; then
        echo -e "  ${MAGENTA}Classic HDR images:       ${WHITE}${STATS_HDR_DETECTED}${NC}"
        [[ $STATS_HDR_TONEMAPPED -gt 0 ]] && echo -e "    Tone mapped → SDR:    ${WHITE}${STATS_HDR_TONEMAPPED}${NC}"
        [[ $STATS_HDR_PRESERVED -gt 0 ]]  && echo -e "    Preserved HDR:        ${WHITE}${STATS_HDR_PRESERVED}${NC}"
    fi
    if [[ $STATS_DJI_DETECTED -gt 0 ]]; then
        echo -e "  ${GREEN}DJI photos:               ${WHITE}${STATS_DJI_DETECTED}${NC}"
        [[ $STATS_DJI_EXPORTED -gt 0 ]]   && echo -e "    Metadata exported:    ${WHITE}${STATS_DJI_EXPORTED}${NC}"
        [[ $STATS_DJI_LIVEPHOTO -gt 0 ]]  && echo -e "    Live Photo extracted: ${WHITE}${STATS_DJI_LIVEPHOTO}${NC}"
        [[ $STATS_DJI_STRIPPED -gt 0 ]]   && echo -e "    Privacy stripped:     ${WHITE}${STATS_DJI_STRIPPED}${NC}"
    fi
    if [[ $STATS_DNG_DETECTED -gt 0 ]]; then
        echo -e "  ${MAGENTA}DNG files:                ${WHITE}${STATS_DNG_DETECTED}${NC}"
        [[ $STATS_DNG_JXL -gt 0 ]]     && echo -e "    DNG 1.7+ (JPEG XL):   ${WHITE}${STATS_DNG_JXL}${NC}"
        [[ $STATS_DNG_PREVIEW -gt 0 ]] && echo -e "    Preview extracted:    ${GREEN}${STATS_DNG_PREVIEW}${NC}"
        [[ $STATS_DNG_FAILED -gt 0 ]]  && echo -e "    Decode failed:        ${RED}${STATS_DNG_FAILED}${NC}"
    fi

    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    if [[ "$DRY_RUN" != "true" && "$MOTION_ONLY" != "true" && $STATS_TOTAL_IN_SIZE -gt 0 ]]; then
        local saved=$((STATS_TOTAL_IN_SIZE - STATS_TOTAL_OUT_SIZE))
        echo -e "  Total input:              ${WHITE}$(format_size $STATS_TOTAL_IN_SIZE)${NC}"
        echo -e "  Total output:             ${WHITE}$(format_size $STATS_TOTAL_OUT_SIZE)${NC}"
        [[ $saved -gt 0 ]] && { local sp; sp=$(awk "BEGIN{printf\"%.1f\",($saved/$STATS_TOTAL_IN_SIZE)*100}"); echo -e "  Space saved:              ${GREEN}$(format_size $saved) (${sp}%)${NC}"; }
        if [[ $converted -gt 0 ]]; then
            local avg_ratio; avg_ratio=$(awk "BEGIN{printf\"%.1f\",(${STATS_TOTAL_OUT_SIZE}/${STATS_TOTAL_IN_SIZE})*100}")
            echo -e "  Avg compression:          ${WHITE}${avg_ratio}%${NC}"
        fi
        print_compression_report
    fi
    echo -e "  Processing time:          ${WHITE}$(format_duration $dur)${NC}"
    [[ $converted -gt 0 && $dur -gt 0 ]] && echo -e "  Average per image:        ${WHITE}$(format_duration $((dur/converted)))${NC}"
    # Input format distribution
    if [[ ${#FORMAT_COUNTS[@]} -gt 0 ]]; then
        local fmt_str=""
        for ext in $(echo "${!FORMAT_COUNTS[@]}" | tr ' ' '\n' | sort); do
            [[ -n "$fmt_str" ]] && fmt_str+=", "
            fmt_str+="${ext^^}:${FORMAT_COUNTS[$ext]}"
        done
        echo -e "  Input formats:            ${GRAY}${fmt_str}${NC}"
    fi
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "  Format: ${WHITE}${OUTPUT_FORMAT^^}${NC} | HDR: ${WHITE}${HDR_MODE}${NC}$(if [[ -n "$UHDR_ACTION" ]]; then echo " | UHDR: ${WHITE}${UHDR_ACTION}${NC}"; fi)"
    echo -e "  Output: ${WHITE}${output_dir}${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ── Parse arguments ──────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)           INPUT_DIR="$2"; shift 2 ;;
            -o|--output)          OUTPUT_DIR="$2"; shift 2 ;;
            -f|--format)          OUTPUT_FORMAT="${2,,}"; shift 2 ;;
            -q|--quality)         QUALITY="$2"; shift 2 ;;
            -p|--preset)          QUALITY_PRESET="${2,,}"; shift 2 ;;
            --max-size)           MAX_FILE_SIZE="$2"; shift 2 ;;
            -r|--resize)          RESIZE="$2"; shift 2 ;;
            --resize-mode)        RESIZE_MODE="$2"; shift 2 ;;
            --crop)               CROP_RATIO="$2"; shift 2 ;;
            --depth)              BIT_DEPTH="$2"; shift 2 ;;
            --force-sdr)          HDR_MODE="force-sdr"; shift ;;
            --force-hdr)          HDR_MODE="force-hdr"; shift ;;
            --uhdr)               UHDR_ACTION="${2,,}"; shift 2 ;;
            --dji)                DJI_ACTION="${2,,}"; shift 2 ;;
            --dng-preview)        DNG_PREVIEW_MODE="true"; shift ;;
            --strip-exif)         STRIP_EXIF="true"; shift ;;
            --keep-exif)          STRIP_EXIF="false"; shift ;;
            --auto-rotate)        AUTO_ROTATE="true"; shift ;;
            --no-auto-rotate)     AUTO_ROTATE="false"; shift ;;
            --srgb)               SRGB_CONVERT="true"; shift ;;
            --watermark-text)     WATERMARK_TEXT="$2"; shift 2 ;;
            --watermark-image)    WATERMARK_IMAGE="$2"; shift 2 ;;
            --watermark-pos)      WATERMARK_POSITION="$2"; shift 2 ;;
            --watermark-opacity)  WATERMARK_OPACITY="$2"; shift 2 ;;
            --prefix)             OUTPUT_PREFIX="$2"; shift 2 ;;
            --suffix)             OUTPUT_SUFFIX="$2"; shift 2 ;;
            --min-res)            MIN_RESOLUTION="$2"; shift 2 ;;
            --lossless-jpeg)      LOSSLESS_JPEG="true"; shift ;;
            --skip-duplicates)    SKIP_DUPLICATES="true"; shift ;;
            -m|--extract-motion)  EXTRACT_MOTION="true"; shift ;;
            --motion-only)        MOTION_ONLY="true"; EXTRACT_MOTION="true"; shift ;;
            -j|--jobs)            PARALLEL_JOBS="$2"; shift 2 ;;
            --skip-existing)      SKIP_EXISTING="true"; shift ;;
            --profile)            PROFILE="$2"; shift 2 ;;
            --watch)              WATCH_MODE="true"; shift ;;
            --watch-interval)     WATCH_INTERVAL="$2"; shift 2 ;;
            --no-recursive)       RECURSIVE="false"; shift ;;
            --flat)               PRESERVE_STRUCTURE="false"; shift ;;
            --overwrite)          OVERWRITE="true"; shift ;;
            --dry-run)            DRY_RUN="true"; shift ;;
            -v|--verbose)         VERBOSE="true"; shift ;;
            --compare)            COMPARE="true"; shift ;;
            -h|--help)            usage ;;
            --version)            echo "photo_encoder.sh v${VERSION}"; exit 0 ;;
            *)                    log_error "Unknown: $1"; exit 1 ;;
        esac
    done
}

validate_args() {
    [[ -z "$INPUT_DIR" ]] && { log_error "Input required (-i)"; exit 1; }
    [[ ! -d "$INPUT_DIR" ]] && { log_error "Not found: $INPUT_DIR"; exit 1; }
    [[ -z "$OUTPUT_DIR" ]] && { log_error "Output required (-o)"; exit 1; }
    case "$OUTPUT_FORMAT" in avif|webp|jpeg|jpg|heic|png|jxl) ;; *) log_error "Bad format"; exit 1;; esac
    [[ "$OUTPUT_FORMAT" == "jpg" ]] && OUTPUT_FORMAT="jpeg"
    [[ -n "$QUALITY_PRESET" ]] && case "$QUALITY_PRESET" in web|social|archive|print|max|thumb) ;; *) log_error "Bad preset"; exit 1;; esac
    [[ -n "$BIT_DEPTH" ]] && case "$BIT_DEPTH" in 8|10|16) ;; *) log_error "Depth: 8/10/16"; exit 1;; esac
    [[ -n "$UHDR_ACTION" ]] && case "$UHDR_ACTION" in detect|strip|extract|decode|info) ;; *) log_error "UHDR: detect/strip/extract/decode/info"; exit 1;; esac
    [[ -n "$DJI_ACTION" ]] && case "$DJI_ACTION" in detect|export|privacy-strip) ;; *) log_error "DJI: detect/export/privacy-strip"; exit 1;; esac
    [[ -n "$CROP_RATIO" && ! "$CROP_RATIO" =~ ^[0-9]+:[0-9]+$ ]] && { log_error "Crop: W:H"; exit 1; }
    mkdir -p "$OUTPUT_DIR"
}

main() {
    local interactive_mode="false"

    # ── Launch mode (when no args given on CLI) ──────────────────────────────
    if [[ $# -eq 0 ]]; then
        echo ""
        echo -e "  ${WHITE}Input:${NC}  ${INPUT_DIR}"
        echo -e "  ${WHITE}Output:${NC} ${OUTPUT_DIR}"
        echo ""
        echo -e "  ${GREEN}1)${NC} Normal      — encodeaza cu setarile default"
        echo -e "  ${YELLOW}2)${NC} Dry-run     — doar analiza, fara conversie"
        echo -e "  ${CYAN}3)${NC} Interactiv  — profile save/load, configurare manuala"
        echo ""
        read -p "  Alege [1-3, implicit=1]: " launch_choice
        case "${launch_choice:-1}" in
            2) DRY_RUN="true" ;;
            3) interactive_mode="true" ;;
        esac
    fi

    parse_args "$@"

    # ── Interactive UserProfiles/ load (option 3) ───────────────────────────
    if [[ "$interactive_mode" == "true" ]]; then
        mkdir -p "$USER_PROFILES_DIR"

        local prof_files=()
        while IFS= read -r -d '' pf; do
            prof_files+=("$pf")
        done < <(find "$USER_PROFILES_DIR" -maxdepth 1 -name "*.conf" -type f -print0 2>/dev/null | sort -z)

        if [[ ${#prof_files[@]} -gt 0 ]]; then
            echo ""
            echo -e "  ${WHITE}Profile salvate in UserProfiles/:${NC}"
            echo -e "  ${CYAN}────────────────────────────────────${NC}"
            local idx=0
            for pf in "${prof_files[@]}"; do
                idx=$((idx + 1))
                local bn; bn=$(basename "$pf" .conf)
                echo -e "    ${GREEN}${idx})${NC} ${bn}"
            done
            echo ""
            echo -e "    ${GRAY}0) Skip — configurare manuala${NC}"
            echo ""
            read -p "  Incarca profil [0-${idx}]: " prof_choice
            if [[ -n "$prof_choice" && "$prof_choice" != "0" ]]; then
                local ci=$((prof_choice - 1))
                if [[ $ci -ge 0 && $ci -lt ${#prof_files[@]} ]]; then
                    local load_file="${prof_files[$ci]}"
                    local load_name; load_name=$(basename "$load_file" .conf)
                    log_info "Incarc profil: ${load_name}"
                    load_profile_conf "$load_file"
                    # Display loaded settings for confirmation
                    echo -e "  ${CYAN}────────────────────────────────────${NC}"
                    echo -e "  Format       : ${WHITE}${OUTPUT_FORMAT}${NC}"
                    [[ -n "$QUALITY_PRESET" ]] && echo -e "  Quality      : ${WHITE}${QUALITY_PRESET}${NC}" || echo -e "  Quality      : ${WHITE}${QUALITY}${NC}"
                    echo -e "  Input        : ${WHITE}${INPUT_DIR}${NC}"
                    echo -e "  Output       : ${WHITE}${OUTPUT_DIR}${NC}"
                    [[ -n "$RESIZE" ]]     && echo -e "  Resize       : ${WHITE}${RESIZE}${NC}"
                    [[ -n "$CROP_RATIO" ]] && echo -e "  Crop         : ${WHITE}${CROP_RATIO}${NC}"
                    echo -e "  HDR          : ${WHITE}${HDR_MODE}${NC}"
                    [[ -n "$UHDR_ACTION" ]]    && echo -e "  Ultra HDR    : ${WHITE}${UHDR_ACTION}${NC}"
                    [[ -n "$WATERMARK_TEXT" ]]  && echo -e "  Watermark    : ${WHITE}${WATERMARK_TEXT}${NC}"
                    echo -e "  ${CYAN}────────────────────────────────────${NC}"
                    read -p "  Lanseaza cu aceste setari? (D/n): " prof_confirm
                    if [[ "${prof_confirm,,}" == "n" ]]; then
                        echo -e "  ${YELLOW}Profil anulat — continuam cu configurare manuala.${NC}"
                        # Reset to defaults (paths raman cele din Paths)
                        OUTPUT_FORMAT="avif"; QUALITY=80; QUALITY_PRESET=""; RESIZE=""; CROP_RATIO=""
                        HDR_MODE="auto"; UHDR_ACTION=""; DJI_ACTION=""
                        STRIP_EXIF="false"; SRGB_CONVERT="false"; WATERMARK_TEXT=""
                    else
                        log_info "Profil incarcat."
                    fi
                fi
            fi
        else
            echo -e "  ${GRAY}Niciun profil salvat. Profilele se salveaza in UserProfiles/.${NC}"
        fi

    fi

    # Load profile from photo_profiles.conf (CLI --profile flag)
    [[ -n "$PROFILE" ]] && load_profile "$PROFILE"

    print_header
    validate_args
    check_dependencies

    # HEIC output support check
    check_heic_output_support

    local dq; dq=$(get_effective_quality)
    log_info "Configuration:"
    echo -e "  Input:      ${WHITE}${INPUT_DIR}${NC}"
    echo -e "  Output:     ${WHITE}${OUTPUT_DIR}${NC}"
    echo -e "  Format:     ${WHITE}${OUTPUT_FORMAT^^}${NC}"
    [[ -n "$QUALITY_PRESET" ]] && echo -e "  Preset:     ${WHITE}${QUALITY_PRESET}${NC} (q${dq})" || echo -e "  Quality:    ${WHITE}${QUALITY}${NC}"
    [[ -n "$PROFILE" ]] && echo -e "  Profile:    ${WHITE}${PROFILE}${NC}"
    echo -e "  HDR:        ${WHITE}${HDR_MODE}${NC}"
    [[ -n "$UHDR_ACTION" ]] && echo -e "  Ultra HDR:  ${WHITE}${UHDR_ACTION}${NC}" || echo -e "  Ultra HDR:  ${WHITE}auto-detect${NC}"
    [[ -n "$DJI_ACTION" ]] && echo -e "  DJI:        ${WHITE}${DJI_ACTION}${NC}" || echo -e "  DJI:        ${WHITE}auto-detect${NC}"
    [[ -n "$BIT_DEPTH" ]] && echo -e "  Bit depth:  ${WHITE}${BIT_DEPTH}-bit${NC}" || echo -e "  Bit depth:  ${WHITE}auto${NC}"
    [[ $PARALLEL_JOBS -gt 1 ]] && echo -e "  Parallel:   ${WHITE}${PARALLEL_JOBS} jobs${NC}"
    [[ "$SKIP_EXISTING" == "true" ]] && echo -e "  Resume:     ${WHITE}skip existing${NC}"
    [[ "$WATCH_MODE" == "true" ]] && echo -e "  Watch:      ${WHITE}every ${WATCH_INTERVAL}s${NC}"
    [[ "$HAS_ULTRAHDR_APP" == "true" ]] && echo -e "  libultrahdr: ${GREEN}available${NC}" || echo -e "  libultrahdr: ${GRAY}not installed${NC}"
    [[ "$HAS_EXIFTOOL" == "true" ]] && echo -e "  exiftool:   ${GREEN}available${NC}" || echo -e "  exiftool:   ${GRAY}not installed${NC}"
    [[ -n "$RESIZE" ]] && echo -e "  Resize:     ${WHITE}${RESIZE} (${RESIZE_MODE})${NC}"
    [[ -n "$CROP_RATIO" ]] && echo -e "  Crop:       ${WHITE}${CROP_RATIO}${NC}"
    [[ -n "$WATERMARK_TEXT" ]] && echo -e "  Watermark:  ${WHITE}\"${WATERMARK_TEXT}\"${NC}"
    [[ "$EXTRACT_MOTION" == "true" ]] && echo -e "  Motion:     ${WHITE}Samsung + Google + iPhone + DJI${NC}"
    [[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}DRY RUN${NC}"
    echo ""

    # ── Auto-preset suggestion ─────────────────────────────────────────────
    if [[ -z "$QUALITY_PRESET" && "$QUALITY" == "80" && -z "$PROFILE" ]]; then
        local sample_mp=0 sample_count=0
        while IFS= read -r -d '' sf; do
            is_supported_image "$sf" || continue
            local dims; dims=$($MAGICK_CMD identify -format "%w %h" "$sf[0]" 2>/dev/null | head -1)
            if [[ "$dims" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
                local mp=$(( ${BASH_REMATCH[1]} * ${BASH_REMATCH[2]} / 1000000 ))
                sample_mp=$((sample_mp + mp)); sample_count=$((sample_count + 1))
            fi
            [[ $sample_count -ge 10 ]] && break
        done < <(find "$INPUT_DIR" -maxdepth 1 -type f -print0 2>/dev/null)
        if [[ $sample_count -gt 0 ]]; then
            local avg_mp=$((sample_mp / sample_count))
            local suggested=""
            if [[ $avg_mp -ge 20 ]]; then suggested="max"
            elif [[ $avg_mp -ge 8 ]]; then suggested="archive"
            else suggested="web"; fi
            echo -e "  ${CYAN}[SUGGEST]${NC} Detected ${WHITE}${avg_mp}MP${NC} average (${sample_count} samples)"
            echo -e "  ${CYAN}[SUGGEST]${NC} Recommended preset: ${WHITE}${suggested}${NC} (use ${WHITE}-p ${suggested}${NC})"
            echo ""
        fi
    fi

    # Watch mode — infinite loop monitoring
    if [[ "$WATCH_MODE" == "true" ]]; then
        run_watch_mode "$INPUT_DIR" "$OUTPUT_DIR"
        exit 0
    fi

    process_files "$INPUT_DIR" "$OUTPUT_DIR"

    # ── Save Profile Option (interactive only, not dry-run) ──────────────────
    if [[ "$interactive_mode" == "true" && "$DRY_RUN" != "true" ]]; then
        save_profile_conf
    fi
}

main "$@"
