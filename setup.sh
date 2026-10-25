#!/usr/bin/env bash
# ==============================================================================
# Script Name: Android Ultimate Flasher
# Description: Professional Android flashing tool for Termux (Version 1.2)
# ==============================================================================

set -uo pipefail

VERSION="1.2"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"

mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

# ---------------------------- UI Colors --------------------------------------
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
GRAY='\033[1;90m'
BOLD='\033[1m'
RESET='\033[0m'

SPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

cursor_show() { printf '\033[?25h'; }
cursor_hide() { printf '\033[?25l'; }
cleanup() { cursor_show; }
trap cleanup EXIT
trap 'cursor_show; echo; echo -e "${YELLOW}[!]${RESET} Interrupted."; exit 130' INT TERM

log() {
    local level="${1:-INFO}"
    shift || true
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

say()  { echo -e "${BLUE}[*]${RESET} $*"; log "INFO" "$*"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; log "SUCCESS" "$*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; log "WARN" "$*"; }
bad()  { echo -e "${RED}[-]${RESET} $*"; log "ERROR" "$*"; }

# ---------------------------- Animations -------------------------------------
# Spinner while a command runs in background
animate() {
    local message="$1"
    shift
    ("$@") > "$LAST_OUT" 2>&1 &
    local pid=$!
    local i=0
    cursor_hide
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}[%s]${RESET} %s ..." "${SPIN_FRAMES[$((i % 10))]}" "$message"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    local rc=$?
    printf "\r\033[K"
    cursor_show
    return $rc
}

# Smooth progress bar (visual only)
progress_bar() {
    local msg="$1" steps="${2:-24}" i filled empty
    cursor_hide
    for ((i = 0; i <= steps; i++)); do
        filled=$(printf '%*s' "$i" '' | tr ' ' '#')
        empty=$(printf '%*s' "$((steps - i))" '' | tr ' ' '.')
        printf "\r${CYAN}[*]${RESET} %s [${GREEN}%s${GRAY}%s${RESET}] %3d%%" \
            "$msg" "$filled" "$empty" "$((i * 100 / steps))"
        sleep 0.02
    done
    echo ""
    cursor_show
}

# Typewriter effect
typewriter() {
    local text="$1" i
    for ((i = 0; i < ${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep 0.012
    done
    echo ""
}

center() {
    local text="$1" width="$2"
    local len=${#text}
    local left=$(( (width - len) / 2 ))
    local right=$(( width - len - left ))
    [ "$left" -lt 0 ] && left=0
    [ "$right" -lt 0 ] && right=0
    printf "%*s%s%*s" "$left" "" "$text" "$right" ""
}

pause() {
    if [ -t 0 ]; then
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
    fi
}

header() {
    clear
    echo -e "${CYAN}=== $1 ===${RESET}"
    echo ""
}

# ---------------------------- Storage setup ----------------------------------
DL_DIR=""

find_dl_dir() {
    local d
    for d in "$HOME/storage/downloads" "$HOME/storage/shared/Download" \
             "/storage/emulated/0/Download" "/sdcard/Download"; do
        if [ -d "$d" ] && ls "$d" >/dev/null 2>&1; then
            DL_DIR="$d"
            return 0
        fi
    done
    return 1
}

setup_storage() {
    if find_dl_dir; then
        return 0
    fi
    warn "Storage access not available. Requesting permission..."
    if command -v termux-setup-storage >/dev/null 2>&1; then
        termux-setup-storage
        local t
        for t in $(seq 1 20); do
            printf "\r${CYAN}[%s]${RESET} Waiting for storage permission (%ss) ..." "${SPIN_FRAMES[$((t % 10))]}" "$t"
            sleep 1
            if find_dl_dir; then
                printf "\r\033[K"
                ok "Storage linked: $DL_DIR"
                return 0
            fi
        done
        printf "\r\033[K"
    fi
    DL_DIR="$HOME/Download"
    mkdir -p "$DL_DIR"
    bad "Could not access phone Downloads. Using $DL_DIR"
    warn "Allow storage permission for Termux, then restart the tool (or press 'r' in menu)."
    sleep 2
}

# find_files <maxdepth> <pattern>...   -> prints sorted paths
find_files() {
    local depth="$1"
    shift
    local -a args=()
    local p first=1
    for p in "$@"; do
        [ "$first" -eq 0 ] && args+=(-o)
        args+=(-iname "$p")
        first=0
    done
    [ -d "$DL_DIR" ] || return 0
    find -L "$DL_DIR" -maxdepth "$depth" -type f \( "${args[@]}" \) 2>/dev/null | sort
}

human_size() {
    local s
    s=$(du -h "$1" 2>/dev/null | cut -f1)
    echo "${s:-?}"
}

# pick_file <title> <maxdepth> <pattern>...  -> sets PICKED, returns 1 on cancel/none
PICKED=""
pick_file() {
    local title="$1" depth="$2"
    shift 2
    local -a files=()
    mapfile -t files < <(find_files "$depth" "$@")

    echo -e "  ${GRAY}Folder: $DL_DIR${RESET}"
    echo ""
    if [ "${#files[@]}" -eq 0 ] || [ -z "${files[0]:-}" ]; then
        warn "No matching files found in: $DL_DIR"
        echo -e "  ${GRAY}Looking for: $*${RESET}"
        return 1
    fi

    local i=0 f rel
    for f in "${files[@]}"; do
        i=$((i + 1))
        rel="${f#"$DL_DIR"/}"
        echo -e "  ${GREEN}[$i]${RESET} $rel ${GRAY}($(human_size "$f"))${RESET}"
    done
    echo ""
    local choice
    printf "  %s (0 to cancel): " "$title"
    read -r choice || choice=0
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -le 0 ] || [ "$choice" -gt "${#files[@]}" ]; then
        return 1
    fi
    PICKED="${files[$((choice - 1))]}"
    return 0
}

# ---------------------------- Tools & Devices --------------------------------
check_tools() {
    local missing=0 cmd
    for cmd in fastboot adb; do
        command -v "$cmd" >/dev/null 2>&1 || missing=1
    done
    if [ "$missing" -eq 1 ]; then
        warn "fastboot/adb not found. Installing android-tools..."
        if animate "Installing android-tools" bash -c "pkg update -y && pkg install -y android-tools"; then
            ok "android-tools installed."
        else
            bad "Failed to install android-tools. Check internet connection."
            tail -n 3 "$LAST_OUT"
            sleep 2
        fi
    fi
}

fb_present()      { fastboot devices 2>/dev/null | grep -q "fastboot"; }
adb_present()     { adb devices 2>/dev/null | awk 'NR>1 && ($2=="device" || $2=="sideload" || $2=="recovery"){f=1} END{exit !f}'; }
sideload_present(){ adb devices 2>/dev/null | awk 'NR>1 && $2=="sideload"{f=1} END{exit !f}'; }

# wait_for_device <fastboot|sideload|any> -> 0 when found, 1 if user went back
wait_for_device() {
    local mode="$1" label tip
    case "$mode" in
        fastboot) label="fastboot"; tip="Phone: power off, then hold Power + Volume Down (bootloader mode)." ;;
        sideload) label="ADB sideload"; tip="Phone: Recovery > Apply update > Apply from ADB." ;;
        *)        label="fastboot / ADB"; tip="Connect phone via USB (OTG) with USB debugging or fastboot mode." ;;
    esac

    _present() {
        case "$mode" in
            fastboot) fb_present ;;
            sideload) sideload_present ;;
            *)        fb_present || adb_present ;;
        esac
    }

    if _present; then
        return 0
    fi

    echo -e "  ${GRAY}$tip${RESET}"
    echo ""
    local start=$SECONDS i=0 key=""
    cursor_hide
    while true; do
        printf "\r\033[K${CYAN}[%s]${RESET} Searching for %s device... %ss  ${GRAY}[0 / q = Back]${RESET}" \
            "${SPIN_FRAMES[$((i % 10))]}" "$label" "$((SECONDS - start))"
        i=$((i + 1))

        if [ -t 0 ]; then
            if read -rsn1 -t 0.2 key; then
                case "$key" in
                    0|q|Q|b|B)
                        printf "\r\033[K"
                        cursor_show
                        say "Search cancelled."
                        return 1
                        ;;
                esac
            fi
        else
            sleep 0.2
        fi

        if [ $((i % 5)) -eq 0 ]; then
            if _present; then
                printf "\r\033[K"
                cursor_show
                ok "Device found!"
                sleep 0.4
                return 0
            fi
        fi
    done
}

