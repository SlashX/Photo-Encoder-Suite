#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  photo_profile_diff.sh — compara doua profile Photo Encoder
# ═══════════════════════════════════════════════════════════════
# Usage:
#   photo_profile_diff.sh <fileA.conf> <fileB.conf>
#       Diff intre doua UserProfiles (KEY=VALUE format).
#
#   photo_profile_diff.sh --predefined <nameA> <nameB> [--file <profiles.conf>]
#       Diff intre doua entries din photo_profiles.conf (flag bundles).
#       Default --file: <repo>/src/profiles/photo_profiles.conf.
#
# Exit codes: 0 identice, 1 difera, 2 eroare argumente / fisier lipsa.
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
unset _self _dir

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

[[ $# -lt 2 ]] && usage

# Optional --predefined mode
MODE="user"
PRED_FILE="$PHOTO_SCRIPT_DIR/profiles/photo_profiles.conf"
ARG_A=""
ARG_B=""

if [[ "$1" == "--predefined" ]]; then
    MODE="predefined"
    shift
    [[ $# -lt 2 ]] && usage
    ARG_A="$1"
    ARG_B="$2"
    shift 2
    if [[ $# -gt 0 ]]; then
        if [[ "$1" == "--file" && -n "${2:-}" ]]; then
            PRED_FILE="$2"
            shift 2
        else
            echo "  x argument necunoscut: $1" >&2
            usage
        fi
    fi
else
    ARG_A="$1"
    ARG_B="$2"
fi

# ── Mode 1: predefined ──────────────────────────────────────────────────────
extract_predefined_flags() {
    local file="$1" want="$2" line name flags
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            flags="${BASH_REMATCH[2]}"
            flags="${flags%"${flags##*[![:space:]]}"}"
            if [[ "$name" == "$want" ]]; then
                echo "$flags"
                return 0
            fi
        fi
    done < "$file"
    return 1
}

# Tokenize flag string into "key value" pairs (or "key <NONE>" for booleans).
# Echoes one "KEY\tVALUE" per line.
tokenize_flag_pairs() {
    local flagstr="$1"
    local -a tokens
    eval "tokens=($flagstr)" 2>/dev/null || return 1
    local i=0 n=${#tokens[@]} tok next
    while [[ $i -lt $n ]]; do
        tok="${tokens[$i]}"
        if [[ ! "$tok" =~ ^- ]]; then
            i=$((i+1))
            continue
        fi
        next="${tokens[$((i+1))]:-}"
        if [[ -z "$next" || "$next" == -* ]]; then
            printf '%s\t<NONE>\n' "$tok"
            i=$((i+1))
        else
            printf '%s\t%s\n' "$tok" "$next"
            i=$((i+2))
        fi
    done
}

if [[ "$MODE" == "predefined" ]]; then
    [[ ! -f "$PRED_FILE" ]] && { echo "  x Profil inexistent: $PRED_FILE" >&2; exit 2; }
    flagsA=$(extract_predefined_flags "$PRED_FILE" "$ARG_A") || {
        echo "  x Profilul '$ARG_A' nu exista in $PRED_FILE" >&2; exit 2; }
    flagsB=$(extract_predefined_flags "$PRED_FILE" "$ARG_B") || {
        echo "  x Profilul '$ARG_B' nu exista in $PRED_FILE" >&2; exit 2; }

    echo "════════════════════════════════════════════════════════════"
    echo "  Profile diff (predefined)"
    echo "    A: $ARG_A"
    echo "    B: $ARG_B"
    echo "    File: $PRED_FILE"
    echo "════════════════════════════════════════════════════════════"

    declare -A MAP_A MAP_B
    declare -a ORDER_A ORDER_B
    while IFS=$'\t' read -r k v; do
        [[ -z "$k" ]] && continue
        MAP_A["$k"]="$v"
        ORDER_A+=("$k")
    done < <(tokenize_flag_pairs "$flagsA")
    while IFS=$'\t' read -r k v; do
        [[ -z "$k" ]] && continue
        MAP_B["$k"]="$v"
        ORDER_B+=("$k")
    done < <(tokenize_flag_pairs "$flagsB")

    only_a=(); only_b=(); diff_keys=()
    for k in "${ORDER_A[@]}"; do
        [[ -z "${MAP_B[$k]+x}" ]] && only_a+=("$k")
    done
    for k in "${ORDER_B[@]}"; do
        [[ -z "${MAP_A[$k]+x}" ]] && only_b+=("$k")
    done
    for k in "${ORDER_A[@]}"; do
        if [[ -n "${MAP_B[$k]+x}" ]] && [[ "${MAP_A[$k]}" != "${MAP_B[$k]}" ]]; then
            diff_keys+=("$k")
        fi
    done

    if [[ ${#only_a[@]} -gt 0 ]]; then
        echo ""
        echo "── Doar in A ($ARG_A) ──"
        for k in "${only_a[@]}"; do printf "  %-25s %s\n" "$k" "${MAP_A[$k]}"; done
    fi
    if [[ ${#only_b[@]} -gt 0 ]]; then
        echo ""
        echo "── Doar in B ($ARG_B) ──"
        for k in "${only_b[@]}"; do printf "  %-25s %s\n" "$k" "${MAP_B[$k]}"; done
    fi
    if [[ ${#diff_keys[@]} -gt 0 ]]; then
        echo ""
        echo "── Valori diferite ──"
        printf "  %-25s %-25s %-25s\n" "FLAG" "A" "B"
        printf "  %-25s %-25s %-25s\n" "---" "---" "---"
        for k in "${diff_keys[@]}"; do
            printf "  %-25s %-25s %-25s\n" "$k" "${MAP_A[$k]}" "${MAP_B[$k]}"
        done
    fi
    if [[ ${#only_a[@]} -eq 0 && ${#only_b[@]} -eq 0 && ${#diff_keys[@]} -eq 0 ]]; then
        echo ""
        echo "  Profilele sunt identice."
        exit 0
    fi
    echo ""
    echo "── Sumar ──"
    echo "  Doar in A:        ${#only_a[@]}"
    echo "  Doar in B:        ${#only_b[@]}"
    echo "  Valori diferite:  ${#diff_keys[@]}"
    exit 1
fi

# ── Mode 2: user (KEY=VALUE) ────────────────────────────────────────────────
[[ ! -f "$ARG_A" ]] && { echo "  x Fisier inexistent: $ARG_A" >&2; exit 2; }
[[ ! -f "$ARG_B" ]] && { echo "  x Fisier inexistent: $ARG_B" >&2; exit 2; }

declare -A UMAP_A UMAP_B
declare -a UORDER_A UORDER_B

parse_user_conf() {
    local file="$1" map_name="$2" order_name="$3"
    local lineno=0 key value line
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno+1))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            printf -v "${map_name}[$key]" '%s' "$value"
            eval "$order_name+=(\"\$key\")"
        fi
    done < "$file"
}

parse_user_conf "$ARG_A" UMAP_A UORDER_A
parse_user_conf "$ARG_B" UMAP_B UORDER_B

NAME_A="$(basename "$ARG_A" .conf)"
NAME_B="$(basename "$ARG_B" .conf)"

echo "════════════════════════════════════════════════════════════"
echo "  Profile diff (user)"
echo "    A: $NAME_A  ($ARG_A)"
echo "    B: $NAME_B  ($ARG_B)"
echo "════════════════════════════════════════════════════════════"

uonly_a=(); uonly_b=(); udiff_keys=()
for k in "${UORDER_A[@]}"; do
    [[ -z "${UMAP_B[$k]+x}" ]] && uonly_a+=("$k")
done
for k in "${UORDER_B[@]}"; do
    [[ -z "${UMAP_A[$k]+x}" ]] && uonly_b+=("$k")
done
for k in "${UORDER_A[@]}"; do
    if [[ -n "${UMAP_B[$k]+x}" ]] && [[ "${UMAP_A[$k]}" != "${UMAP_B[$k]}" ]]; then
        udiff_keys+=("$k")
    fi
done

if [[ ${#uonly_a[@]} -gt 0 ]]; then
    echo ""
    echo "── Doar in A ($NAME_A) ──"
    for k in "${uonly_a[@]}"; do printf "  %-25s = \"%s\"\n" "$k" "${UMAP_A[$k]}"; done
fi
if [[ ${#uonly_b[@]} -gt 0 ]]; then
    echo ""
    echo "── Doar in B ($NAME_B) ──"
    for k in "${uonly_b[@]}"; do printf "  %-25s = \"%s\"\n" "$k" "${UMAP_B[$k]}"; done
fi
if [[ ${#udiff_keys[@]} -gt 0 ]]; then
    echo ""
    echo "── Valori diferite ──"
    printf "  %-25s %-30s %-30s\n" "KEY" "A ($NAME_A)" "B ($NAME_B)"
    printf "  %-25s %-30s %-30s\n" "---" "---" "---"
    for k in "${udiff_keys[@]}"; do
        printf "  %-25s %-30s %-30s\n" "$k" "\"${UMAP_A[$k]}\"" "\"${UMAP_B[$k]}\""
    done
fi
if [[ ${#uonly_a[@]} -eq 0 && ${#uonly_b[@]} -eq 0 && ${#udiff_keys[@]} -eq 0 ]]; then
    echo ""
    echo "  Profilele sunt identice."
    exit 0
fi
echo ""
echo "── Sumar ──"
echo "  Doar in A:        ${#uonly_a[@]}"
echo "  Doar in B:        ${#uonly_b[@]}"
echo "  Valori diferite:  ${#udiff_keys[@]}"
exit 1
