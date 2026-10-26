#!/usr/bin/env bash
# ==============================================================================
# Android Ultimate Flasher - Professional Advanced Setup Script
# Version: 1.1 | Crafted for Global Termux Environment
# ==============================================================================

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# ------------------------------ Colors & UI Styles ----------------------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[1;90m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*"; }

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          ANDROID ULTIMATE FLASHER - INSTALLER            ║"
echo "║               Professional Setup Utility                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

log_info "Initializing installation environment..."

# ------------------------------ 1. Dependency Checks --------------------------
log_info "Verifying and updating system package repositories..."

pkg update -y >/dev/null 2>&1 || true

REQUIRED_PKGS=("git" "curl" "android-tools" "termux-api" "unzip")
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    log_warn "Installing missing core packages: ${MISSING_PKGS[*]}..."
    if ! pkg install -y "${MISSING_PKGS[@]}" >/dev/null 2>&1; then
        log_warn "Standard installation failed. Executing full system upgrade & fix..."
        pkg update -y && pkg full-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
        apt --fix-broken install -y || true
        pkg install -y "${MISSING_PKGS[@]}" || {
            log_error "Failed to install required packages. Please check your internet connection."
            exit 1
        }
    fi
fi
log_ok "All core dependencies are installed and verified."

# ------------------------------ 2. Environment Setup --------------------------
BASE_DIR="$HOME/.android-ultimate-flasher"
TARGET_SCRIPT="$BASE_DIR/android_flasher_v1.0.sh"

log_info "Configuring application directory at: $BASE_DIR"
mkdir -p "$BASE_DIR"

# ------------------------------ 3. Script Deployment --------------------------
log_info "Locating and deploying the core flashing engine..."

SOURCE_DEPLOYED=0

# Priority A: Check local repository files if run from git clone
for candidate in "android_flasher_v1.0.sh" "android_flasher.sh" "flasher.sh"; do
    if [ -f "$candidate" ] && grep -q "Android Ultimate Flasher" "$candidate" 2>/dev/null; then
        log_info "Found local source file: $candidate"
        cp "$candidate" "$TARGET_SCRIPT"
        SOURCE_DEPLOYED=1
        break
    fi
done

# Priority B: Fallback to direct raw download from GitHub if local file is missing
if [ "$SOURCE_DEPLOYED" -eq 0 ] || [ ! -s "$TARGET_SCRIPT" ]; then
    log_warn "Local source not found. Fetching directly from official GitHub repository..."
    RAW_URL="https://raw.githubusercontent.com/rudra1212a/android-ultimate-flasher/main/android_flasher_v1.0.sh"
    
    if curl -fsSL "$RAW_URL" -o "$TARGET_SCRIPT"; then
        SOURCE_DEPLOYED=1
    else
        log_error "Failed to download core script from remote repository."
        exit 1
    fi
fi

# ------------------------------ 4. Integrity Validation -----------------------
if [ ! -s "$TARGET_SCRIPT" ]; then
    log_error "Deployment validation failed: Target program file is empty or corrupted."
    exit 1
fi

chmod +x "$TARGET_SCRIPT"
log_ok "Core flashing engine deployed and permissions configured successfully."

# ------------------------------ 5. Global Command Linking ---------------------
log_info "Creating global executable shortcut..."

BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
mkdir -p "$BIN_DIR"

SYM_LINK="$BIN_DIR/rudra"

# Clean up any broken links
if [ -L "$SYM_LINK" ] || [ -f "$SYM_LINK" ]; then
    rm -f "$SYM_LINK"
fi

if ln -sf "$TARGET_SCRIPT" "$SYM_LINK"; then
    chmod +x "$SYM_LINK"
    log_ok "Global command '${BOLD}rudra${RESET}' linked successfully."
else
    log_error "Failed to create global command link in $BIN_DIR."
    exit 1
fi

# ------------------------------ 6. Final Success Screen -----------------------
echo ""
echo -e "${GREEN}┌──────────────────────────────────────────────────────────┐${RESET}"
echo -e "${GREEN}│          INSTALLATION COMPLETED SUCCESSFULLY!            │${RESET}"
echo -e "${GREEN}└──────────────────────────────────────────────────────────┘${RESET}"
echo -e " You can now launch the tool from anywhere in Termux by typing:"
echo -e ""
echo -e "                   ${BOLD}${CYAN}rudra${RESET}"
echo -e ""
echo -e "${GRAY} Repository: https://github.com/rudra1212a/android-ultimate-flasher${RESET}"
echo -e "${GRAY} Author: Rudra (Crafted for Android & Termux)${RESET}"
echo ""
