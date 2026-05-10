#!/usr/bin/env bash
# photo_validate_flag_string + photo_validate_predefined_profiles.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT_DIR="$PROJECT_ROOT/src"
source "$SCRIPT_DIR/photo_common.sh"

# 1) Built-in photo_profiles.conf trebuie sa fie valid integral.
photo_validate_predefined_profiles "$SCRIPT_DIR/profiles/photo_profiles.conf" 2>/dev/null
assert_zero $? "built-in photo_profiles.conf valid"

# 2) Valid hand-written flag string
photo_validate_flag_string "-f jpeg -p social -r 1080 --crop 1:1 --srgb --strip-exif" "good" 2>/dev/null
assert_zero $? "valid flag string accepted"

# 3) Unknown flag
photo_validate_flag_string "-f jpeg --bogus-flag value" "bad1" 2>/dev/null
assert_nonzero $? "unknown flag rejected"

# 4) Bad enum value
photo_validate_flag_string "-f xyz" "bad2" 2>/dev/null
assert_nonzero $? "bad enum value rejected"

# 5) Out-of-range int
photo_validate_flag_string "-q 200" "bad3" 2>/dev/null
assert_nonzero $? "out-of-range quality rejected"

# 6) Missing required value
photo_validate_flag_string "-f" "bad4" 2>/dev/null
assert_nonzero $? "missing value rejected"

# 7) optional-value: --skip-similar without value should pass
photo_validate_flag_string "--skip-similar -p web" "good2" 2>/dev/null
assert_zero $? "--skip-similar without value OK"

# 8) optional-value: --skip-similar with valid number
photo_validate_flag_string "--skip-similar 5 -p web" "good3" 2>/dev/null
assert_zero $? "--skip-similar 5 OK"

# 9) Quoted watermark text
photo_validate_flag_string "-f jpeg -p social --watermark-text \"© COCA\"" "good4" 2>/dev/null
assert_zero $? "quoted watermark text OK"

# 10) Bad predefined file: unknown flag
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/bad.conf" <<'EOF'
demo = -f jpeg --completely-fake-flag x
EOF
photo_validate_predefined_profiles "$TMP/bad.conf" 2>/dev/null
assert_nonzero $? "bad predefined entry rejected"
