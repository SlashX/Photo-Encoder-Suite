#!/usr/bin/env bash
# photo_validate_user_profile — accepts valid, rejects bad enum/regex/intrange.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT_DIR="$PROJECT_ROOT/src"
source "$SCRIPT_DIR/photo_common.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# 1) Valid profile
cat > "$TMPDIR/valid.conf" <<'EOF'
Format=avif
Quality=80
Preset=web
SkipDuplicates=true
WatermarkOpacity=30
EOF
photo_validate_user_profile "$TMPDIR/valid.conf" 2>/dev/null
assert_zero $? "valid profile passes"

# 2) Bad enum
cat > "$TMPDIR/bad_enum.conf" <<'EOF'
Format=avi
EOF
photo_validate_user_profile "$TMPDIR/bad_enum.conf" 2>/dev/null
assert_nonzero $? "bad enum fails"

# 3) intrange out-of-range
cat > "$TMPDIR/bad_range.conf" <<'EOF'
Quality=200
EOF
photo_validate_user_profile "$TMPDIR/bad_range.conf" 2>/dev/null
assert_nonzero $? "out-of-range int fails"

# 4) Bad bool
cat > "$TMPDIR/bad_bool.conf" <<'EOF'
StripExif=yes
EOF
photo_validate_user_profile "$TMPDIR/bad_bool.conf" 2>/dev/null
assert_nonzero $? "non-bool string rejected"

# 5) Unknown key — warning, NOT error
cat > "$TMPDIR/unknown.conf" <<'EOF'
Format=avif
SOME_FUTURE_FIELD=value
EOF
photo_validate_user_profile "$TMPDIR/unknown.conf" 2>/dev/null
assert_zero $? "unknown key not blocking"

# 6) Comments + blanks ignored
cat > "$TMPDIR/comments.conf" <<'EOF'
# header comment
Format=avif

# blank above
Quality=80
EOF
photo_validate_user_profile "$TMPDIR/comments.conf" 2>/dev/null
assert_zero $? "comments + blanks ignored"

# 7) Missing file
photo_validate_user_profile "$TMPDIR/nope.conf" 2>/dev/null
assert_nonzero $? "missing file fails"

# 8) Quoted values
cat > "$TMPDIR/quoted.conf" <<'EOF'
Format="avif"
WatermarkText="© Photo Co"
EOF
photo_validate_user_profile "$TMPDIR/quoted.conf" 2>/dev/null
assert_zero $? "quoted values accepted"
