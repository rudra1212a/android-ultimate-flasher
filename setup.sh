#!/usr/bin/env bash
# ==============================================================================
# Script Name: Android Ultimate Flasher (Fixed & Stable Edition)
# Description: Professional Android flashing tool for Termux
# ==============================================================================

set -uo pipefail

VERSION="1.3"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"
DL_DIR="$HOME/storage/downloads"

if [ ! -d "$DL_DIR" ]; then
    DL_DIR="$HOME/Download"
    mkdir -p "$DL_DIR"
fi

mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

# Safe color variables using printf-compatible definitions
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RESET='\033[0m'

log() {
    local level="${1:-INFO}"
    shift || true
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

say()  { printf "${BLUE}[*]${RESET} %s\n" "$*"; log "INFO" "$*"; }
ok()   { printf "${GREEN}[+]${RESET} %s\n" "$*"; log "SUCCESS" "$*"; }
warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; log "WARN" "$*"; }
bad()  { printf "${RED}[-]${RESET} %s\n" "$*"; log "ERROR" "$*"; }

pause() {
    printf "\n"
    read -n 1 -s -r -p "Press any key to continue..."
    printf "\n"
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
        printf "UNKNOWN"
    else
        printf "%s" "$val" | tr -d '\r'
    fi
}

flash_image_screen() {
    clear
    printf "==========================================\n"
    printf "         FLASH INDIVIDUAL IMAGE (.IMG)    \n"
    printf "==========================================\n"
    
    if [ ! -d "$DL_DIR" ]; then
        warn "Download folder not found: $DL_DIR"
        pause
        return
    fi

    local count=0
    printf "\n"
    shopt -s nullglob
    local imgs=("$DL_DIR"/*.img)
    shopt -u nullglob

    for img in "${imgs[@]}"; do
        if [ -f "$img" ]; then
            count=$((count + 1))
            printf "  [%d] %s\n" "$count" "$(basename "$img")"
        fi
    done

    if [ "$count" -eq 0 ]; then
        warn "No .img files found in Downloads folder."
        pause
        return
    fi

    printf "\nSelect image number (0 to cancel): "
    read -r img_choice

    if [[ ! "$img_choice" =~ ^[0-9]+$ ]] || [ "$img_choice" -le 0 ] || [ "$img_choice" -gt "$count" ]; then
        say "Cancelled."
        pause
        return
    fi

    local selected_img="${imgs[$((img_choice - 1))]}"
    say "Selected: $(basename "$selected_img")"
    
    printf "Common partitions: boot, recovery, vbmeta, dtbo\n"
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
    printf "==========================================\n"
    printf "          ADB SIDELOAD CUSTOM ROM         \n"
    printf "==========================================\n"

    local count=0
    printf "\n"
    shopt -s nullglob
    local zips=("$DL_DIR"/*.zip)
    shopt -u nullglob

    for z in "${zips[@]}"; do
        if [ -f "$z" ]; then
            count=$((count + 1))
            printf "  [%d] %s\n" "$count" "$(basename "$z")"
        fi
    done

    if [ "$count" -eq 0 ]; then
        warn "No .zip files found in Downloads."
        pause
        return
    fi

    printf "\nSelect zip number to sideload (0 to cancel): "
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
    printf "==========================================\n"
    printf "            DEVICE INFORMATION            \n"
    printf "==========================================\n\n"
    say "Fetching device variables..."
    printf "------------------------------------------\n"
    printf " Product : %s\n" "$(fb_var product)"
    printf " Slot    : %s\n" "$(fb_var current-slot)"
    printf " Locked  : %s\n" "$(fb_var unlocked)"
    printf "------------------------------------------\n"
    pause
}

switch_slot_screen() {
    clear
    printf "==========================================\n"
    printf "             SWITCH A/B SLOT              \n"
    printf "==========================================\n\n"
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
    printf "==========================================\n"
    printf "              REBOOT OPTIONS              \n"
    printf "==========================================\n"
    printf " 1) Reboot to System\n"
    printf " 2) Reboot to Recovery\n"
    printf " 3) Reboot to Bootloader\n"
    printf " 0) Back\n\n"
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
    printf "==========================================\n"
    printf "           FACTORY RESET / WIPE           \n"
    printf "==========================================\n"
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

        printf "==========================================\n"
        printf "        ANDROID ULTIMATE FLASHER          \n"
        printf "        Version %s • By Rudra         \n" "$VERSION"
        printf "==========================================\n"
        printf " Fastboot : %b\n" "$fb_status"
        printf " ADB      : %b\n" "$adb_status"
        printf "==========================================\n"
        printf " 1) Flash Image (.img)\n"
        printf " 2) Custom ROM (ADB Sideload .zip)\n"
        printf " 3) Device Information\n"
        printf " 4) Switch A/B Slot\n"
        printf " 5) Reboot Options\n"
        printf " 6) Erase Data (Factory Reset)\n"
        printf " 0) Exit\n"
        printf "==========================================\n"
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

install_tool() {
    mkdir -p "$BASE_DIR"
    if [ -f "$0" ]; then
        cp "$0" "$BASE_DIR/setup.sh"
    fi
    chmod +x "$BASE_DIR/setup.sh"
    
    mkdir -p "$PREFIX/bin"
    ln -sf "$BASE_DIR/setup.sh" "$PREFIX/bin/rudra"
    chmod +x "$PREFIX/bin/rudra"
}

install_tool

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi
