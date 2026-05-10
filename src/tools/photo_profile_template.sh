#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  photo_profile_template.sh — genereaza UserProfiles/_template.conf
#  cu toate cheile cunoscute + comentarii cu valorile permise.
#
#  Usage:
#    photo_profile_template.sh [--force] [-o <output.conf>]
#    --force / -f   suprascrie daca _template.conf exista
#    -o <path>      output path (default: $USER_PROFILES_DIR/_template.conf)
#  Exit: 0 OK, 1 exista (fara --force), 2 eroare argumente / IO.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# Symlink-safe self resolve (tools/ -> parent = src/)
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
    _dir="$(cd "$(dirname "$_self")" && pwd)"
    _self="$(readlink "$_self")"
    [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
PHOTO_SCRIPT_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
COMMON_PATH="$PHOTO_SCRIPT_DIR/photo_common.sh"
unset _self _dir
[[ -f "$COMMON_PATH" ]] || { echo "  x photo_common.sh negasit: $COMMON_PATH" >&2; exit 2; }
# shellcheck source=../photo_common.sh
source "$COMMON_PATH"

FORCE=0
OUT_FILE="$USER_PROFILES_DIR/_template.conf"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force) FORCE=1; shift ;;
        -o)         OUT_FILE="$2"; shift 2 ;;
        -h|--help)  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "  x argument necunoscut: $1" >&2; exit 2 ;;
    esac
done

if [[ -f "$OUT_FILE" && $FORCE -eq 0 ]]; then
    echo "  ! exista deja: $OUT_FILE (foloseste --force pentru suprascriere)"
    exit 1
fi

# Ordine logica (nu alfabetica) — corespunde cu save_profile_conf().
KEYS=(
    InputDir OutputDir
    Format Quality Preset
    Resize ResizeMode Crop MaxSize Depth HdrMode
    UHDR UHDRGainmapQuality
    DJI DJIBurstGroup DJILut
    DNGPreview StripExif SRGB NoAutoRotate
    WatermarkText WatermarkImage WatermarkPos WatermarkOpacity
    NoRecursive Flat Prefix Suffix
    MinRes SkipDuplicates SkipSimilar SkipSimilarThreshold LosslessJpeg
    ExtractMotion MotionOnly MotionShareable MotionShareableStrict
    SkipExisting Overwrite Verbose Compare
)

# Default-uri sugerate per cheie
default_for() {
    case "$1" in
        InputDir|OutputDir)             echo "" ;;
        Format)                         echo "avif" ;;
        Quality)                        echo "80" ;;
        Preset)                         echo "" ;;
        Resize|Crop|MaxSize|Depth|HdrMode|UHDR|DJI|DJIBurstGroup|DJILut) echo "" ;;
        UHDRGainmapQuality)             echo "" ;;
        ResizeMode)                     echo "fit" ;;
        DNGPreview|StripExif|SRGB|NoAutoRotate) echo "false" ;;
        WatermarkText|WatermarkImage)   echo "" ;;
        WatermarkPos)                   echo "southeast" ;;
        WatermarkOpacity)               echo "30" ;;
        NoRecursive|Flat)               echo "false" ;;
        Prefix|Suffix)                  echo "" ;;
        MinRes)                         echo "" ;;
        SkipDuplicates|SkipSimilar)     echo "false" ;;
        SkipSimilarThreshold)           echo "5" ;;
        LosslessJpeg|ExtractMotion|MotionOnly|MotionShareable|MotionShareableStrict) echo "false" ;;
        SkipExisting|Overwrite|Verbose|Compare) echo "false" ;;
        *) echo "" ;;
    esac
}

# Comentariu human-friendly pentru o schema "TYPE:CONSTRAINT".
schema_to_comment() {
    local schema="$1"
    local stype="${schema%%:*}"
    local sc="${schema#*:}"
    case "$stype" in
        enum)     echo "permise: ${sc}" ;;
        bool)     echo "true | false" ;;
        intrange) echo "intreg in ${sc%,*}..${sc#*,}" ;;
        int)      echo "intreg" ;;
        regex)    echo "pattern: ${sc}" ;;
        path)     echo "path catre fisier (lasa gol pentru a sari)" ;;
        string)   echo "text liber" ;;
        *)        echo "" ;;
    esac
}

mkdir -p "$(dirname "$OUT_FILE")"
{
    echo "# ═══════════════════════════════════════════════════════════════"
    echo "# Photo Encoder UserProfile — TEMPLATE"
    echo "# Generat: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "#"
    echo "# Copiaza/redenumeste acest fisier (ex: my-archive.conf), elimina"
    echo "# # din fata cheilor pe care vrei sa le activezi, si apoi incarca"
    echo "# profilul din meniul interactiv (optiunea 3) sau direct cu"
    echo "#   photo_encoder.sh -i ./input -o ./output --profile my-archive"
    echo "# ═══════════════════════════════════════════════════════════════"
    echo ""
    for key in "${KEYS[@]}"; do
        schema=$(photo_profile_schema_get "$key")
        comment=$(schema_to_comment "$schema")
        default=$(default_for "$key")
        if [[ -n "$comment" ]]; then
            echo "# $key — $comment"
        fi
        echo "#${key}=${default}"
        echo ""
    done
} > "$OUT_FILE"

echo "  + $OUT_FILE"
echo "  Toate cheile sunt comentate. Decomenteaza ce vrei sa setezi."
exit 0