fb_var() {
    local var_name="${1:-}" val
    val=$(fastboot getvar "$var_name" 2>&1 | awk -F': *' -v k="$var_name" \
        '{sub(/^\(bootloader\) /,"")} tolower($1)==tolower(k){print $2; exit}' | tr -d '\r')
    echo "${val:-UNKNOWN}"
}

# ---------------------------- Screens ----------------------------------------
CRITICAL_PARTS="bootloader|xbl|xbl_config|abl|modem|persist|efs|modemst1|modemst2|fsg|sbl1|tz|aboot|rpm|hyp|devcfg|keymaster|cmnlib|cmnlib64"

flash_image_screen() {
    header "Flash Individual Image (.img)"
    wait_for_device fastboot || return 0
    echo ""

    pick_file "Select image number to flash" 3 "*.img" || { say "Cancelled."; pause; return 0; }
    local selected_img="$PICKED"
    say "Selected Image: $(basename "$selected_img")"

    local guess
    guess="$(basename "$selected_img")"
    guess="${guess%.*}"
    guess="${guess,,}"

    echo -e "  ${GRAY}Common partitions: boot, recovery, vbmeta, dtbo, vendor_boot${RESET}"
    local target_part
    printf "  Target partition [%s]: " "$guess"
    read -r target_part || target_part=""
    target_part="${target_part:-$guess}"

    if [[ ! "$target_part" =~ ^[a-zA-Z0-9_]+$ ]]; then
        bad "Invalid partition name."
        pause
        return 1
    fi

    if [[ "$target_part" =~ ^($CRITICAL_PARTS)$ ]]; then
        warn "[$target_part] is a CRITICAL partition. A wrong image can hard-brick your phone!"
        local crit
        printf "  Type YES to continue: "
        read -r crit || crit=""
        if [ "$crit" != "YES" ]; then
            say "Flashing cancelled."
            pause
            return 0
        fi
    fi

    local confirm
    printf "  Flash [%s] to partition [%s]? (y/N): " "$(basename "$selected_img")" "$target_part"
    read -r confirm || confirm=""
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        say "Flashing cancelled."
        pause
        return 0
    fi

    local rc
    if [[ "$target_part" == vbmeta* ]]; then
        local vb_conf
        printf "  Disable verity and verification? (y/N): "
        read -r vb_conf || vb_conf=""
        if [[ "$vb_conf" =~ ^[yY]$ ]]; then
            animate "Flashing $target_part (verity/verification disabled)" \
                fastboot --disable-verity --disable-verification flash "$target_part" "$selected_img"
            rc=$?
            if [ "$rc" -eq 0 ]; then
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
    rc=$?
    if [ "$rc" -eq 0 ]; then
        ok "Image flashed successfully!"
    else
        bad "Flashing failed! Last output:"
        tail -n 5 "$LAST_OUT"
    fi
    pause
}

flash_sideload_screen() {
    header "ADB Sideload Custom ROM"
    wait_for_device sideload || return 0
    echo ""

    pick_file "Select zip number to sideload" 2 "*.zip" || { say "Cancelled."; pause; return 0; }
    local selected_zip="$PICKED"
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
    header "Fastboot ROM Package"
    warn "Feature is under development."
    pause
}

flash_gsi_screen() {
    header "Flash GSI (Generic System Image)"
    warn "Feature is under development."
    pause
}

device_info_screen() {
    header "Device Information & Status"
    wait_for_device fastboot || return 0
    echo ""
    progress_bar "Reading device info" 16
    local product slot unlocked serial
    product=$(fb_var product)
    slot=$(fb_var current-slot)
    unlocked=$(fb_var unlocked)
    serial=$(fb_var serialno)
    echo "------------------------------------------"
    echo " Product : $product"
    echo " Serial  : $serial"
    echo " Slot    : $slot"
    echo " Unlocked: $unlocked"
    echo "------------------------------------------"
    pause
}

switch_slot_screen() {
    header "Switch A/B Slot"
    wait_for_device fastboot || return 0
    echo ""
    local slot
    printf "  Enter target slot (a / b, 0 to cancel): "
    read -r slot || slot=0
    slot="${slot,,}"
    if [[ "$slot" =~ ^[ab]$ ]]; then
        if animate "Switching active slot to $slot" fastboot set_active "$slot"; then
            ok "Successfully switched to slot $slot."
        else
            bad "Failed to switch slot."
            tail -n 3 "$LAST_OUT"
        fi
    else
        say "Cancelled."
    fi
    pause
}

