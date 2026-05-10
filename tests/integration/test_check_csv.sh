#!/usr/bin/env bash
# photo_check.sh -> CSV with 50 fields. Skip when deps / samples missing.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CHECK="$PROJECT_ROOT/src/photo_check.sh"
FIXTURES="$PROJECT_ROOT/tests/fixtures/samples"

[[ -f "$CHECK" ]] || { echo "photo_check missing: $CHECK" >&2; exit 1; }

if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
    skip_test "ImageMagick not installed"
fi
if ! command -v exiftool &>/dev/null; then
    skip_test "exiftool not installed"
fi

SAMPLE="$FIXTURES/test_1024.jpg"
[[ -f "$SAMPLE" ]] || skip_test "sample JPEG missing — run generate_samples.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
INDIR="$WORK/in"
mkdir -p "$INDIR"
cp "$SAMPLE" "$INDIR/"

LOG="$WORK/check.log"
bash "$CHECK" -i "$INDIR" --csv "$WORK/report.csv" > "$LOG" 2>&1
rc=$?
assert_zero "$rc" "photo_check exit 0"
assert_file_exists "$WORK/report.csv" "CSV produced"

if [[ -f "$WORK/report.csv" ]]; then
    header=$(head -1 "$WORK/report.csv")
    # Count commas + 1
    cols=$(awk -F',' 'NR==1{print NF; exit}' "$WORK/report.csv")
    [[ "$cols" -ge 40 ]] && _pass || _fail "CSV has $cols columns, expected >= 40"
    assert_contains "$header" "Filename" "CSV header has Filename"
fi
