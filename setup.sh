#!/usr/bin/env bash
# ==============================================================================
# Script Name  : Android Ultimate Flasher
# Version      : 1.3
# Description  : Professional Android flashing tool for Termux
# Author       : Rudra
# ==============================================================================

set -uo pipefail

VERSION="1.3"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"

mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[1;90m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
RESET='\033[0m'

log() {
    local level="${1:-INFO}"
    shift || true
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

say()  { echo -e "\( {BLUE}[*] \){RESET} \( *"; log "INFO" " \)*"; }
ok()   { echo -e "\( {GREEN}[+] \){RESET} \( *"; log "SUCCESS" " \)*"; }
warn() { echo -e "\( {YELLOW}[!] \){RESET} \( *"; log "WARN" " \)*"; }
bad()  { echo -e "\( {RED}[-] \){RESET} \( *"; log "ERROR" " \)*"; }
info() { echo -e "\( {CYAN}[i] \){RESET} $*"; }

# Smooth spinner animation
animate() {
    local message="$1"
    shift
    ("$@") > "$LAST_OUT" 2>&1 &
    local pid=$!
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r\( {CYAN}[*] \){RESET} %s %s" "\( message" " \){spin:$i:1}"
        sleep 0.08
    done
    wait $pid
    local rc=$?
    printf "\r\033[K"
    return $rc
}

spin_msg() {
    local msg="$1"
    local duration="${2:-1}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local end=$((SECONDS + duration))
    while [ $SECONDS -lt $end ]; do
        i=$(( (i+1) % 10 ))
        printf "\r\( {CYAN}[*] \){RESET} %s %s" "\( msg" " \){spin:$i:1}"
        sleep 0.08
    done
    printf "\r\033[K"
}

pause() {
    if [ -t 0 ]; then
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
    fi
}

# ===================== SMART DOWNLOAD DIRECTORY DETECTION =====================
detect_dl_dir() {
    # Priority order - real paths first (fixes the "0 files" issue)
    local candidates=(
        "/storage/emulated/0/Download"
        "/sdcard/Download"
        "/storage/emulated/0/Downloads"
        "/sdcard/Downloads"
        "$HOME/storage/downloads"
        "$HOME/storage/shared/Download"
        "$HOME/storage/shared/Downloads"
        "$HOME/Download"
        "$HOME/Downloads"
    )

    local best=""
    local best_count=-1

    for dir in "${candidates[@]}"; do
        if [ -d "$dir" ] && [ -r "$dir" ]; then
            local cnt
            cnt=$(find "$dir" -maxdepth 1 -type f \( \
                -name "*.img" -o -name "*.zip" -o -name "*.img.xz" -o -name "*.tgz" -o -name "*.tar.gz" \
            \) 2>/dev/null | wc -l)
            
            if [ "$cnt" -gt "$best_count" ]; then
                best="$dir"
                best_count=$cnt
            fi
        fi
    done

    if [ -z "$best" ]; then
        best="/storage/emulated/0/Download"
        mkdir -p "$best" 2>/dev/null || best="$HOME/Download"
        mkdir -p "$best"
        warn "Using fallback: $best"
        warn "If files still not showing, run: termux-setup-storage"
    fi

    echo "$best"
}

DL_DIR="$(detect_dl_dir)"

# ===================== TOOL CHECK =====================
check_tools() {
    local need_install=0
    for cmd in fastboot adb; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            need_install=1
            break
        fi
    done

    if [ "$need_install" -eq 1 ]; then
        warn "android-tools not found. Installing..."
        if pkg update -y >/dev/null 2>&1 && pkg install -y android-tools >/dev/null 2>&1; then
            ok "android-tools installed."
        else
            bad "Failed to install android-tools."
        fi
    fi
}

check_fastboot_device() {
    if ! fastboot devices 2>/dev/null | grep -q "fastboot"; then
        bad "No device in Fastboot mode!"
        info "Boot into Fastboot/Bootloader and connect USB cable."
        pause
        return 1
    fi
    return 0
}

check_sideload_device() {
    if ! adb devices 2>/dev/null | grep -q "sideload$"; then
        bad "Device is not in Sideload mode."
        info "Recovery → Apply update → Apply from ADB"
        pause
        return 1
    fi
    return 0
}

fb_var() {
    local var_name="${1:-}"
    local val
    val=$(fastboot getvar "$var_name" 2>&1 | grep -i "$var_name" | head -n1 | awk '{print $2}')
    [ -z "$val" ] && echo "UNKNOWN" || echo "$val" | tr -d '\r'
}

hr_size() {
    local bytes=${1:-0}
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes/1024)) KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        printf "%.1f MB" "$(echo "scale=1; $bytes/1048576" | bc 2>/dev/null || echo $((bytes/1048576)))"
    else
        printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc 2>/dev/null || echo $((bytes/1073741824)))"
    fi
}

