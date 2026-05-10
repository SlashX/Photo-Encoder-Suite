#!/usr/bin/env bash
# photo_profile_diff.sh — predefined + user mode.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DIFF="$PROJECT_ROOT/src/tools/photo_profile_diff.sh"
PRED_FILE="$PROJECT_ROOT/src/profiles/photo_profiles.conf"

[[ -x "$DIFF" || -f "$DIFF" ]] || { echo "tool missing: $DIFF" >&2; exit 1; }

# 1) predefined: instagram vs facebook -> exit 1, mentions --crop / -r
out=$(bash "$DIFF" --predefined instagram facebook 2>&1); rc=$?
assert_eq 1 "$rc" "predefined diff exit=1 (different)"
assert_contains "$out" "Profile diff (predefined)" "predefined header"
assert_contains "$out" "instagram" "mentions instagram"
assert_contains "$out" "facebook" "mentions facebook"

# 2) predefined identical: same name compared with itself -> exit 0
out=$(bash "$DIFF" --predefined instagram instagram 2>&1); rc=$?
assert_eq 0 "$rc" "predefined identical exit=0"
assert_contains "$out" "identice" "identical message"

# 3) predefined: missing profile name -> exit 2
out=$(bash "$DIFF" --predefined instagram nonexistent_xyz 2>&1); rc=$?
assert_eq 2 "$rc" "missing predefined name exit=2"

# 4) user mode: two KEY=VALUE files with diffs
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/a.conf" <<'EOF'
Format=avif
Quality=80
Preset=web
EOF
cat > "$TMP/b.conf" <<'EOF'
Format=jpeg
Quality=80
Preset=social
StripExif=true
EOF
out=$(bash "$DIFF" "$TMP/a.conf" "$TMP/b.conf" 2>&1); rc=$?
assert_eq 1 "$rc" "user diff exit=1"
assert_contains "$out" "Profile diff (user)" "user header"
assert_contains "$out" "Format" "shows differing key Format"
assert_contains "$out" "StripExif" "shows only-in-B key StripExif"

# 5) user mode: identical files -> exit 0
cp "$TMP/a.conf" "$TMP/aa.conf"
out=$(bash "$DIFF" "$TMP/a.conf" "$TMP/aa.conf" 2>&1); rc=$?
assert_eq 0 "$rc" "identical user files exit=0"
