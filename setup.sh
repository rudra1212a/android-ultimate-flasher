#!/usr/bin/env bash
# ==============================================================================
# Android Ultimate Flasher - Version 1.6 (simple & automatic)
# Run in Termux:  bash android_flasher_v1.6.sh   (afterwards just type: rudra)
# ==============================================================================

set -uo pipefail

VERSION="1.6"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"
SCAN_FILE="$BASE_DIR/scan.txt"
GSI_DIR="$BASE_DIR/gsi"
mkdir -p "$BASE_DIR"
touch "$LOG_FILE" "$LAST_OUT"

# ------------------------------ Colors & messages -----------------------------
RED='\033[1;31m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; BLUE='\033[1;34m'
CYAN='\033[1;36m'; GRAY='\033[1;90m'; BOLD='\033[1m'; RESET='\033[0m'
SPIN=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
US=$'\x1f'

say()  { echo -e "${BLUE}[*]${RESET} $*"; echo "[INFO] $*" >> "$LOG_FILE"; }
ok()   { echo -e "${GREEN}[+]${RESET} $*"; echo "[OK] $*" >> "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; echo "[WARN] $*" >> "$LOG_FILE"; }
bad()  { echo -e "${RED}[-]${RESET} $*"; echo "[ERROR] $*" >> "$LOG_FILE"; }

WAKELOCK=0
unlock_screen() { [ "$WAKELOCK" = 1 ] && { termux-wake-unlock 2>/dev/null || true; WAKELOCK=0; }; return 0; }
trap 'printf "\033[?25h"; unlock_screen' EXIT
trap 'printf "\033[?25h"; unlock_screen; echo; warn "Interrupted."; exit 130' INT TERM

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
# Run a command in background with a spinner
animate() {
    local msg; msg=$(shorten "$1" $((COLS - 14))); shift
    ("$@") > "$LAST_OUT" 2>&1 &
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
    local msg="$1" n="${2:-24}" i
    printf '\033[?25l'
    for ((i = 0; i <= n; i++)); do
        printf "\r\033[K${CYAN}[*]${RESET} %s ${GREEN}%s${GRAY}%s${RESET} %3d%%" \
            "$msg" "$(hline "$i" "█")" "$(hline "$((n - i))" "░")" "$((i * 100 / n))"
        sleep 0.02
    done
    echo; printf '\033[?25h'
}
typewriter() { local i; for ((i = 0; i < ${#1}; i++)); do printf "%s" "${1:$i:1}"; sleep 0.012; done; echo; }
pause() { [ -t 0 ] && { echo; read -n 1 -s -r -p "Press any key to continue..."; echo; }; return 0; }
ask_yn() { # ask_yn "question" [y|n default]
    local def="${2:-n}" hint="(y/N)" a
    [ "$def" = y ] && hint="(Y/n)"
    printf " %s %s: " "$1" "$hint"; read -r a || a=""
    [[ "${a:-$def}" =~ ^[yY]$ ]]
}

# ------------------------------ USB backend (no-root support) -----------------
# termux mode = termux-adb / termux-fastboot wrappers (works WITHOUT root)
USB_MODE="native"
detect_usb_mode() {
    if type -P termux-fastboot >/dev/null 2>&1 && type -P termux-adb >/dev/null 2>&1; then USB_MODE="termux"; else USB_MODE="native"; fi
}
fastboot() { if [ "$USB_MODE" = termux ]; then termux-fastboot "$@"; else command fastboot "$@"; fi; }
adb()      { if [ "$USB_MODE" = termux ]; then termux-adb "$@"; else command adb "$@"; fi; }
detect_usb_mode

# Installs everything needed, automatically
setup_tools() { # setup_tools [force]
    local marker="$BASE_DIR/.setup_done" force="${1:-}"
    if [ -z "$force" ] && [ -f "$marker" ] && type -P fastboot >/dev/null 2>&1; then return 0; fi
    type -P fastboot >/dev/null 2>&1 || animate "Installing android-tools" bash -c "pkg update -y && pkg install -y android-tools"
    type -P termux-usb >/dev/null 2>&1 || animate "Installing termux-api" pkg install -y termux-api
    if ! type -P termux-fastboot >/dev/null 2>&1; then
        type -P curl >/dev/null 2>&1 || animate "Installing curl" pkg install -y curl
        animate "Installing USB helper (no-root)" bash -c "curl -fsSL https://raw.githubusercontent.com/nohajc/termux-adb/master/install.sh | bash"
    fi
    hash -r; detect_usb_mode; touch "$marker"
    if [ "$USB_MODE" = termux ]; then ok "USB helper ready (no-root mode)."
    else warn "USB helper not installed (internet?). Open menu 9 to retry."; fi
}

fb_present()       { fastboot devices 2>/dev/null | grep -q "fastboot"; }
adb_present()      { adb devices 2>/dev/null | awk 'NR>1 && ($2=="device"||$2=="sideload"||$2=="recovery"){f=1} END{exit !f}'; }
sideload_present() { adb devices 2>/dev/null | awk 'NR>1 && $2=="sideload"{f=1} END{exit !f}'; }
fb_var() {
    local v; v=$(fastboot getvar "$1" 2>&1 | awk -F': *' -v k="$1" '{sub(/^\(bootloader\) /,"")} tolower($1)==tolower(k){print $2; exit}' | tr -d '\r')
    echo "${v:-UNKNOWN}"
}

DEV_STATE="unchecked"
# wait_for_device fastboot|sideload|any  -> 0 found, 1 user pressed back
wait_for_device() {
    local mode="$1" label="$1" tip chk=5 key="" i=0 t=$SECONDS hinted=0
    case "$mode" in
        fastboot) tip="Phone: power off, hold Power + Volume Down." ;;
        sideload) tip="Phone: Recovery > Apply update > Apply from ADB." ;;
        *)        tip="Connect the phone with a data cable (OTG)."; label="fastboot/adb" ;;
    esac
    _here() { case "$mode" in fastboot) fb_present ;; sideload) sideload_present ;; *) fb_present || adb_present ;; esac; }
    _here && return 0
    [ "$USB_MODE" = termux ] && chk=20
    echo -e " ${GRAY}${tip}\n Press 0 or q to go back.${RESET}\n"
    printf '\033[?25l'
    while true; do
        if [ "$hinted" -eq 0 ] && [ $((SECONDS - t)) -ge 10 ]; then
            hinted=1; printf "\r\033[K${YELLOW}[!]${RESET} Not found? Press 0, then open menu 9.\n"
        fi
        printf "\r\033[K${CYAN}[%s]${RESET} Searching %s device... %ss" "${SPIN[$((i % 10))]}" "$label" "$((SECONDS - t))"
        i=$((i + 1))
        if [ -t 0 ]; then
            if read -rsn1 -t 0.2 key; then
                case "$key" in 0|q|Q|b|B) printf "\r\033[K\033[?25h"; say "Cancelled."; return 1 ;; esac
            fi
        else sleep 0.2; fi
        if [ $((i % chk)) -eq 0 ] && _here; then
            printf "\r\033[K\033[?25h"
            [ "$mode" = fastboot ] && DEV_STATE=fastboot || DEV_STATE=adb
            ok "Device found!"; sleep 0.4; return 0
        fi
    done
}

