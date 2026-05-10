#!/usr/bin/env bash
# Tests pentru helpers din photo_common.sh: detect_platform, GNU/BSD wrappers.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT_DIR="$PROJECT_ROOT/src"
source "$SCRIPT_DIR/photo_common.sh"

# Platform detection
assert_match "$PHOTO_PLATFORM" "^(termux|linux|macos)$"
assert_match "$PHOTO_OS_LABEL" "^(Termux|Linux|macOS)"

# Path resolution: must produce existing source paths
assert_dir_exists "$PHOTO_SCRIPT_DIR" "PHOTO_SCRIPT_DIR exists"
assert_match "$PHOTO_SCRIPT_DIR" "src$" "PHOTO_SCRIPT_DIR ends in src"

# nproc
np=$(photo_nproc)
assert_match "$np" "^[0-9]+$" "photo_nproc returns integer"
[[ "$np" -ge 1 ]] && _pass || _fail "photo_nproc >= 1 (got $np)"

# stat / sed wrappers exist
type photo_stat_size >/dev/null 2>&1 && _pass || _fail "photo_stat_size declared"
type photo_stat_mtime >/dev/null 2>&1 && _pass || _fail "photo_stat_mtime declared"
type photo_sed_inplace >/dev/null 2>&1 && _pass || _fail "photo_sed_inplace declared"
type photo_readlink_f >/dev/null 2>&1 && _pass || _fail "photo_readlink_f declared"
type photo_mktemp_dir >/dev/null 2>&1 && _pass || _fail "photo_mktemp_dir declared"

# stat_size on a known small file
TMP=$(photo_mktemp_dir)
trap 'rm -rf "$TMP"' EXIT
echo -n "abc" > "$TMP/x"
sz=$(photo_stat_size "$TMP/x")
assert_eq "3" "$sz" "stat_size returns 3 for 'abc'"

# sed_inplace
echo "hello world" > "$TMP/y"
photo_sed_inplace "s/world/photo/" "$TMP/y"
content=$(cat "$TMP/y")
assert_eq "hello photo" "$content" "sed_inplace replaces"

# readlink_f
abs=$(photo_readlink_f "$TMP/y")
assert_match "$abs" "y$" "readlink_f returns absolute path"

# Tool detection helpers (no claim about availability — just shouldn't crash)
photo_has_imagemagick >/dev/null 2>&1; _pass
photo_has_exiftool   >/dev/null 2>&1; _pass
photo_has_ffmpeg     >/dev/null 2>&1; _pass

# Schema function actually used by validation
type photo_profile_schema_get >/dev/null 2>&1 && _pass || _fail "photo_profile_schema_get declared"
type photo_validate_user_profile >/dev/null 2>&1 && _pass || _fail "photo_validate_user_profile declared"
type photo_validate_predefined_profiles >/dev/null 2>&1 && _pass || _fail "photo_validate_predefined_profiles declared"
