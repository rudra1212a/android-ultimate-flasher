#!/usr/bin/env bash
# ==============================================================================
# Android Ultimate Flasher - Version 1.0
# Termux tool. Run once:  bash android_flasher_v1.0.sh   -> afterwards just: rudra
# ==============================================================================

set -uo pipefail

VERSION="1.0"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
ROMS_DIR="$HOME/flasher_roms"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"
SCAN_FILE="$BASE_DIR/scan.txt"
PARTS_FILE="$BASE_DIR/parts.txt"
RESUME_FILE="$BASE_DIR/resume.state"
GSI_DIR="$BASE_DIR/gsi"
mkdir -p "$BASE_DIR" "$ROMS_DIR"
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

# Keep Termux awake for the whole session (stops Android from freezing the tool)
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
# Runs a command in the background (never touches the keyboard) with a spinner
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
pause() { if [ -t 0 ]; then echo; read -n 1 -s -r -p "Press any key to continue..."; echo; fi; return 0; }
ask_yn() { # ask_yn "question" [y|n = default]
    local def="${2:-n}" hint="(y/N)" a
    [ "$def" = y ] && hint="(Y/n)"
    printf " %s %s: " "$1" "$hint"; read -r a || a=""
    [[ "${a:-$def}" =~ ^[yY]$ ]]
}

# ------------------------------ USB backend (works without root) --------------
USB_MODE="native"
detect_usb_mode() {
    if type -P termux-fastboot >/dev/null 2>&1 && type -P termux-adb >/dev/null 2>&1; then USB_MODE="termux"; else USB_MODE="native"; fi
}
fastboot() { if [ "$USB_MODE" = termux ]; then termux-fastboot "$@"; else command fastboot "$@"; fi; }
adb()      { if [ "$USB_MODE" = termux ]; then termux-adb "$@"; else command adb "$@"; fi; }
detect_usb_mode

# Installs everything automatically (first start, or menu 9)
setup_tools() { # setup_tools [force]
    local marker="$BASE_DIR/.setup_done" force="${1:-}"
    if [ -z "$force" ] && [ -f "$marker" ] && type -P fastboot >/dev/null 2>&1; then return 0; fi
    export DEBIAN_FRONTEND=noninteractive
    type -P fastboot >/dev/null 2>&1 || animate "Installing android-tools" bash -c "pkg update -y && pkg install -y android-tools"
    type -P termux-usb >/dev/null 2>&1 || animate "Installing termux-api" pkg install -y termux-api
    if ! type -P termux-fastboot >/dev/null 2>&1; then
        type -P curl >/dev/null 2>&1 || animate "Installing curl" pkg install -y curl
        animate "Installing USB helper (no-root)" bash -c "curl -fsSL https://raw.githubusercontent.com/nohajc/termux-adb/master/install.sh | bash"
    fi
    hash -r; detect_usb_mode; touch "$marker"
    if [ "$USB_MODE" = termux ]; then ok "USB helper ready (no-root mode)."
    else warn "USB helper not installed (check internet). Menu 9 retries."; fi
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
        warn "Allow storage permission for Termux..."
        command -v termux-setup-storage >/dev/null 2>&1 && termux-setup-storage
        for t in $(seq 1 20); do sleep 1; if _find_root; then found=1; break; fi; done
    fi
    if [ "$found" -eq 0 ]; then
        STORAGE_ROOT="$HOME/Download"; mkdir -p "$STORAGE_ROOT"
        bad "No storage access. Allow it, then press 'r' in the menu."; sleep 2
    fi
    SCAN_ROOTS=("$STORAGE_ROOT" "$ROMS_DIR")
    for d in "$HOME"/storage/external-*; do if [ -d "$d" ] && ls "$d" >/dev/null 2>&1; then SCAN_ROOTS+=("$d"); fi; done
}

# Looks through ALL folders of the phone (depth 10) for everything flashable
do_scan() {
    : > "$SCAN_FILE"
    local r
    for r in "${SCAN_ROOTS[@]}"; do
        find -L "$r" -maxdepth 10 \( -path '*/Android/data' -o -path '*/Android/obb' -o -name '.*' \) -prune -o \
            -type f \( -iname '*.img' -o -iname '*.zip' -o -iname '*.tgz' -o -iname '*.tar' -o -iname '*.tar.gz' \
                       -o -iname '*.img.xz' -o -iname '*.img.gz' -o -iname 'flash_all*.sh' \) -print 2>/dev/null
    done | sort -u > "$SCAN_FILE"
    return 0
}
scan_storage() {
    animate "Scanning phone storage" do_scan
    ok "Found $(grep -c . "$SCAN_FILE" 2>/dev/null || echo 0) flashable file(s)."
}
scan_list() { if [ -s "$SCAN_FILE" ]; then grep -iE "$1" "$SCAN_FILE" || true; fi; return 0; }
human_size() { du -h "$1" 2>/dev/null | cut -f1; }