# ------------------------------ Phone storage scan ----------------------------
DL_DIR=""; STORAGE_ROOT=""; SCAN_ROOTS=()

setup_storage() {
    local d t
    find_dl() {
        for d in "$HOME/storage/shared" "/storage/emulated/0" "/sdcard"; do
            if [ -d "$d" ] && ls "$d" >/dev/null 2>&1; then STORAGE_ROOT="$d"; return 0; fi
        done
        return 1
    }
    if ! find_dl; then
        warn "Allow storage permission for Termux..."
        command -v termux-setup-storage >/dev/null 2>&1 && termux-setup-storage
        for t in $(seq 1 20); do sleep 1; find_dl && break; done
    fi
    if [ -z "$STORAGE_ROOT" ]; then
        STORAGE_ROOT="$HOME/Download"; mkdir -p "$STORAGE_ROOT"
        bad "No storage access. Allow it, then press 'r' in the menu."
        sleep 2
    fi
    SCAN_ROOTS=("$STORAGE_ROOT")
    for d in "$HOME"/storage/external-*; do [ -d "$d" ] && ls "$d" >/dev/null 2>&1 && SCAN_ROOTS+=("$d"); done
    DL_DIR="$STORAGE_ROOT/Download"
}

do_scan() {
    : > "$SCAN_FILE"
    local r
    for r in "${SCAN_ROOTS[@]}"; do
        find -L "$r" -maxdepth 7 \( -path '*/Android/data' -o -path '*/Android/obb' -o -name '.*' \) -prune -o \
            -type f \( -iname '*.img' -o -iname '*.zip' -o -iname '*.tgz' -o -iname '*.tar.gz' \
                       -o -iname '*.img.xz' -o -iname '*.img.gz' -o -iname 'flash_all*.sh' \) -print 2>/dev/null
    done | sort -u > "$SCAN_FILE"
}
scan_storage() {
    animate "Scanning phone storage" do_scan
    ok "Found $(grep -c . "$SCAN_FILE" 2>/dev/null || echo 0) flashable file(s)."
}
scan_list()        { [ -s "$SCAN_FILE" ] && { grep -iE "$1" "$SCAN_FILE" || true; }; return 0; }
find_rom_dirs()    { scan_list '/flash_all[^/]*\.sh$' | while IFS= read -r f; do dirname "$f"; done | sort -u; }
find_rom_archives(){ scan_list '\.(tgz|tar\.gz)$'; }
human_size()       { du -h "$1" 2>/dev/null | cut -f1; }

