#!/usr/bin/env bash
# ============================================================================
# photo_common.sh v4.7 — Cross-platform Foundation
# ============================================================================
# Source-uit de toate scripturile .sh ale Photo-Encoder-Suite.
# Centralizeaza:
#   - detect_platform (termux / linux / macos)
#   - path resolution (Termux unchanged, Linux/macOS = $PHOTO_SCRIPT_DIR/...)
#   - 13 wrappere GNU vs BSD (nproc, stat, sed, readlink, mktemp, grep -P,
#     date, du, df)
#   - bash 4+ check (refuz macOS bash 3.2)
#   - wake-lock / notify / open-folder cross-platform
#   - photo_pkg_install_hint (pkg / brew / apt / dnf / pacman / zypper)
#   - color codes + log helpers
#   - tool detection helpers (ImageMagick, ExifTool, ffmpeg, heif-convert,
#     ultrahdr_app)
#
# Idempotent: re-source-ul nu re-defineste / nu duplica.
# ============================================================================

# ── Idempotency guard ───────────────────────────────────────────────────────
[[ "${PHOTO_COMMON_LOADED:-}" == "1" ]] && return 0
PHOTO_COMMON_LOADED=1

# ── Bash 4+ check ───────────────────────────────────────────────────────────
if (( BASH_VERSINFO[0] < 4 )); then
    echo "[ERROR] Photo-Encoder-Suite necesita bash 4+ (folosesti ${BASH_VERSION})." >&2
    case "$(uname -s)" in
        Darwin*) echo "  Pe macOS instaleaza bash modern: brew install bash" >&2 ;;
        *)       echo "  Actualizeaza bash-ul la versiunea 4 sau mai noua." >&2 ;;
    esac
    return 1 2>/dev/null || exit 1
fi

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';   GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m';  BLUE='\033[0;34m';   MAGENTA='\033[0;35m'
NC='\033[0m'

# ── Platform detection ──────────────────────────────────────────────────────
detect_platform() {
    case "$(uname -s)" in
        Linux*)
            if [[ -d "/data/data/com.termux" ]]; then
                PHOTO_PLATFORM="termux"
                PHOTO_OS_LABEL="Termux (Android)"
            else
                PHOTO_PLATFORM="linux"
                local distro="Linux"
                if [[ -f /etc/os-release ]]; then
                    distro=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Linux}")
                fi
                PHOTO_OS_LABEL="$distro"
            fi
            ;;
        Darwin*)
            PHOTO_PLATFORM="macos"
            local arch_label="Intel"
            [[ "$(uname -m)" == "arm64" ]] && arch_label="Apple Silicon"
            local mac_ver
            mac_ver=$(sw_vers -productVersion 2>/dev/null || echo "")
            PHOTO_OS_LABEL="macOS ${mac_ver} (${arch_label})"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            # Windows POSIX layer — tratat ca linux pentru semantica path-urilor
            PHOTO_PLATFORM="linux"
            PHOTO_OS_LABEL="Windows POSIX ($(uname -s))"
            ;;
        *)
            PHOTO_PLATFORM="unknown"
            PHOTO_OS_LABEL="Unknown ($(uname -s))"
            ;;
    esac
    PHOTO_IS_TERMUX="false"
    [[ "$PHOTO_PLATFORM" == "termux" ]] && PHOTO_IS_TERMUX="true"
    export PHOTO_PLATFORM PHOTO_IS_TERMUX PHOTO_OS_LABEL
}
detect_platform

# ── SCRIPT_DIR resolution (caller's directory) ──────────────────────────────
# Daca caller-ul a setat PHOTO_SCRIPT_DIR inainte de source (ex. dupa rezolvare
# symlinks), respectam valoarea. Altfel rezolvam din BASH_SOURCE.
if [[ -z "${PHOTO_SCRIPT_DIR:-}" ]]; then
    if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
        PHOTO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    else
        PHOTO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi
# Daca caller-ul e in src/tools/, urca un nivel ca paths sa rezolve la src/
# (TOOLS_DIR=src/tools, NU src/tools/tools).
if [[ "$(basename "$PHOTO_SCRIPT_DIR")" == "tools" ]]; then
    PHOTO_SCRIPT_DIR="$(dirname "$PHOTO_SCRIPT_DIR")"
fi
export PHOTO_SCRIPT_DIR

