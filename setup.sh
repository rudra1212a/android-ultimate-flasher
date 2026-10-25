
#!/usr/bin/env bash
# Android Ultimate Flasher v1.2 - Termux
# Created by Rudra
# Use firmware only for the exact device/model/region.
# Flashing can brick a device or erase data.

set -uo pipefail

VERSION="1.2"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"

mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RESET='\033[0m'

log() {
    local level="${1:-INFO}"
    shift || true
    printf '[%s] [%s] %s\n' \
        "$(date '+%F %T')" "$level" "$*" >> "$LOG_FILE"
}

say() {
    printf '%b[*]%b %s\n' "$BLUE" "$RESET" "$*"
    log INFO "$*"
}

ok() {
    printf '%b[+]%b %s\n' "$GREEN" "$RESET" "$*"
    log SUCCESS "$*"
}

warn() {
    printf '%b[!]%b %s\n' "$YELLOW" "$RESET" "$*"
    log WARN "$*"
}

bad() {
    printf '%b[-]%b %s\n' "$RED" "$RESET" "$*"
    log ERROR "$*"
}

# Android shared Downloads directory in Termux
DL_DIR="$HOME/storage/downloads"

if [[ ! -d "$DL_DIR" && -d /storage/emulated/0/Download ]]; then
    DL_DIR="/storage/emulated/0/Download"
fi

pause() {
    if [[ -t 0 ]]; then
        printf '\nPress Enter to return to menu...'
        IFS= read -r _ || true
    fi
}

clear_screen() {
    if [[ -t 1 ]]; then
        clear 2>/dev/null || printf '\033[2J\033[H'
    else
        printf '\n'
    fi
}

# Animated command runner
run_animated() {
    local message="$1"
    shift

    "$@" >"$LAST_OUT" 2>&1 &
    local pid=$!
    local spin='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%b[*]%b %s [%c]' \
            "$CYAN" "$RESET" "$message" "${spin:i%4:1}"
        i=$((i + 1))
        sleep 0.12
    done

    local rc=0
    wait "$pid" || rc=$?
    printf '\r\033[K'
    return "$rc"
}

install_deps() {
    local missing=0 cmd

    for cmd in adb fastboot; do
        command -v "$cmd" >/dev/null 2>&1 || missing=1
    done

    if (( missing )); then
        warn "Installing Android platform-tools..."

        if ! command -v pkg >/dev/null 2>&1; then
            bad "Run this script inside Termux."
            return 1
        fi

        pkg update -y &&
            pkg install -y android-tools || {
                bad "Could not install android-tools."
                return 1
            }
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        warn "Python is optional and is not installed."
    fi
}

# Device status detection
adb_state() {
    command -v adb >/dev/null 2>&1 || {
        printf 'adb not installed'
        return
    }

    local out
    out="$(adb devices 2>&1)"

    if printf '%s\n' "$out" |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+device$'; then
        printf 'ADB connected'

    elif printf '%s\n' "$out" |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+unauthorized$'; then
        printf 'USB debugging unauthorized'

    elif printf '%s\n' "$out" |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+offline$'; then
        printf 'ADB device offline'

    elif printf '%s\n' "$out" |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+sideload$'; then
        printf 'Recovery sideload connected'

    else
        printf 'No ADB device'
    fi
}

fb_state() {
    command -v fastboot >/dev/null 2>&1 || {
        printf 'fastboot not installed'
        return
    }

    if fastboot devices 2>/dev/null |
        awk 'NF>=2 && $2=="fastboot" {found=1}
             END {exit !found}'; then
        printf 'Fastboot connected'
    else
        printf 'No fastboot device'
    fi
}

refresh_devices() {
    clear_screen
    printf '=== Device Detection ===\n\n'

    say "Checking ADB and Fastboot..."

    if command -v adb >/dev/null 2>&1; then
        adb start-server >/dev/null 2>&1 || true
    fi

    printf '\nADB:      %s\n' "$(adb_state)"
    printf 'Fastboot: %s\n\n' "$(fb_state)"

    if command -v adb >/dev/null 2>&1; then
        printf '%s\n' '--- adb devices -l ---'
        adb devices -l 2>&1 || true
    fi

    if command -v fastboot >/dev/null 2>&1; then
        printf '\n%s\n' '--- fastboot devices ---'
        fastboot devices 2>&1 || true
    fi

    printf '\nConnection help:\n'
    printf '%s\n' \
        '1. Use a USB data cable and compatible OTG adapter.' \
        '2. For ADB, enable USB debugging and approve the RSA prompt.' \
        '3. For Fastboot, boot the phone into bootloader/Fastboot mode.' \
        '4. Check USB permissions if the device is still missing.' \
        '5. Some Android devices restrict USB-host access.'

    pause
}

check_fastboot() {
    if ! command -v fastboot >/dev/null 2>&1; then
        bad "fastboot is missing. Install android-tools first."
        pause
        return 1
    fi

    if ! fastboot devices 2>/dev/null |
        awk 'NF>=2 && $2=="fastboot" {found=1}
             END {exit !found}'; then
        bad "No Fastboot device detected."
        printf 'Check cable, OTG, bootloader mode and USB permissions.\n'
        pause
        return 1
    fi

    return 0
}

check_adb() {
    if ! command -v adb >/dev/null 2>&1; then
        bad "adb is missing."
        pause
        return 1
    fi

    local out
    out="$(adb devices 2>&1)"

    if ! printf '%s\n' "$out" |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+device$'; then
        bad "No authorized ADB device detected."
        printf '%s\n' "$out"
        printf '\nUnlock phone and approve USB debugging.\n'
        pause
        return 1
    fi

    return 0
}

check_sideload() {
    if ! command -v adb >/dev/null 2>&1; then
        bad "adb is missing."
        pause
        return 1
    fi

    if ! adb devices 2>/dev/null |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+sideload$'; then
        bad "No recovery sideload device detected."
        printf 'Recovery > Apply update > Apply from ADB\n'
        pause
        return 1
    fi

    return 0
}

fb_var() {
    local key="$1"
    local out val

    out="$(fastboot getvar "$key" 2>&1 || true)"

    val="$(printf '%s\n' "$out" |
        sed -nE 's/.*'"$key"'[^:]*:[[:space:]]*([^[:space:]]+).*/\1/p' |
        head -n1 |
        tr -d '\r')"

    printf '%s' "${val:-UNKNOWN}"
}

# Scan and list all top-level Downloads entries
list_download_files() {
    clear_screen
    printf '=== Download Folder Scan ===\n\n'
    printf 'Folder: %s\n\n' "$DL_DIR"

    if [[ ! -d "$DL_DIR" ]]; then
        warn "Downloads folder unavailable."
        printf 'Run termux-setup-storage and grant permission.\n'
        pause
        return
    fi

    local n=0 path

    while IFS= read -r -d '' path; do
        n=$((n + 1))
        printf '  %3d. %s' "$n" "$(basename "$path")"

        if [[ -d "$path" ]]; then
            printf '  [folder]\n'
        else
            printf '  [%s]\n' \
                "$(du -h "$path" 2>/dev/null | cut -f1)"
        fi
    done < <(
        find "$DL_DIR" -mindepth 1 -maxdepth 1 \
            -print0 2>/dev/null | sort -z
    )

    (( n > 0 )) || warn "Folder empty or inaccessible."

    printf '\nFlashable file counts (top-level):\n'

    printf '  .img: %s\n' "$(
        find "$DL_DIR" -maxdepth 1 -type f \
            -iname '*.img' 2>/dev/null | wc -l | tr -d ' '
    )"

    printf '  .zip: %s\n' "$(
        find "$DL_DIR" -maxdepth 1 -type f \
            -iname '*.zip' 2>/dev/null | wc -l | tr -d ' '
    )"

    printf '  .tgz/.tar.gz: %s\n' "$(
        find "$DL_DIR" -maxdepth 1 -type f \
            \( -iname '*.tgz' -o -iname '*.tar.gz' \) \
            2>/dev/null | wc -l | tr -d ' '
    )"

    printf '\n.img.xz and .tgz are archives, not directly flashable images.\n'
    pause
}

