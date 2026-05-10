#!/usr/bin/env bash
# Encode 1 sample (PNG -> AVIF) end-to-end via photo_encoder.sh.
# Skip gracefully when ImageMagick / sample / output format unavailable.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ENCODER="$PROJECT_ROOT/src/photo_encoder.sh"
FIXTURES="$PROJECT_ROOT/tests/fixtures/samples"

[[ -f "$ENCODER" ]] || { echo "encoder missing: $ENCODER" >&2; exit 1; }

# Need ImageMagick for the encoder itself
if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
    skip_test "ImageMagick not installed"
fi

# Need a sample PNG (run generate_samples first)
SAMPLE="$FIXTURES/test_256.png"
if [[ ! -f "$SAMPLE" ]]; then
    skip_test "sample PNG missing — run tests/fixtures/generate_samples.sh first"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
INDIR="$WORK/in"
OUTDIR="$WORK/out"
mkdir -p "$INDIR" "$OUTDIR"
cp "$SAMPLE" "$INDIR/"

# Run encoder: PNG -> AVIF, web preset
LOG="$WORK/encoder.log"
bash "$ENCODER" -i "$INDIR" -o "$OUTDIR" -f avif -p web -q 70 > "$LOG" 2>&1
rc=$?

# Encoder may exit nonzero if AVIF output isn't supported by the local
# ImageMagick build — treat that as a skip rather than a hard failure.
if [[ $rc -ne 0 ]]; then
    if grep -qE "(no encode delegate|delegate.*avif|cannot write)" "$LOG"; then
        skip_test "ImageMagick lacks AVIF write support"
    fi
    echo "encoder log tail:"
    tail -20 "$LOG"
fi

assert_zero "$rc" "encoder exit 0"

# Output file should exist (PNG -> AVIF rename)
out_file=$(find "$OUTDIR" -maxdepth 5 -name "*.avif" -type f | head -1)
assert_file_exists "$out_file" "AVIF output produced"

# Sanity: file is non-empty
if [[ -f "$out_file" ]]; then
    sz=$(stat -c%s "$out_file" 2>/dev/null || stat -f%z "$out_file" 2>/dev/null)
    [[ "$sz" -gt 100 ]] && _pass || _fail "AVIF output too small: ${sz:-0} bytes"
fi