# pick_file <title> <regex> [exclude-regex]  -> sets PICKED (numbered list, type a number)
PICKED=""
pick_file() {
    local title="$1" ere="$2" excl="${3:-}" files=() total page=0 per=12 pages i s e choice
    if [ -n "$excl" ]; then mapfile -t files < <(scan_list "$ere" | grep -viE "$excl" || true)
    else mapfile -t files < <(scan_list "$ere"); fi
    if [ "${#files[@]}" -eq 0 ] || [ -z "${files[0]:-}" ]; then
        warn "Nothing found on your phone."
        echo -e " ${GRAY}Copy the file to the phone, then press 'r' in the main menu.${RESET}"
        return 1
    fi
    total=${#files[@]}; pages=$(( (total + per - 1) / per ))
    echo -e " ${GRAY}Found $total file(s) on your phone:${RESET}\n"
    while true; do
        s=$((page * per)); e=$((s + per)); [ "$e" -gt "$total" ] && e=$total
        for ((i = s; i < e; i++)); do
            echo -e " ${GREEN}[$((i + 1))]${RESET} ${GRAY}$(printf '%6s' "$(human_size "${files[$i]}")")${RESET} $(shorten "${files[$i]#"$STORAGE_ROOT"/}" $((COLS - 16)))"
        done
        [ "$pages" -gt 1 ] && echo -e "\n ${GRAY}Page $((page + 1))/$pages (n = next, p = previous)${RESET}"
        printf "\n %s (0 = back): " "$title"; read -r choice || choice=0
        case "$choice" in
            n|N) page=$(( (page + 1) % pages )); continue ;;
            p|P) page=$(( (page + pages - 1) % pages )); continue ;;
        esac
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ] || return 1
        PICKED="${files[$((choice - 1))]}"; return 0
    done
}

# ------------------------------ Safe flashing ---------------------------------
# Keeps screen awake while flashing and warns on low battery
flash_begin() {
    if type -P termux-battery-status >/dev/null 2>&1; then
        local b pct; b=$(timeout 5 termux-battery-status 2>/dev/null || true)
        pct=$(printf '%s' "$b" | grep -o '"percentage": *[0-9]*' | grep -o '[0-9]*$' | head -n1)
        if [[ "${pct:-}" =~ ^[0-9]+$ ]] && [ "$pct" -lt 30 ] && [[ "$b" == *UNPLUGGED* ]]; then
            warn "This phone's battery is ${pct}%. Low power can break a flash!"
            ask_yn "Continue anyway?" n || return 1
        fi
    fi
    type -P termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null && WAKELOCK=1
    echo -e " ${GRAY}Keep the screen ON and do not unplug the cable.${RESET}"
    return 0
}

# run_step <label> <tries> <fastboot args...>  (auto retry, waits if USB drops; 99 = user went back)
run_step() {
    local label="$1" max="$2" try=1 rc; shift 2
    while true; do
        animate "$label" fastboot "$@"; rc=$?
        [ "$rc" -eq 0 ] && return 0
        [ "$try" -ge "$max" ] && return "$rc"
        if ! fb_present; then
            echo -e " ${YELLOW}!${RESET} Device disconnected. Reconnect cable (tap Allow)."
            wait_for_device fastboot || return 99
        elif grep -qiE 'FAILED \(remote|not allowed|unknown command|no such partition|not found' "$LAST_OUT"; then
            return "$rc"
        else
            warn "Failed. Retrying ($((try + 1))/$max)..."; sleep 2
        fi
        try=$((try + 1))
    done
}

# ------------------------------ 1. Flash Image --------------------------------
CRITICAL="bootloader|xbl|xbl_config|abl|modem|persist|efs|modemst1|modemst2|fsg|sbl1|tz|aboot|rpm|hyp|devcfg|keymaster|preloader|lk"
PARTS=(boot recovery vendor_boot init_boot dtbo vbmeta vbmeta_system vbmeta_vendor logo super)