# ===================== FILE LISTING (FIXED) =====================
get_flashable_files() {
    local -n out_array=$1
    local pattern="$2"   # img / zip / all
    out_array=()

    [ ! -d "$DL_DIR" ] && return

    local find_args=()
    case "$pattern" in
        img)  find_args=(-name "*.img" -o -name "*.img.xz") ;;
        zip)  find_args=(-name "*.zip") ;;
        all)  find_args=(-name "*.img" -o -name "*.zip" -o -name "*.img.xz" -o -name "*.tgz" -o -name "*.tar.gz") ;;
        *)    find_args=(-name "*.img" -o -name "*.zip") ;;
    esac

    while IFS= read -r -d '' f; do
        out_array+=("$f")
    done < <(find "\( DL_DIR" -maxdepth 1 -type f \( " \){find_args[@]}" \) -print0 2>/dev/null | sort -z)
}

# ===================== SCREENS =====================

flash_image_screen() {
    clear
    echo -e "\n\( {BOLD}=== Flash Individual Image === \){RESET}"
    echo -e "${GRAY}Folder: \( DL_DIR \){RESET}\n"

    check_fastboot_device || return 1

    local files=()
    get_flashable_files files "img"

    if [ ${#files[@]} -eq 0 ]; then
        warn "No .img or .img.xz files found!"
        echo -e "  Checked: ${GRAY}\( DL_DIR \){RESET}"
        info "Make sure files are in the Download folder."
        pause
        return 1
    fi

    local i=1
    for f in "${files[@]}"; do
        local name size
        name=$(basename "$f")
        size=$(hr_size $(stat -c%s "$f" 2>/dev/null || echo 0))
        if [[ "$name" == *.xz ]]; then
            printf "  \( {YELLOW}[%d] \){RESET} %-45s %s  \( {YELLOW}(needs extract) \){RESET}\n" "$i" "$name" "$size"
        else
            printf "  \( {GREEN}[%d] \){RESET} %-45s %s\n" "$i" "$name" "$size"
        fi
        ((i++))
    done

    echo ""
    printf "  Select number (0 = cancel): "
    read -r choice

    if [[ ! "\( choice" =\~ ^[0-9]+ \) ]] || [ "$choice" -le 0 ] || [ "$choice" -gt ${#files[@]} ]; then
        say "Cancelled."
        pause
        return 0
    fi

    local selected="\( {files[ \)((choice-1))]}"
    local selected_name
    selected_name=$(basename "$selected")

    if [[ "$selected_name" == *.xz ]]; then
        warn "This is a compressed .img.xz file."
        info "Please extract it first using:"
        echo -e "  ${CYAN}xz -d \"\( selected\" \){RESET}"
        info "Then run this option again."
        pause
        return 0
    fi

    ok "Selected: $selected_name"

    echo -e "\n  Common partitions: \( {CYAN}boot  recovery  vbmeta  dtbo  vendor_boot  init_boot \){RESET}"
    printf "  Enter partition name: "
    read -r part

    if [ -z "$part" ]; then
        bad "Partition name empty."
        pause
        return 1
    fi

    printf "  Flash [%s] → [%s]? (y/N): " "$selected_name" "$part"
    read -r conf
    [[ ! "\( conf" =\~ ^[yY] \) ]] && { say "Cancelled."; pause; return 0; }

    if [[ "$part" == vbmeta* ]]; then
        printf "  Disable verity + verification? (y/N): "
        read -r vb
        if [[ "\( vb" =\~ ^[yY] \) ]]; then
            animate "Flashing $part (disable verity/verification)" \
                fastboot --disable-verity --disable-verification flash "$part" "$selected"
            [ $? -eq 0 ] && ok "Success!" || { bad "Failed:"; tail -n 6 "$LAST_OUT"; }
            pause
            return 0
        fi
    fi

    animate "Flashing $selected_name → $part" fastboot flash "$part" "$selected"
    if [ $? -eq 0 ]; then
        ok "Image flashed successfully!"
    else
        bad "Flash failed:"
        tail -n 6 "$LAST_OUT"
    fi
    pause
}

flash_sideload_screen() {
    clear
    echo -e "\n\( {BOLD}=== ADB Sideload Custom ROM === \){RESET}"
    echo -e "${GRAY}Folder: \( DL_DIR \){RESET}\n"

    check_sideload_device || return 1

    local files=()
    get_flashable_files files "zip"

    if [ ${#files[@]} -eq 0 ]; then
        warn "No .zip files found in Downloads."
        pause
        return 1
    fi

    local i=1
    for f in "${files[@]}"; do
        local size
        size=$(hr_size $(stat -c%s "$f" 2>/dev/null || echo 0))
        printf "  \( {GREEN}[%d] \){RESET} %-45s %s\n" "\( i" " \)(basename "$f")" "$size"
        ((i++))
    done

    echo ""
    printf "  Select zip (0 = cancel): "
    read -r choice

    if [[ ! "\( choice" =\~ ^[0-9]+ \) ]] || [ "$choice" -le 0 ] || [ "$choice" -gt ${#files[@]} ]; then
        say "Cancelled."
        pause
        return 0
    fi

    local selected="\( {files[ \)((choice-1))]}"
    say "Sideloading: $(basename "$selected")"
    echo ""

    adb sideload "$selected" 2>&1 | tee "$LAST_OUT"
    local rc=${PIPESTATUS[0]}

    if [ "$rc" -eq 0 ]; then
        ok "Sideload completed successfully!"
    else
        warn "Exit code: $rc (sometimes still succeeds — check recovery)"
    fi
    pause
}

flash_gsi_screen() {
    clear
    echo -e "\n\( {BOLD}=== Flash GSI === \){RESET}"
    echo -e "${GRAY}Folder: \( DL_DIR \){RESET}\n"

    check_fastboot_device || return 1

    local files=()
    get_flashable_files files "img"

    if [ ${#files[@]} -eq 0 ]; then
        warn "No GSI image found."
        pause
        return 1
    fi

    local i=1
    for f in "${files[@]}"; do
        local name size
        name=$(basename "$f")
        size=$(hr_size $(stat -c%s "$f" 2>/dev/null || echo 0))
        if [[ "$name" == *.xz ]]; then
            printf "  \( {YELLOW}[%d] \){RESET} %-45s %s  \( {YELLOW}(extract first) \){RESET}\n" "$i" "$name" "$size"
        else
            printf "  \( {GREEN}[%d] \){RESET} %-45s %s\n" "$i" "$name" "$size"
        fi
        ((i++))
    done

    echo ""
    printf "  Select GSI (0 = cancel): "
    read -r choice
    if [[ ! "\( choice" =\~ ^[0-9]+ \) ]] || [ "$choice" -le 0 ] || [ "$choice" -gt ${#files[@]} ]; then
        say "Cancelled."; pause; return 0
    fi

    local gsi="\( {files[ \)((choice-1))]}"
    local gsi_name
    gsi_name=$(basename "$gsi")

    if [[ "$gsi_name" == *.xz ]]; then
        warn "Compressed file detected. Extract first:"
        echo -e "  ${CYAN}xz -d \"\( gsi\" \){RESET}"
        pause
        return 0
    fi

    ok "Selected: $gsi_name"
    warn "GSI flashing is device-specific. Proceed with caution."
    printf "  Continue? (y/N): "
    read -r conf
    [[ ! "\( conf" =\~ ^[yY] \) ]] && { say "Cancelled."; pause; return 0; }

    animate "Trying fastbootd..." fastboot reboot fastboot
    sleep 2
    animate "Flashing system" fastboot flash system "$gsi"
    if [ $? -eq 0 ]; then
        ok "GSI flash command finished."
        info "You may need to wipe data after this."
    else
        bad "Failed. Check if your device needs different partition name."
        tail -n 5 "$LAST_OUT"
    fi
    pause
}

flash_fastboot_screen() {
    clear
    echo -e "\n\( {BOLD}=== Fastboot ROM Package === \){RESET}"
    warn "This feature is under development."
    info "For now extract the ROM and flash images one by one (Option 1)."
    pause
}

# ---------- Device Scanner (with Back option) ----------
scan_device_screen() {
    while true; do
        clear
        echo -e "\n\( {BOLD}=== Device Scanner === \){RESET}\n"

        spin_msg "Scanning devices" 1

        local fb_status="\( {RED}Not found \){RESET}"
        local adb_status="\( {RED}Not found \){RESET}"
        local mode="None"

        if fastboot devices 2>/dev/null | grep -q "fastboot"; then
            fb_status="\( {GREEN}Connected \){RESET}"
            mode="Fastboot"
        fi

        if adb devices 2>/dev/null | grep -q "device$"; then
            adb_status="\( {GREEN}Connected (ADB) \){RESET}"
            mode="ADB"
        elif adb devices 2>/dev/null | grep -q "sideload$"; then
            adb_status="\( {GREEN}Connected (Sideload) \){RESET}"
            mode="Sideload"
        fi

        echo -e "  Fastboot : $fb_status"
        echo -e "  ADB      : $adb_status"
        echo -e "  Current  : ${CYAN}\( mode \){RESET}"
        echo ""

        if [ "$mode" = "Fastboot" ]; then
            echo -e "  Product  : $(fb_var product)"
            echo -e "  Slot     : $(fb_var current-slot)"
            echo -e "  Unlocked : $(fb_var unlocked)"
            echo -e "  Serial   : $(fb_var serialno)"
        elif [ "$mode" = "None" ]; then
            echo -e "  \( {YELLOW}No device detected. \){RESET}"
            echo -e "  \( {GRAY}• Put phone in Fastboot or enable USB Debugging \){RESET}"
            echo -e "  \( {GRAY}• Check cable / USB mode \){RESET}"
        fi

        echo ""
        echo -e "  \( {CYAN}1 \){RESET}) Refresh"
        echo -e "  \( {CYAN}2 \){RESET}) Detailed Info"
        echo -e "  \( {CYAN}0 \){RESET}) Back to Main Menu"
        echo ""
        printf "  Select: "
        read -r opt

        case "${opt:-}" in
            1) continue ;;
            2) device_info_screen ;;
            0) return 0 ;;
            *) bad "Invalid"; sleep 0.6 ;;
        esac
    done
}

device_info_screen() {
    clear
    echo -e "\n\( {BOLD}=== Device Information === \){RESET}\n"

    if fastboot devices 2>/dev/null | grep -q "fastboot"; then
        echo "--------------------------------------------"
        echo -e "  Product      : $(fb_var product)"
        echo -e "  Current Slot : $(fb_var current-slot)"
        echo -e "  Unlocked     : $(fb_var unlocked)"
        echo -e "  Serial       : $(fb_var serialno)"
        echo -e "  Bootloader   : $(fb_var version-bootloader)"
        echo "--------------------------------------------"
    elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
        adb devices -l
    else
        bad "No device connected."
    fi
    pause
}

switch_slot_screen() {
    clear
    echo -e "\n\( {BOLD}=== Switch A/B Slot === \){RESET}\n"
    check_fastboot_device || return 1

    echo -e "  Current slot: \( {CYAN} \)(fb_var current-slot)${RESET}"
    printf "  Switch to (a/b): "
    read -r slot
    slot="${slot,,}"
    if [[ "\( slot" =\~ ^[ab] \) ]]; then
        animate "Switching to slot $slot" fastboot set_active "$slot"
        [ $? -eq 0 ] && ok "Switched to slot $slot" || bad "Failed"
    else
        bad "Invalid slot"
    fi
    pause
}

reboot_screen() {
    clear
    echo -e "\n\( {BOLD}=== Reboot Options === \){RESET}\n"
    echo "  1) System"
    echo "  2) Recovery"
    echo "  3) Bootloader"
    echo "  4) Fastbootd"
    echo "  0) Back"
    printf "\n  Select: "
    read -r opt

    case "${opt:-}" in
        1)
            if fastboot devices 2>/dev/null | grep -q "fastboot"; then
                animate "Rebooting to system" fastboot reboot
            elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
                animate "Rebooting to system" adb reboot
            else bad "No device"; pause; return; fi
            ok "Done"
            ;;
        2)
            if fastboot devices 2>/dev/null | grep -q "fastboot"; then
                animate "Rebooting to recovery" fastboot reboot recovery
            elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
                animate "Rebooting to recovery" adb reboot recovery
            else bad "No device"; pause; return; fi
            ok "Done"
            ;;
        3)
            if fastboot devices 2>/dev/null | grep -q "fastboot"; then
                animate "Rebooting to bootloader" fastboot reboot bootloader
            elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
                animate "Rebooting to bootloader" adb reboot bootloader
            else bad "No device"; pause; return; fi
            ok "Done"
            ;;
        4)
            if fastboot devices 2>/dev/null | grep -q "fastboot"; then
                animate "Rebooting to fastbootd" fastboot reboot fastboot
            elif adb devices 2>/dev/null | grep -qE "(device|sideload)$"; then
                animate "Rebooting to fastbootd" adb reboot fastboot
            else bad "No device"; pause; return; fi
            ok "Done"
            ;;
        *) say "Cancelled" ;;
    esac
    pause
}

