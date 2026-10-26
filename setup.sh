#!/usr/bin/env bash
# ==============================================================================
# Android Ultimate Flasher - Version 1.1 (Optimized for Low-End Devices)
# Termux tool. Run once:  bash android_flasher_v1.0.sh   -> afterwards just: rudra
# ==============================================================================

set -uo pipefail

VERSION="1.1"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
ROMS_DIR="$HOME/flasher_roms"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"
SCAN_FILE="$BASE_DIR/scan.txt"
PARTS_FILE="$BASE_DIR/parts.txt"
ZIPKIND_FILE="$BASE_DIR/zipkinds.txt"
RESUME_FILE="$BASE_DIR/resume.state"
GSI_DIR="$BASE_DIR/gsi"
mkdir -p "$BASE_DIR" "$ROMS_DIR"
touch "$LOG_FILE" "$LAST_OUT" "$SCAN_FILE" "$ZIPKIND_FILE"

# ------------------------------ Colors & messages -----------------------------
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'
CYAN='\033[1;36m'; GRAY='\033[1;90m'; BOLD='\033[1m'; RESET='\033[0m'
SPIN=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
US=$'\x1f'

say()  { echo -e "${BLUE}[*]${RESET} $*"; echo "[INFO] $*" >> "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; echo "[OK] $*" >> "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; echo "[WARN] $*" >> "$LOG_FILE"; }
bad()  { echo -e "${RED}[-]${RESET} $*"; echo "[ERROR] $*" >> "$LOG_FILE"; }

# Keep Termux awake for the whole session
WAKELOCK=0
lock_awake()   { if [ "$WAKELOCK" = 0 ] && type -P termux-wake-lock >/dev/null 2>&1; then termux-wake-lock 2>/dev/null && WAKELOCK=1; fi; return 0; }
unlock_awake() { if [ "$WAKELOCK" = 1 ]; then termux-wake-unlock 2>/dev/null || true; WAKELOCK=0; fi; return 0; }
trap 'printf "\033[?25h"; unlock_awake' EXIT
trap 'printf "\033[?25h"; unlock_awake; echo; warn "Interrupted."; exit 130' INT TERM HUP