# ── Path resolution per platform ────────────────────────────────────────────
# Termux pastreaza locatiile actuale (zero migrare pentru utilizatorii
# existenti). Linux + macOS folosesc directorul scriptului (paritate cu PS1
# care foloseste $PSScriptRoot).
photo_resolve_paths() {
    if [[ "$PHOTO_PLATFORM" == "termux" ]]; then
        : "${INPUT_DIR:=/storage/emulated/0/Media/InputPhotos}"
        : "${OUTPUT_DIR:=/storage/emulated/0/Media/OutputPhotos}"
        : "${TOOLS_DIR:=/storage/emulated/0/Media/Scripts/tools}"
        : "${PROFILES_DIR:=/storage/emulated/0/Media/Scripts/profiles}"
        : "${USER_PROFILES_DIR:=/storage/emulated/0/Media/UserProfiles}"
        : "${LUTS_DIR:=/storage/emulated/0/Media/Scripts/luts}"
    else
        : "${INPUT_DIR:=$PHOTO_SCRIPT_DIR/InputPhotos}"
        : "${OUTPUT_DIR:=$PHOTO_SCRIPT_DIR/OutputPhotos}"
        : "${TOOLS_DIR:=$PHOTO_SCRIPT_DIR/tools}"
        : "${PROFILES_DIR:=$PHOTO_SCRIPT_DIR/profiles}"
        : "${USER_PROFILES_DIR:=$PHOTO_SCRIPT_DIR/UserProfiles}"
        : "${LUTS_DIR:=$PHOTO_SCRIPT_DIR/luts}"
    fi
    export INPUT_DIR OUTPUT_DIR TOOLS_DIR PROFILES_DIR USER_PROFILES_DIR LUTS_DIR
}

# ============================================================================
# WRAPPERE GNU vs BSD
# ============================================================================

# CPU count (cores logice)
photo_nproc() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        sysctl -n hw.ncpu 2>/dev/null || echo 1
    else
        nproc 2>/dev/null || echo 1
    fi
}

# File size in bytes
photo_stat_size() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        stat -f%z "$1" 2>/dev/null
    else
        stat -c%s "$1" 2>/dev/null
    fi
}

# File mtime (epoch seconds)
photo_stat_mtime() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        stat -f%m "$1" 2>/dev/null
    else
        stat -c%Y "$1" 2>/dev/null
    fi
}

# In-place sed
# Usage: photo_sed_inplace 's/foo/bar/g' file.txt
photo_sed_inplace() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Resolve symlink to canonical absolute path
photo_readlink_f() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        if command -v greadlink &>/dev/null; then
            greadlink -f "$1"
        elif command -v python3 &>/dev/null; then
            python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"
        else
            local target="$1"
            (cd "$(dirname "$target")" 2>/dev/null && echo "$(pwd)/$(basename "$target")")
        fi
    else
        readlink -f "$1"
    fi
}

# mktemp directory
photo_mktemp_dir() {
    mktemp -d 2>/dev/null
}

# mktemp with extension (BSD doesn't support --suffix)
# Usage: tmpfile=$(photo_mktemp_ext json)
photo_mktemp_ext() {
    local ext="$1"
    local tmp
    tmp=$(mktemp 2>/dev/null) || return 1
    local final="${tmp}.${ext}"
    if mv "$tmp" "$final" 2>/dev/null; then
        echo "$final"
    else
        echo "$tmp"
    fi
}

# PCRE grep — macOS BSD grep nu suporta -P
photo_grep_perl() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]] && ! grep -P '' </dev/null &>/dev/null; then
        if command -v ggrep &>/dev/null; then
            ggrep -P "$@"
        elif command -v pcregrep &>/dev/null; then
            pcregrep "$@"
        else
            grep -E "$@"
        fi
    else
        grep -P "$@"
    fi
}

# Date string → epoch seconds
photo_date_to_epoch() {
    local datestr="$1"
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        date -j -f "%Y-%m-%d %H:%M:%S" "$datestr" "+%s" 2>/dev/null || \
        date -j -f "%Y-%m-%dT%H:%M:%S" "$datestr" "+%s" 2>/dev/null || \
        date -j -f "%Y:%m:%d %H:%M:%S" "$datestr" "+%s" 2>/dev/null || \
        echo 0
    else
        date -d "$datestr" +%s 2>/dev/null || echo 0
    fi
}

# Disk free in KB (POSIX, 1K blocks)
photo_df_kb() {
    df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Disk usage in MB
photo_du_mb() {
    if [[ "$PHOTO_PLATFORM" == "macos" ]]; then
        du -sk "$1" 2>/dev/null | awk '{print int($1/1024)}'
    else
        du -sm "$1" 2>/dev/null | awk '{print $1}'
    fi
}

# ============================================================================
# WAKE-LOCK / NOTIFY / OPEN FOLDER
# ============================================================================
PHOTO_WAKELOCK_PID=""

photo_wake_lock() {
    case "$PHOTO_PLATFORM" in
        termux)
            command -v termux-wake-lock &>/dev/null && termux-wake-lock 2>/dev/null
            ;;
        linux)
            if [[ -z "$PHOTO_WAKELOCK_PID" ]] && command -v systemd-inhibit &>/dev/null; then
                systemd-inhibit --who="Photo Encoder" --why="Encoding batch" --what="sleep" \
                    sleep infinity &>/dev/null &
                PHOTO_WAKELOCK_PID=$!
            fi
            ;;
        macos)
            if [[ -z "$PHOTO_WAKELOCK_PID" ]] && command -v caffeinate &>/dev/null; then
                caffeinate -i &>/dev/null &
                PHOTO_WAKELOCK_PID=$!
            fi
            ;;
    esac
}

photo_wake_unlock() {
    case "$PHOTO_PLATFORM" in
        termux)
            command -v termux-wake-unlock &>/dev/null && termux-wake-unlock 2>/dev/null
            ;;
        linux|macos)
            if [[ -n "$PHOTO_WAKELOCK_PID" ]]; then
                kill "$PHOTO_WAKELOCK_PID" 2>/dev/null
                PHOTO_WAKELOCK_PID=""
            fi
            ;;
    esac
}

photo_notify_done() {
    local title="${1:-Photo Encoder}"
    local body="${2:-Batch complet}"
    case "$PHOTO_PLATFORM" in
        termux)
            command -v termux-notification &>/dev/null && \
                termux-notification --title "$title" --content "$body" 2>/dev/null
            ;;
        linux)
            command -v notify-send &>/dev/null && \
                notify-send "$title" "$body" 2>/dev/null
            ;;
        macos)
            command -v osascript &>/dev/null && \
                osascript -e "display notification \"${body}\" with title \"${title}\"" 2>/dev/null
            ;;
    esac
}

photo_open_path() {
    local target="$1"
    [[ -e "$target" ]] || return 1
    case "$PHOTO_PLATFORM" in
        termux)
            command -v termux-open &>/dev/null && termux-open "$target" 2>/dev/null
            ;;
        linux)
            command -v xdg-open &>/dev/null && xdg-open "$target" &>/dev/null &
            ;;
        macos)
            open "$target" &>/dev/null
            ;;
    esac
}

# ============================================================================
# PACKAGE INSTALL HINT
# ============================================================================
# Usage: photo_pkg_install_hint <pkg> [termux_pkg] [brew_pkg] [apt_pkg] [dnf_pkg] [pacman_pkg]
# Daca se omit, foloseste $pkg pentru toate.
photo_pkg_install_hint() {
    local pkg="$1"
    local termux_pkg="${2:-$pkg}"
    local brew_pkg="${3:-$pkg}"
    local apt_pkg="${4:-$pkg}"
    local dnf_pkg="${5:-$pkg}"
    local pacman_pkg="${6:-$pkg}"

    case "$PHOTO_PLATFORM" in
        termux)
            echo "  pkg install $termux_pkg"
            ;;
        macos)
            echo "  brew install $brew_pkg"
            ;;
        linux)
            if   command -v apt    &>/dev/null; then echo "  sudo apt install $apt_pkg"
            elif command -v dnf    &>/dev/null; then echo "  sudo dnf install $dnf_pkg"
            elif command -v pacman &>/dev/null; then echo "  sudo pacman -S $pacman_pkg"
            elif command -v zypper &>/dev/null; then echo "  sudo zypper install $apt_pkg"
            else echo "  (instaleaza '$pkg' cu package manager-ul distributiei)"
            fi
            ;;
        *)
            echo "  (instaleaza '$pkg' manual)"
            ;;
    esac
}

# ============================================================================
# LOGGING HELPERS
# ============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_dry()     { echo -e "${CYAN}[DRY]${NC} $*"; }
log_verbose() { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${GRAY}[VERB]${NC} $*"; }

# ============================================================================
# OS BANNER
# ============================================================================
photo_print_os_banner() {
    local bash_v="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    echo -e "${GRAY}[OS]${NC} ${WHITE}${PHOTO_OS_LABEL}${NC} ${GRAY}— bash ${bash_v}${NC}"
}

# ============================================================================
# TOOL DETECTION HELPERS
# ============================================================================
photo_has_imagemagick()  { command -v magick &>/dev/null || command -v convert &>/dev/null; }
photo_has_exiftool()     { command -v exiftool &>/dev/null; }
photo_has_ffmpeg()       { command -v ffmpeg &>/dev/null; }
photo_has_heif_convert() { command -v heif-convert &>/dev/null; }
photo_has_ultrahdr_app() { command -v ultrahdr_app &>/dev/null; }
photo_has_jpegtran()     { command -v jpegtran &>/dev/null; }
photo_has_python3()      { command -v python3 &>/dev/null; }

# ImageMagick command name (v7 magick / v6 convert fallback)
photo_magick_cmd() {
    if command -v magick &>/dev/null; then echo "magick"
    elif command -v convert &>/dev/null; then echo "convert"
    else echo ""; fi
}

# ── Auto-resolve paths la sourcing ──────────────────────────────────────────
photo_resolve_paths

# Daca exista $TOOLS_DIR/bin/, prepend-l la PATH ca encoder sa gaseasca
# ultrahdr_app instalat local de photo_build_ultrahdr.sh.
if [[ -d "$TOOLS_DIR/bin" && ":$PATH:" != *":$TOOLS_DIR/bin:"* ]]; then
    export PATH="$TOOLS_DIR/bin:$PATH"
fi
