#!/usr/bin/env bash
# ==============================================================================
# Android Ultimate Flasher - Professional Setup Script
# Crafted for Global Termux Users
# ==============================================================================

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# Colors for professional UI logs
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${BLUE}[*]${RESET} Initializing Android Ultimate Flasher setup..."

# 1. Update and install core dependencies robustly
echo -e "${BLUE}[*]${RESET} Checking and installing required packages (git, curl, android-tools, termux-api, unzip)..."
pkg update -y >/dev/null 2>&1 || true

if ! pkg install -y git curl android-tools termux-api unzip >/dev/null 2>&1; then
    echo -e "${YELLOW}[!]${RESET} Standard installation encountered an issue. Performing full system upgrade & fix..."
    pkg update -y && pkg full-upgrade -y || true
    apt --fix-broken install -y || true
    pkg install -y git curl android-tools termux-api unzip || {
        echo -e "${RED}[-]${RESET} Critical error: Failed to install required packages. Check your internet connection."
        exit 1
    }
fi

# 2. Setup hidden configuration directory
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
mkdir -p "$BASE_DIR"

# 3. Locate, verify, and copy the main script files safely
TARGET_SCRIPT="$BASE_DIR/flasher.sh"
SOURCE_FOUND=0

# Check if running from cloned git repo containing the main script
for f in "android_flasher_v1.0.sh" "android_flasher.sh" "setup.sh"; do
    if [ -f "$f" ] && grep -q "Android Ultimate Flasher" "$f" 2>/dev/null; then
        if [ "$(realpath "$f")" != "$(realpath "$0")" ]; then
            cp "$f" "$TARGET_SCRIPT"
            SOURCE_FOUND=1
            break
        fi
    fi
done

# If not found locally in the repo, download directly from GitHub raw as a fail-safe
if [ "$SOURCE_FOUND" -eq 0 ] || [ ! -s "$TARGET_SCRIPT" ]; then
    echo -e "${BLUE}[*]${RESET} Fetching core components from repository..."
    curl -fsSL "https://raw.githubusercontent.com/rudra1212a/android-ultimate-flasher/main/android_flasher_v1.0.sh" -o "$TARGET_SCRIPT" 2>/dev/null || true
fi

# Ultimate Fallback: if target script is still empty, copy the running script itself if valid
if [ ! -s "$TARGET_SCRIPT" ] && grep -q "Android Ultimate Flasher" "$0" 2>/dev/null; then
    cp "$0" "$TARGET_SCRIPT"
fi

if [ ! -s "$TARGET_SCRIPT" ]; then
    echo -e "${RED}[-]${RESET} Error: Could not locate or download the main program file."
    exit 1
fi

chmod +x "$TARGET_SCRIPT"

# 4. Create global executable shortcut command 'rudra'
BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
mkdir -p "$BIN_DIR"

if [ -f "$TARGET_SCRIPT" ]; then
    ln -sf "$TARGET_SCRIPT" "$BIN_DIR/rudra"
    chmod +x "$BIN_DIR/rudra"
    
    echo ""
    echo -e "${GREEN}[+]${RESET} ========================================================"
    echo -e "${GREEN}[+]${RESET} ${BOLD}Android Ultimate Flasher Installed Successfully!${RESET}"
    echo -e "${GREEN}[+]${RESET} You can now type: ${BOLD}rudra${RESET} anywhere in Termux to launch."
    echo -e "${GREEN}[+]${RESET} ========================================================"
else
    echo -e "${RED}[-]${RESET} Error: Failed to link global command."
    exit 1
fi