# ------------------------------ Layout (always centered) ----------------------
COLS=54; CW=46; M=""
calc_layout() {
    local c; c=$(tput cols 2>/dev/null || echo "${COLUMNS:-54}")
    [[ "$c" =~ ^[0-9]+$ ]] || c=54
    [ "$c" -lt 30 ] && c=30
    COLS=$c; CW=46; [ "$COLS" -lt 48 ] && CW=$((COLS - 2))
    M=$(printf '%*s' "$(( (COLS - CW) / 2 ))" '')
}
hline() { local s; s=$(printf '%*s' "$1" ''); printf '%s' "${s// /$2}"; }
center() {
    local len=${#1} l r
    l=$(( ($2 - len) / 2 )); r=$(( $2 - len - l ))
    [ "$l" -lt 0 ] && l=0; [ "$r" -lt 0 ] && r=0
    printf "%*s%s%*s" "$l" "" "$1" "$r" ""
}
shorten() {
    local s="$1" max="$2"; [ "$max" -lt 10 ] && max=10
    if [ "${#s}" -le "$max" ]; then printf '%s' "$s"
    else local h=$(( (max - 1) / 2 )); printf '%s…%s' "${s:0:$h}" "${s: -$((max - 1 - h))}"; fi
}
draw_box() {
    local w=$((CW - 2)) top t; top=$(hline "$w" "═")
    echo -e "${M}${GREEN}╔${top}╗${RESET}"
    for t in "$@"; do echo -e "${M}${GREEN}║${RESET}${BOLD}$(center "$t" "$w")${RESET}${GREEN}║${RESET}"; done
    echo -e "${M}${GREEN}╚${top}╝${RESET}"
}
header() { clear; calc_layout; draw_box "$1"; echo ""; }

# ------------------------------ Animations ------------------------------------
animate() {
    local msg; msg=$(shorten "$1" $((COLS - 14))); shift
    ("$@") > "$LAST_OUT" 2>&1 < /dev/null &
    local pid=$! i=0 t=$SECONDS
    printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[K${CYAN}[%s]${RESET} %s ${GRAY}%ss${RESET}" "${SPIN[$((i % 10))]}" "$msg" "$((SECONDS - t))"
        i=$((i + 1)); sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf "\r\033[K\033[?25h"
    return $rc
}
progress_bar() {
    local msg="$1" n="${2:-20}" i
    printf '\033[?25l'
    for ((i = 0; i <= n; i++)); do
        printf "\r\033[K${CYAN}[*]${RESET} %s ${GREEN}%s${GRAY}%s${RESET} %3d%%" \
            "$msg" "$(hline "$i" "█")" "$(hline "$((n - i))" "░")" "$((i * 100 / n))"
        sleep 0.01
    done
    echo; printf '\033[?25h'
}
typewriter() { local i; for ((i = 0; i < ${#1}; i++)); do printf "%s" "${1:$i:1}"; sleep 0.008; done; echo; }
pause() { if [ -t 0 ]; then echo; read -n 1 -s -r -p "Press any key to continue..."; echo; fi; return 0; }
ask_yn() {
    local def="${2:-n}" hint="(y/N)" a
    [ "$def" = y ] && hint="(Y/n)"
    printf " %s %s: " "$1" "$hint"; read -r a || a=""
    [[ "${a:-$def}" =~ ^[yY]$ ]]
}

# ------------------------------ USB backend ---------------------------------
USB_MODE="native"
detect_usb_mode() {
    if type -P termux-fastboot >/dev/null 2>&1 && type -P termux-adb >/dev/null 2>&1; then USB_MODE="termux"; else USB_MODE="native"; fi
}
fastboot() { if [ "$USB_MODE" = termux ]; then termux-fastboot "$@"; else command fastboot "$@"; fi; }
adb()      { if [ "$USB_MODE" = termux ]; then termux-adb "$@"; else command adb "$@"; fi; }
detect_usb_mode

# Robust Package Setup & Symbol Fix
setup_tools() {
    local marker="$BASE_DIR/.setup_done" force="${1:-}"
    if [ -z "$force" ] && [ -f "$marker" ] && type -P fastboot >/dev/null 2>&1; then return 0; fi
    export DEBIAN_FRONTEND=noninteractive
    
    # Fix libcurl / openssl symbol mismatch errors by forcing package upgrade
    animate "Updating packages & fixing libraries" bash -c "pkg update -y && pkg full-upgrade -y" || true
    
    type -P fastboot >/dev/null 2>&1 || animate "Installing android-tools" pkg install -y android-tools
    type -P termux-usb >/dev/null 2>&1 || animate "Installing termux-api" pkg install -y termux-api
    type -P unzip >/dev/null 2>&1 || animate "Installing unzip" pkg install -y unzip
    
    if ! type -P termux-fastboot >/dev/null 2>&1; then
        type -P curl >/dev/null 2>&1 || pkg install -y curl
        animate "Installing USB helper" bash -c "curl -fsSL https://raw.githubusercontent.com/nohajc/termux-adb/master/install.sh | bash" || true
    fi
    hash -r; detect_usb_mode; touch "$marker"
}

fb_present()       { fastboot devices 2>/dev/null | grep -q "fastboot"; }
adb_present()      { adb devices 2>/dev/null | awk 'NR>1 && ($2=="device"||$2=="sideload"||$2=="recovery"){f=1} END{exit !f}'; }
sideload_present() { adb devices 2>/dev/null | awk 'NR>1 && $2=="sideload"{f=1} END{exit !f}'; }
declare -A FBV=()

fb_load() {
    local raw k
    FBV=()
    raw=$(fastboot getvar all 2>&1 | tr -d '\r' | sed 's/^(bootloader) //')
    for k in product serialno unlocked current-slot; do
        FBV[$k]=$(printf '%s\n' "$raw" | awk -F': *' -v k="$k" '$1==k{print $2; exit}')
    done
    return 0
}
fb_var() {
    local k="${1:-}" v=""
    case "$k" in product|serialno|unlocked) v="${FBV[$k]:-}" ;; esac
    if [ -z "$v" ]; then
        v=$(fastboot getvar "$k" 2>&1 | awk -F': *' -v k="$k" '{sub(/^\(bootloader\) /,"")} tolower($1)==tolower(k){print $2; exit}' | tr -d '\r')
    fi
    echo "${v:-UNKNOWN}"
}

USB_DEV=""
usb_seen() {
    command -v termux-usb >/dev/null 2>&1 || return 1
    USB_DEV=$(timeout 3 termux-usb -l 2>/dev/null | grep -o '/dev/bus/usb/[0-9/]*' | head -n1)
    [ -n "$USB_DEV" ]
}

DEV_STATE="unchecked"
device_card() {
    local prod slot unl ser mode_txt
    if fb_present; then
        DEV_STATE=fastboot; mode_txt="fastboot"
        fb_load
        prod=$(fb_var product); slot="${FBV[current-slot]:-}"; unl=$(fb_var unlocked); ser=$(fb_var serialno)
        [ -z "$slot" ] && slot="-"
    else
        DEV_STATE=adb; mode_txt="adb / recovery"
        prod=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r' | head -n1)
        ser=$(adb get-serialno 2>/dev/null | tr -d '\r' | head -n1)
        slot="-"; unl="-"
    fi
    [ -z "${prod:-}" ] && prod="UNKNOWN"
    [ -z "${ser:-}" ] && ser="UNKNOWN"
    ok "Connected successfully!"
    echo -e " ${GRAY}$(hline $((CW - 2)) "─")${RESET}"
    echo -e "  Codename : ${BOLD}${prod}${RESET}"
    echo -e "  Mode     : ${BOLD}${mode_txt}${RESET}"
    echo -e "  Serial   : ${BOLD}$(shorten "$ser" 24)${RESET}"
    if [ "$mode_txt" = fastboot ]; then
        echo -e "  Slot     : ${BOLD}${slot}${RESET}"
        echo -e "  Unlocked : ${BOLD}${unl}${RESET}"
    fi
    echo -e " ${GRAY}$(hline $((CW - 2)) "─")${RESET}"
    return 0
}

wait_for_device() {
    local mode="$1" label="$1" tip chk=5 key="" i=0 t=$SECONDS hinted=0 asked=0 note=""
    case "$mode" in
        fastboot) tip="Phone: power off, hold Power + Volume Down." ;;
        sideload) tip="Phone: Recovery > Apply update > Apply from ADB." ;;
        *)        tip="Connect the phone with a data cable (OTG)."; label="fastboot/adb" ;;
    esac
    _here() { case "$mode" in fastboot) fb_present ;; sideload) sideload_present ;; *) fb_present || adb_present ;; esac; }
    if _here; then device_card; return 0; fi
    [ "$USB_MODE" = termux ] && chk=10
    echo -e " ${GRAY}${tip}\n Press 0 or q to go back.${RESET}\n"
    printf '\033[?25l'
    while true; do
        if [ "$hinted" -eq 0 ] && [ $((SECONDS - t)) -ge 10 ]; then
            hinted=1
            printf "\r\033[K${YELLOW}[!]${RESET} Not found? Check cable/OTG.\n"
        fi
        printf "\r\033[K${CYAN}[%s]${RESET} Searching %s device... %ss%s" "${SPIN[$((i % 10))]}" "$label" "$((SECONDS - t))" "$note"
        i=$((i + 1))
        if [ -t 0 ]; then
            if read -rsn1 -t 0.2 key; then
                case "$key" in 0|q|Q|b|B) printf "\r\033[K\033[?25h"; say "Cancelled."; return 1 ;; esac
            fi
        else sleep 0.2; fi
        if [ $((i % chk)) -eq 0 ]; then
            if _here; then
                printf "\r\033[K\033[?25h"
                device_card; sleep 0.5; return 0
            fi
        fi
    done
}

# ------------------------------ Storage & Fast Scan ---------------------------
STORAGE_ROOT=""; SCAN_ROOTS=()

setup_storage() {
    local d t found=0
    _find_root() {
        for d in "$HOME/storage/shared" "/storage/emulated/0" "/sdcard"; do
            if [ -d "$d" ] && ls "$d" >/dev/null 2>&1; then STORAGE_ROOT="$d"; return 0; fi
        done
        return 1
    }
    if _find_root; then found=1; else
        command -v termux-setup-storage >/dev/null 2>&1 && termux-setup-storage
        for t in $(seq 1 10); do sleep 0.5; if _find_root; then found=1; break; fi; done
    fi
    [ "$found" -eq 0 ] && STORAGE_ROOT="$HOME/Download"
    mkdir -p "$STORAGE_ROOT" "$ROMS_DIR"
    SCAN_ROOTS=("$STORAGE_ROOT" "$ROMS_DIR")
}

# Optimized fast scan (limits depth to 5 to prevent low-end freezing)
do_scan() {
    : > "$SCAN_FILE"
    local r
    for r in "${SCAN_ROOTS[@]}"; do
        [ -d "$r" ] || continue
        find -L "$r" -maxdepth 5 \( -path '*/Android/data' -o -path '*/Android/obb' -o -name '.*' \) -prune -o \
            -type f \( -iname '*.img' -o -iname '*.zip' -o -iname '*.tgz' -o -iname '*.tar' -o -iname '*.tar.gz' \
                       -o -iname '*.img.xz' -o -iname '*.img.gz' -o -iname 'flash_all*.sh' \) -print 2>/dev/null
    done | sort -u > "$SCAN_FILE"
    classify_zips
    return 0
}

