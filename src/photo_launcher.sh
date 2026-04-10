#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# photo_launcher.sh — Meniu Interactiv Photo Encoder
# ============================================================================
# Lanseaza photo_encoder.sh cu parametri selectati din meniu.
# Acelasi concept ca launcher.sh (FFmpeg) dar pentru poze.
# ============================================================================

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
ANDROID_DIR="/storage/emulated/0/Media/Scripts"
INPUT_DIR="/storage/emulated/0/Media/InputPhotos"
OUTPUT_DIR="/storage/emulated/0/Media/OutputPhotos"
TOOLS_DIR="/storage/emulated/0/Media/Scripts/tools"
PROFILES_DIR="/storage/emulated/0/Media/Scripts/profiles"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; BLUE='\033[0;34m'; NC='\033[0m'

# ── Check encoder exists ────────────────────────────────────────────────────
ENCODER="${ANDROID_DIR}/photo_encoder.sh"
if [[ ! -f "$ENCODER" ]]; then
    echo -e "${RED}[ERROR]${NC} photo_encoder.sh nu a fost gasit in: $ANDROID_DIR"
    echo "  Asigura-te ca photo_encoder.sh este in acelasi folder cu photo_launcher.sh"
    exit 1
fi

# ── Create folders ───────────────────────────────────────────────────────────
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR"

# ── Functions ────────────────────────────────────────────────────────────────

print_header() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}          Photo Encoder — Meniu Principal                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${GRAY}          Samsung / Google / iPhone / DJI • Ultra HDR        ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Input:  ${WHITE}${INPUT_DIR}${NC}"
    echo -e "  Output: ${WHITE}${OUTPUT_DIR}${NC}"

    # Count files
    local count=0
    for ext in jpg jpeg png heic heif avif webp tiff tif bmp gif; do
        count=$((count + $(find "$INPUT_DIR" -maxdepth 1 -iname "*.${ext}" 2>/dev/null | wc -l)))
    done
    echo -e "  Fisiere: ${WHITE}${count}${NC} imagini in Input"
    echo ""
}

select_format() {
    echo -e "${WHITE}  Format output:${NC}"
    echo -e "    ${GREEN}1)${NC} AVIF  — cel mai eficient, lent (recomandat web)"
    echo -e "    ${GREEN}2)${NC} WEBP  — bun, rapid, universal"
    echo -e "    ${GREEN}3)${NC} JPEG  — universal, compatibil cu orice"
    echo -e "    ${GREEN}4)${NC} HEIC  — standard Apple/Samsung"
    echo -e "    ${GREEN}5)${NC} PNG   — lossless, fisiere mari"
    echo -e "    ${GREEN}6)${NC} JXL   — JPEG XL, calitate superioara, HDR nativ"
    echo ""
    read -p "  Alege format [1-6, default=1 AVIF]: " fmt_choice
    case "${fmt_choice:-1}" in
        1) FORMAT="avif" ;;
        2) FORMAT="webp" ;;
        3) FORMAT="jpeg" ;;
        4) FORMAT="heic" ;;
        5) FORMAT="png" ;;
        6) FORMAT="jxl" ;;
        *) FORMAT="avif" ;;
    esac
    echo -e "  → ${GREEN}${FORMAT^^}${NC}"
    echo ""
}

select_preset() {
    echo -e "${WHITE}  Quality preset:${NC}"
    echo -e "    ${GREEN}1)${NC} web      — optimizat web (fisiere mici)"
    echo -e "    ${GREEN}2)${NC} social   — social media (Instagram, WhatsApp)"
    echo -e "    ${GREEN}3)${NC} archive  — arhivare calitate inalta"
    echo -e "    ${GREEN}4)${NC} print    — print maxim calitate"
    echo -e "    ${GREEN}5)${NC} custom   — alege quality manual (1-100)"
    echo ""
    read -p "  Alege preset [1-5, default=1 web]: " preset_choice
    case "${preset_choice:-1}" in
        1) PRESET="web"; QUALITY_FLAG="-p web" ;;
        2) PRESET="social"; QUALITY_FLAG="-p social" ;;
        3) PRESET="archive"; QUALITY_FLAG="-p archive" ;;
        4) PRESET="print"; QUALITY_FLAG="-p print" ;;
        5)
            read -p "  Quality (1-100) [80]: " custom_q
            PRESET="custom"
            QUALITY_FLAG="-q ${custom_q:-80}"
            ;;
        *) PRESET="web"; QUALITY_FLAG="-p web" ;;
    esac
    echo -e "  → ${GREEN}${PRESET}${NC}"
    echo ""
}

select_resize() {
    echo -e "${WHITE}  Resize:${NC}"
    echo -e "    ${GREEN}1)${NC} Pastreaza originala [default]"
    echo -e "    ${GREEN}2)${NC} 3840  — 4K UHD"
    echo -e "    ${GREEN}3)${NC} 1920  — Full HD"
    echo -e "    ${GREEN}4)${NC} 1080  — Social media"
    echo -e "    ${GREEN}5)${NC} 800   — Web thumbnail"
    echo -e "    ${GREEN}6)${NC} Custom"
    echo ""
    read -p "  Alege resize [1-6, default=1]: " resize_choice
    case "${resize_choice:-1}" in
        1) RESIZE_FLAG="" ;;
        2) RESIZE_FLAG="-r 3840" ;;
        3) RESIZE_FLAG="-r 1920" ;;
        4) RESIZE_FLAG="-r 1080" ;;
        5) RESIZE_FLAG="-r 800" ;;
        6)
            read -p "  Width (px): " custom_w
            RESIZE_FLAG="-r ${custom_w:-1920}"
            ;;
        *) RESIZE_FLAG="" ;;
    esac
    [[ -n "$RESIZE_FLAG" ]] && echo -e "  → ${GREEN}Resize: ${RESIZE_FLAG#-r }px${NC}" || echo -e "  → ${GREEN}Fara resize${NC}"
    echo ""
}

select_crop() {
    echo -e "${WHITE}  Crop aspect ratio:${NC}"
    echo -e "    ${GREEN}1)${NC} Fara crop [default]"
    echo -e "    ${GREEN}2)${NC} 1:1   — patrat (Instagram)"
    echo -e "    ${GREEN}3)${NC} 16:9  — landscape (YouTube)"
    echo -e "    ${GREEN}4)${NC} 9:16  — portrait (Stories/Reels)"
    echo -e "    ${GREEN}5)${NC} 4:3   — clasic"
    echo -e "    ${GREEN}6)${NC} 3:2   — DSLR standard"
    echo ""
    read -p "  Alege crop [1-6, default=1]: " crop_choice
    case "${crop_choice:-1}" in
        1) CROP_FLAG="" ;;
        2) CROP_FLAG="--crop 1:1" ;;
        3) CROP_FLAG="--crop 16:9" ;;
        4) CROP_FLAG="--crop 9:16" ;;
        5) CROP_FLAG="--crop 4:3" ;;
        6) CROP_FLAG="--crop 3:2" ;;
        *) CROP_FLAG="" ;;
    esac
    [[ -n "$CROP_FLAG" ]] && echo -e "  → ${GREEN}Crop: ${CROP_FLAG#--crop }${NC}" || echo -e "  → ${GREEN}Fara crop${NC}"
    echo ""
}