wipe_data_screen() {
    clear
    echo -e "\n\( {BOLD}=== Factory Reset / Wipe Data === \){RESET}\n"
    check_fastboot_device || return 1

    echo -e "\( {RED}WARNING: All user data will be erased! \){RESET}"
    printf "  Type \( {BOLD}WIPE \){RESET} to confirm: "
    read -r conf
    if [ "$conf" = "WIPE" ]; then
        animate "Wiping data" fastboot -w
        if [ $? -eq 0 ]; then
            ok "Wipe successful"
        else
            warn "Trying manual erase..."
            animate "Erasing userdata" fastboot erase userdata
            animate "Erasing metadata" fastboot erase metadata
            ok "Manual wipe done"
        fi
    else
        say "Cancelled"
    fi
    pause
}

# ===================== MAIN MENU =====================
main_menu() {
    check_tools
    while true; do
        clear

        local fb_dot="\( {RED}● \){RESET}"
        local adb_dot="\( {RED}● \){RESET}"
        local py_dot="\( {RED}● \){RESET}"
        local dev_text="\( {RED}Not connected \){RESET}"

        if fastboot devices 2>/dev/null | grep -q "fastboot"; then
            fb_dot="\( {GREEN}● \){RESET}"
            dev_text="\( {GREEN}Fastboot \){RESET}"
        fi
        if adb devices 2>/dev/null | grep -q "device$"; then
            adb_dot="\( {GREEN}● \){RESET}"
            [[ "\( dev_text" == *"Not"* ]] && dev_text=" \){GREEN}ADB${RESET}"
        elif adb devices 2>/dev/null | grep -q "sideload$"; then
            adb_dot="\( {GREEN}● \){RESET}"
            [[ "\( dev_text" == *"Not"* ]] && dev_text=" \){GREEN}Sideload${RESET}"
        fi
        command -v python3 >/dev/null 2>&1 && py_dot="\( {GREEN}● \){RESET}"

        local file_count=0
        if [ -d "$DL_DIR" ]; then
            file_count=$(find "$DL_DIR" -maxdepth 1 -type f \( \
                -name "*.img" -o -name "*.zip" -o -name "*.img.xz" \
            \) 2>/dev/null | wc -l)
        fi

        echo -e "\( {GREEN}+----------------------------------------------+ \){RESET}"
        echo -e "\( {GREEN}| \){RESET}        \( {BOLD}ANDROID ULTIMATE FLASHER \){RESET}           \( {GREEN}| \){RESET}"
        echo -e "\( {GREEN}| \){RESET}     Version ${VERSION}  •  Created by Rudra       \( {GREEN}| \){RESET}"
        echo -e "\( {GREEN}+----------------------------------------------+ \){RESET}"
        echo ""
        echo -e "  Tools    $fb_dot fastboot   $adb_dot adb   $py_dot python"
        echo -e "  Device   $dev_text"
        echo -e "  Files    ${CYAN}\( file_count \){RESET}  items found"
        echo -e "  Path     ${GRAY}\( DL_DIR \){RESET}"
        echo ""
        echo -e " \( {CYAN}─ FLASH ─ \){RESET}"
        echo -e "  1 \( {GREEN}● \){RESET} Flash Image          .img / vbmeta / boot..."
        echo -e "  2 \( {GREEN}● \){RESET} Custom ROM (ADB)     sideload .zip"
        echo -e "  3 \( {YELLOW}● \){RESET} Fastboot ROM         (under development)"
        echo -e "  4 \( {GREEN}● \){RESET} Flash GSI            system image"
        echo -e " \( {CYAN}─ DEVICE ─ \){RESET}"
        echo -e "  5 \( {GREEN}● \){RESET} Device Scanner       live status + refresh"
        echo -e "  6 \( {GREEN}● \){RESET} Device Info"
        echo -e "  7 \( {GREEN}● \){RESET} Switch A/B Slot"
        echo -e "  8 \( {GREEN}● \){RESET} Reboot Options"
        echo -e "  9 \( {RED}● \){RESET} Erase Data           factory reset"
        echo -e " \( {CYAN}─ EXIT ─ \){RESET}"
        echo -e "  0 \( {GREEN}● \){RESET} Exit"
        echo ""
        echo -e "  \( {GREEN}● \){RESET} Safe     \( {YELLOW}● \){RESET} Careful     \( {RED}● \){RESET} Dangerous"
        echo ""
        printf "  Select: "
        read -r opt || exit 0

        case "${opt:-}" in
            1) flash_image_screen ;;
            2) flash_sideload_screen ;;
            3) flash_fastboot_screen ;;
            4) flash_gsi_screen ;;
            5) scan_device_screen ;;
            6) device_info_screen ;;
            7) switch_slot_screen ;;
            8) reboot_screen ;;
            9) wipe_data_screen ;;
            0) say "Exiting..."; exit 0 ;;
            *) bad "Invalid option"; sleep 0.6 ;;
        esac
    done
}

# Install as command 'rudra'
install_tool() {
    mkdir -p "$BASE_DIR" "$TERMUX_PREFIX/bin"
    local target="$BASE_DIR/setup.sh"
    if [ -f "$0" ]; then
        cp "$0" "$target" 2>/dev/null || true
        chmod +x "$target" 2>/dev/null || true
        ln -sf "$target" "$TERMUX_PREFIX/bin/rudra" 2>/dev/null || true
        chmod +x "$TERMUX_PREFIX/bin/rudra" 2>/dev/null || true
    fi
}

install_tool

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi