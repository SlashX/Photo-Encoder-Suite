#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# photo_build_ultrahdr.sh — Compileaza libultrahdr pe Termux (Android)
# ============================================================================
# Produce: ultrahdr_app — tool-ul necesar pentru --uhdr decode
# Durata: ~2-5 minute pe telefon modern
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}  Build libultrahdr — Termux${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Pasul 1: Instaleaza dependinte ───────────────────────────────────────────
echo -e "${GREEN}[1/5]${NC} Instalare dependinte..."
pkg update -y 2>/dev/null
pkg install -y git cmake clang ninja libjpeg-turbo 2>/dev/null

# Verifica
for tool in git cmake clang ninja; do
    if ! command -v $tool &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} $tool nu s-a instalat. Ruleaza manual: pkg install $tool"
        exit 1
    fi
done
echo -e "${GREEN}  OK${NC} — git, cmake, clang, ninja, libjpeg-turbo"
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
echo -e "${GREEN}[4/5]${NC} Compilare... (poate dura 2-5 minute)"
ninja 2>&1 | tail -3

if [[ ! -f "ultrahdr_app" ]]; then
    echo -e "${RED}[ERROR]${NC} Compilare esuata. ultrahdr_app nu exista."
    echo "  Ruleaza manual: cd $BUILD_DIR/libultrahdr/build && ninja"
    exit 1
fi

echo -e "${GREEN}  OK${NC} — ultrahdr_app compilat"
echo ""

# ── Pasul 5: Instaleaza in PATH ─────────────────────────────────────────────
echo -e "${GREEN}[5/5]${NC} Instalare in PATH..."
cp ultrahdr_app "$PREFIX/bin/"
chmod +x "$PREFIX/bin/ultrahdr_app"

# Verifica
if command -v ultrahdr_app &>/dev/null; then
    echo -e "${GREEN}  OK${NC} — ultrahdr_app instalat in $PREFIX/bin/"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  BUILD COMPLET!${NC}"
    echo -e "${WHITE}  ultrahdr_app este acum disponibil in PATH.${NC}"
    echo -e "${WHITE}  Poti folosi: photo_encoder.sh --uhdr decode${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
else
    echo -e "${RED}[ERROR]${NC} ultrahdr_app nu e in PATH."
    echo "  Copiaza manual: cp $BUILD_DIR/libultrahdr/build/ultrahdr_app \$PREFIX/bin/"
    exit 1
fi

# ── Cleanup optional ─────────────────────────────────────────────────────────
echo ""
echo -e "${GRAY}  Sursa ramane in: $BUILD_DIR/libultrahdr/${NC}"
echo -e "${GRAY}  Pentru stergere: rm -rf $BUILD_DIR${NC}"
echo ""