classify_zips() {
    : > "$ZIPKIND_FILE"
    local z names kind
    while IFS= read -r z; do
        [ -n "$z" ] || continue
        kind=other
        if type -P unzip >/dev/null 2>&1; then
            names=$(unzip -Z1 "$z" 2>/dev/null | head -n 1000)
            if printf '%s\n' "$names" | grep -qiE '(^|/)flash_all[^/]*\.sh$|(^|/)images/[^/]+\.img$'; then kind=fastboot
            elif [ "$(stat -c %s "$z" 2>/dev/null || echo 0)" -ge 31457280 ] \
                && printf '%s\n' "$names" | grep -qiE '(^|/)payload\.bin$|\.new\.dat(\.(br|xz|lzma))?$|^(system|super|vendor|product|boot)\.img$|META-INF/com/android/metadata$'; then kind=sideload
            fi
        fi
        echo "${kind}|${z}" >> "$ZIPKIND_FILE"
    done < <(grep -iE '\.zip$' "$SCAN_FILE" || true)
    return 0
}
zip_list() { [ -s "$ZIPKIND_FILE" ] && { grep "^$1|" "$ZIPKIND_FILE" | cut -d'|' -f2-; }; return 0; }
scan_storage() {
    # If scan file doesn't exist, build it; otherwise skip heavy scan on startup for speed
    if [ ! -s "$SCAN_FILE" ]; then
        animate "Scanning storage" do_scan
    else
        do_scan >/dev/null 2>&1 & # background refresh
    fi
}
scan_list() { if [ -s "$SCAN_FILE" ]; then grep -iE "$1" "$SCAN_FILE" || true; fi; return 0; }
human_size() { du -h "$1" 2>/dev/null | cut -f1; }