# Select a file safely
choose_file() {
    local pattern="$1"
    local label="$2"
    local path
    local -a files=()

    while IFS= read -r -d '' path; do
        [[ -f "$path" ]] && files+=("$path")
    done < <(
        find "$DL_DIR" -maxdepth 1 -type f \
            -iname "$pattern" -print0 2>/dev/null | sort -z
    )

    if ((${#files[@]} == 0)); then
        warn "No $label found in $DL_DIR"
        pause
        return 1
    fi

    local i
    for i in "${!files[@]}"; do
        printf '  [%d] %s\n' \
            "$((i + 1))" "$(basename "${files[$i]}")"
    done

    printf 'Select number (0 to cancel): '
    local choice
    IFS= read -r choice || return 1

    [[ "$choice" =~ ^[0-9]+$ ]] || {
        say "Cancelled."
        return 1
    }

    (( choice > 0 && choice <= ${#files[@]} )) || {
        say "Cancelled."
        return 1
    }

    CHOSEN_FILE="${files[$((choice - 1))]}"
}

flash_image_screen() {
    clear_screen
    printf '=== Flash Individual Image (.img) ===\n\n'

    check_fastboot || return

    [[ -d "$DL_DIR" ]] || {
        bad "Downloads folder unavailable."
        pause
        return
    }

    choose_file '*.img' '.img image' || return

    local image="$CHOSEN_FILE"
    local part confirm vb

    printf '\nSelected: %s\n' "$(basename "$image")"
    printf 'Target partition: '
    IFS= read -r part || return

    part="${part,,}"

    [[ "$part" =~ ^[a-z0-9_]+$ ]] || {
        bad "Invalid partition name."
        pause
        return
    }

    printf 'Type FLASH to confirm flashing %s to %s: ' \
        "$(basename "$image")" "$part"
    IFS= read -r confirm || return

    [[ "$confirm" == FLASH ]] || {
        say "Cancelled."
        pause
        return
    }

    if [[ "$part" == vbmeta* ]]; then
        warn "Disabling AVB can weaken security and cause boot failure."
        printf 'Use verification-disable flags? Type YES to confirm: '
        IFS= read -r vb || return

        if [[ "$vb" == YES ]]; then
            if run_animated "Flashing $part" \
                fastboot --disable-verity --disable-verification \
                flash "$part" "$image"; then
                ok "Fastboot reported success."
            else
                bad "Flash failed:"
                tail -n 12 "$LAST_OUT"
            fi
            pause
            return
        fi
    fi

    if run_animated "Flashing $part" \
        fastboot flash "$part" "$image"; then
        ok "Fastboot reported success."
    else
        bad "Flash failed:"
        tail -n 12 "$LAST_OUT"
    fi

    pause
}

flash_sideload_screen() {
    clear_screen
    printf '=== ADB Sideload ZIP ===\n\n'

    check_sideload || return

    [[ -d "$DL_DIR" ]] || {
        bad "Downloads folder unavailable."
        pause
        return
    }

    choose_file '*.zip' '.zip package' || return

    local zip="$CHOSEN_FILE"
    local confirm rc

    printf '\nSelected: %s\n' "$(basename "$zip")"
    printf 'Use only a package made for this exact device.\n'
    printf 'Type SIDELOAD to continue: '
    IFS= read -r confirm || return

    [[ "$confirm" == SIDELOAD ]] || {
        say "Cancelled."
        pause
        return
    }

    adb sideload "$zip" >"$LAST_OUT" 2>&1
    rc=$?

    cat "$LAST_OUT"

    if (( rc == 0 )); then
        ok "Sideload command completed. Verify recovery status."
    else
        warn "adb sideload exited with code $rc."
        printf 'Check the final message on the recovery screen.\n'
    fi

    pause
}

fastboot_rom_preview() {
    clear_screen
    printf '=== Fastboot ROM Package Preview ===\n\n'

    warn "Preview only: this version DOES NOT flash Fastboot ROM archives."

    if [[ -d "$DL_DIR" ]]; then
        find "$DL_DIR" -maxdepth 1 -type f \
            \( -iname '*.tgz' -o -iname '*.tar.gz' \
               -o -iname '*.zip' -o -iname '*.xz' \) \
            -printf '  %f (%s bytes)\n' 2>/dev/null | head -n 40
    fi

    printf '\nVerify ROM device, region and package instructions before flashing.\n'
    pause
}

flash_gsi_screen() {
    clear_screen
    printf '=== GSI ===\n\n'

    warn "GSI flashing is not implemented in v1.2."
    printf 'No flash command will run from this screen.\n'
    printf 'GSI installation depends on Treble support, partitions and AVB.\n'

    pause
}

device_info_screen() {
    clear_screen
    printf '=== Device Information ===\n\n'

    check_fastboot || return

    printf 'Product     : %s\n' "$(fb_var product)"
    printf 'Active slot : %s\n' "$(fb_var current-slot)"
    printf 'Unlocked    : %s\n' "$(fb_var unlocked)"

    pause
}

switch_slot_screen() {
    clear_screen
    printf '=== Switch A/B Slot ===\n\n'

    check_fastboot || return

    local current slot confirm
    current="$(fb_var current-slot)"

    printf 'Current slot: %s\n' "$current"
    printf 'Target slot (a/b): '
    IFS= read -r slot || return
    slot="${slot,,}"

    [[ "$slot" =~ ^[ab]$ ]] || {
        bad "Choose a or b."
        pause
        return
    }

    [[ "$current" == "$slot" ]] && {
        say "Slot $slot is already active."
        pause
        return
    }

    printf 'Changing slots can make the phone unbootable.\n'
    printf 'Type SLOT to continue: '
    IFS= read -r confirm || return

    [[ "$confirm" == SLOT ]] || {
        say "Cancelled."
        pause
        return
    }

    if run_animated "Switching to slot $slot" \
        fastboot set_active "$slot"; then
        ok "Fastboot reported slot $slot active."
    else
        bad "Slot switch failed:"
        tail -n 10 "$LAST_OUT"
    fi

    pause
}

check_fastboot_quiet() {
    command -v fastboot >/dev/null 2>&1 &&
        fastboot devices 2>/dev/null |
        awk 'NF>=2 && $2=="fastboot" {found=1}
             END {exit !found}'
}

check_adb_quiet() {
    command -v adb >/dev/null 2>&1 &&
        adb devices 2>/dev/null |
        grep -qE '^[[:space:]]*[^[:space:]]+[[:space:]]+device$'
}

reboot_screen() {
    clear_screen
    printf '=== Reboot Options ===\n'
    printf ' 1) System\n 2) Recovery\n 3) Bootloader/Fastboot\n 0) Back\n'
    printf 'Select: '

    local choice
    IFS= read -r choice || return

    case "$choice" in
        1)
            if check_fastboot_quiet; then
                run_animated "Rebooting system" fastboot reboot
            elif check_adb_quiet; then
                run_animated "Rebooting system" adb reboot
            else
                bad "No connected ADB/Fastboot device."
            fi
            ;;
        2)
            if check_fastboot_quiet; then
                run_animated "Rebooting recovery" fastboot reboot recovery
            elif check_adb_quiet; then
                run_animated "Rebooting recovery" adb reboot recovery
            else
                bad "No connected ADB/Fastboot device."
            fi
            ;;
        3)
            if check_fastboot_quiet; then
                run_animated "Rebooting bootloader" fastboot reboot bootloader
            elif check_adb_quiet; then
                run_animated "Rebooting bootloader" adb reboot bootloader
            else
                bad "No connected ADB/Fastboot device."
            fi
            ;;
        0) return ;;
        *) warn "Invalid choice." ;;
    esac

    pause
}

wipe_data_screen() {
    clear_screen
    printf '=== Factory Reset / Wipe Data ===\n\n'

    check_fastboot || return

    warn "DANGER: fastboot -w permanently erases user data."
    printf 'Type WIPE-ALL-DATA to confirm: '

    local confirm
    IFS= read -r confirm || return

    [[ "$confirm" == WIPE-ALL-DATA ]] || {
        say "Wipe cancelled."
        pause
        return
    }

    if run_animated "Wiping user data" fastboot -w; then
        ok "Fastboot reported wipe success."
    else
        bad "Wipe failed. No automatic fallback erase will be attempted."
        tail -n 12 "$LAST_OUT"
    fi

    pause
}

main_menu() {
    install_deps || true

    while true; do
        clear_screen

        local adb_status fb_status dev_text
        local files_count dirs_count

        adb_status="$(adb_state)"
        fb_status="$(fb_state)"
        dev_text="Not connected"

        if [[ "$adb_status" == "ADB connected" ||
              "$adb_status" == "Recovery sideload connected" ||
              "$fb_status" == "Fastboot connected" ]]; then
            dev_text="Connected"
        fi

        files_count=0
        dirs_count=0

        if [[ -d "$DL_DIR" ]]; then
            files_count="$(
                find "$DL_DIR" -maxdepth 1 -type f \
                    \( -iname '*.img' -o -iname '*.zip' \) \
                    2>/dev/null | wc -l | tr -d ' '
            )"

            dirs_count="$(
                find "$DL_DIR" -mindepth 1 -maxdepth 1 \
                    -type d 2>/dev/null | wc -l | tr -d ' '
            )"
        fi

        printf '%b+------------------------------------------------+%b\n' "$GREEN" "$RESET"
        printf '%b|%b           ANDROID ULTIMATE FLASHER              %b|%b\n' "$GREEN" "$RESET" "$GREEN" "$RESET"
        printf '%b|%b          Version %s • Created by Rudra           %b|%b\n' "$GREEN" "$RESET" "$VERSION" "$GREEN" "$RESET"
        printf '%b+------------------------------------------------+%b\n\n' "$GREEN" "$RESET"

        printf 'ADB: %s\n' "$adb_status"
        printf 'Fastboot: %s\n' "$fb_status"
        printf 'Device: %s\n' "$dev_text"
        printf 'Downloads: %s flash-ready files, %s folders\n' "$files_count" "$dirs_count"
        printf 'Path: %s\n\n' "$DL_DIR"

        printf '%b- FLASH -%b\n' "$CYAN" "$RESET"
        printf '  1  Flash Image (.img)\n'
        printf '  2  Custom ROM via ADB sideload (.zip)\n'
        printf '  3  Fastboot ROM package preview (not flashing)\n'
        printf '  4  GSI (not implemented)\n'

        printf '\n%b- DEVICE -%b\n' "$CYAN" "$RESET"
        printf '  5  Fastboot Device Info\n'
        printf '  6  Switch A/B Slot\n'
        printf '  7  Reboot options\n'
        printf '  8  Wipe Data (DANGER)\n'
        printf '  9  Refresh / Detect Device\n'
        printf ' 10  Scan Downloads folder\n'

        printf '\n%b- EXIT -%b\n  0  Exit\n\n' "$CYAN" "$RESET"
        printf '%b●%b Safe/read-only   %b●%b Caution   %b●%b Data destructive\n\n' "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"

        printf 'Select: '
        local opt
        IFS= read -r opt || exit 0

        case "$opt" in
            1) flash_image_screen ;;
            2) flash_sideload_screen ;;
            3) fastboot_rom_preview ;;
            4) flash_gsi_screen ;;
            5) device_info_screen ;;
            6) switch_slot_screen ;;
            7) reboot_screen ;;
            8) wipe_data_screen ;;
            9) refresh_devices ;;
            10) list_download_files ;;
            0)
                say "Exiting."
                exit 0
                ;;
            *)
                bad "Invalid option. Enter a listed number."
                sleep 1
                ;;
        esac
    done
}

install_tool() {
    mkdir -p "$BASE_DIR" "$TERMUX_PREFIX/bin" 2>/dev/null || return 0

    local self
    self="$(realpath "$0" 2>/dev/null || printf '%s' "$0")"

    if [[ -f "$self" && "$self" != "$BASE_DIR/setup.sh" ]]; then
        cp "$self" "$BASE_DIR/setup.sh" 2>/dev/null || true
    fi

    if [[ -f "$BASE_DIR/setup.sh" ]]; then
        chmod 700 "$BASE_DIR/setup.sh" 2>/dev/null || true
        ln -sf "$BASE_DIR/setup.sh" "$TERMUX_PREFIX/bin/rudra" 2>/dev/null || true
    fi
}

install_tool

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi
