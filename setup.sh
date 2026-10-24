#!/usr/bin/env bash
# ==============================================================================
# Script Name: Android Ultimate Flasher (Classic UI & Secured Edition)
# Description: Professional Android flashing tool with original UI layout
# ==============================================================================

set -uo pipefail

# --- Configuration & Constants ---
VERSION="1.1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
readonly BASE_DIR="$HOME/.android-ultimate-flashing-tool"
readonly LOG_FILE="$BASE_DIR/tool.log"
readonly LAST_OUT="$BASE_DIR/last_output.txt"
readonly DL_DIR="$HOME/Download"

# UI Colors & Styles
if [ -t 1 ] && [ "${NO_COLOR:-0}" = "0" ]; then
    readonly RED='\033[1;31m'
    readonly GREEN='\033[1;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[1;34m'
    readonly CYAN='\033[1;36m'
    readonly GRAY='\033[1;90m'
    readonly RESET='\033[0m'
else
    readonly RED='' readonly GREEN='' readonly YELLOW='' readonly BLUE='' readonly CYAN='' readonly GRAY='' readonly RESET=''
fi

# Initialize Environment
mkdir -p "$BASE_DIR" "$DL_DIR"
touch "$LOG_FILE" "$LAST_OUT"
chmod 600 "$LOG_FILE" "$LAST_OUT"

# --- Logging & Output Functions ---
log() {
    local level="${1:-INFO}"
    shift || true
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "$msg" >> "$LOG_FILE"
}

say()  { echo -e "${BLUE}[*]${RESET} $*"; log "INFO" "$*"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; log "SUCCESS" "$*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; log "WARN" "$*"; }
bad()  { echo -e "${RED}[-]${RESET} $*"; log "ERROR" "$*"; }

# --- Timeout Helper ---
HAS_TIMEOUT=0
command -v timeout >/dev/null 2>&1 && HAS_TIMEOUT=1

run_t() {
    local timeout_sec="$1"
    shift
    if [ "$HAS_TIMEOUT" = 1 ]; then
        timeout "$timeout_sec" "$@"
    else
        "$@"
    fi
}

# --- Device Detection & Fastboot Helpers ---
fb_var() {
    local var_name="${1:-}"
    local output
    output=$(run_t 8 fastboot getvar "$var_name" 2>&1 | tr -d '\r')
    local val
    val=$(echo "$output" | awk -F': *' -v k="$var_name" '{
        sub(/^\(bootloader\)[[:space:]]*/, "", $1);
        if ($1 == k && NF >= 2) { print $2; exit }
    }')
    if [ -z "$val" ]; then
        echo "UNKNOWN"
        return 1
    fi
    echo "$val"
    return 0
}

bootloader_gate() {
    say "Verifying bootloader lock status..."
    local u="UNKNOWN"
    u="$(fb_var unlocked || echo "UNKNOWN")"
    if [[ "${u,,}" =~ ^(yes|true|1)$ ]]; then
        ok "Bootloader is verified as UNLOCKED."
        return 0
    else
        bad "Bootloader is LOCKED or status could not be verified ($u). Operation cancelled."
        return 1
    fi
}

device_identity_gate() {
    local expected_model="${1:-}"
    say "Checking connected device identity..."
    
    if ! command -v fastboot >/dev/null 2>&1; then
        bad "Fastboot command not found."
        return 1
    }

    local current_product="UNKNOWN"
    current_product="$(fb_var product || echo "UNKNOWN")"
    say "Detected Device Product: $current_product"

    if [ -n "$expected_model" ]; then
        if [ "$current_product" != "$expected_model" ]; then
            bad "Model Mismatch! Expected: '$expected_model', Connected: '$current_product'. Operation aborted."
            return 1
        else
            ok "Device model matches expected firmware package."
        fi
    fi
    return 0
}

pause() {
    if [ -t 0 ]; then
        printf '\n  %sPress Enter to continue%s ' "$GRAY" "$RESET"
        read -r _ || true
    fi
}

# --- Feature Screens ---
flash_image_screen() {
    echo -e "\n=== Flash Individual Image (.img) ==="
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
        warn "No .img files found in $DL_DIR."
        pause
        return 1
    fi

    printf "  Select image number to flash (0 to cancel): "
    read -r img_choice

    if [[ ! "$img_choice" =~ ^[0-9]+$ ]] || [ "$img_choice" -le 0 ] || [ "$img_choice" -gt "$count" ]; then
        say "Cancelled."
        return 0
    fi

    local selected_img="${imgs[$((img_choice - 1))]}"
    say "Selected Image: $(basename "$selected_img")"
    
    echo "  Common Partitions: boot, recovery, vbmeta, dtbo, vendor_boot"
    printf "  Enter target partition name: "
    read -r target_part

    if [ -z "$target_part" ]; then
        bad "Partition name cannot be empty."
        pause
        return 1
    fi

    if bootloader_gate; then
        say "Flashing $(basename "$selected_img") to partition [$target_part]..."
        if fastboot flash "$target_part" "$selected_img" > "$LAST_OUT" 2>&1; then
            ok "Image flashed successfully!"
        else
            bad "Flashing failed! Check last output for details."
        fi
    fi
    pause
}