reboot_to() {
    local mode="$1" label="$2"
    wait_for_device any || return 1
    local rc
    if fb_present; then
        case "$mode" in
            system) animate "Rebooting to $label" fastboot reboot ;;
            *)      animate "Rebooting to $label" fastboot reboot "$mode" ;;
        esac
        rc=$?
    else
        case "$mode" in
            system) animate "Rebooting to $label" adb reboot ;;
            *)      animate "Rebooting to $label" adb reboot "$mode" ;;
        esac
        rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
        ok "Reboot command sent ($label)."
    else
        bad "Reboot failed."
        tail -n 3 "$LAST_OUT"
    fi
    return 0
}

reboot_screen() {
    header "Reboot Options"
    echo " 1) Reboot to System"
    echo " 2) Reboot to Recovery"
    echo " 3) Reboot to Bootloader"
    echo " 0) Back"
    echo ""
    printf " Select mode: "
    local r_opt
    read -r r_opt || r_opt=0
    case "${r_opt:-}" in
        1) reboot_to system "System" ;;
        2) reboot_to recovery "Recovery" ;;
        3) reboot_to bootloader "Bootloader" ;;
        *) return 0 ;;
    esac
    pause
}

wipe_data_screen() {
    header "Factory Reset / Wipe Data"
    wait_for_device fastboot || return 0
    echo ""
    warn "WARNING: This will erase ALL personal data!"
    local confirm
    printf "  Type 'WIPE' to confirm (anything else cancels): "
    read -r confirm || confirm=""
    if [ "$confirm" = "WIPE" ]; then
        if animate "Wiping user data" fastboot -w; then
            ok "Data wiped successfully."
        else
            warn "Standard wipe failed, trying manual userdata/metadata erase..."
            if animate "Erasing userdata" fastboot erase userdata; then
                animate "Erasing metadata" fastboot erase metadata || true
                ok "Manual data erase completed."
            else
                bad "Wipe operation failed completely."
                tail -n 3 "$LAST_OUT"
            fi
        fi
    else
        say "Wipe cancelled."
    fi
    pause
}

# ---------------------------- Main Menu --------------------------------------
splash() {
    clear
    echo ""
    typewriter "  ANDROID ULTIMATE FLASHER  v${VERSION}"
    echo ""
    progress_bar "Initializing" 24
    check_tools
    setup_storage
    progress_bar "Scanning files" 12
}

