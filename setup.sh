#!/usr/bin/env bash
# ==============================================================================
# Script Name: Android Ultimate Flasher
# Description: Professional Android flashing tool for Termux (Version 1.1)
# ==============================================================================

set -uo pipefail

VERSION="1.1"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"

mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

# UI Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[1;90m'
RESET='\033[0m'

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
    if [ -t 0 ]; then
        echo -e ""
        read -n 1 -s -r -p "Press any key to continue..."
        echo -e ""
    fi
}

# Downloads directory setup (Placed safely after 'warn' function)
DL_DIR="$HOME/storage/downloads"
if [ ! -d "$DL_DIR" ]; then
    warn "Storage not linked. Run 'termux-setup-storage' if needed."
    DL_DIR="$HOME/Download"
    mkdir -p "$DL_DIR"
fi

check_tools() {
    for cmd in fastboot adb; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "$cmd is not installed. Installing platform-tools..."
            pkg update -y && pkg install -y android-tools >/dev/null 2>&1 || {
                bad "Failed to install android-tools. Check internet connection."
            }
            break
        fi
    done
}

check_fastboot_device() {
    if ! fastboot devices 2>/dev/null | grep -q "fastboot"; then
        bad "No fastboot device connected! Please connect phone in fastboot mode."
        pause
        return 1
    fi
    return 0
}

check_adb_device() {
    if ! adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
        bad "No ADB/Sideload device connected! Check USB debugging or recovery sideload mode."
        pause
        return 1
    fi
    return 0
}

check_sideload_device() {
    if ! adb devices 2>/dev/null | grep -q "sideload$"; then
        bad "Device not in sideload mode. Recovery > Apply update > ADB."
        pause
        return 1
    fi
    return 0
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
    echo -e "\n=== Flash Individual Image (.img) ==="
    
    check_fastboot_device || return 1

    if [ ! -d "$DL_DIR" ]; then
        warn "Download directory not found."
        pause
        return 1
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
        warn "No .img files found in Downloads."
        pause
        return 1
    fi

    printf "  Select image number to flash (0 to cancel): "
    read -r img_choice

    # Fixed: Removed extra ']'
    if [[ ! "$img_choice" =~ ^[0-9]+$ ]] || [ "$img_choice" -le 0 ] || [ "$img_choice" -gt "$count" ]; then
        say "Cancelled."
        pause
        return 0
    fi

    local selected_img="${imgs[$((img_choice - 1))]}"
    say "Selected Image: $(basename "$selected_img")"
    
    echo "  Common Partitions: boot, recovery, vbmeta, dtbo"
    printf "  Enter target partition name: "
    read -r target_part

    if [ -z "$target_part" ]; then
        bad "Partition name cannot be empty."
        pause
        return 1
    fi

    printf "  Are you sure you want to flash [%s] to partition [%s]? (y/N): " "$(basename "$selected_img")" "$target_part"
    read -r confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        say "Flashing cancelled."
        pause
        return 0
    fi

    if [[ "$target_part" == vbmeta* ]]; then
        printf "  Do you want to disable verity and verification? (y/N): "
        read -r vb_conf
        if [[ "$vb_conf" =~ ^[yY]$ ]]; then
            say "Flashing $target_part with disable flags..."
            if fastboot --disable-verity --disable-verification flash "$target_part" "$selected_img" > "$LAST_OUT" 2>&1; then
                ok "Vbmeta flashed successfully with disable flags!"
            else
                bad "Flashing failed! Last output:"
                tail -n 5 "$LAST_OUT"
            fi
            pause
            return 0
        fi
    fi

    say "Flashing to [$target_part]..."
    if fastboot flash "$target_part" "$selected_img" > "$LAST_OUT" 2>&1; then
        ok "Image flashed successfully!"
    else
        bad "Flashing failed! Last output:"
        tail -n 5 "$LAST_OUT"
    fi
    pause
}

flash_sideload_screen() {
    clear
    echo -e "\n=== ADB Sideload Custom ROM ==="

    check_sideload_device || return 1

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
        return 1
    fi

    printf "  Select zip file number to sideload (0 to cancel): "
    read -r zip_choice

    # Fixed: Removed extra ']'
    if [[ ! "$zip_choice" =~ ^[0-9]+$ ]] || [ "$zip_choice" -le 0 ] || [ "$zip_choice" -gt "$count" ]; then
        say "Cancelled."
        pause
        return 0
    fi

    local selected_zip="${zips[$((zip_choice - 1))]}"
    say "Starting ADB sideload for $(basename "$selected_zip")..."
    
    adb sideload "$selected_zip" 2>&1 | tee "$LAST_OUT"
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ]; then
        ok "ADB sideload completed successfully!"
    else
        warn "Exit code $rc. Check recovery screen; it may still have succeeded."
    fi
    pause
}

flash_fastboot_screen() {
    echo -e "\n=== Fastboot ROM Package Preview ==="
    warn "Feature is under development."
    pause
}

flash_gsi_screen() {
    echo -e "\n=== Flash GSI (Generic System Image) ==="
    warn "Feature is under development."
    pause
}

device_info_screen() {
    echo -e "\n=== Device Information & Status ==="
    check_fastboot_device || return 1
    echo "------------------------------------------"
    echo " Product : $(fb_var product)"
    echo " Slot    : $(fb_var current-slot)"
    echo " Unlocked: $(fb_var unlocked)"
    echo "------------------------------------------"
    pause
}

switch_slot_screen() {
    echo -e "\n=== Switch A/B Slot ==="
    check_fastboot_device || return 1
    printf "  Enter target slot to switch (a or b): "
    read -r slot
    slot="${slot,,}"
    if [[ "$slot" =~ ^[ab]$ ]]; then
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
    echo -e "\n=== Reboot Options ==="
    echo " 1) Reboot to System"
    echo " 2) Reboot to Recovery"
    echo " 3) Reboot to Bootloader"
    echo " 0) Back"
    printf " Select mode: "
    read -r r_opt
    case "${r_opt:-}" in
        1) 
           if fastboot devices 2>/dev/null | grep -q "fastboot"; then
               fastboot reboot || { bad "Reboot failed."; pause; return; }
           elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
               adb reboot || { bad "Reboot failed."; pause; return; }
           else
               bad "No device connected to reboot."
               pause
               return
           fi
           say "Rebooting..." 
           ;;
        2) 
           if fastboot devices 2>/dev/null | grep -q "fastboot"; then
               fastboot reboot recovery || { bad "Reboot failed."; pause; return; }
           elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
               adb reboot recovery || { bad "Reboot failed."; pause; return; }
           else
               bad "No device connected."
               pause
               return
           fi
           say "Rebooting to recovery..." 
           ;;
        3) 
           if fastboot devices 2>/dev/null | grep -q "fastboot"; then
               fastboot reboot bootloader || { bad "Reboot failed."; pause; return; }
           elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
               adb reboot bootloader || { bad "Reboot failed."; pause; return; }
           else
               bad "No device connected."
               pause
               return
           fi
           say "Rebooting to bootloader..." 
           ;;
        *) say "Cancelled." ;;
    esac
    pause
}

wipe_data_screen() {
    echo -e "\n=== Factory Reset / Wipe Data ==="
    check_fastboot_device || return 1
    warn "WARNING: This will erase all personal data!"
    printf "  Type 'WIPE' to confirm: "
    read -r confirm
    if [ "$confirm" = "WIPE" ]; then
        say "Wiping user data..."
        if fastboot -w > "$LAST_OUT" 2>&1; then
            ok "Data wiped successfully."
        else
            warn "Standard wipe failed, trying manual userdata/metadata erase..."
            if fastboot erase userdata > "$LAST_OUT" 2>&1 && fastboot erase metadata >> "$LAST_OUT" 2>&1; then
                ok "Manual data erase completed successfully."
            else
                bad "Wipe operation failed completely."
            fi
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
        
        local fb_dot="${RED}●${RESET}"
        if fastboot devices 2>/dev/null | grep -q "fastboot"; then
            fb_dot="${GREEN}●${RESET}"
        fi

        local adb_dot="${RED}●${RESET}"
        if adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
            adb_dot="${GREEN}●${RESET}"
        fi

        local py_dot="${RED}●${RESET}"
        if command -v python3 >/dev/null 2>&1; then
            py_dot="${GREEN}●${RESET}"
        fi

        local dev_text="${RED}Not connected${RESET}"
        if fastboot devices 2>/dev/null | grep -q "fastboot" || adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
            dev_text="${GREEN}Connected${RESET}"
        fi

        local file_count=0
        if [ -d "$DL_DIR" ]; then
            file_count=$(find "$DL_DIR" -mindepth 1 -maxdepth 1 \( -name "*.img" -o -name "*.zip" \) -type f 2>/dev/null | wc -l)
        fi

        echo -e "${GREEN}+------------------------------------+${RESET}"
        echo -e "${GREEN}|${RESET}      ANDROID ULTIMATE FLASHER      ${GREEN}|${RESET}"
        # Fixed: Added extra space at the end for perfect right-border alignment
        echo -e "${GREEN}|${RESET}   Version ${VERSION} • Created by Rudra   ${GREEN}|${RESET}"
        echo -e "${GREEN}+------------------------------------+${RESET}"
        echo ""
        echo -e " Tools    $fb_dot fastboot   $adb_dot adb   $py_dot python"
        echo -e " Device   $dev_text"
        echo -e " Files    $file_count in Downloads"
        echo ""
        echo -e " ${CYAN}- FLASH -${RESET}"
        echo -e "  1 ${GREEN}●${RESET} Flash Image        boot / recovery .img"
        echo -e "  2 ${GREEN}●${RESET} Custom ROM (ADB)   install .zip package"
        echo -e "  3 ${YELLOW}●${RESET} Fastboot ROM       extract & flash pkg"
        echo -e "  4 ${GREEN}●${RESET} Flash GSI          generic system image"
        echo -e " ${CYAN}- DEVICE -${RESET}"
        echo -e "  5 ${GREEN}●${RESET} Device Info        model, slot, lock"
        echo -e "  6 ${GREEN}●${RESET} Switch Slot        active A/B slot"
        echo -e "  7 ${GREEN}●${RESET} Reboot             restart to a mode"
        echo -e "  8 ${RED}●${RESET} Erase Data         factory reset"
        echo -e " ${CYAN}- EXIT -${RESET}"
        echo -e "  0 ${GREEN}●${RESET} Exit               Quit application"
        echo ""
        echo -e " ${GREEN}●${RESET} Safe    ${YELLOW}●${RESET} Careful    ${RED}●${RESET} Erases data"
        echo ""
        printf " Select: "
        read -r opt || exit 0

        case "${opt:-}" in
            1) flash_image_screen ;;
            2) flash_sideload_screen ;;
            3) flash_fastboot_screen ;;
            4) flash_gsi_screen ;;
            5) device_info_screen ;;
            6) switch_slot_screen ;;
            7) reboot_screen ;;
            8) wipe_data_screen ;;
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
    mkdir -p "$BASE_DIR" "$TERMUX_PREFIX/bin"
    
    local self target
    self="$(realpath "$0" 2>/dev/null)"
    target="$(realpath "$BASE_DIR/setup.sh" 2>/dev/null)"
    
    if [ -f "$0" ] && [ "$self" != "$target" ]; then
        cp "$0" "$BASE_DIR/setup.sh" 2>/dev/null || true
    fi
    
    [ -f "$BASE_DIR/setup.sh" ] || cp "$0" "$BASE_DIR/setup.sh" 2>/dev/null || true
    [ -f "$BASE_DIR/setup.sh" ] || return 0
    
    chmod +x "$BASE_DIR/setup.sh" 2>/dev/null || true
    ln -sf "$BASE_DIR/setup.sh" "$TERMUX_PREFIX/bin/rudra"
    chmod +x "$TERMUX_PREFIX/bin/rudra" 2>/dev/null || true
}

install_tool

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi
