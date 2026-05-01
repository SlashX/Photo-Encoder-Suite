#!/usr/bin/env bash
# ============================================================================
# photo_build_ultrahdr.sh — Compileaza libultrahdr cross-platform
# ============================================================================
# Produce: ultrahdr_app — tool-ul necesar pentru --uhdr decode / convert*
# Platforme suportate: Termux (Android), Linux, macOS
# Durata: ~2-5 minute (telefon) / ~1-2 minute (desktop modern)
#
# Locatii install:
#   - Termux:      $PREFIX/bin/ultrahdr_app
#   - Linux/macOS: $TOOLS_DIR/bin/ultrahdr_app  (langa scripturi, paritate PS1)
# ============================================================================

set -euo pipefail

# ── Cross-platform foundation ───────────────────────────────────────────────
# Rezolva symlinks (cross-platform: GNU + BSD readlink, single-hop loop)
_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
    _dir="$(cd "$(dirname "$_self")" && pwd)"
    _self="$(readlink "$_self")"
    [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
# Setam PHOTO_SCRIPT_DIR ca parintele tools/ ca paths sa rezolve la src/
PHOTO_SCRIPT_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
COMMON_PATH="$PHOTO_SCRIPT_DIR/photo_common.sh"
unset _self _dir
if [[ ! -f "$COMMON_PATH" ]]; then
    echo "[ERROR] photo_common.sh nu a fost gasit: $COMMON_PATH" >&2
    echo "        Acest script trebuie pus in src/tools/, alaturi de src/photo_common.sh" >&2
    exit 1
fi
# shellcheck source=../photo_common.sh
source "$COMMON_PATH"

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}  Build libultrahdr — ${PHOTO_OS_LABEL}${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Pasul 1: Verifica / instaleaza dependinte ───────────────────────────────
echo -e "${GREEN}[1/5]${NC} Verificare dependinte (git, cmake, clang, ninja, libjpeg-turbo)..."

case "$PHOTO_PLATFORM" in
    termux)
        pkg update -y 2>/dev/null
        pkg install -y git cmake clang ninja libjpeg-turbo 2>/dev/null
        ;;
    macos)
        # Verifica brew
        if ! command -v brew &>/dev/null; then
            echo -e "${RED}[ERROR]${NC} Homebrew nu e instalat."
            echo "  Instaleaza: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
        # Xcode CLI Tools (clang)
        if ! command -v clang &>/dev/null; then
            echo -e "${YELLOW}  Xcode CLI Tools lipsesc — ruleaza: xcode-select --install${NC}"
            echo "  Apoi reia scriptul."
            exit 1
        fi
        echo -e "${GRAY}  Verific cmake / ninja prin brew (instaleaza daca lipsesc)...${NC}"
        for pkg in cmake ninja jpeg-turbo; do
            if ! brew list "$pkg" &>/dev/null; then
                echo -e "${GRAY}  Instalez $pkg...${NC}"
                brew install "$pkg" 2>&1 | tail -3
            fi
        done
        ;;
    linux)
        # Detect package manager si sugereaza
        if command -v apt &>/dev/null; then
            for pkg in git cmake clang ninja-build libjpeg-turbo8-dev; do
                if ! dpkg -s "$pkg" &>/dev/null; then
                    echo -e "${YELLOW}  Lipseste pachetul $pkg.${NC}"
                    echo "  Instaleaza: sudo apt install git cmake clang ninja-build libjpeg-turbo8-dev"
                    echo "  (apoi reia scriptul)"
                    exit 1
                fi
            done
        elif command -v dnf &>/dev/null; then
            for pkg in git cmake clang ninja-build libjpeg-turbo-devel; do
                if ! rpm -q "$pkg" &>/dev/null; then
                    echo -e "${YELLOW}  Lipseste pachetul $pkg.${NC}"
                    echo "  Instaleaza: sudo dnf install git cmake clang ninja-build libjpeg-turbo-devel"
                    exit 1
                fi
            done
        elif command -v pacman &>/dev/null; then
            for pkg in git cmake clang ninja libjpeg-turbo; do
                if ! pacman -Qi "$pkg" &>/dev/null; then
                    echo -e "${YELLOW}  Lipseste pachetul $pkg.${NC}"
                    echo "  Instaleaza: sudo pacman -S git cmake clang ninja libjpeg-turbo"
                    exit 1
                fi
            done
        else
            echo -e "${YELLOW}[WARN]${NC} Distributie Linux necunoscuta. Asigura-te ca ai:"
            echo "  git, cmake, clang, ninja, libjpeg-turbo (devel package)"
        fi
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Platforma nesuportata: $PHOTO_PLATFORM"
        exit 1
        ;;
esac

# Verifica
for tool in git cmake clang ninja; do
    if ! command -v $tool &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} '$tool' nu se gaseste in PATH."
        photo_pkg_install_hint "$tool" "$tool" "$tool" "$tool" "$tool" "$tool"
        exit 1
    fi
done
echo -e "${GREEN}  OK${NC} — git, cmake, clang, ninja prezente"
echo ""

# ── Pasul 2: Cloneaza repository ────────────────────────────────────────────
BUILD_DIR="$HOME/libultrahdr_build"

if [[ -d "$BUILD_DIR/libultrahdr" ]]; then
    echo -e "${YELLOW}[2/5]${NC} Repository exista deja, actualizez..."
    cd "$BUILD_DIR/libultrahdr"
    git pull --ff-only 2>/dev/null || {
        echo -e "${YELLOW}  Pull failed, reclonez...${NC}"
        cd "$HOME"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"
        git clone https://github.com/google/libultrahdr.git
    }
else
    echo -e "${GREEN}[2/5]${NC} Clonare repository..."
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    git clone https://github.com/google/libultrahdr.git
fi

cd "$BUILD_DIR/libultrahdr"
echo -e "${GREEN}  OK${NC} — $(git log --oneline -1)"
echo ""

# ── Pasul 3: Configureaza build ─────────────────────────────────────────────
echo -e "${GREEN}[3/5]${NC} Configurare CMake..."
rm -rf build 2>/dev/null
mkdir build && cd build

cmake -G Ninja \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DUHDR_BUILD_DEPS=0 \
    -DUHDR_BUILD_TESTS=0 \
    -DUHDR_BUILD_BENCHMARK=0 \
    -DUHDR_BUILD_FUZZERS=0 \
    .. 2>&1 | tail -5

echo -e "${GREEN}  OK${NC}"
echo ""

# ── Pasul 4: Compileaza ─────────────────────────────────────────────────────
echo -e "${GREEN}[4/5]${NC} Compilare... (poate dura 1-5 minute)"
ninja 2>&1 | tail -3

if [[ ! -f "ultrahdr_app" ]]; then
    echo -e "${RED}[ERROR]${NC} Compilare esuata. ultrahdr_app nu exista."
    echo "  Ruleaza manual: cd $BUILD_DIR/libultrahdr/build && ninja"
    exit 1
fi

echo -e "${GREEN}  OK${NC} — ultrahdr_app compilat"
echo ""

# ── Pasul 5: Instaleaza ─────────────────────────────────────────────────────
echo -e "${GREEN}[5/5]${NC} Instalare..."

if [[ "$PHOTO_PLATFORM" == "termux" ]]; then
    INSTALL_DEST="$PREFIX/bin/ultrahdr_app"
    cp ultrahdr_app "$INSTALL_DEST"
    chmod +x "$INSTALL_DEST"
else
    # Linux / macOS — instaleaza in $TOOLS_DIR/bin/ (langa scripturi)
    mkdir -p "$TOOLS_DIR/bin"
    INSTALL_DEST="$TOOLS_DIR/bin/ultrahdr_app"
    cp ultrahdr_app "$INSTALL_DEST"
    chmod +x "$INSTALL_DEST"
fi

# Verifica (re-source common.sh ca PATH sa includa $TOOLS_DIR/bin/ pentru detect)
unset PHOTO_COMMON_LOADED
source "$COMMON_PATH"

if command -v ultrahdr_app &>/dev/null; then
    echo -e "${GREEN}  OK${NC} — ultrahdr_app instalat: ${INSTALL_DEST}"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  BUILD COMPLET!${NC}"
    echo -e "${WHITE}  ultrahdr_app este acum disponibil.${NC}"
    echo -e "${WHITE}  Folosire: photo_encoder.sh --uhdr decode${NC}"
    echo -e "${WHITE}  Sau:      photo_encoder.sh --uhdr convert${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${YELLOW}[WARN]${NC} ultrahdr_app instalat la $INSTALL_DEST dar nu e gasit in PATH."
    if [[ "$PHOTO_PLATFORM" != "termux" ]]; then
        echo "  Va fi gasit automat de photo_encoder.sh prin photo_common.sh (PATH-ul include $TOOLS_DIR/bin)."
        echo "  Daca vrei sa-l accesezi din shell direct: export PATH=\"$TOOLS_DIR/bin:\$PATH\""
    fi
fi

# ── Cleanup info ────────────────────────────────────────────────────────────
echo ""
echo -e "${GRAY}  Sursa ramane in: $BUILD_DIR/libultrahdr/${NC}"
echo -e "${GRAY}  Pentru stergere: rm -rf $BUILD_DIR${NC}"
echo ""