main_menu() {
    splash
    while true; do
        clear

        local fb_ok=0 adb_ok=0
        fb_present && fb_ok=1
        adb_present && adb_ok=1

        local fb_dot="${RED}●${RESET}" adb_dot="${RED}●${RESET}" py_dot="${RED}●${RESET}"
        [ "$fb_ok" -eq 1 ] && fb_dot="${GREEN}●${RESET}"
        [ "$adb_ok" -eq 1 ] && adb_dot="${GREEN}●${RESET}"
        command -v python3 >/dev/null 2>&1 && py_dot="${GREEN}●${RESET}"

        local dev_text="${RED}Not connected${RESET}"
        if [ "$fb_ok" -eq 1 ]; then
            dev_text="${GREEN}Connected (fastboot)${RESET}"
        elif [ "$adb_ok" -eq 1 ]; then
            dev_text="${GREEN}Connected (adb)${RESET}"
        fi

        local img_count zip_count
        img_count=$(find_files 3 "*.img" | grep -c . || true)
        zip_count=$(find_files 2 "*.zip" | grep -c . || true)

        echo -e "${GREEN}╔════════════════════════════════════╗${RESET}"
        echo -e "${GREEN}║${RESET}$(center "ANDROID ULTIMATE FLASHER" 36)${GREEN}║${RESET}"
        echo -e "${GREEN}║${RESET}$(center "Version ${VERSION} - Created by Rudra" 36)${GREEN}║${RESET}"
        echo -e "${GREEN}╚════════════════════════════════════╝${RESET}"
        echo ""
        echo -e " Tools    $fb_dot fastboot   $adb_dot adb   $py_dot python"
        echo -e " Device   $dev_text"
        echo -e " Files    ${img_count} img • ${zip_count} zip in Downloads"
        echo ""
        echo -e " ${CYAN}- FLASH -${RESET}"
        echo -e "  1 ${GREEN}●${RESET} Flash Image        boot / recovery .img"
        echo -e "  2 ${GREEN}●${RESET} Custom ROM (ADB)   install .zip package"
        echo -e "  3 ${YELLOW}●${RESET} Fastboot ROM       coming soon"
        echo -e "  4 ${YELLOW}●${RESET} Flash GSI          coming soon"
        echo -e " ${CYAN}- DEVICE -${RESET}"
        echo -e "  5 ${GREEN}●${RESET} Device Info        model, slot, lock"
        echo -e "  6 ${GREEN}●${RESET} Switch Slot        active A/B slot"
        echo -e "  7 ${GREEN}●${RESET} Reboot             restart to a mode"
        echo -e "  8 ${RED}●${RESET} Erase Data         factory reset"
        echo -e " ${CYAN}- EXIT -${RESET}"
        echo -e "  0 ${GREEN}●${RESET} Exit               Quit application"
        echo ""
        echo -e " ${GREEN}●${RESET} Safe    ${YELLOW}●${RESET} Careful    ${RED}●${RESET} Erases data"
        echo -e " ${GRAY}r = rescan storage${RESET}"
        echo ""
        printf " Select: "
        local opt
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
            r|R)
                DL_DIR=""
                setup_storage
                ok "Storage: $DL_DIR"
                sleep 1
                ;;
            0)
                say "Exiting tool safely. Goodbye!"
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
    self="$(realpath "$0" 2>/dev/null || echo "")"
    target="$(realpath "$BASE_DIR/setup.sh" 2>/dev/null || echo "$BASE_DIR/setup.sh")"

    if [ -f "$0" ] && [ -n "$self" ] && [ "$self" != "$target" ]; then
        cp "$0" "$BASE_DIR/setup.sh" 2>/dev/null || true
    fi

    [ -f "$BASE_DIR/setup.sh" ] || return 0

    chmod +x "$BASE_DIR/setup.sh" 2>/dev/null || true
    ln -sf "$BASE_DIR/setup.sh" "$TERMUX_PREFIX/bin/rudra" 2>/dev/null || true
}

install_tool

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main_menu
fi
