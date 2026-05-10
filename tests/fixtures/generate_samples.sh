#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  generate_samples.sh — synth tiny test images via ImageMagick
#  Idempotent (skip-if-exists, override with --force).
#  Outputs to tests/fixtures/samples/
#  HEIC requires libheif in ImageMagick; skipped gracefully if absent.
# ═══════════════════════════════════════════════════════════════

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLES_DIR="$SCRIPT_DIR/samples"
mkdir -p "$SAMPLES_DIR"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        -h|--help)  echo "Usage: $0 [--force]"; exit 0 ;;
    esac
done

# Detect ImageMagick
if command -v magick &>/dev/null; then
    MAGICK="magick"
elif command -v convert &>/dev/null; then
    MAGICK="convert"
else
    echo "  x ImageMagick (magick/convert) negasit. Esuat." >&2
    exit 1
fi

_skip() {
    [[ $FORCE -eq 1 ]] && return 1
    [[ -f "$1" ]] && { echo "  ~ exists: $(basename "$1")"; return 0; }
    return 1
}

_size_kb() {
    local f="$1"
    if [[ -f "$f" ]]; then
        if stat -c%s "$f" &>/dev/null; then
            awk -v b="$(stat -c%s "$f")" 'BEGIN{printf "%.0f", b/1024}'
        else
            awk -v b="$(stat -f%z "$f")" 'BEGIN{printf "%.0f", b/1024}'
        fi
    fi
}

echo "Generating synthetic samples in: $SAMPLES_DIR"

# 1) PNG 256x256 gradient
out="$SAMPLES_DIR/test_256.png"
if ! _skip "$out"; then
    $MAGICK -size 256x256 gradient:blue-yellow "$out"
    echo "  + $(basename "$out") ($(_size_kb "$out") KB)"
fi

# 2) PNG 512x512 with text
out="$SAMPLES_DIR/test_512.png"
if ! _skip "$out"; then
    $MAGICK -size 512x512 plasma: -fill white -gravity center -pointsize 36 -annotate 0 "PHOTO" "$out"
    echo "  + $(basename "$out") ($(_size_kb "$out") KB)"
fi

# 3) JPEG 256x256
out="$SAMPLES_DIR/test_256.jpg"
if ! _skip "$out"; then
    $MAGICK -size 256x256 gradient:red-blue -quality 85 "$out"
    echo "  + $(basename "$out") ($(_size_kb "$out") KB)"
fi

# 4) JPEG 1024x768 (more realistic resolution)
out="$SAMPLES_DIR/test_1024.jpg"
if ! _skip "$out"; then
    $MAGICK -size 1024x768 plasma: -quality 85 "$out"
    echo "  + $(basename "$out") ($(_size_kb "$out") KB)"
fi

# 5) HEIC — best effort. ImageMagick must have libheif support.
out="$SAMPLES_DIR/test_256.heic"
if ! _skip "$out"; then
    if $MAGICK -size 256x256 gradient:green-magenta "$out" 2>/dev/null && [[ -f "$out" ]]; then
        echo "  + $(basename "$out") ($(_size_kb "$out") KB)"
    else
        rm -f "$out"
        echo "  ~ skipped: HEIC (libheif not available in ImageMagick)"
    fi
fi

echo ""
echo "Done. Samples directory: $SAMPLES_DIR"
ls "$SAMPLES_DIR" 2>/dev/null
