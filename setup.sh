#!/usr/bin/env bash
# ==============================================================================
# Script Name: Android Ultimate Flasher (Optimized & Stable Edition)
# Description: Professional Android flashing tool for Termux
# ==============================================================================

set -uo pipefail

# --- Configuration & Constants ---
VERSION="1.2"
readonly BASE_DIR="$HOME/.android-ultimate-flashing-tool"
readonly LOG_FILE="$BASE_DIR/tool.log"
readonly LAST_OUT="$BASE_DIR/last_output.txt"
readonly DL_DIR="$HOME/storage/downloads"

# Fallback to standard download dir if storage is not linked
if [ ! -d "$DL_DIR" ]; then
    DL_DIR="$HOME/Download"
    mkdir -p "$DL_DIR"
fi

# UI Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[1;90m'
RESET='\033[0m'

mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

log() {
    local level="${1:-INFO}"
    shift || true
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

say()  { echo -e "${BLUE}[*]${RESET} $*"; log "INFO" "$*"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; log "SUCCESS" "$*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; log "WARN" "$*"; }
bad()  { echo -e "${RED}[-]${RESET} $*"; log "ERROR" "$*"; }

pause() {
    echo -e ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo -e ""
}

check_tools() {
    for cmd in fastboot adb; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "$cmd is not installed. Installing platform-tools..."
            pkg update -y && pkg install -y android-tools
            break
        fi
    done
}

fb_var() {
    local var_name="${1:-}"
    local val
    val=$(fastboot getvar "$var_name" 2>&1 | grep -i "$var_name" | head -n1 | awk '{print $2}')
    if [ -z "$val" ]; then
        echo "UNKNOWN"
    else
        echo "$val" | tr -d '\r'
    fi
}

flash_image_screen() {
    clear
    echo "=========================================="
    echo "         FLASH INDIVIDUAL IMAGE (.IMG)    "
    echo "=========================================="
    
    if [ ! -d "$DL_DIR" ]; then
        warn "Download folder not found: $DL_DIR"
        pause
        return
    fi

    local count=0
    echo ""
    shopt -s nullglob
    local imgs=("$DL_DIR"/*.img)
    shopt -u nullglob

    for img in "${imgs[@]}"; do
        if [ -f "$img" ]; then
            echo "  [$((++count))] $(basename "$img")"
        fi
    done

    if [ "$count" -eq 0 ]; then
        warn "No .img files found in Downloads folder."
        pause
        return
    fi

    echo ""
    printf "Select image number (0 to cancel): "
    read -r img_choice

    if [[ ! "$img_choice" =~ ^[0-9]+$ ]] || [ "$img_choice" -le 0 ] || [ "$img_choice" -gt "$count" ]; then
        say "Cancelled."
        pause
        return
    fi

    local selected_img="${imgs[$((img_choice - 1))]}"
    say "Selected: $(basename "$selected_img")"
    
    echo "Common partitions: boot, recovery, vbmeta, dtbo"
    printf "Enter target partition name: "
    read -r target_part

    if [ -z "$target_part" ]; then
        bad "Partition name cannot be empty."
        pause
        return
    fi

    say "Flashing to [$target_part]..."
    if fastboot flash "$target_part" "$selected_img" > "$LAST_OUT" 2>&1; then
        ok "Flashed successfully!"
    else
        bad "Flashing failed! Check last_output.txt for details."
    fi
    pause
}

flash_sideload_screen() {
    clear
    echo "=========================================="
    echo "          ADB SIDELOAD CUSTOM ROM         "
    echo "=========================================="

    local count=0
    echo ""
    shopt -s nullglob
    local zips=("$DL_DIR"/*.zip)
    shopt -u nullglob

    for z in "${zips[@]}"; do
        if [ -f "$z" ]; then
            echo "  [$((++count))] $(basename "$z")"
        fi
    done

    if [ "$count" -eq 0 ]; then
        warn "No .zip files found in Downloads."
        pause
        return
    fi

    echo ""
    printf "Select zip number to sideload (0 to cancel): "
    read -r zip_choice

    if [[ ! "$zip_choice" =~ ^[0-9]+$ ]] || [ "$zip_choice" -le 0 ] || [ "$zip_choice" -gt "$count" ]; then
        say "Cancelled."
        pause
        return
    fi

    local selected_zip="${zips[$((zip_choice - 1))]}"
    say "Starting sideload for $(basename "$selected_zip")..."
    
    if adb sideload "$selected_zip" > "$LAST_OUT" 2>&1; then
        ok "ADB sideload completed successfully!"
    else
        bad "ADB sideload failed."
    fi
    pause
}

device_info_screen() {
    clear
    echo "=========================================="
    echo "            DEVICE INFORMATION            "
    echo "=========================================="
    echo ""
    say "Fetching device variables..."
    echo "------------------------------------------"
    echo " Product : $(fb_var product)"
    echo " Slot    : $(fb_var current-slot)"
    echo " Locked  : $(fb_var unlocked)"
    echo "------------------------------------------"
    pause
}

switch_slot_screen() {
    clear
    echo "=========================================="
    echo "             SWITCH A/B SLOT              "
    echo "=========================================="
    echo ""
    printf "Enter target slot (a or b): "
    read -r slot
    if [[ "$slot" =~ ^[abAB]$ ]]; then
        say "Switching to slot $slot..."
        if fastboot set_active "$slot" > "$LAST_OUT" 2>&1; then
            ok "Successfully switched to slot $slot."
        else
            bad "Failed to switch slot."
        fi
    else
        bad "Invalid slot choice."
    fi
    pause
}

reboot_screen() {
    clear
    echo "=========================================="
    echo "              REBOOT OPTIONS              "
    echo "=========================================="
    echo " 1) Reboot to System"
    echo " 2) Reboot to Recovery"
    echo " 3) Reboot to Bootloader"
    echo " 0) Back"
    echo ""
    printf "Select option: "
    read -r r_opt
    case "${r_opt:-}" in
        1) fastboot reboot || adb reboot; say "Rebooting..." ;;
        2) fastboot reboot recovery || adb reboot recovery; say "Rebooting to recovery..." ;;
        3) fastboot reboot bootloader || adb reboot bootloader; say "Rebooting to bootloader..." ;;
        *) say "Cancelled." ;;
    esac
    pause
}

wipe_data_screen() {
    clear
    echo "=========================================="
    echo "           FACTORY RESET / WIPE           "
    echo "=========================================="
    warn "WARNING: This will erase all user data!"
    printf "Type 'WIPE' to confirm: "
    read -r confirm
    if [ "$confirm" = "WIPE" ]; then
        say "Wiping user data..."
        if fastboot -w > "$LAST_OUT" 2>&1; then
            ok "Data wiped successfully."
        else
            bad "Wipe failed."
        fi
    else
        say "Wipe cancelled."
    fi
    pause
}

# --- Main Menu Loop ---
main_menu() {
    check_tools
    while true; do
        clear
        
        local fb_status="${RED}Disconnected${RESET}"
        if fastboot devices 2>/dev/null | grep -q "fastboot"; then
            fb_status="${GREEN}Connected${RESET}"
        fi

        local adb_status="${RED}Disconnected${RESET}"
        if adb devices 2>/dev/null | grep -q "device$"; then
            adb_status="${GREEN}Connected${RESET}"
        fi

        echo "=========================================="
        echo "        ANDROID ULTIMATE FLASHER          "
        echo "        Version $VERSION • By Rudra         "
        echo "=========================================="
        echo " Fastboot : $fb_status"
        echo " ADB      : $adb_status"
        echo "=========================================="
        echo " 1) Flash Image (.img)"
        echo " 2) Custom ROM (ADB Sideload .zip)"
        echo " 3) Device Information"
        echo " 4) Switch A/B Slot"
        echo " 5) Reboot Options"
        echo " 6) Erase Data (Factory Reset)"
        echo " 0) Exit"
        echo "=========================================="
        printf "Select option: "
        read -r opt

        case "${opt:-}" in
            1) flash_image_screen ;;
            2) flash_sideload_screen ;;
            3) device_info_screen ;;
            4) switch_slot_screen ;;
            5) reboot_screen ;;
            6) wipe_data_screen ;;
            0) 
               say "Exiting tool safely."
               exit 0
               ;;
            *) 
               bad "Invalid option."
               sleep 1
               ;;
        esac
    done
}

# --- Self-Installation / Shortcut Setup ---
install_tool() {
    local target_dir="$HOME/.android-ultimate-flashing-tool"
    mkdir -p "$target_dir"
    
    # Copy current script to target directory if executed via bash <(...) or clone
    if [ -f "$0" ]; then
        cp "$0" "$target_dir/setup.sh"
    fi
    
    chmod +x "$target_dir/setup.sh"
    
    # Create persistent global symlink in termux bin
    mkdir -p "$PREFIX/bin"
    ln -sf "$target_dir/setup.sh" "$PREFIX/bin/rudra"
    chmod +x "$PREFIX/bin/rudra"
}

# Run installation setup on first execution
install_tool

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi
