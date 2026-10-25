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

# Smooth Loading Spinner Animation Function
animate() {
    local message="$1"
    shift
    ("$@") > "$LAST_OUT" 2>&1 &
    local pid=$!
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r${CYAN}[*]${RESET} %s [%c]" "$message" "${spin:$i:1}"
        sleep 0.1
    done
    wait $pid
    local rc=$?
    printf "\r\033[K"
    return $rc
}

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
    warn "Storage not linked. Run 'termux-setup-storage' if needed.[span_5](start_span)[span_6](start_span)"[span_5](end_span)[span_6](end_span)
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
        bad "No fastboot device connected! Please connect phone in fastboot mode.[span_7](start_span)[span_8](start_span)"[span_7](end_span)[span_8](end_span)
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
    
    check_fastboot_device || return 1[span_9](start_span)[span_9](end_span)[span_10](start_span)[span_10](end_span)

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
        warn "No .img files found in Downloads.[span_11](start_span)"[span_11](end_span)
        pause
        return 1
    fi

    printf "  Select image number to flash (0 to cancel): "
    read -r img_choice

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
            animate "Flashing $target_part with disable flags" fastboot --disable-verity --disable-verification flash "$target_part" "$selected_img"
            if [ $? -eq 0 ]; then
                ok "Vbmeta flashed successfully with disable flags!"
            else
                bad "Flashing failed! Last output:"
                tail -n 5 "$LAST_OUT"
            fi
            pause
            return 0
        fi
    fi

    animate "Flashing image to [$target_part]" fastboot flash "$target_part" "$selected_img"
    if [ $? -eq 0 ]; then
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
        warn "No .zip files found in Downloads.[span_12](start_span)"[span_12](end_span)
        pause
        return 1
    fi

    printf "  Select zip file number to sideload (0 to cancel): "
    read -r zip_choice

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
    echo -e "\n=== Fastboot ROM Package Preview ===[span_13](start_span)"[span_13](end_span)
    warn "Feature is under development.[span_14](start_span)"[span_14](end_span)
    pause
}

flash_gsi_screen() {
    echo -e "\n=== Flash GSI (Generic System Image) ===[span_15](start_span)"[span_15](end_span)
    warn "Feature is under development.[span_16](start_span)"[span_16](end_span)
    pause
}

device_info_screen() {
    echo -e "\n=== Device Information & Status ===[span_17](start_span)"[span_17](end_span)
    check_fastboot_device || return 1[span_18](start_span)[span_18](end_span)[span_19](start_span)[span_19](end_span)
    echo "------------------------------------------"
    echo " Product : $(fb_var product)"
    echo " Slot    : $(fb_var current-slot)"
    echo " Unlocked: $(fb_var unlocked)"
    echo "------------------------------------------"
    pause
}

switch_slot_screen() {
    echo -e "\n=== Switch A/B Slot ===[span_20](start_span)"[span_20](end_span)
    check_fastboot_device || return 1[span_21](start_span)[span_21](end_span)[span_22](start_span)[span_22](end_span)
    printf "  Enter target slot to switch (a or b): "
    read -r slot
    slot="${slot,,}"
    if [[ "$slot" =~ ^[ab]$ ]]; then
        animate "Switching active slot to $slot" fastboot set_active "$slot"
        if [ $? -eq 0 ]; then
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
               animate "Rebooting system" fastboot reboot || { bad "Reboot failed."; pause; return; }
           elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
               animate "Rebooting system" adb reboot || { bad "Reboot failed."; pause; return; }
           else
               bad "No device connected to reboot."
               pause
               return
           fi
           say "Rebooting..." 
           ;;
        2) 
           if fastboot devices 2>/dev/null | grep -q "fastboot"; then
               animate "Rebooting to recovery" fastboot reboot recovery || { bad "Reboot failed."; pause; return; }
           elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
               animate "Rebooting to recovery" adb reboot recovery || { bad "Reboot failed."; pause; return; }
           else
               bad "No device connected."
               pause
               return
           fi
           say "Rebooting to recovery..." 
           ;;
        3) 
           if fastboot devices 2>/dev/null | grep -q "fastboot"; then
               animate "Rebooting to bootloader" fastboot reboot bootloader || { bad "Reboot failed."; pause; return; }
           elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
               animate "Rebooting to bootloader" adb reboot bootloader || { bad "Reboot failed."; pause; return; }
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
    check_fastboot_device || return 1[span_23](start_span)[span_23](end_span)[span_24](start_span)[span_24](end_span)
    warn "WARNING: This will erase all personal data!"
    printf "  Type 'WIPE' to confirm: "
    read -r confirm
    if [ "$confirm" = "WIPE" ]; then
        animate "Wiping user data" fastboot -w
        if [ $? -eq 0 ]; then
            ok "Data wiped successfully."
        else
            warn "Standard wipe failed, trying manual userdata/metadata erase..."
            animate "Erasing userdata and metadata" fastboot erase userdata
            if [ $? -eq 0 ]; then
                animate "Erasing metadata" fastboot erase metadata
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

        local dev_text="${RED}Not connected${RESET}[span_25](start_span)[span_26](start_span)[span_27](start_span)[span_28](start_span)[span_29](start_span)"[span_25](end_span)[span_26](end_span)[span_27](end_span)[span_28](end_span)[span_29](end_span)
        if fastboot devices 2>/dev/null | grep -q "fastboot" || adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
            dev_text="${GREEN}Connected${RESET}"
        fi

        local file_count=0
        if [ -d "$DL_DIR" ]; then
            file_count=$(find "$DL_DIR" -mindepth 1 -maxdepth 1 \( -name "*.img" -o -name "*.zip" \) -type f 2>/dev/null | wc -l)[span_30](start_span)[span_30](end_span)
        fi

        echo -e "${GREEN}+------------------------------------+${RESET}[span_31](start_span)"[span_31](end_span)
        echo -e "${GREEN}|${RESET}      ANDROID ULTIMATE FLASHER      ${GREEN}|${RESET}[span_32](start_span)"[span_32](end_span)
        echo -e "${GREEN}|${RESET}   Version ${VERSION} • Created by Rudra   ${GREEN}|${RESET}[span_33](start_span)"[span_33](end_span)
        echo -e "${GREEN}+------------------------------------+${RESET}[span_34](start_span)"[span_34](end_span)
        echo ""
        echo -e " Tools    $fb_dot fastboot   $adb_dot adb   $py_dot python"
        echo -e " Device   $dev_text[span_35](start_span)[span_36](start_span)[span_37](start_span)[span_38](start_span)[span_39](start_span)"[span_35](end_span)[span_36](end_span)[span_37](end_span)[span_38](end_span)[span_39](end_span)
        echo -e " Files    $file_count in Downloads[span_40](start_span)"[span_40](end_span)
        echo ""
        echo -e " ${CYAN}- FLASH -${RESET}"
        echo -e "  1 ${GREEN}●${RESET} Flash Image        boot / recovery .img"
        echo -e "  2 ${GREEN}●${RESET} Custom ROM (ADB)   install .zip package"
        echo -e "  3 ${YELLOW}●${RESET} Fastboot ROM       extract & flash pkg[span_41](start_span)"[span_41](end_span)
        echo -e "  4 ${GREEN}●${RESET} Flash GSI          generic system image[span_42](start_span)"[span_42](end_span)
        echo -e " ${CYAN}- DEVICE -${RESET}"
        echo -e "  5 ${GREEN}●${RESET} Device Info        model, slot, lock[span_43](start_span)"[span_43](end_span)
        echo -e "  6 ${GREEN}●${RESET} Switch Slot        active A/B slot[span_44](start_span)"[span_44](end_span)
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
            3) flash_fastboot_screen ;;[span_45](start_span)[span_45](end_span)
            4) flash_gsi_screen ;;[span_46](start_span)[span_46](end_span)
            5) device_info_screen ;;[span_47](start_span)[span_47](end_span)
            6) switch_slot_screen ;;[span_48](start_span)[span_48](end_span)
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