flash_sideload_screen() {
    echo -e "\n=== ADB Sideload Custom ROM ==="
    if ! command -v adb >/dev/null 2>&1; then
        bad "ADB command not found."
        pause
        return 1
    fi

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
        warn "No .zip files found in $DL_DIR."
        pause
        return 1
    fi

    printf "  Select zip file number to sideload (0 to cancel): "
    read -r zip_choice

    if [[ ! "$zip_choice" =~ ^[0-9]+$ ]] || [ "$zip_choice" -le 0 ] || [ "$zip_choice" -gt "$count" ]; then
        say "Cancelled."
        return 0
    fi

    local selected_zip="${zips[$((zip_choice - 1))]}"
    say "Starting ADB sideload for $(basename "$selected_zip")..."
    
    if adb sideload "$selected_zip" > "$LAST_OUT" 2>&1; then
        ok "ADB sideload completed successfully!"
    else
        bad "ADB sideload failed or interrupted."
    fi
    pause
}

flash_fastboot_screen() {
    echo -e "\n=== Fastboot ROM Package Preview ==="
    say "Scanning $DL_DIR for extracted ROM folders..."
    local count=0
    echo ""
    shopt -s nullglob
    for d in "$DL_DIR"/*/; do
        if [ -d "$d" ]; then
            echo "  [$((++count))] $(basename "$d")"
        fi
    done
    shopt -u nullglob

    if [ "$count" -eq 0 ]; then
        warn "No extracted packages found."
    fi
    pause
}

switch_slot_screen() {
    echo -e "\n=== Switch A/B Slot ==="
    if bootloader_gate; then
        local current_slot
        current_slot="$(fb_var current-slot || echo "UNKNOWN")"
        say "Current Active Slot: $current_slot"
        printf "  Enter target slot to switch (a or b): "
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
    fi
    pause
}

wipe_data_screen() {
    echo -e "\n=== Factory Reset / Wipe Data ==="
    warn "WARNING: This will erase all personal data!"
    printf "  Type 'WIPE' to confirm: "
    read -r confirm
    if [ "$confirm" = "WIPE" ]; then
        if bootloader_gate; then
            say "Wiping user data..."
            if fastboot -w > "$LAST_OUT" 2>&1; then
                ok "User data wiped successfully."
            else
                bad "Wipe operation failed."
            fi
        fi
    else
        say "Wipe cancelled."
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
        1) fastboot reboot || adb reboot; say "Rebooting..." ;;
        2) fastboot reboot recovery || adb reboot recovery; say "Rebooting to recovery..." ;;
        3) fastboot reboot bootloader || adb reboot bootloader; say "Rebooting to bootloader..." ;;
        *) say "Cancelled." ;;
    esac
    pause
}

# --- Main Menu ---
main_menu() {
    while true; do
        clear
        
        local fb_dot="${RED}●${RESET}"
        command -v fastboot >/dev/null 2>&1 && fb_dot="${GREEN}●${RESET}"

        local adb_dot="${RED}●${RESET}"
        command -v adb >/dev/null 2>&1 && adb_dot="${GREEN}●${RESET}"

        local py_dot="${RED}●${RESET}"
        command -v python3 >/dev/null 2>&1 && py_dot="${GREEN}●${RESET}"

        local dev_text="${RED}Not connected${RESET}"
        if fastboot devices 2>/dev/null | grep -q "fastboot" || adb devices 2>/dev/null | grep -q "device$"; then
            dev_text="${GREEN}Connected${RESET}"
        fi

        local file_count=0
        if [ -d "$DL_DIR" ]; then
            file_count=$(find "$DL_DIR" -mindepth 1 -maxdepth 1 \( -name "*.img" -o -name "*.zip" -o -type d \) | wc -l)
        fi

        echo -e "${GREEN}┌──────────────────────────────────────────────────┐${RESET}"
        echo -e "${GREEN}│${RESET}             ANDROID ULTIMATE FLASHER             ${GREEN}│${RESET}"
        echo -e "${GREEN}│${RESET}        Version 1.1  •  Crafted by Rudra          ${GREEN}│${RESET}"
        echo -e "${GREEN}┌──────────────────────────────────────────────────┐${RESET}" | sed 's/┌/└/;s/┐/┘/'
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
        read -r opt

        case "${opt:-}" in
            1) flash_image_screen ;;
            2) flash_sideload_screen ;;
            3) flash_fastboot_screen ;;
            4) 
               echo -e "\n=== Device Information & Status ==="
               if bootloader_gate; then
                   device_identity_gate
               fi
               pause
               ;;
            5) switch_slot_screen ;;
            6) wipe_data_screen ;;
            7) reboot_screen ;;
            8) wipe_data_screen ;;
            0) 
               say "Exiting tool safely."
               return 0 2>/dev/null || exit 0
               ;;
            *) 
               bad "Invalid option."
               sleep 1 
               ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi
