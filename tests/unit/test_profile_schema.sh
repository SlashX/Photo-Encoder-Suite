#!/usr/bin/env bash
# photo_profile_schema_get + photo_flag_kind + photo_flag_value_schema.
source "$(dirname "${BASH_SOURCE[0]}")/../framework.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT_DIR="$PROJECT_ROOT/src"
source "$SCRIPT_DIR/photo_common.sh"

# UserProfile schema lookups
schema=$(photo_profile_schema_get "Format")
assert_eq "enum:avif,webp,jpeg,heic,png,jxl" "$schema" "Format enum"

schema=$(photo_profile_schema_get "Quality")
assert_eq "intrange:1,100" "$schema" "Quality intrange"

schema=$(photo_profile_schema_get "Preset")
assert_contains "$schema" "web" "Preset includes web"
assert_contains "$schema" "social" "Preset includes social"

schema=$(photo_profile_schema_get "StripExif")
assert_eq "bool:" "$schema" "StripExif bool"

schema=$(photo_profile_schema_get "TOTALLY_BOGUS_KEY_XYZ")
assert_eq "" "$schema" "unknown key returns empty"

schema=$(photo_profile_schema_get "InputDir")
assert_eq "path:" "$schema" "InputDir path"

# Flag kind
assert_eq "value" "$(photo_flag_kind --format)" "--format takes value"
assert_eq "value" "$(photo_flag_kind -f)" "-f takes value"
assert_eq "none" "$(photo_flag_kind --strip-exif)" "--strip-exif boolean"
assert_eq "optional-value" "$(photo_flag_kind --skip-similar)" "--skip-similar optional"
assert_eq "" "$(photo_flag_kind --no-such-flag)" "unknown flag"

# Flag value schema
fs=$(photo_flag_value_schema --uhdr)
assert_contains "$fs" "convert-preserve" "--uhdr accepts convert-preserve"

fs=$(photo_flag_value_schema --depth)
assert_eq "enum:8,10,16" "$fs" "--depth enum"