MIN_ARCHIVE_MB="${MIN_ARCHIVE_MB:-150}"
ROM_KIND=(); ROM_PATH=()
declare -A ARC_SCRIPT=()
archive_has_script() {
    local f="$1" key lst r
    key="$f|$(stat -c %s "$f" 2>/dev/null || echo 0)"
    [ -n "${ARC_SCRIPT[$key]:-}" ] && { [ "${ARC_SCRIPT[$key]}" = yes ]; return; }
    lst=$(tar -tf "$f" 2>/dev/null | head -n 1000 || true)
    if printf '%s\n' "$lst" | grep -qiE '(^|/)flash_all[^/]*\.sh$'; then r=yes; else r=no; fi
    ARC_SCRIPT[$key]="$r"
    [ "$r" = yes ]
}
collect_roms() {
    ROM_KIND=(); ROM_PATH=()
    local f d n p base seen=$'\n' i j dup
    local tk=() tp=()

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        d="$(dirname "$f")"
        case "$seen" in *$'\n'"$d"$'\n'*) continue ;; esac
        seen+="$d"$'\n'; tk+=(script); tp+=("$d")
    done < <(scan_list '/flash_all[^/]*\.sh$')

    for ((i = 0; i < ${#tp[@]}; i++)); do
        ROM_KIND+=("${tk[$i]}"); ROM_PATH+=("${tp[$i]}")
    done

    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -ge $((MIN_ARCHIVE_MB * 1048576)) ] || continue
        case "${f,,}" in *.zip) ;; *) archive_has_script "$f" || continue ;; esac
        base="$(basename "$f")"; base="${base%.tar.gz}"; base="${base%.tgz}"; base="${base%.tar}"; base="${base%.zip}"
        ROM_KIND+=(arc); ROM_PATH+=("$f")
    done < <({ scan_list '\.(tgz|tar\.gz|tar)$'; zip_list fastboot; } | sort -u)
}

LIST=(); IDX=0; PICK_DEFAULT=0
pick_index() {
    local title="$1" total=${#LIST[@]} page=0 per=10 pages s e i choice
    pages=$(( (total + per - 1) / per ))
    while true; do
        s=$((page * per)); e=$((s + per)); [ "$e" -gt "$total" ] && e=$total
        for ((i = s; i < e; i++)); do echo -e " ${GREEN}[$((i + 1))]${RESET} ${LIST[$i]}"; done
        [ "$pages" -gt 1 ] && echo -e "\n ${GRAY}Page $((page + 1))/$pages  (n = next, p = previous)${RESET}"
        printf "\n %s (0 = back): " "$title"; read -r choice || choice=0
        case "$choice" in
            n|N) page=$(( (page + 1) % pages )); echo; continue ;;
            p|P) page=$(( (page + pages - 1) % pages )); echo; continue ;;
        esac
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then IDX=$((choice - 1)); return 0; fi
        return 1
    done
}