flash_image_screen() {
    header "Flash Individual Image"
    wait_for_device fastboot || return 0
    echo ""
    pick_file "Select image number" '\.img$' || { say "Cancelled."; pause; return 0; }
    local img="$PICKED" guess part="" i=0 p mark sel def=0
    [ -s "$img" ] || { bad "Image file is empty."; pause; return 1; }
    guess="$(basename "$img")"; guess="${guess%.*}"; guess="${guess,,}"

    echo -e "\n ${CYAN}Choose partition:${RESET}"
    for p in "${PARTS[@]}"; do
        i=$((i + 1)); mark=""
        [ "$p" = "$guess" ] && { mark=" ${GREEN}★ suggested${RESET}"; def=$i; }
        echo -e "  ${GREEN}[$i]${RESET} $p$mark"
    done
    echo -e "  ${GREEN}[c]${RESET} Other name"
    printf "\n Select%s (0 = back): " "$([ "$def" -gt 0 ] && echo " [$def]")"
    read -r sel || sel=0; sel="${sel:-$def}"
    if [[ "$sel" =~ ^[cC]$ ]]; then printf " Partition name: "; read -r part || part=""
    elif [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#PARTS[@]}" ]; then part="${PARTS[$((sel - 1))]}"
    else say "Cancelled."; pause; return 0; fi
    [[ "$part" =~ ^[a-zA-Z0-9_]+$ ]] || { bad "Invalid partition name."; pause; return 1; }

    local targets=("$part")
    if [ "$(fb_var current-slot)" != UNKNOWN ] && [[ ! "$part" =~ _[ab]$ ]]; then
        ask_yn "A/B phone: flash BOTH slots (a and b)?" n && targets=("${part}_a" "${part}_b")
    fi

    if [[ "$part" =~ ^($CRITICAL)$ ]]; then
        warn "[$part] is CRITICAL. A wrong image can hard-brick the phone!"
        printf " Type YES to continue: "; read -r sel || sel=""
        [ "$sel" = YES ] || { say "Cancelled."; pause; return 0; }
    fi
    if [ "$guess" != "${part%_[ab]}" ] && printf '%s\n' "${PARTS[@]}" | grep -qx "$guess"; then
        warn "File is named '$guess' but you picked '$part'. Wrong image = bootloop!"
        ask_yn "Are you SURE?" n || { say "Cancelled."; pause; return 0; }
    fi

    echo -e "\n Image  : ${BOLD}$(shorten "$(basename "$img")" $((COLS - 14)))${RESET}\n Target : ${BOLD}${targets[*]}${RESET}"
    ask_yn "Flash now?" n || { say "Cancelled."; pause; return 0; }
    local nov=0; [[ "$part" == vbmeta* ]] && ask_yn "Disable verity & verification?" n && nov=1

    flash_begin || { pause; return 0; }
    local t rc=0
    for t in "${targets[@]}"; do
        if [ "$nov" -eq 1 ]; then run_step "Flashing $t" 3 --disable-verity --disable-verification flash "$t" "$img"
        else run_step "Flashing $t" 3 flash "$t" "$img"; fi
        rc=$?
        [ "$rc" -eq 0 ] && ok "$t flashed!" || { bad "Flashing $t failed:"; tail -n 4 "$LAST_OUT"; break; }
    done
    unlock_screen
    pause
}

# ------------------------------ 2. Custom ROM (sideload) ----------------------
flash_sideload_screen() {
    header "ADB Sideload Custom ROM"
    wait_for_device sideload || return 0
    echo ""
    pick_file "Select zip number" '\.zip$' || { say "Cancelled."; pause; return 0; }
    say "Sideloading $(shorten "$(basename "$PICKED")" $((COLS - 16)))..."
    adb sideload "$PICKED" 2>&1 | tee "$LAST_OUT"
    [ "${PIPESTATUS[0]}" -eq 0 ] && ok "Sideload finished!" || warn "Check the recovery screen; it may still have worked."
    pause
}

# ------------------------------ 3. Fastboot ROM -------------------------------
ROM_DIR=""; PLAN=(); PLAN_ERR=""

extract_archive() {
    local arc="$1" base out found
    base="$(basename "$arc")"; base="${base%.tar.gz}"; base="${base%.tgz}"
    out="$(dirname "$arc")/${base}_extracted"
    found=$(find -L "$out" -maxdepth 6 -iname 'flash_all*.sh' 2>/dev/null | head -n1)
    if [ -z "$found" ]; then
        local need free
        need=$(( $(stat -c %s "$arc" 2>/dev/null || echo 0) * 3 / 1024 ))
        free=$(df -kP "$(dirname "$arc")" 2>/dev/null | awk 'NR==2{print $4}')
        if [[ "${free:-}" =~ ^[0-9]+$ ]] && [ "$free" -lt "$need" ]; then bad "Not enough storage (need ~$((need / 1024)) MB)."; return 1; fi
        mkdir -p "$out"
        animate "Extracting $(basename "$arc")" tar -xzf "$arc" -C "$out" --no-same-owner --no-same-permissions \
            || { bad "Extraction failed:"; tail -n 3 "$LAST_OUT"; return 1; }
        ok "Extracted."
        found=$(find -L "$out" -maxdepth 6 -iname 'flash_all*.sh' 2>/dev/null | head -n1)
    fi
    [ -n "$found" ] || { bad "No flash_all script inside the archive."; return 1; }
    ROM_DIR="$(dirname "$found")"
}

# Reads flash_all*.sh and turns it into fastboot steps (no eval, safe)
build_plan() {
    local script="$1" imgdir="$2" line args tok toks out joined
    PLAN=(); PLAN_ERR=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        args=$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*("?\$\{?[A-Za-z_]*\}?"?|[^[:space:]#]*fastboot[^[:space:]]*)[[:space:]]+((flash|erase|set_active|reboot|flashing|oem|-w|--set-active|--disable-verity|--disable-verification)([[:space:]].*)?)$/\2/p')
        [ -z "$args" ] && continue
        args=$(printf '%s\n' "$args" | sed -E 's#\$\(dirname[^)]*\)/?##g; s/[[:space:]]*(\|\||&&|;|[0-9]?>).*$//')
        [ -z "$args" ] && continue
        read -ra toks <<< "$args"; out=(); joined=""
        for tok in "${toks[@]}"; do
            tok="${tok//\"/}"; tok="${tok//\'/}"
            case "$tok" in *.img|*.bin|*.mbn|*.elf|*.hex|*.mdt|*.pro|*.lz4|*.ubi|*.zip|*.txt|*.xml) tok="$imgdir/$(basename "$tok")" ;; esac
            [[ "$tok" == *'$'* ]] && { PLAN_ERR="Unsupported script line: $line"; return 1; }
            joined+="${tok}${US}"
        done
        PLAN+=("${joined%"$US"}")
    done < "$script"
    [ "${#PLAN[@]}" -gt 0 ] || { PLAN_ERR="No flash commands found in script."; return 1; }
}

script_label() {
    case "${1,,}" in
        *lock*) echo "Flash + re-LOCK bootloader (risky)" ;;
        *except_storage*|*except_data*|*save*) echo "Flash, KEEP my data" ;;
        flash_all.sh) echo "Clean flash (erases ALL data)" ;;
        *) echo "Custom script" ;;
    esac
}

flash_fastboot_screen() {
    header "Fastboot ROM Flash"
    wait_for_device fastboot || return 0
    echo ""
    local kind=() path=() x i
    while IFS= read -r x; do [ -n "$x" ] && { kind+=(dir); path+=("$x"); }; done < <(find_rom_dirs)
    while IFS= read -r x; do [ -n "$x" ] && { kind+=(arc); path+=("$x"); }; done < <(find_rom_archives)
    if [ "${#path[@]}" -eq 0 ]; then
        warn "No fastboot ROM (folder or .tgz) found on your phone."
        echo -e " ${GRAY}Copy it to the phone, then press 'r' in the main menu.${RESET}"
        pause; return 0
    fi
    echo -e " ${CYAN}ROM packages on your phone:${RESET}"
    for ((i = 0; i < ${#path[@]}; i++)); do
        if [ "${kind[$i]}" = dir ]; then
            echo -e " ${GREEN}[$((i + 1))]${RESET} ${GREEN}FOLDER${RESET}  $(shorten "${path[$i]#"$STORAGE_ROOT"/}" $((COLS - 16)))"
        else
            echo -e " ${GREEN}[$((i + 1))]${RESET} ${YELLOW}ARCHIVE${RESET} $(shorten "$(basename "${path[$i]}")" $((COLS - 24))) ${GRAY}$(human_size "${path[$i]}")${RESET}"
        fi
    done
    printf "\n Select ROM (0 = back): "; read -r x || x=0
    [[ "$x" =~ ^[0-9]+$ ]] && [ "$x" -ge 1 ] && [ "$x" -le "${#path[@]}" ] || { say "Cancelled."; pause; return 0; }
    echo ""
    if [ "${kind[$((x - 1))]}" = arc ]; then extract_archive "${path[$((x - 1))]}" || { pause; return 1; }
    else ROM_DIR="${path[$((x - 1))]}"; fi

    local scripts=() script
    mapfile -t scripts < <(find "$ROM_DIR" -maxdepth 1 -type f -iname 'flash_all*.sh' | sort)
    [ "${#scripts[@]}" -gt 0 ] || { bad "No flash_all*.sh in the ROM folder."; pause; return 1; }
    script="${scripts[0]}"
    if [ "${#scripts[@]}" -gt 1 ]; then
        echo -e " ${CYAN}Flash mode:${RESET}"
        for ((i = 0; i < ${#scripts[@]}; i++)); do echo -e " ${GREEN}[$((i + 1))]${RESET} $(script_label "$(basename "${scripts[$i]}")")"; done
        printf " Select mode (0 = back): "; read -r x || x=0
        [[ "$x" =~ ^[0-9]+$ ]] && [ "$x" -ge 1 ] && [ "$x" -le "${#scripts[@]}" ] || { say "Cancelled."; pause; return 0; }
        script="${scripts[$((x - 1))]}"
    fi
    local imgdir="$ROM_DIR"; [ -d "$ROM_DIR/images" ] && imgdir="$ROM_DIR/images"
    build_plan "$script" "$imgdir" || { bad "$PLAN_ERR"; pause; return 1; }

    # check files, product and what will happen
    local step toks t missing=0 erase=0 lockit=0 nflash=0 j
    for step in "${PLAN[@]}"; do
        IFS="$US" read -ra toks <<< "$step"; j=" ${toks[*]} "
        for t in "${toks[@]}"; do [[ "$t" == "$imgdir"/* ]] && [ ! -f "$t" ] && { missing=$((missing + 1)); [ "$missing" -le 4 ] && bad "Missing: $(basename "$t")"; }; done
        [[ "$j" == *" flash "* ]] && nflash=$((nflash + 1))
        [[ "$j" == *" -w "* || "$j" == *" erase userdata "* ]] && erase=1
        [[ "$j" == *" lock "* ]] && lockit=1
    done
    [ "$missing" -eq 0 ] || { bad "ROM package is incomplete."; pause; return 1; }

    local rp dp; rp=$(grep -m1 -E 'product: ?\*?[A-Za-z0-9_]+' "$script" 2>/dev/null | sed -nE 's/.*product: ?\*?([A-Za-z0-9_]+).*/\1/p')
    dp=$(fb_var product)
    echo -e "\n ${CYAN}--- ROM Summary ---${RESET}"
    echo -e " ROM for    : ${BOLD}${rp:-unknown}${RESET}\n Your phone : ${BOLD}${dp}${RESET}\n Steps      : ${BOLD}${#PLAN[@]}${RESET} (${nflash} flash)"
    [ "$erase" -eq 1 ] && echo -e " Your data  : ${RED}WILL BE ERASED${RESET}" || echo -e " Your data  : ${GREEN}kept${RESET}"
    if [ -n "$rp" ] && [ "$dp" != UNKNOWN ] && [ "${rp,,}" != "${dp,,}" ]; then
        echo; bad "WRONG DEVICE! ROM is for '$rp', phone is '$dp'."
        printf " Type FORCE to flash anyway: "; read -r x || x=""; [ "$x" = FORCE ] || { say "Cancelled."; pause; return 0; }
    fi
    if [ "$lockit" -eq 1 ]; then
        warn "This script RE-LOCKS the bootloader."
        printf " Type LOCK to continue: "; read -r x || x=""; [ "$x" = LOCK ] || { say "Cancelled."; pause; return 0; }
    fi
    echo; ask_yn "Start flashing now?" n || { say "Cancelled."; pause; return 0; }
    flash_begin || { pause; return 0; }

    local total=${#PLAN[@]} n=0 rc short stop=0 tries
    echo ""
    for step in "${PLAN[@]}"; do
        n=$((n + 1)); IFS="$US" read -ra toks <<< "$step"
        short="${toks[*]:0:2}"; short="${short//$imgdir\//}"
        tries=3; [[ " ${toks[*]} " == *" reboot "* ]] && tries=1
        run_step "[$n/$total] $short" "$tries" "${toks[@]}"; rc=$?
        if [ "$rc" -eq 0 ]; then
            echo -e " ${GREEN}✔${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14)))"
        elif [ "$rc" -eq 99 ]; then stop=1; break
        elif [[ " ${toks[*]} " == *" flash "* || " ${toks[*]} " == *" set_active "* ]]; then
            echo -e " ${RED}✘${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14)))"
            bad "Step failed:"; tail -n 4 "$LAST_OUT"; stop=1; break
        else
            echo -e " ${YELLOW}!${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14))) (skipped)"
        fi
    done
    unlock_screen; echo ""
    if [ "$stop" -eq 0 ]; then ok "ROM flashed successfully!"
    else bad "Stopped at step $n of $total. Do NOT boot the phone yet - reconnect and flash again."; fi
    pause
}

# ------------------------------ 4. GSI ----------------------------------------
wait_userspace() {
    local i
    for i in $(seq 1 60); do sleep 1; fb_present && [ "$(fb_var is-userspace)" = yes ] && return 0; done
    return 1
}

flash_gsi_screen() {
    header "Flash GSI System Image"
    wait_for_device fastboot || return 0
    echo ""
    pick_file "Select GSI image" '(\.img\.(xz|gz)|/system[^/]*\.img|gsi[^/]*\.img)$' '/images/' || { say "Cancelled."; pause; return 0; }
    local gsi="$PICKED" bn l slot ab=0 nab=0 sysimg
    bn="$(basename "$gsi")"; l="${bn,,}"; sysimg="$gsi"
    slot=$(fb_var current-slot); [ "$slot" != UNKNOWN ] && ab=1
    [[ "$l" == *-ab* || "$l" == *_ab* ]] && nab=1
    echo ""
    [ "$ab" -eq 1 ] && [ "$nab" -eq 0 ] && warn "Phone is A/B but this image looks A-only."
    [ "$ab" -eq 0 ] && [ "$nab" -eq 1 ] && warn "Phone looks A-only but this is an 'ab' image."

    case "$l" in *.img.xz|*.img.gz)
        local dec=xz pk=xz-utils; [[ "$l" == *.gz ]] && { dec=gzip; pk=gzip; }
        type -P "$dec" >/dev/null 2>&1 || animate "Installing $pk" pkg install -y "$pk"
        mkdir -p "$GSI_DIR"; sysimg="$GSI_DIR/system.img"; rm -f "$sysimg"
        local free; free=$(df -kP "$BASE_DIR" 2>/dev/null | awk 'NR==2{print $4}')
        if [[ "${free:-}" =~ ^[0-9]+$ ]] && [ "$free" -lt 4000000 ]; then warn "Low free space ($((free / 1024)) MB). Decompress may fail."; fi
        animate "Decompressing $bn" bash -c "$dec -dc \"\$1\" > \"\$2\"" _ "$gsi" "$sysimg" \
            || { bad "Decompression failed."; tail -n 3 "$LAST_OUT"; rm -f "$sysimg"; pause; return 1; }
        ok "Decompressed ($(human_size "$sysimg"))." ;;
    esac

    local vbm wipe=0
    vbm=$(scan_list '/vbmeta\.img$' | grep -F "$(dirname "$gsi")/" | head -n1 || true)
    [ -z "$vbm" ] && vbm=$(scan_list '/vbmeta\.img$' | head -n1)
    ask_yn "Wipe user data (recommended)?" y && wipe=1

    echo -e "\n ${CYAN}--- GSI Summary ---${RESET}"
    echo -e " Image  : ${BOLD}$(shorten "$bn" $((COLS - 14)))${RESET}"
    echo -e " Phone  : ${BOLD}$([ "$ab" -eq 1 ] && echo "A/B (slot $slot)" || echo "A-only")${RESET}"
    echo -e " vbmeta : ${BOLD}$([ -n "$vbm" ] && echo "$(basename "$vbm") (verity off)" || echo "not found - skipped")${RESET}"
    [ "$wipe" -eq 1 ] && echo -e " Data   : ${RED}WILL BE ERASED${RESET}" || echo -e " Data   : ${GREEN}kept${RESET}"
    echo; ask_yn "Start GSI flashing now?" n || { say "Cancelled."; pause; return 0; }
    flash_begin || { pause; return 0; }
    echo ""

    if [ "$(fb_var is-userspace)" != yes ]; then
        if animate "Rebooting to fastbootd" fastboot reboot fastboot; then
            echo -e " ${GRAY}If a USB popup appears, tap Allow.${RESET}"
            animate "Waiting for fastbootd" wait_userspace && ok "fastbootd ready." || warn "fastbootd not detected. Trying direct flash."
        else warn "No fastbootd. Flashing directly."; fi
    fi
    run_step "Erasing system" 2 erase system || warn "Erase skipped."
    run_step "Flashing system image" 3 flash system "$sysimg" \
        || { bad "System flash failed:"; tail -n 4 "$LAST_OUT"; unlock_screen; pause; return 1; }
    ok "System image flashed."
    if [ -n "$vbm" ]; then
        run_step "Flashing vbmeta" 2 --disable-verity --disable-verification flash vbmeta "$vbm" && ok "vbmeta flashed." || warn "vbmeta failed (not always needed)."
    else warn "No vbmeta.img found. If it will not boot, flash vbmeta via menu 1."; fi
    [ "$wipe" -eq 1 ] && { run_step "Wiping user data" 2 -w && ok "Data wiped." || warn "Wipe failed; reset from recovery."; }
    rm -f "$GSI_DIR/system.img"; unlock_screen
    ok "GSI flashing finished!"
    ask_yn "Reboot to system now?" y && { fastboot reboot >/dev/null 2>&1 || adb reboot >/dev/null 2>&1; ok "Rebooting..."; }
    pause
}

# ------------------------------ 5-8. Device screens ---------------------------
device_info_screen() {
    header "Device Information"
    wait_for_device fastboot || return 0
    echo; progress_bar "Reading device info" 16
    echo -e "\n ${CYAN}$(hline $((COLS - 2)) "─")${RESET}"
    echo -e "  Product  : ${BOLD}$(fb_var product)${RESET}\n  Serial   : ${BOLD}$(fb_var serialno)${RESET}"
    echo -e "  Slot     : ${BOLD}$(fb_var current-slot)${RESET}\n  Unlocked : ${BOLD}$(fb_var unlocked)${RESET}"
    echo -e " ${CYAN}$(hline $((COLS - 2)) "─")${RESET}"
    pause
}

switch_slot_screen() {
    header "Switch A/B Slot"
    wait_for_device fastboot || return 0
    echo -e "\n Current slot: ${BOLD}$(fb_var current-slot)${RESET}"
    local s; printf " Target slot (a / b, 0 = back): "; read -r s || s=0; s="${s,,}"
    if [[ "$s" =~ ^[ab]$ ]]; then
        animate "Switching to slot $s" fastboot set_active "$s" && ok "Active slot is now $s." || { bad "Failed."; tail -n 3 "$LAST_OUT"; }
    else say "Cancelled."; fi
    pause
}

reboot_to() { # reboot_to <mode> <label>
    wait_for_device any || return 0
    local cmd=(reboot); [ "$1" != system ] && cmd+=("$1")
    if fb_present; then animate "Rebooting to $2" fastboot "${cmd[@]}"; else animate "Rebooting to $2" adb "${cmd[@]}"; fi \
        && ok "Reboot command sent ($2)." || { bad "Reboot failed."; tail -n 3 "$LAST_OUT"; }
}
reboot_screen() {
    header "Reboot Options"
    echo -e " ${GREEN}1${RESET}) System\n ${GREEN}2${RESET}) Recovery\n ${GREEN}3${RESET}) Bootloader\n ${GREEN}4${RESET}) Fastbootd\n ${GREEN}0${RESET}) Back\n"
    local o; printf " Select mode: "; read -r o || o=0
    case "$o" in
        1) reboot_to system System ;; 2) reboot_to recovery Recovery ;;
        3) reboot_to bootloader Bootloader ;; 4) reboot_to fastboot Fastbootd ;;
        *) return 0 ;;
    esac
    pause
}

wipe_data_screen() {
    header "Factory Reset / Wipe Data"
    wait_for_device fastboot || return 0
    echo; warn "This will erase ALL personal data!"
    local c; printf " Type WIPE to confirm: "; read -r c || c=""
    if [ "$c" = WIPE ]; then
        if animate "Wiping user data" fastboot -w; then ok "Data wiped."
        elif animate "Erasing userdata" fastboot erase userdata; then animate "Erasing metadata" fastboot erase metadata || true; ok "Data erased."
        else bad "Wipe failed."; tail -n 3 "$LAST_OUT"; fi
    else say "Cancelled."; fi
    pause
}

# ------------------------------ 9. Setup / fix connection ---------------------
setup_screen() {
    header "Setup & Fix Connection"
    setup_tools force
    echo -e "\n USB mode : ${BOLD}${USB_MODE}${RESET}"
    type -P termux-usb >/dev/null 2>&1 && echo -e " USB list : $(timeout 5 termux-usb -l 2>/dev/null | tr -d '\n ' | cut -c1-40)"
    echo -e "\n ${CYAN}If the phone is not found:${RESET}"
    echo "  1. Install the Termux:API app (same source as Termux)."
    echo "  2. Use a data cable + OTG adapter."
    echo "  3. Put the target phone in fastboot mode."
    echo "  4. Tap Allow on the USB popup."
    pause
}

# ------------------------------ Main menu -------------------------------------
ANIM=1
mline() { echo -e "${M}$1 $2●${RESET} $(printf '%-18s' "$3") ${GRAY}$4${RESET}"; [ "$ANIM" -eq 1 ] && sleep 0.025; return 0; }
msec()  { echo -e "${M}${CYAN}── $1 ──${RESET}"; [ "$ANIM" -eq 1 ] && sleep 0.025; return 0; }

main_menu() {
    clear; calc_layout; echo; echo -n "$M"
    typewriter " ANDROID ULTIMATE FLASHER  v${VERSION}"; echo
    progress_bar "Starting" 20
    setup_tools
    setup_storage
    scan_storage

    while true; do
        clear; calc_layout
        local fb=0 ad=0
        if [ "$USB_MODE" = native ]; then
            fb_present && DEV_STATE=fastboot || { adb_present && DEV_STATE=adb || DEV_STATE=none; }
        fi
        [ "$DEV_STATE" = fastboot ] && fb=1
        [ "$DEV_STATE" = adb ] && ad=1
        local d1="${RED}●${RESET}" d2="${RED}●${RESET}" d3="${RED}●${RESET}" dev="${RED}Not connected${RESET}"
        [ "$fb" -eq 1 ] && d1="${GREEN}●${RESET}"; [ "$ad" -eq 1 ] && d2="${GREEN}●${RESET}"
        command -v python3 >/dev/null 2>&1 && d3="${GREEN}●${RESET}"
        [ "$fb" -eq 1 ] && dev="${GREEN}Connected (fastboot)${RESET}"
        [ "$ad" -eq 1 ] && dev="${GREEN}Connected (adb)${RESET}"
        [ "$DEV_STATE" = unchecked ] && dev="${GRAY}Not checked (press c)${RESET}"

        draw_box "ANDROID ULTIMATE FLASHER" "Version ${VERSION} - Created by Rudra"
        echo -e "\n${M}Tools    $d1 fastboot  $d2 adb  $d3 python"
        echo -e "${M}USB      ${USB_MODE} mode\n${M}Device   $dev"
        echo -e "${M}Phone    $(scan_list '\.img$' | grep -c . || true) img • $(scan_list '\.zip$' | grep -c . || true) zip • $( { find_rom_dirs; find_rom_archives; } | grep -c . || true) rom\n"
        msec "FLASH"
        mline 1 "$GREEN"  "Flash Image"      "boot / recovery .img"
        mline 2 "$GREEN"  "Custom ROM (ADB)" "install .zip package"
        mline 3 "$YELLOW" "Fastboot ROM"     "auto extract & flash"
        mline 4 "$YELLOW" "Flash GSI"        "generic system image"
        msec "DEVICE"
        mline 5 "$GREEN"  "Device Info"      "model, slot, lock"
        mline 6 "$GREEN"  "Switch Slot"      "active A/B slot"
        mline 7 "$GREEN"  "Reboot"           "restart to a mode"
        mline 8 "$RED"    "Erase Data"       "factory reset"
        mline 9 "$CYAN"   "Setup / Fix USB"  "fix connection issues"
        msec "EXIT"
        mline 0 "$GREEN"  "Exit"             "quit application"
        echo -e "\n${M}${GREEN}●${RESET} Safe  ${YELLOW}●${RESET} Careful  ${RED}●${RESET} Erases data"
        echo -e "${M}${GRAY}r = rescan phone   c = check device${RESET}\n"
        ANIM=0
        local o; printf "%s Select: " "$M"; read -r o || exit 0
        case "$o" in
            1) flash_image_screen ;;   2) flash_sideload_screen ;;
            3) flash_fastboot_screen ;; 4) flash_gsi_screen ;;
            5) device_info_screen ;;   6) switch_slot_screen ;;
            7) reboot_screen ;;        8) wipe_data_screen ;;
            9) setup_screen ;;
            c|C) DEV_STATE=none; fb_present && DEV_STATE=fastboot || { adb_present && DEV_STATE=adb; }; say "Device: $DEV_STATE"; sleep 1 ;;
            r|R) setup_storage; scan_storage; sleep 1 ;;
            0) echo; typewriter " Goodbye!"; exit 0 ;;
            *) bad "Invalid option."; sleep 1 ;;
        esac
    done
}

# Install a short command:  rudra
install_shortcut() {
    local self target="$BASE_DIR/setup.sh" bin="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    self="$(realpath "$0" 2>/dev/null || echo "")"
    [ -f "$0" ] && [ -n "$self" ] && [ "$self" != "$(realpath "$target" 2>/dev/null)" ] && cp "$0" "$target" 2>/dev/null
    [ -f "$target" ] && { chmod +x "$target"; mkdir -p "$bin"; ln -sf "$target" "$bin/rudra" 2>/dev/null; }
    return 0
}

install_shortcut
[[ "${BASH_SOURCE[0]:-$0}" == "$0" ]] && main_menu