select_extras() {
    EXTRA_FLAGS=""

    read -p "  Sterge EXIF/GPS? (d/N) [N]: " strip_exif
    [[ "${strip_exif,,}" == "d" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --strip-exif"

    read -p "  Converteste la sRGB? (d/N) [N]: " srgb
    [[ "${srgb,,}" == "d" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --srgb"

    read -p "  Watermark text? (Enter = fara): " wm_text
    [[ -n "$wm_text" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --watermark-text \"$wm_text\""

    read -p "  Max file size? (ex: 500k, 2m, Enter = fara): " max_size
    [[ -n "$max_size" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --max-size $max_size"

    read -p "  Skip duplicati? (d/N) [N]: " skip_dupes
    [[ "${skip_dupes,,}" == "d" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --skip-duplicates"

    read -p "  Min resolution filter? (px, Enter = fara): " min_res
    [[ -n "$min_res" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --min-res $min_res"

    read -p "  Prefix filename? (Enter = fara): " prefix
    [[ -n "$prefix" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --prefix \"$prefix\""

    read -p "  Suffix filename? (Enter = fara): " suffix
    [[ -n "$suffix" ]] && EXTRA_FLAGS="$EXTRA_FLAGS --suffix \"$suffix\""

    echo ""
}

select_uhdr_action() {
    echo -e "${WHITE}  Ultra HDR actiune:${NC}"
    echo -e "    ${GREEN}1)${NC} Detect    — detecteaza UHDR, afiseaza info (fara conversie)"
    echo -e "    ${GREEN}2)${NC} Info      — info detaliat UHDR per fisier"
    echo -e "    ${GREEN}3)${NC} Strip     — sterge gain map (JPEG mai mic, SDR only)"
    echo -e "    ${GREEN}4)${NC} Extract   — extrage gain map ca imagine separata"
    echo -e "    ${GREEN}5)${NC} Decode    — decodare COMPLETA → HDR AVIF/HEIC 10-bit"
    echo -e "              ${GRAY}(necesita libultrahdr / ultrahdr_app)${NC}"
    echo ""
    read -p "  Alege actiune [1-5]: " uhdr_choice
    case "$uhdr_choice" in
        1) UHDR_FLAG="--uhdr detect" ;;
        2) UHDR_FLAG="--uhdr info" ;;
        3) UHDR_FLAG="--uhdr strip" ;;
        4) UHDR_FLAG="--uhdr extract" ;;
        5) UHDR_FLAG="--uhdr decode" ;;
        *) UHDR_FLAG="--uhdr detect" ;;
    esac
    echo -e "  → ${GREEN}${UHDR_FLAG}${NC}"
    echo ""
}

run_command() {
    local cmd="$1"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  Comanda:${NC}"
    echo -e "  ${GRAY}$cmd${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}D)${NC} Ruleaza normal"
    echo -e "  ${YELLOW}S)${NC} Dry-run (doar analiza, fara conversie)"
    echo -e "  ${RED}N)${NC} Anuleaza"
    echo ""
    read -p "  Alege [D/s/n, implicit=D]: " confirm
    case "${confirm,,}" in
        n) echo -e "${YELLOW}  Anulat.${NC}" ;;
        s) eval "$cmd --dry-run" ;;
        *) eval "$cmd" ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ══════════════════════════════════════════════════════════════════════════════

while true; do
    print_header
    echo -e "  ${WHITE}Optiuni:${NC}"
    echo -e "    ${GREEN}1)${NC} Conversie rapida (format + preset, automat)"
    echo -e "    ${GREEN}2)${NC} Conversie avansata (toate optiunile)"
    echo -e "    ${GREEN}3)${NC} Conversie cu profil (instagram, web, dji, etc.)"
    echo -e "    ${GREEN}4)${NC} Extrage Motion / Live Photo video"
    echo -e "    ${GREEN}5)${NC} Ultra HDR (detect / strip / extract / decode)"
    echo -e "    ${GREEN}6)${NC} DJI (detect / export metadata CSV / privacy strip)"
    echo -e "    ${GREEN}7)${NC} Lossless JPEG optimization"
    echo -e "    ${GREEN}8)${NC} Watch mode (monitorizeaza folder, converteste automat)"
    echo -e "    ${GREEN}9)${NC} Verifica fisiere foto (analiza + CSV 50 campuri)"
    echo -e "    ${GREEN}0)${NC} Iesire"
    echo ""
    read -p "  Alege optiune [0-9]: " main_choice

    case "$main_choice" in
        1)
            # ── Conversie rapida ──────────────────────────────────────────
            echo ""
            select_format
            select_preset
            run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f $FORMAT $QUALITY_FLAG --skip-existing"
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        2)
            # ── Conversie avansata ────────────────────────────────────────
            echo ""
            select_format
            select_preset
            select_resize
            select_crop
            select_extras
            local_cmd="$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f $FORMAT $QUALITY_FLAG $RESIZE_FLAG $CROP_FLAG $EXTRA_FLAGS --skip-existing"
            run_command "$local_cmd"
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        3)
            # ── Profile ───────────────────────────────────────────────────
            echo ""
            echo -e "${WHITE}  Profile disponibile:${NC}"
            conf="${PROFILES_DIR}/photo_profiles.conf"
            if [[ ! -f "$conf" ]]; then
                conf="$HOME/photo_profiles.conf"
            fi
            if [[ -f "$conf" ]]; then
                while IFS= read -r line; do
                    [[ -z "$line" || "$line" == \#* ]] && continue
                    pn="${line%%=*}"; pn="${pn// /}"
                    pa="${line#*=}"; pa="${pa# }"
                    echo -e "    ${GREEN}${pn}${NC} ${GRAY}→ ${pa}${NC}"
                done < "$conf"
            else
                echo -e "    ${RED}photo_profiles.conf nu exista.${NC}"
                echo -e "    ${GRAY}Copiaza-l in: $PROFILES_DIR/${NC}"
            fi
            echo ""
            read -p "  Numele profilului (sau Enter pt anulare): " profile_name
            if [[ -n "$profile_name" ]]; then
                run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" --profile $profile_name --skip-existing"
            fi
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        4)
            # ── Motion / Live Photo ───────────────────────────────────────
            echo ""
            echo -e "${WHITE}  Extragere video din Motion / Live Photo:${NC}"
            echo -e "    ${GREEN}1)${NC} Extrage video + converteste pozele"
            echo -e "    ${GREEN}2)${NC} DOAR extrage video (fara conversie poze)"
            echo ""
            read -p "  Alege [1-2, default=1]: " motion_choice

            if [[ "${motion_choice:-1}" == "2" ]]; then
                run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" --motion-only --skip-existing"
            else
                select_format
                select_preset
                run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f $FORMAT $QUALITY_FLAG -m --skip-existing"
            fi
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        5)
            # ── Ultra HDR ─────────────────────────────────────────────────
            echo ""
            select_uhdr_action

            if [[ "$UHDR_FLAG" == *"decode"* ]]; then
                select_format
                run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f $FORMAT $UHDR_FLAG --depth 10"
            elif [[ "$UHDR_FLAG" == *"strip"* ]]; then
                run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f jpeg $UHDR_FLAG"
            else
                run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" $UHDR_FLAG"
            fi
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        6)
            # ── DJI ───────────────────────────────────────────────────────
            echo ""
            echo -e "${WHITE}  DJI Photo actiune:${NC}"
            echo -e "    ${GREEN}1)${NC} Detect    — detecteaza poze DJI, afiseaza info"
            echo -e "    ${GREEN}2)${NC} Export    — export metadata DJI → CSV"
            echo -e "    ${GREEN}3)${NC} Privacy   — sterge serial number, GPS, device info"
            echo ""
            read -p "  Alege actiune [1-3]: " dji_choice
            case "$dji_choice" in
                1) run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" --dji detect" ;;
                2) run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" --dji export" ;;
                3)
                    select_format
                    run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f $FORMAT --dji privacy-strip"
                    ;;
                *) echo -e "${RED}  Optiune invalida.${NC}" ;;
            esac
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        7)
            # ── Lossless JPEG ─────────────────────────────────────────────
            echo ""
            echo -e "${WHITE}  Lossless JPEG optimization — fara pierdere calitate${NC}"
            echo -e "  ${GRAY}Optimizeaza Huffman tables, sterge metadata. Economia: 5-15%.${NC}"
            echo ""
            run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f jpeg --lossless-jpeg"
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        8)
            # ── Watch Mode ────────────────────────────────────────────────
            echo ""
            echo -e "${WHITE}  Watch mode — monitorizeaza folderul InputPhotos${NC}"
            echo -e "  ${GRAY}Pozele noi sunt convertite automat. Ctrl+C opreste.${NC}"
            echo ""
            select_format
            select_preset
            read -p "  Interval scanare (secunde) [5]: " watch_int
            run_command "$ENCODER -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" -f $FORMAT $QUALITY_FLAG --watch --watch-interval ${watch_int:-5}"
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        9)
            # ── Check Media Photo ─────────────────────────────────────────
            echo ""
            check_script="${ANDROID_DIR}/photo_check.sh"
            if [[ ! -f "$check_script" ]]; then
                echo -e "${RED}  photo_check.sh nu a fost gasit in: $ANDROID_DIR${NC}"
            else
                read -p "  Verbose (toate campurile)? (d/N) [N]: " check_verbose
                check_flags=""
                [[ "${check_verbose,,}" == "d" ]] && check_flags="-v"
                run_command "$check_script -i \"$INPUT_DIR\" -o \"$OUTPUT_DIR\" $check_flags"
            fi
            echo ""
            read -p "  Apasa Enter pentru meniu..." _
            ;;

        0|q|Q)
            echo ""
            echo -e "${GREEN}  La revedere!${NC}"
            echo ""
            exit 0
            ;;

        *)
            echo -e "${RED}  Optiune invalida.${NC}"
            sleep 1
            ;;
    esac
done