PICKED=""
pick_file() {
    local title="$1" ere="$2" excl="${3:-}" files=() f
    mapfile -t files < <(scan_list "$ere")
    [ "${#files[@]}" -eq 0 ] && return 1
    LIST=()
    for f in "${files[@]}"; do
        LIST+=("${GRAY}$(printf '%6s' "$(human_size "$f")")${RESET} $(shorten "${f#"$STORAGE_ROOT"/}" $((COLS - 16)))")
    done
    pick_index "$title" || return 1
    PICKED="${files[$IDX]}"
}

ROM_TREES=()
refresh_rom_trees() {
    collect_roms
    ROM_TREES=("$ROMS_DIR")
    local i
    for ((i = 0; i < ${#ROM_PATH[@]}; i++)); do
        [ "${ROM_KIND[$i]}" = arc ] || ROM_TREES+=("${ROM_PATH[$i]}")
    done
}
in_rom_tree() { local t; for t in "${ROM_TREES[@]}"; do [[ "$1" == "$t"/* ]] && return 0; done; return 1; }
file_size() { stat -c %s "$1" 2>/dev/null || echo 0; }
refresh_scan() { do_scan; refresh_rom_trees; }

flash_begin() {
    lock_awake
    echo -e " ${GRAY}Keep screen ON and do not unplug cable.${RESET}"
    return 0
}

run_step() {
    local label="$1" max="$2" try=1 rc; shift 2
    while true; do
        animate "$label" fastboot "$@"; rc=$?
        [ "$rc" -eq 0 ] && return 0
        [ "$try" -ge "$max" ] && return "$rc"
        if ! fb_present; then
            echo -e " ${YELLOW}!${RESET} Device disconnected. Reconnect cable."
            wait_for_device fastboot || return 99
        else
            warn "Retrying ($((try + 1))/$max)..."; sleep 1
        fi
        try=$((try + 1))
    done
}

run_wipe() {
    local label="${1:-Wiping user data}"
    if run_step "$label" 1 -w; then ok "Data wiped."; return 0; fi
    if run_step "Erasing userdata" 2 erase userdata; then
        run_step "Erasing metadata" 2 erase metadata || true
        ok "Data erased."; return 0;
    fi
    return 1
}

standalone_imgs() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        in_rom_tree "$f" && continue
        [ "$(file_size "$f")" -gt 629145600 ] && continue
        echo "$f"
    done < <(scan_list '\.img$')
}

sideload_zips() {
    local z
    while IFS= read -r z; do
        [ -n "$z" ] || continue
        in_rom_tree "$z" && continue
        echo "$z"
    done < <(zip_list sideload)
}

CRITICAL="bootloader|xbl|xbl_config|abl|modem|persist|efs|modemst1|modemst2|fsg|sbl1|tz|aboot|rpm|hyp|devcfg|keymaster"
PARTS=(boot recovery vendor_boot init_boot dtbo vbmeta vbmeta_system logo super)

read_partitions() {
    local raw
    raw=$(fastboot getvar all 2>&1 | grep -oE 'partition-type:[A-Za-z0-9_]+' | cut -d: -f2 | sed -E 's/_(a|b)$//' | sort -u)
    : > "$PARTS_FILE"
    local p
    for p in "${PARTS[@]}"; do printf '%s\n' "$raw" | grep -qx "$p" && echo "$p" >> "$PARTS_FILE"; done
    printf '%s\n' "$raw" | grep -vxE 'userdata|metadata|cache|misc|frp' | grep -vxFf "$PARTS_FILE" | grep . >> "$PARTS_FILE" || true
}

flash_image_screen() {
    header "Flash Individual Image"
    refresh_scan; echo ""
    pick_file "Select image" '\.img$' || { pause; return 0; }
    local img="$PICKED" guess part=""
    guess="$(basename "$img")"; guess="${guess%.*}"; guess="${guess,,}"

    wait_for_device fastboot || return 0
    animate "Reading partitions" read_partitions
    local parts=()
    mapfile -t parts < "$PARTS_FILE"
    [ "${#parts[@]}" -eq 0 ] && parts=("${PARTS[@]}")

    LIST=()
    for p in "${parts[@]}"; do
        LIST+=("$p $([ "$p" = "$guess" ] && echo "${GREEN}★ suggested${RESET}")")
    done
    pick_index "Select partition" || { pause; return 0; }
    part="${parts[$IDX]}"

    flash_begin || { pause; return 0; }
    run_step "Flashing $part" 3 flash "$part" "$img" && ok "Flashed successfully!" || bad "Flash failed."
    pause
}

flash_sideload_screen() {
    header "ADB Sideload Custom ROM"
    refresh_scan; echo ""
    local zips=() z
    mapfile -t zips < <(sideload_zips)
    [ "${#zips[@]}" -eq 0 ] && { warn "No ROM zip found."; pause; return 0; }
    LIST=()
    for z in "${zips[@]}"; do LIST+=("$(shorten "${z#"$STORAGE_ROOT"/}" 40)"); done
    pick_index "Select zip" || { pause; return 0; }
    wait_for_device sideload || return 0
    adb sideload "${zips[$IDX]}" 2>&1 | tee "$LAST_OUT"
    pause
}

flash_fastboot_screen() {
    header "Fastboot ROM Flash"
    refresh_scan; echo ""
    collect_roms
    [ "${#ROM_PATH[@]}" -eq 0 ] && { warn "No fastboot ROM found."; pause; return 0; }
    LIST=()
    for ((i=0; i<${#ROM_PATH[@]}; i++)); do LIST+=("$(basename "${ROM_PATH[$i]}")"); done
    pick_index "Select ROM" || { pause; return 0; }
    wait_for_device fastboot || return 0
    ok "Ready to flash selected ROM."
    pause
}

flash_gsi_screen() {
    header "Flash GSI System Image"
    refresh_scan; echo ""
    pick_file "Select GSI" '\.img$' || { pause; return 0; }
    wait_for_device fastboot || return 0
    run_step "Flashing system" 3 flash system "$PICKED" && ok "GSI Flashed!"
    pause
}

device_info_screen() {
    header "Device Information"
    wait_for_device fastboot || return 0
    echo -e " Product  : ${BOLD}$(fb_var product)${RESET}"
    echo -e " Serial   : ${BOLD}$(fb_var serialno)${RESET}"
    echo -e " Slot     : ${BOLD}$(fb_var current-slot)${RESET}"
    echo -e " Unlocked : ${BOLD}$(fb_var unlocked)${RESET}"
    pause
}

reboot_screen() {
    header "Reboot Options"
    echo -e " 1) System\n 2) Recovery\n 3) Bootloader\n 4) Fastbootd\n 0) Back"
    local o; read -r o
    case "$o" in
        1) fastboot reboot || adb reboot ;;
        2) fastboot reboot recovery || adb reboot recovery ;;
        3) fastboot reboot bootloader || adb reboot bootloader ;;
        4) fastboot reboot fastboot ;;
    esac
    pause
}

setup_screen() {
    header "Setup & Fix Connection"
    setup_tools force
    ok "Tools verified and reinstalled."
    pause
}

# ------------------------------ Main Menu (Optimized) -------------------------
main_menu() {
    setup_storage
    scan_storage

    while true; do
        clear; calc_layout
        local fb=0 ad=0
        if fb_present; then DEV_STATE=fastboot; elif adb_present; then DEV_STATE=adb; else DEV_STATE=none; fi
        [ "$DEV_STATE" = fastboot ] && fb=1
        [ "$DEV_STATE" = adb ] && ad=1

        local dev="${RED}Not Connected${RESET}"
        [ "$fb" -eq 1 ] && dev="${GREEN}Connected (fastboot)${RESET}"
        [ "$ad" -eq 1 ] && dev="${GREEN}Connected (adb)${RESET}"

        draw_box "ANDROID ULTIMATE FLASHER" "Version ${VERSION} - By Rudra"
        echo -e "\n${M}USB Mode : ${USB_MODE}"
        echo -e "${M}Status   : $dev\n"
        echo -e "${M} 1) Flash Image (.img)"
        echo -e "${M} 2) Custom ROM (Sideload)"
        echo -e "${M} 3) Fastboot ROM"
        echo -e "${M} 4) Flash GSI"
        echo -e "${M} 5) Device Info"
        echo -e "${M} 6) Switch Slot"
        echo -e "${M} 7) Reboot Options"
        echo -e "${M} 8) Erase / Wipe Data"
        echo -e "${M} 9) Setup / Fix USB"
        echo -e "${M} 0) Exit\n"
        printf "%s Select option: " "$M"; read -r o
        case "$o" in
            1) flash_image_screen ;;
            2) flash_sideload_screen ;;
            3) flash_fastboot_screen ;;
            4) flash_gsi_screen ;;
            5) device_info_screen ;;
            6) header "Switch Slot"; fastboot set_active $([ "$(fb_var current-slot)" = a ] && echo b || echo a); pause ;;
            7) reboot_screen ;;
            8) header "Wipe Data"; run_wipe; pause ;;
            9) setup_screen ;;
            r|R) scan_storage ;;
            0) echo; exit 0 ;;
        esac
    done
}

install_shortcut() {
    local target="$BASE_DIR/setup.sh" bin="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    if [ -f "$0" ]; then cp "$0" "$target" 2>/dev/null || true; fi
    if [ -f "$target" ]; then chmod +x "$target" 2>/dev/null || true; mkdir -p "$bin"; ln -sf "$target" "$bin/rudra" 2>/dev/null || true; fi
}

install_shortcut
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then main_menu; fi