# Fastboot ROM sources (only REAL ROMs are listed, no random folders)
#   script = extracted ROM with flash_all.sh   images = folder of partition images   arc = big archive
MIN_ARCHIVE_MB="${MIN_ARCHIVE_MB:-150}"
ROM_KIND=(); ROM_PATH=()
collect_roms() {
    ROM_KIND=(); ROM_PATH=()
    local f d n s inside seen=$'\n'
    local sdirs=()

    # 1) extracted ROMs: flash_all.sh next to an images folder (or several image files)
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        d="$(dirname "$f")"
        [[ "$d" == "$ROMS_DIR"/* ]] && continue
        case "$seen" in *$'\n'"$d"$'\n'*) continue ;; esac
        if [ ! -d "$d/images" ]; then
            n=$(find "$d" -maxdepth 1 -type f \( -iname '*.img' -o -iname '*.bin' -o -iname '*.mbn' \) 2>/dev/null | grep -c .)
            [ "$n" -ge 3 ] || continue
        fi
        seen+="$d"$'\n'; sdirs+=("$d"); ROM_KIND+=(script); ROM_PATH+=("$d")
    done < <(scan_list '/flash_all[^/]*\.sh$')

    # 2) plain image folders: boot.img or super.img + at least 4 images, not inside a ROM above
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        [[ "$d" == "$ROMS_DIR"/* ]] && continue
        [ "$d" = "$STORAGE_ROOT" ] || [ "$d" = "$STORAGE_ROOT/Download" ] && continue
        [ -f "$d/boot.img" ] || [ -f "$d/super.img" ] || continue
        n=$(find "$d" -maxdepth 1 -type f -iname '*.img' 2>/dev/null | grep -c .)
        [ "$n" -ge 4 ] || continue
        inside=0
        for s in "${sdirs[@]}"; do [[ "$d" == "$s"/* ]] && { inside=1; break; }; done
        [ "$inside" -eq 0 ] || continue
        case "$seen" in *$'\n'"$d"$'\n'*) continue ;; esac
        seen+="$d"$'\n'; ROM_KIND+=(images); ROM_PATH+=("$d")
    done < <(scan_list '\.img$' | while IFS= read -r f; do dirname "$f"; done | sort -u)

    # 3) archives: big .tgz / .tar.gz, ROM-named .tar, fastboot-named .zip
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        [[ "$f" == "$ROMS_DIR"/* ]] && continue
        [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -ge $((MIN_ARCHIVE_MB * 1048576)) ] || continue
        ROM_KIND+=(arc); ROM_PATH+=("$f")
    done < <(scan_list '\.(tgz|tar\.gz)$|(rom|image|fastboot)[^/]*\.tar$|(fastboot|_images_|images_v)[^/]*\.zip$')
}

# ------------------------------ Generic numbered list -------------------------
# Fill LIST with labels, call pick_index "<title>"  -> IDX (0-based) or return 1
LIST=(); IDX=0; PICK_DEFAULT=0
pick_index() {
    local title="$1" total=${#LIST[@]} page=0 per=12 pages s e i choice
    pages=$(( (total + per - 1) / per ))
    while true; do
        s=$((page * per)); e=$((s + per)); [ "$e" -gt "$total" ] && e=$total
        for ((i = s; i < e; i++)); do echo -e " ${GREEN}[$((i + 1))]${RESET} ${LIST[$i]}"; done
        [ "$pages" -gt 1 ] && echo -e "\n ${GRAY}Page $((page + 1))/$pages  (n = next, p = previous)${RESET}"
        printf "\n %s (0 = back): " "$title"; read -r choice || choice=0
        if [ -z "$choice" ] && [ "$PICK_DEFAULT" -gt 0 ]; then choice="$PICK_DEFAULT"; fi
        case "$choice" in
            n|N) page=$(( (page + 1) % pages )); echo; continue ;;
            p|P) page=$(( (page + pages - 1) % pages )); echo; continue ;;
        esac
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$total" ]; then IDX=$((choice - 1)); return 0; fi
        return 1
    done
}

# pick_file <title> <regex> [exclude-regex] -> PICKED
PICKED=""
pick_file() {
    local title="$1" ere="$2" excl="${3:-}" files=() f
    if [ -n "$excl" ]; then mapfile -t files < <(scan_list "$ere" | grep -viE "$excl" || true)
    else mapfile -t files < <(scan_list "$ere"); fi
    if [ "${#files[@]}" -eq 0 ] || [ -z "${files[0]:-}" ]; then
        warn "Nothing found on your phone."
        echo -e " ${GRAY}Copy the file to the phone, then press 'r' in the main menu.${RESET}"
        return 1
    fi
    LIST=()
    for f in "${files[@]}"; do
        LIST+=("${GRAY}$(printf '%6s' "$(human_size "$f")")${RESET} $(shorten "${f#"$STORAGE_ROOT"/}" $((COLS - 16)))")
    done
    echo -e " ${GRAY}Found ${#files[@]} file(s) on your phone:${RESET}\n"
    pick_index "$title" || return 1
    PICKED="${files[$IDX]}"
}

refresh_scan() { animate "Looking for files" do_scan; }

# ------------------------------ Safe flashing ---------------------------------
flash_begin() { # battery warning + reminder
    if type -P termux-battery-status >/dev/null 2>&1; then
        local b pct; b=$(timeout 5 termux-battery-status 2>/dev/null || true)
        pct=$(printf '%s' "$b" | grep -o '"percentage": *[0-9]*' | grep -o '[0-9]*$' | head -n1)
        if [[ "${pct:-}" =~ ^[0-9]+$ ]] && [ "$pct" -lt 30 ] && [[ "$b" == *UNPLUGGED* ]]; then
            warn "This phone's battery is ${pct}%. Low power can break a flash!"
            ask_yn "Continue anyway?" n || return 1
        fi
    fi
    lock_awake
    echo -e " ${GRAY}Keep the screen ON and do not unplug the cable.${RESET}"
    return 0
}

# run_step <label> <tries> <fastboot args...>  (retries; waits for reconnect; 99 = user went back)
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
CRITICAL="bootloader|xbl|xbl_config|abl|modem|persist|efs|modemst1|modemst2|fsg|sbl1|tz|aboot|rpm|hyp|devcfg|keymaster|preloader|lk|nvram|nvdata|proinfo|protect1|protect2|seccfg"
PARTS=(boot recovery vendor_boot init_boot dtbo vbmeta vbmeta_system vbmeta_vendor logo super)
SKIP_PARTS="userdata|metadata|cache|misc|frp|sdcard"

# Reads the REAL partition list from the phone (no typing needed)
read_partitions() {
    local raw
    raw=$(fastboot getvar all 2>&1 | grep -oE 'partition-type:[A-Za-z0-9_]+' | cut -d: -f2 | sed -E 's/_(a|b)$//' | sort -u)
    : > "$PARTS_FILE"
    local p
    for p in "${PARTS[@]}"; do printf '%s\n' "$raw" | grep -qx "$p" && echo "$p" >> "$PARTS_FILE"; done
    printf '%s\n' "$raw" | grep -vxE "$SKIP_PARTS" | grep -vxFf "$PARTS_FILE" | grep . >> "$PARTS_FILE" || true
    return 0
}

flash_image_screen() {
    header "Flash Individual Image"
    refresh_scan; echo ""
    pick_file "Select image number" '\.img$' || { say "Cancelled."; pause; return 0; }
    local img="$PICKED" guess part="" p i=0 def=0 sel
    [ -s "$img" ] || { bad "Image file is empty."; pause; return 1; }
    guess="$(basename "$img")"; guess="${guess%.*}"; guess="${guess,,}"

    echo ""
    wait_for_device fastboot || return 0
    animate "Reading partitions from phone" read_partitions
    local parts=() verified=1
    mapfile -t parts < "$PARTS_FILE"
    if [ "${#parts[@]}" -eq 0 ] || [ -z "${parts[0]:-}" ]; then parts=("${PARTS[@]}"); verified=0; fi

    echo -e "\n ${CYAN}Choose partition$([ "$verified" -eq 0 ] && echo " (could not verify on phone)"):${RESET}"
    LIST=()
    for p in "${parts[@]}"; do
        i=$((i + 1)); sel="$p"
        [ "$p" = "$guess" ] && { sel="$p ${GREEN}★ suggested${RESET}"; def=$i; }
        [[ "$p" =~ ^($CRITICAL)$ ]] && sel="$sel ${RED}(critical)${RESET}"
        LIST+=("$sel")
    done
    if [ "$def" -gt 0 ]; then
        echo -e " ${GRAY}Press Enter to use the suggested one [$def].${RESET}"
    fi
    PICK_DEFAULT=$def
    pick_index "Select partition" || { PICK_DEFAULT=0; say "Cancelled."; pause; return 0; }
    PICK_DEFAULT=0
    part="${parts[$IDX]}"

    local targets=("$part")
    if [ "$(fb_var current-slot)" != UNKNOWN ]; then
        ask_yn "A/B phone: flash BOTH slots (a and b)?" n && targets=("${part}_a" "${part}_b")
    fi

    if [[ "$part" =~ ^($CRITICAL)$ ]]; then
        warn "[$part] is CRITICAL. A wrong image can hard-brick the phone!"
        printf " Type YES to continue: "; read -r sel || sel=""
        [ "$sel" = YES ] || { say "Cancelled."; pause; return 0; }
    fi
    if [ "$guess" != "$part" ] && printf '%s\n' "${PARTS[@]}" | grep -qx "$guess"; then
        warn "File is named '$guess' but you picked '$part'. Wrong image = bootloop!"
        ask_yn "Are you SURE?" n || { say "Cancelled."; pause; return 0; }
    fi

    echo -e "\n Image  : ${BOLD}$(shorten "$(basename "$img")" $((COLS - 14)))${RESET}\n Target : ${BOLD}${targets[*]}${RESET}"
    ask_yn "Flash now?" n || { say "Cancelled."; pause; return 0; }
    local nov=0
    if [[ "$part" == vbmeta* ]]; then ask_yn "Disable verity & verification?" n && nov=1; fi

    flash_begin || { pause; return 0; }
    local t rc=0
    for t in "${targets[@]}"; do
        if [ "$nov" -eq 1 ]; then run_step "Flashing $t" 3 --disable-verity --disable-verification flash "$t" "$img"
        else run_step "Flashing $t" 3 flash "$t" "$img"; fi
        rc=$?
        if [ "$rc" -eq 0 ]; then ok "$t flashed!"; else bad "Flashing $t failed:"; tail -n 4 "$LAST_OUT"; break; fi
    done
    if [ "$rc" -eq 0 ] && [ "$part" = recovery ]; then
        ask_yn "Reboot to recovery now (recommended)?" y && { fastboot reboot recovery >/dev/null 2>&1; ok "Rebooting to recovery..."; }
    fi
    pause
}

# ------------------------------ 2. Custom ROM (sideload) ----------------------
flash_sideload_screen() {
    header "ADB Sideload Custom ROM"
    refresh_scan; echo ""
    pick_file "Select zip number" '\.zip$' || { say "Cancelled."; pause; return 0; }
    echo ""
    wait_for_device sideload || return 0
    say "Sideloading $(shorten "$(basename "$PICKED")" $((COLS - 16)))..."
    adb sideload "$PICKED" 2>&1 | tee "$LAST_OUT"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then ok "Sideload finished!"; else warn "Check the recovery screen; it may still have worked."; fi
    pause
}

# ------------------------------ 3. Fastboot ROM -------------------------------
PLAN=(); PLAN_ERR=""; R_KIND=""; R_SRC=""; R_IMGDIR=""; R_TEMP=0

# Extracts an archive into the Termux folder (fast & safe). Sets R_KIND / R_SRC.
extract_archive() {
    local arc="$1" base out need free found
    base="$(basename "$arc")"; base="${base%.tar.gz}"; base="${base%.tgz}"; base="${base%.tar}"; base="${base%.zip}"
    out="$ROMS_DIR/$base"
    if [ ! -f "$out/.extract_ok" ]; then
        need=$(( $(stat -c %s "$arc" 2>/dev/null || echo 0) * 3 / 1024 ))
        free=$(df -kP "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
        if [[ "${free:-}" =~ ^[0-9]+$ ]] && [ "$free" -lt "$need" ]; then bad "Not enough storage (need ~$((need / 1024)) MB)."; return 1; fi
        rm -rf "$out"; mkdir -p "$out"
        case "${arc,,}" in
            *.zip)
                type -P unzip >/dev/null 2>&1 || animate "Installing unzip" pkg install -y unzip
                animate "Extracting $(basename "$arc")" unzip -q -o "$arc" -d "$out" ;;
            *.tar) animate "Extracting $(basename "$arc")" tar -xf "$arc" -C "$out" --no-same-owner ;;
            *)     animate "Extracting $(basename "$arc")" tar -xzf "$arc" -C "$out" --no-same-owner ;;
        esac || { bad "Extraction failed:"; tail -n 3 "$LAST_OUT"; rm -rf "$out"; return 1; }
        touch "$out/.extract_ok"; ok "Extracted."
    else
        ok "Already extracted. Using saved copy."
    fi
    found=$(find "$out" -maxdepth 6 -type f -iname 'flash_all*.sh' 2>/dev/null | head -n1)
    if [ -n "$found" ]; then R_KIND=script; R_SRC="$(dirname "$found")"
    else
        found=$(find "$out" -maxdepth 6 -type f \( -iname 'boot.img' -o -iname 'super.img' \) 2>/dev/null | head -n1)
        [ -n "$found" ] || { bad "No flashable ROM found inside the archive."; return 1; }
        R_KIND=images; R_SRC="$(dirname "$found")"
    fi
    R_TEMP=1
}

# Reads flash_all*.sh and turns it into fastboot steps (no eval = safe)
build_plan() {
    local script="$1" imgdir="$2" line args tok toks joined
    PLAN=(); PLAN_ERR=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        args=$(printf '%s\n' "$line" | sed -nE 's/^[[:space:]]*("?\$\{?[A-Za-z_]*\}?"?|[^[:space:]#]*fastboot[^[:space:]]*)[[:space:]]+((flash|erase|set_active|reboot|flashing|oem|-w|--set-active|--disable-verity|--disable-verification)([[:space:]].*)?)$/\2/p')
        [ -z "$args" ] && continue
        args=$(printf '%s\n' "$args" | sed -E 's#\$\(dirname[^)]*\)/?##g; s/[[:space:]]*(\|\||&&|;|[0-9]?>).*$//')
        [ -z "$args" ] && continue
        read -ra toks <<< "$args"; joined=""
        for tok in "${toks[@]}"; do
            tok="${tok//\"/}"; tok="${tok//\'/}"
            case "$tok" in *.img|*.bin|*.mbn|*.elf|*.hex|*.mdt|*.pro|*.lz4|*.ubi|*.zip|*.txt|*.xml) tok="$imgdir/$(basename "$tok")" ;; esac
            if [[ "$tok" == *'$'* ]]; then PLAN_ERR="Unsupported script line: $line"; return 1; fi
            joined+="${tok}${US}"
        done
        PLAN+=("${joined%"$US"}")
    done < "$script"
    [ "${#PLAN[@]}" -gt 0 ] || { PLAN_ERR="No flash commands found in the script."; return 1; }
}

# Images-only folder: flash only the safe, well-known partitions
build_plan_images() {
    local dir="$1" p
    PLAN=(); PLAN_ERR=""
    for p in boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system vbmeta_vendor logo super; do
        [ -f "$dir/$p.img" ] && PLAN+=("flash${US}${p}${US}${dir}/${p}.img")
    done
    [ "${#PLAN[@]}" -gt 0 ] || PLAN_ERR="No supported images in this folder."
    [ "${#PLAN[@]}" -gt 0 ]
}

script_label() {
    case "${1,,}" in
        *lock*) echo "Flash + re-LOCK bootloader (risky)" ;;
        *except_storage*|*except_data*|*save*) echo "Flash, KEEP my data" ;;
        flash_all.sh) echo "Clean flash (erases ALL data)" ;;
        *) echo "Custom script" ;;
    esac
}

# Builds the plan, checks files/device, shows summary. 0 = OK to continue
rom_prepare() {
    local script="" step toks t missing=0 erase=0 lockit=0 nflash=0 j rp="" dp x
    R_IMGDIR="$R_SRC"
    if [ "$R_KIND" = script ]; then
        local scripts=() i
        mapfile -t scripts < <(find "$R_SRC" -maxdepth 1 -type f -iname 'flash_all*.sh' | sort)
        [ "${#scripts[@]}" -gt 0 ] || { bad "No flash_all*.sh in the ROM folder."; return 1; }
        script="${scripts[0]}"
        if [ "${#scripts[@]}" -gt 1 ]; then
            echo -e " ${CYAN}Flash mode:${RESET}"
            LIST=()
            for ((i = 0; i < ${#scripts[@]}; i++)); do LIST+=("$(script_label "$(basename "${scripts[$i]}")")"); done
            pick_index "Select mode" || { say "Cancelled."; return 1; }
            script="${scripts[$IDX]}"
        fi
        R_SRC="$script"
        [ -d "$(dirname "$script")/images" ] && R_IMGDIR="$(dirname "$script")/images" || R_IMGDIR="$(dirname "$script")"
        build_plan "$script" "$R_IMGDIR" || { bad "$PLAN_ERR"; return 1; }
        rp=$(grep -m1 -E 'product: ?\*?[A-Za-z0-9_]+' "$script" 2>/dev/null | sed -nE 's/.*product: ?\*?([A-Za-z0-9_]+).*/\1/p')
    else
        build_plan_images "$R_SRC" || { bad "$PLAN_ERR"; return 1; }
    fi

    for step in "${PLAN[@]}"; do
        IFS="$US" read -ra toks <<< "$step"; j=" ${toks[*]} "
        for t in "${toks[@]}"; do
            if [[ "$t" == "$R_IMGDIR"/* ]]; then
                if [ ! -s "$t" ]; then missing=$((missing + 1)); [ "$missing" -le 4 ] && bad "Missing/empty: $(basename "$t")"; fi
            fi
        done
        [[ "$j" == *" flash "* ]] && nflash=$((nflash + 1))
        [[ "$j" == *" -w "* || "$j" == *" erase userdata "* ]] && erase=1
        [[ "$j" == *" lock "* ]] && lockit=1
    done
    [ "$missing" -eq 0 ] || { bad "ROM package is incomplete."; return 1; }

    dp=$(fb_var product)
    echo -e "\n ${CYAN}--- ROM Summary ---${RESET}"
    echo -e " Type       : ${BOLD}$([ "$R_KIND" = script ] && echo "Fastboot ROM" || echo "Images folder (basic)")${RESET}"
    [ "$R_KIND" = script ] && echo -e " ROM for    : ${BOLD}${rp:-unknown}${RESET}"
    echo -e " Your phone : ${BOLD}${dp}${RESET}\n Steps      : ${BOLD}${#PLAN[@]}${RESET} (${nflash} flash)"
    if [ "$erase" -eq 1 ]; then echo -e " Your data  : ${RED}WILL BE ERASED${RESET}"; else echo -e " Your data  : ${GREEN}kept${RESET}"; fi

    if [ "$R_KIND" = images ]; then
        warn "No device check is possible for a plain images folder."
        printf " Type YES if these images are for your phone: "; read -r x || x=""
        [ "$x" = YES ] || { say "Cancelled."; return 1; }
    elif [ -n "$rp" ] && [ "$dp" != UNKNOWN ] && [ "${rp,,}" != "${dp,,}" ]; then
        echo; bad "WRONG DEVICE! ROM is for '$rp', phone is '$dp'."
        printf " Type FORCE to flash anyway: "; read -r x || x=""
        [ "$x" = FORCE ] || { say "Cancelled."; return 1; }
    fi
    if [ "$lockit" -eq 1 ]; then
        warn "This script RE-LOCKS the bootloader."
        printf " Type LOCK to continue: "; read -r x || x=""
        [ "$x" = LOCK ] || { say "Cancelled."; return 1; }
    fi
    return 0
}

run_plan() { # run_plan <start_step>
    local start="$1" total=${#PLAN[@]} n=0 rc short stop=0 tries step toks
    echo ""
    for step in "${PLAN[@]}"; do
        n=$((n + 1))
        [ "$n" -lt "$start" ] && continue
        IFS="$US" read -ra toks <<< "$step"
        short="${toks[*]:0:2}"; short="${short//$R_IMGDIR\//}"
        tries=3; [[ " ${toks[*]} " == *" reboot "* ]] && tries=1
        run_step "[$n/$total] $short" "$tries" "${toks[@]}"; rc=$?
        if [ "$rc" -eq 0 ]; then
            echo -e " ${GREEN}✔${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14)))"
            echo "${R_KIND}|${R_SRC}|${n}|${R_IMGDIR}|${R_TEMP}" > "$RESUME_FILE"
        elif [ "$rc" -eq 99 ]; then stop=1; break
        elif [[ " ${toks[*]} " == *" flash "* || " ${toks[*]} " == *" set_active "* ]]; then
            echo -e " ${RED}✘${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14)))"
            bad "Step failed:"; tail -n 4 "$LAST_OUT"; stop=1; break
        else
            echo -e " ${YELLOW}!${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14))) (skipped)"
            echo "${R_KIND}|${R_SRC}|${n}|${R_IMGDIR}|${R_TEMP}" > "$RESUME_FILE"
        fi
    done
    echo ""
    if [ "$stop" -eq 0 ]; then
        rm -f "$RESUME_FILE"; ok "ROM flashed successfully!"
        if [ "$R_KIND" = images ]; then ask_yn "Reboot to system now?" y && { fastboot reboot >/dev/null 2>&1; ok "Rebooting..."; }; fi
        if [ "$R_TEMP" = 1 ]; then
            ask_yn "Delete the extracted copy to free space?" y && { rm -rf "${ROMS_DIR:?}"/*; animate "Updating list" do_scan; ok "Space freed."; }
        fi
    else
        bad "Stopped at step $n of $total. Do NOT boot the phone yet."
        warn "Reconnect, open menu 3 again: it will offer to RESUME."
    fi
}

# Unfinished flash? Offer to continue. Returns 0 if handled (caller returns), 1 if nothing to resume
try_resume() {
    [ -f "$RESUME_FILE" ] || return 1
    local rk rs rn ri rt rp="" pd
    IFS='|' read -r rk rs rn ri rt < "$RESUME_FILE" || true
    if ! [[ "${rn:-}" =~ ^[0-9]+$ ]] || [ ! -e "${rs:-/nonexistent}" ]; then rm -f "$RESUME_FILE"; return 1; fi
    warn "An unfinished flash was found (stopped after step $rn)."
    if ! ask_yn "Resume it now?" y; then rm -f "$RESUME_FILE"; return 1; fi
    echo ""
    wait_for_device fastboot || return 0
    R_KIND="$rk"; R_SRC="$rs"; R_IMGDIR="$ri"; R_TEMP="${rt:-0}"
    if [ "$R_KIND" = script ]; then
        build_plan "$rs" "$ri" || { bad "$PLAN_ERR"; pause; return 0; }
        rp=$(grep -m1 -E 'product: ?\*?[A-Za-z0-9_]+' "$rs" 2>/dev/null | sed -nE 's/.*product: ?\*?([A-Za-z0-9_]+).*/\1/p')
    else
        build_plan_images "$rs" || { bad "$PLAN_ERR"; pause; return 0; }
    fi
    pd=$(fb_var product)
    echo -e " Your phone : ${BOLD}${pd}${RESET}   Steps: ${BOLD}${#PLAN[@]}${RESET}"
    if [ -n "$rp" ] && [ "$pd" != UNKNOWN ] && [ "${rp,,}" != "${pd,,}" ]; then
        bad "WRONG DEVICE! ROM is for '$rp', phone is '$pd'."; pause; return 0
    fi
    ask_yn "Continue from step $((rn + 1))?" y || { say "Cancelled."; pause; return 0; }
    flash_begin || { pause; return 0; }
    run_plan $((rn + 1)); pause
    return 0
}

flash_fastboot_screen() {
    header "Fastboot ROM Flash"
    refresh_scan; echo ""

    try_resume && return 0

    collect_roms
    if [ "${#ROM_PATH[@]}" -eq 0 ]; then
        warn "No fastboot ROM found on your phone."
        echo -e " ${GRAY}Looked for: .tgz / .tar.gz archives, extracted ROM folders,${RESET}"
        echo -e " ${GRAY}and image folders. Copy it to the phone, then press 'r'.${RESET}"
        pause; return 0
    fi
    LIST=()
    local i k
    for ((i = 0; i < ${#ROM_PATH[@]}; i++)); do
        case "${ROM_KIND[$i]}" in
            script) k="${GREEN}FOLDER ${RESET}" ;;
            images) k="${GREEN}IMAGES ${RESET}" ;;
            *)      k="${YELLOW}ARCHIVE${RESET}" ;;
        esac
        if [ "${ROM_KIND[$i]}" = arc ]; then
            LIST+=("$k $(shorten "$(basename "${ROM_PATH[$i]}")" $((COLS - 28))) ${GRAY}$(human_size "${ROM_PATH[$i]}")${RESET}")
        else
            LIST+=("$k $(shorten "$(basename "${ROM_PATH[$i]}")" $((COLS - 20)))")
        fi
    done
    echo -e " ${CYAN}Fastboot ROMs on your phone:${RESET}"
    echo -e " ${GRAY}FOLDER = extracted, ARCHIVE = auto-extract${RESET}\n"
    pick_index "Select ROM" || { say "Cancelled."; pause; return 0; }
    local sel="${ROM_PATH[$IDX]}"
    R_KIND="${ROM_KIND[$IDX]}"; R_SRC="$sel"; R_TEMP=0
    [[ "$sel" == "$ROMS_DIR"/* ]] && R_TEMP=1
    echo ""
    if [ "$R_KIND" = arc ]; then extract_archive "$sel" || { pause; return 1; }; fi

    echo ""
    wait_for_device fastboot || return 0
    rom_prepare || { pause; return 0; }
    echo ""
    ask_yn "Start flashing now?" n || { say "Cancelled."; pause; return 0; }
    flash_begin || { pause; return 0; }
    run_plan 1
    pause
}

# ------------------------------ 4. GSI ----------------------------------------
wait_userspace() {
    local i
    for i in $(seq 1 60); do sleep 1; if fb_present && [ "$(fb_var is-userspace)" = yes ]; then return 0; fi; done
    return 1
}

# Lists GSI images: by name, or any big .img (>600 MB) outside ROM folders
gsi_candidates() {
    { scan_list '(\.img\.(xz|gz)|/system[^/]*\.img|gsi[^/]*\.img)$' | grep -viE '/images/'
      scan_list '\.img$' | grep -viE '/images/' | while IFS= read -r f; do
          [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt 629145600 ] && echo "$f"
      done
    } | sort -u
}

flash_gsi_screen() {
    header "Flash GSI System Image"
    refresh_scan; echo ""
    local files=() f
    mapfile -t files < <(gsi_candidates)
    if [ "${#files[@]}" -eq 0 ] || [ -z "${files[0]:-}" ]; then
        warn "No GSI image found on your phone."
        echo -e " ${GRAY}Copy the GSI (.img / .img.xz) to the phone, then press 'r'.${RESET}"
        pause; return 0
    fi
    LIST=()
    for f in "${files[@]}"; do LIST+=("${GRAY}$(printf '%6s' "$(human_size "$f")")${RESET} $(shorten "$(basename "$f")" $((COLS - 16)))"); done
    echo -e " ${CYAN}GSI images on your phone:${RESET}\n"
    pick_index "Select GSI" || { say "Cancelled."; pause; return 0; }
    echo ""
    wait_for_device fastboot || return 0
    local gsi="${files[$IDX]}" bn l slot ab=0 nab=0 sysimg
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
        local free; free=$(df -kP "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
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
    if [ "$wipe" -eq 1 ]; then echo -e " Data   : ${RED}WILL BE ERASED${RESET}"; else echo -e " Data   : ${GREEN}kept${RESET}"; fi
    echo; ask_yn "Start GSI flashing now?" n || { say "Cancelled."; pause; return 0; }
    flash_begin || { pause; return 0; }
    echo ""

    if [ "$(fb_var is-userspace)" != yes ]; then
        if animate "Rebooting to fastbootd" fastboot reboot fastboot; then
            echo -e " ${GRAY}If a USB popup appears, tap Allow.${RESET}"
            if animate "Waiting for fastbootd" wait_userspace; then ok "fastbootd ready."; else warn "fastbootd not detected. Trying direct flash."; fi
        else warn "No fastbootd. Flashing directly."; fi
    fi
    run_step "Erasing system" 2 erase system || warn "Erase skipped."
    if ! run_step "Flashing system image" 3 flash system "$sysimg"; then
        bad "System flash failed:"; tail -n 4 "$LAST_OUT"; pause; return 1
    fi
    ok "System image flashed."
    if [ -n "$vbm" ]; then
        if run_step "Flashing vbmeta" 2 --disable-verity --disable-verification flash vbmeta "$vbm"; then ok "vbmeta flashed."; else warn "vbmeta failed (not always needed)."; fi
    else warn "No vbmeta.img found. If it will not boot, flash vbmeta via menu 1."; fi
    if [ "$wipe" -eq 1 ]; then
        if run_step "Wiping user data" 2 -w; then ok "Data wiped."; else warn "Wipe failed; reset from recovery."; fi
    fi
    rm -f "$GSI_DIR/system.img"
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
        if animate "Switching to slot $s" fastboot set_active "$s"; then ok "Active slot is now $s."; else bad "Failed."; tail -n 3 "$LAST_OUT"; fi
    else say "Cancelled."; fi
    pause
}

reboot_to() { # reboot_to <mode> <label>
    wait_for_device any || return 0
    local cmd=(reboot) rc
    [ "$1" != system ] && cmd+=("$1")
    if fb_present; then animate "Rebooting to $2" fastboot "${cmd[@]}"; rc=$?
    else animate "Rebooting to $2" adb "${cmd[@]}"; rc=$?; fi
    if [ "$rc" -eq 0 ]; then ok "Reboot command sent ($2)."; else bad "Reboot failed."; tail -n 3 "$LAST_OUT"; fi
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
    echo -e "\n ${CYAN}If the phone is not found:${RESET}"
    echo "  1. Install the Termux:API app (same source as Termux)."
    echo "  2. Use a data cable + OTG adapter."
    echo "  3. Put the target phone in fastboot mode."
    echo "  4. Tap Allow on the USB popup."
    echo -e "\n ${CYAN}If Termux closes in the background:${RESET}"
    echo "  Settings > Battery > Termux > Unrestricted, and in"
    echo "  Developer options enable 'Disable child process restrictions'."
    pause
}

# ------------------------------ Main menu -------------------------------------
ANIM=1
mline() { echo -e "${M}$1 $2●${RESET} $(printf '%-18s' "$3") ${GRAY}$4${RESET}"; if [ "$ANIM" -eq 1 ]; then sleep 0.025; fi; return 0; }
msec()  { echo -e "${M}${CYAN}── $1 ──${RESET}"; if [ "$ANIM" -eq 1 ]; then sleep 0.025; fi; return 0; }

main_menu() {
    clear; calc_layout; echo; echo -n "$M"
    typewriter " ANDROID ULTIMATE FLASHER  v${VERSION}"; echo
    progress_bar "Starting" 20
    lock_awake
    setup_tools
    setup_storage
    scan_storage

    while true; do
        clear; calc_layout
        local fb=0 ad=0
        if [ "$USB_MODE" = native ]; then
            if fb_present; then DEV_STATE=fastboot; elif adb_present; then DEV_STATE=adb; else DEV_STATE=none; fi
        fi
        [ "$DEV_STATE" = fastboot ] && fb=1
        [ "$DEV_STATE" = adb ] && ad=1
        local d1="${RED}●${RESET}" d2="${RED}●${RESET}" d3="${RED}●${RESET}" dev="${RED}Not connected${RESET}"
        [ "$fb" -eq 1 ] && d1="${GREEN}●${RESET}"
        [ "$ad" -eq 1 ] && d2="${GREEN}●${RESET}"
        command -v python3 >/dev/null 2>&1 && d3="${GREEN}●${RESET}"
        [ "$fb" -eq 1 ] && dev="${GREEN}Connected (fastboot)${RESET}"
        [ "$ad" -eq 1 ] && dev="${GREEN}Connected (adb)${RESET}"
        [ "$DEV_STATE" = unchecked ] && dev="${GRAY}Not checked (press c)${RESET}"

        collect_roms
        draw_box "ANDROID ULTIMATE FLASHER" "Version ${VERSION} - Created by Rudra"
        echo -e "\n${M}Tools    $d1 fastboot  $d2 adb  $d3 python"
        echo -e "${M}USB      ${USB_MODE} mode\n${M}Device   $dev"
        echo -e "${M}Phone    $(scan_list '\.img$' | grep -c . || true) img • $(scan_list '\.zip$' | grep -c . || true) zip • ${#ROM_PATH[@]} rom"
        [ -f "$RESUME_FILE" ] && echo -e "${M}${YELLOW}⚠ Unfinished flash found - open 3 to resume${RESET}"
        echo ""
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
            1) flash_image_screen ;;    2) flash_sideload_screen ;;
            3) flash_fastboot_screen ;; 4) flash_gsi_screen ;;
            5) device_info_screen ;;    6) switch_slot_screen ;;
            7) reboot_screen ;;         8) wipe_data_screen ;;
            9) setup_screen ;;
            c|C) if fb_present; then DEV_STATE=fastboot; elif adb_present; then DEV_STATE=adb; else DEV_STATE=none; fi
                 say "Device: $DEV_STATE"; sleep 1 ;;
            r|R) setup_storage; scan_storage; sleep 1 ;;
            0) echo; typewriter " Goodbye!"; exit 0 ;;
            *) bad "Invalid option."; sleep 1 ;;
        esac
    done
}

# Short command:  rudra
install_shortcut() {
    local self target="$BASE_DIR/setup.sh" bin="${PREFIX:-/data/data/com.termux/files/usr}/bin"
    self="$(realpath "$0" 2>/dev/null || echo "")"
    if [ -f "$0" ] && [ -n "$self" ] && [ "$self" != "$(realpath "$target" 2>/dev/null || echo x)" ]; then cp "$0" "$target" 2>/dev/null || true; fi
    if [ -f "$target" ]; then chmod +x "$target" 2>/dev/null || true; mkdir -p "$bin"; ln -sf "$target" "$bin/rudra" 2>/dev/null || true; fi
    return 0
}

install_shortcut
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then main_menu; fi
