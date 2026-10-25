#!/usr/bin/env bash
# ==============================================================================
# Script Name: Android Ultimate Flasher
# Description: Professional Android flashing tool for Termux (Version 1.3)
# ==============================================================================

set -uo pipefail

VERSION="1.3"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BASE_DIR="$HOME/.android-ultimate-flashing-tool"
LOG_FILE="$BASE_DIR/tool.log"
LAST_OUT="$BASE_DIR/last_output.txt"
PARTS_FILE="$BASE_DIR/parts.txt"
GSI_DIR="$BASE_DIR/gsi"

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
US=$'\x1f'

cursor_show() { printf '\033[?25h'; }
cursor_hide() { printf '\033[?25l'; }
trap cursor_show EXIT
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

# ---------------------------- Layout helpers ---------------------------------
COLS=54
CW=46
M=""

calc_layout() {
    local c
    c=$(tput cols 2>/dev/null || echo "")
    [[ "$c" =~ ^[0-9]+$ ]] || c="${COLUMNS:-54}"
    [ "$c" -lt 30 ] && c=30
    COLS="$c"
    CW=46
    [ "$COLS" -lt $((CW + 2)) ] && CW=$((COLS - 2))
    M=$(printf '%*s' "$(( (COLS - CW) / 2 ))" '')
}

hline() { local s; s=$(printf '%*s' "$1" ''); printf '%s' "${s// /$2}"; }

center() {
    local text="$1" width="$2"
    local len=${#text}
    local left=$(( (width - len) / 2 ))
    local right=$(( width - len - left ))
    [ "$left" -lt 0 ] && left=0
    [ "$right" -lt 0 ] && right=0
    printf "%*s%s%*s" "$left" "" "$text" "$right" ""
}

shorten() {
    local s="$1" max="$2"
    [ "$max" -lt 10 ] && max=10
    if [ "${#s}" -le "$max" ]; then
        printf '%s' "$s"
    else
        local h=$(( (max - 1) / 2 ))
        printf '%s…%s' "${s:0:$h}" "${s: -$((max - 1 - h))}"
    fi
}

draw_box() {
    local w=$((CW - 2)) top t
    top=$(hline "$w" "═")
    echo -e "${M}${GREEN}╔${top}╗${RESET}"
    for t in "$@"; do
        echo -e "${M}${GREEN}║${RESET}${BOLD}$(center "$t" "$w")${RESET}${GREEN}║${RESET}"
    done
    echo -e "${M}${GREEN}╚${top}╝${RESET}"
}

header() {
    clear
    calc_layout
    draw_box "$1"
    echo ""
}

# ---------------------------- Animations -------------------------------------
animate() {
    local message="$1"
    shift
    ("$@") > "$LAST_OUT" 2>&1 &
    local pid=$! i=0 start=$SECONDS el
    message=$(shorten "$message" $((COLS - 14)))
    cursor_hide
    while kill -0 "$pid" 2>/dev/null; do
        el=$((SECONDS - start))
        printf "\r\033[K${CYAN}[%s]${RESET} %s ${GRAY}%ss${RESET}" "${SPIN_FRAMES[$((i % 10))]}" "$message" "$el"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid"
    local rc=$?
    printf "\r\033[K"
    cursor_show
    return $rc
}

progress_bar() {
    local msg="$1" steps="${2:-24}" i filled empty
    cursor_hide
    for ((i = 0; i <= steps; i++)); do
        filled=$(hline "$i" "█")
        empty=$(hline "$((steps - i))" "░")
        printf "\r\033[K${CYAN}[*]${RESET} %s ${GREEN}%s${GRAY}%s${RESET} %3d%%" \
            "$msg" "$filled" "$empty" "$((i * 100 / steps))"
        sleep 0.02
    done
    echo ""
    cursor_show
}

typewriter() {
    local text="$1" i
    for ((i = 0; i < ${#text}; i++)); do
        printf "%s" "${text:$i:1}"
        sleep 0.012
    done
    echo ""
}

countdown() {
    local n="$1" msg="$2"
    cursor_hide
    while [ "$n" -gt 0 ]; do
        printf "\r\033[K${YELLOW}[%s]${RESET} %s in %s..." "$n" "$msg" "$n"
        sleep 1
        n=$((n - 1))
    done
    printf "\r\033[K"
    cursor_show
}

pause() {
    if [ -t 0 ]; then
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        echo ""
    fi
}

ask_yn() { # ask_yn "question" default(y|n) -> 0 if yes
    local q="$1" def="${2:-n}" ans hint="(y/N)"
    [ "$def" = "y" ] && hint="(Y/n)"
    printf " %s %s: " "$q" "$hint"
    read -r ans || ans=""
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[yY]$ ]]
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
    find_dl_dir && return 0
    warn "Storage access not available. Requesting permission..."
    if command -v termux-setup-storage >/dev/null 2>&1; then
        termux-setup-storage
        local t
        for t in $(seq 1 20); do
            printf "\r${CYAN}[%s]${RESET} Waiting for storage permission (%ss)..." "${SPIN_FRAMES[$((t % 10))]}" "$t"
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
    warn "Allow storage permission for Termux, then press 'r' in the menu."
    sleep 2
}

find_files() { # find_files <maxdepth> <pattern>...
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

find_rom_dirs() {
    [ -d "$DL_DIR" ] || return 0
    find -L "$DL_DIR" -maxdepth 6 -type f -iname 'flash_all*.sh' 2>/dev/null \
        | while IFS= read -r f; do dirname "$f"; done | sort -u
}

find_rom_archives() {
    [ -d "$DL_DIR" ] || return 0
    find -L "$DL_DIR" -maxdepth 2 -type f \( -iname '*.tgz' -o -iname '*.tar.gz' \) 2>/dev/null | sort
}

human_size() {
    local s
    s=$(du -h "$1" 2>/dev/null | cut -f1)
    echo "${s:-?}"
}

PICKED=""
pick_file() { # pick_file <title> <maxdepth> <pattern>...
    local title="$1" depth="$2"
    shift 2
    local -a files=()
    mapfile -t files < <(find_files "$depth" "$@")

    echo -e " ${GRAY}Folder: $(shorten "$DL_DIR" $((COLS - 12)))${RESET}"
    echo ""
    if [ "${#files[@]}" -eq 0 ] || [ -z "${files[0]:-}" ]; then
        warn "No matching files found."
        echo -e " ${GRAY}Looking for: $*${RESET}"
        return 1
    fi

    local total=${#files[@]} per=12 page=0 pages i start end rel choice
    pages=$(( (total + per - 1) / per ))
    while true; do
        start=$((page * per))
        end=$((start + per))
        [ "$end" -gt "$total" ] && end=$total
        for ((i = start; i < end; i++)); do
            rel="${files[$i]#"$DL_DIR"/}"
            echo -e " ${GREEN}[$((i + 1))]${RESET} ${GRAY}$(printf '%6s' "$(human_size "${files[$i]}")")${RESET} $(shorten "$rel" $((COLS - 16)))"
        done
        echo ""
        [ "$pages" -gt 1 ] && echo -e " ${GRAY}Page $((page + 1))/$pages  (n = next, p = previous)${RESET}"
        printf " %s (0 = back): " "$title"
        read -r choice || choice=0
        case "$choice" in
            n|N) page=$(( (page + 1) % pages )); echo ""; continue ;;
            p|P) page=$(( (page + pages - 1) % pages )); echo ""; continue ;;
        esac
        if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -le 0 ] || [ "$choice" -gt "$total" ]; then
            return 1
        fi
        PICKED="${files[$((choice - 1))]}"
        return 0
    done
}

# ---------------------------- Tools & Devices --------------------------------
need_pkg() { # need_pkg <command> <package>
    command -v "$1" >/dev/null 2>&1 && return 0
    warn "Installing $2..."
    animate "Installing $2" pkg install -y "$2" || { bad "Failed to install $2."; return 1; }
    command -v "$1" >/dev/null 2>&1
}

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

fb_present()       { fastboot devices 2>/dev/null | grep -q "fastboot"; }
adb_present()      { adb devices 2>/dev/null | awk 'NR>1 && ($2=="device" || $2=="sideload" || $2=="recovery"){f=1} END{exit !f}'; }
sideload_present() { adb devices 2>/dev/null | awk 'NR>1 && $2=="sideload"{f=1} END{exit !f}'; }

wait_for_device() { # <fastboot|sideload|any> -> 0 found, 1 back
    local mode="$1" label tip
    case "$mode" in
        fastboot) label="fastboot"; tip="Phone: power off, then hold Power + Volume Down." ;;
        sideload) label="sideload"; tip="Phone: Recovery > Apply update > Apply from ADB." ;;
        *)        label="fastboot/adb"; tip="Connect phone via USB (OTG) with USB debugging on." ;;
    esac

    _present() {
        case "$mode" in
            fastboot) fb_present ;;
            sideload) sideload_present ;;
            *)        fb_present || adb_present ;;
        esac
    }

    _present && return 0

    echo -e " ${GRAY}${tip}${RESET}"
    echo -e " ${GRAY}Press 0 or q to go back.${RESET}"
    echo ""
    local start=$SECONDS i=0 key=""
    cursor_hide
    while true; do
        printf "\r\033[K${CYAN}[%s]${RESET} Searching %s device... %ss" \
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

        if [ $((i % 5)) -eq 0 ] && _present; then
            printf "\r\033[K"
            cursor_show
            ok "Device found!"
            sleep 0.4
            return 0
        fi
    done
}

fb_var() {
    local var_name="${1:-}" val
    val=$(fastboot getvar "$var_name" 2>&1 | awk -F': *' -v k="$var_name" \
        '{sub(/^\(bootloader\) /,"")} tolower($1)==tolower(k){print $2; exit}' | tr -d '\r')
    echo "${val:-UNKNOWN}"
}

# ---------------------------- Flash Image ------------------------------------
CRITICAL_PARTS="bootloader|xbl|xbl_config|abl|modem|persist|efs|modemst1|modemst2|fsg|sbl1|tz|aboot|rpm|hyp|devcfg|keymaster|cmnlib|cmnlib64|preloader|lk"
BASE_PARTS=(boot recovery vendor_boot init_boot dtbo vbmeta vbmeta_system vbmeta_vendor logo super)

part_exists() {
    local p="$1" s
    for s in "$p" "${p}_a"; do
        if fastboot getvar "partition-size:$s" 2>&1 | grep -qiE "partition-size:${s}: *(0x)?[0-9a-f]+"; then
            return 0
        fi
    done
    return 1
}

detect_partitions() {
    : > "$PARTS_FILE"
    local p
    for p in "${BASE_PARTS[@]}"; do
        part_exists "$p" && echo "$p" >> "$PARTS_FILE"
    done
    return 0
}

flash_image_screen() {
    header "Flash Individual Image"
    wait_for_device fastboot || return 0
    echo ""

    pick_file "Select image number" 5 "*.img" || { say "Cancelled."; pause; return 0; }
    local selected_img="$PICKED"
    say "Image: $(shorten "$(basename "$selected_img")" $((COLS - 12)))"

    # --- detect partitions on the phone ---
    animate "Detecting partitions on device" detect_partitions
    local -a parts=()
    local verified=1
    mapfile -t parts < "$PARTS_FILE"
    if [ "${#parts[@]}" -eq 0 ] || [ -z "${parts[0]:-}" ]; then
        parts=("${BASE_PARTS[@]}")
        verified=0
    fi

    local guess
    guess="$(basename "$selected_img")"
    guess="${guess%.*}"
    guess="${guess,,}"

    echo ""
    if [ "$verified" -eq 1 ]; then
        echo -e " ${CYAN}Partitions found on your phone:${RESET}"
    else
        echo -e " ${YELLOW}Could not verify partitions. Common list:${RESET}"
    fi
    local i=0 p mark target_part="" default_idx=0
    for p in "${parts[@]}"; do
        i=$((i + 1))
        mark=""
        if [ "$p" = "$guess" ]; then mark=" ${GREEN}★ suggested${RESET}"; default_idx=$i; fi
        echo -e "  ${GREEN}[$i]${RESET} $p$mark"
    done
    echo -e "  ${GREEN}[c]${RESET} Custom partition name"
    echo ""
    local pc
    if [ "$default_idx" -gt 0 ]; then
        printf " Select partition [%s] (0 = back): " "$default_idx"
    else
        printf " Select partition (0 = back): "
    fi
    read -r pc || pc=0
    pc="${pc:-$default_idx}"
    if [[ "$pc" =~ ^[cC]$ ]]; then
        printf " Enter partition name: "
        read -r target_part || target_part=""
    elif [[ "$pc" =~ ^[0-9]+$ ]] && [ "$pc" -ge 1 ] && [ "$pc" -le "${#parts[@]}" ]; then
        target_part="${parts[$((pc - 1))]}"
    else
        say "Cancelled."
        pause
        return 0
    fi

    if [[ ! "$target_part" =~ ^[a-zA-Z0-9_]+$ ]]; then
        bad "Invalid partition name."
        pause
        return 1
    fi

    # --- slot selection (A/B devices) ---
    local -a targets=("$target_part")
    local slot
    slot=$(fb_var current-slot)
    if [ "$slot" != "UNKNOWN" ] && [[ ! "$target_part" =~ _[ab]$ ]]; then
        echo ""
        echo -e " ${CYAN}A/B device detected (active slot: $slot)${RESET}"
        echo "  [1] Active slot (default)"
        echo "  [2] Slot A  ->  ${target_part}_a"
        echo "  [3] Slot B  ->  ${target_part}_b"
        echo "  [4] Both slots"
        printf " Select slot [1]: "
        local sc
        read -r sc || sc=1
        case "${sc:-1}" in
            2) targets=("${target_part}_a") ;;
            3) targets=("${target_part}_b") ;;
            4) targets=("${target_part}_a" "${target_part}_b") ;;
            *) targets=("$target_part") ;;
        esac
    fi

    if [[ "$target_part" =~ ^($CRITICAL_PARTS)$ ]]; then
        echo ""
        warn "[$target_part] is a CRITICAL partition. A wrong image can hard-brick your phone!"
        local crit
        printf " Type YES to continue: "
        read -r crit || crit=""
        if [ "$crit" != "YES" ]; then
            say "Flashing cancelled."
            pause
            return 0
        fi
    fi

    echo ""
    echo -e " Image  : ${BOLD}$(shorten "$(basename "$selected_img")" $((COLS - 14)))${RESET}"
    echo -e " Target : ${BOLD}${targets[*]}${RESET}"
    ask_yn "Flash now?" n || { say "Flashing cancelled."; pause; return 0; }

    local disable_flags=0
    if [[ "$target_part" == vbmeta* ]]; then
        ask_yn "Disable verity and verification?" n && disable_flags=1
    fi

    local t rc failed=0
    for t in "${targets[@]}"; do
        if [ "$disable_flags" -eq 1 ]; then
            animate "Flashing $t (verity off)" fastboot --disable-verity --disable-verification flash "$t" "$selected_img"
        else
            animate "Flashing $t" fastboot flash "$t" "$selected_img"
        fi
        rc=$?
        if [ "$rc" -eq 0 ]; then
            ok "$t flashed successfully!"
        else
            bad "Flashing $t failed! Last output:"
            tail -n 5 "$LAST_OUT"
            failed=1
            break
        fi
    done
    [ "$failed" -eq 0 ] && ok "All done."
    pause
}

# ---------------------------- Sideload ---------------------------------------
flash_sideload_screen() {
    header "ADB Sideload Custom ROM"
    wait_for_device sideload || return 0
    echo ""

    pick_file "Select zip number" 3 "*.zip" || { say "Cancelled."; pause; return 0; }
    local selected_zip="$PICKED"
    say "Sideloading $(shorten "$(basename "$selected_zip")" $((COLS - 16)))..."

    adb sideload "$selected_zip" 2>&1 | tee "$LAST_OUT"
    local rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ]; then
        ok "ADB sideload completed successfully!"
    else
        warn "Exit code $rc. Check recovery screen; it may still have succeeded."
    fi
    pause
}

# ---------------------------- Fastboot ROM -----------------------------------
ROM_DIR=""
PLAN=()
PLAN_ERR=""

extract_archive() {
    local arc="$1" base out existing
    base="$(basename "$arc")"
    base="${base%.tar.gz}"
    base="${base%.tgz}"
    out="$DL_DIR/${base}_extracted"

    existing=$(find -L "$out" -maxdepth 6 -iname 'flash_all*.sh' 2>/dev/null | head -n1)
    if [ -n "$existing" ]; then
        ROM_DIR="$(dirname "$existing")"
        ok "Already extracted. Using existing folder."
        return 0
    fi

    local need_kb free_kb
    need_kb=$(( $(stat -c %s "$arc" 2>/dev/null || echo 0) * 3 / 1024 ))
    free_kb=$(df -kP "$DL_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [[ "${free_kb:-}" =~ ^[0-9]+$ ]] && [ "$free_kb" -lt "$need_kb" ]; then
        bad "Not enough free storage to extract (need about $((need_kb / 1024)) MB)."
        return 1
    fi

    mkdir -p "$out"
    if animate "Extracting $(basename "$arc")" tar -xzf "$arc" -C "$out" --no-same-owner --no-same-permissions; then
        ok "Extraction complete."
    else
        bad "Extraction failed:"
        tail -n 4 "$LAST_OUT"
        return 1
    fi

    existing=$(find -L "$out" -maxdepth 6 -iname 'flash_all*.sh' 2>/dev/null | head -n1)
    if [ -z "$existing" ]; then
        bad "No flash_all script found inside the archive."
        return 1
    fi
    ROM_DIR="$(dirname "$existing")"
    return 0
}

# Parse a Xiaomi-style flash_all*.sh into PLAN (no eval, args split by $US)
build_plan() {
    local script="$1" imgdir="$2" line args tok joined
    local -a toks=() out=()
    PLAN=()
    PLAN_ERR=""
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        args=$(printf '%s\n' "$line" | sed -nE \
            's/^[[:space:]]*("?\$\{?[A-Za-z_]*\}?"?|[^[:space:]#]*fastboot[^[:space:]]*)[[:space:]]+((flash|erase|set_active|reboot|flashing|oem|-w|--set-active|--disable-verity|--disable-verification)([[:space:]].*)?)$/\2/p')
        [ -z "$args" ] && continue
        args=$(printf '%s\n' "$args" | sed -E 's#\$\(dirname[^)]*\)/?##g; s/[[:space:]]*(\|\||&&|;|[0-9]?>).*$//')
        [ -z "$args" ] && continue
        read -ra toks <<< "$args"
        out=()
        for tok in "${toks[@]}"; do
            tok="${tok//\"/}"
            tok="${tok//\'/}"
            case "$tok" in
                *.img|*.bin|*.mbn|*.elf|*.hex|*.mdt|*.pro|*.lz4|*.ubi|*.zip|*.txt|*.xml)
                    tok="$imgdir/$(basename "${tok//\\//}")" ;;
            esac
            if [[ "$tok" == *'$'* ]]; then
                PLAN_ERR="Unsupported script line: $line"
                return 1
            fi
            out+=("$tok")
        done
        joined=""
        for tok in "${out[@]}"; do joined+="${tok}${US}"; done
        PLAN+=("${joined%"$US"}")
    done < "$script"
    [ "${#PLAN[@]}" -gt 0 ] || { PLAN_ERR="No flash commands found in script."; return 1; }
    return 0
}

label_for_script() {
    local n="${1,,}"
    case "$n" in
        *lock*)                       echo "Flash + re-LOCK bootloader (risky)" ;;
        *except_storage*|*except_data*|*save*) echo "Flash, KEEP user data" ;;
        flash_all.sh)                 echo "Clean flash (erases ALL data)" ;;
        *)                            echo "Custom script" ;;
    esac
}

flash_fastboot_screen() {
    header "Fastboot ROM Flash"
    wait_for_device fastboot || return 0
    echo ""

    local -a dirs=() arcs=() kind=() path=()
    local x
    mapfile -t dirs < <(find_rom_dirs)
    mapfile -t arcs < <(find_rom_archives)
    for x in "${dirs[@]}"; do [ -n "$x" ] && { kind+=("dir"); path+=("$x"); }; done
    for x in "${arcs[@]}"; do [ -n "$x" ] && { kind+=("arc"); path+=("$x"); }; done

    if [ "${#path[@]}" -eq 0 ]; then
        warn "No extracted ROM folder or .tgz found in Downloads."
        echo -e " ${GRAY}Put your fastboot ROM (.tgz or extracted folder) in:${RESET}"
        echo -e " ${GRAY}$DL_DIR${RESET}"
        pause
        return 0
    fi

    echo -e " ${CYAN}Detected ROM packages:${RESET}"
    local i
    for ((i = 0; i < ${#path[@]}; i++)); do
        if [ "${kind[$i]}" = "dir" ]; then
            echo -e " ${GREEN}[$((i + 1))]${RESET} ${GREEN}FOLDER${RESET}  $(shorten "${path[$i]#"$DL_DIR"/}" $((COLS - 16)))"
        else
            echo -e " ${GREEN}[$((i + 1))]${RESET} ${YELLOW}ARCHIVE${RESET} $(shorten "$(basename "${path[$i]}")" $((COLS - 24))) ${GRAY}$(human_size "${path[$i]}")${RESET}"
        fi
    done
    echo ""
    local choice
    printf " Select ROM (0 = back): "
    read -r choice || choice=0
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -le 0 ] || [ "$choice" -gt "${#path[@]}" ]; then
        say "Cancelled."
        pause
        return 0
    fi
    local sel_kind="${kind[$((choice - 1))]}" sel_path="${path[$((choice - 1))]}"

    echo ""
    if [ "$sel_kind" = "arc" ]; then
        extract_archive "$sel_path" || { pause; return 1; }
    else
        ROM_DIR="$sel_path"
    fi

    # --- choose flash script ---
    local -a scripts=()
    mapfile -t scripts < <(find "$ROM_DIR" -maxdepth 1 -type f -iname 'flash_all*.sh' 2>/dev/null | sort)
    if [ "${#scripts[@]}" -eq 0 ]; then
        bad "No flash_all*.sh found in ROM folder."
        pause
        return 1
    fi

    local script
    if [ "${#scripts[@]}" -eq 1 ]; then
        script="${scripts[0]}"
    else
        echo ""
        echo -e " ${CYAN}Flash mode:${RESET}"
        for ((i = 0; i < ${#scripts[@]}; i++)); do
            echo -e " ${GREEN}[$((i + 1))]${RESET} $(label_for_script "$(basename "${scripts[$i]}")")"
        done
        printf " Select mode (0 = back): "
        local sc
        read -r sc || sc=0
        if [[ ! "$sc" =~ ^[0-9]+$ ]] || [ "$sc" -le 0 ] || [ "$sc" -gt "${#scripts[@]}" ]; then
            say "Cancelled."
            pause
            return 0
        fi
        script="${scripts[$((sc - 1))]}"
    fi

    local imgdir="$ROM_DIR"
    [ -d "$ROM_DIR/images" ] && imgdir="$ROM_DIR/images"

    if ! build_plan "$script" "$imgdir"; then
        bad "$PLAN_ERR"
        pause
        return 1
    fi

    # --- validate files ---
    local step missing=0 t erases=0 has_lock=0 joined n_flash=0
    local -a toks=()
    for step in "${PLAN[@]}"; do
        IFS="$US" read -ra toks <<< "$step"
        for t in "${toks[@]}"; do
            if [[ "$t" == "$imgdir"/* ]] && [ ! -f "$t" ]; then
                [ "$missing" -lt 5 ] && bad "Missing file: $(basename "$t")"
                missing=$((missing + 1))
            fi
        done
        joined=" ${toks[*]} "
        [[ "$joined" == *" flash "* || "$joined" == *" flash" ]] && n_flash=$((n_flash + 1))
        [[ "$joined" == *" -w "* || "$joined" == *" erase userdata "* ]] && erases=1
        [[ "$joined" == *" lock "* ]] && has_lock=1
    done
    if [ "$missing" -gt 0 ]; then
        bad "$missing file(s) missing. ROM package is incomplete."
        pause
        return 1
    fi

    # --- product check ---
    local rom_product dev_product
    rom_product=$(grep -m1 -E 'product: ?\*?[A-Za-z0-9_]+' "$script" 2>/dev/null \
        | sed -nE 's/.*product: ?\*?([A-Za-z0-9_]+).*/\1/p')
    dev_product=$(fb_var product)
    echo ""
    echo -e " ${CYAN}--- ROM Summary ---${RESET}"
    echo -e " ROM device : ${BOLD}${rom_product:-unknown}${RESET}"
    echo -e " Your phone : ${BOLD}${dev_product}${RESET}"
    echo -e " Steps      : ${BOLD}${#PLAN[@]}${RESET} (${n_flash} flash)"
    if [ "$erases" -eq 1 ]; then
        echo -e " User data  : ${RED}WILL BE ERASED${RESET}"
    else
        echo -e " User data  : ${GREEN}kept${RESET}"
    fi

    if [ -n "$rom_product" ] && [ "$dev_product" != "UNKNOWN" ] && [ "${rom_product,,}" != "${dev_product,,}" ]; then
        echo ""
        bad "DEVICE MISMATCH! This ROM is for '$rom_product', your phone is '$dev_product'."
        local force
        printf " Type FORCE to flash anyway (anything else cancels): "
        read -r force || force=""
        if [ "$force" != "FORCE" ]; then
            say "Cancelled."
            pause
            return 0
        fi
    fi

    if [ "$has_lock" -eq 1 ]; then
        echo ""
        warn "This script RE-LOCKS the bootloader. Only do this on a full official ROM!"
        local lk
        printf " Type LOCK to continue: "
        read -r lk || lk=""
        [ "$lk" = "LOCK" ] || { say "Cancelled."; pause; return 0; }
    fi

    echo ""
    ask_yn "Start flashing now?" n || { say "Flashing cancelled."; pause; return 0; }

    # --- run ---
    local total=${#PLAN[@]} n=0 rc short abort=0
    echo ""
    for step in "${PLAN[@]}"; do
        n=$((n + 1))
        IFS="$US" read -ra toks <<< "$step"
        short="${toks[*]:0:2}"
        short="${short//$imgdir\//}"
        animate "[$n/$total] $short" fastboot "${toks[@]}"
        rc=$?
        if [ "$rc" -eq 0 ]; then
            echo -e " ${GREEN}✔${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14)))"
        else
            joined=" ${toks[*]} "
            if [[ "$joined" == *" flash "* || "$joined" == *" set_active "* ]]; then
                echo -e " ${RED}✘${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14)))"
                bad "Step failed. Last output:"
                tail -n 5 "$LAST_OUT"
                abort=1
                break
            else
                echo -e " ${YELLOW}!${RESET} ${GRAY}[$n/$total]${RESET} $(shorten "$short" $((COLS - 14))) (skipped)"
            fi
        fi
    done

    echo ""
    if [ "$abort" -eq 0 ]; then
        ok "ROM flashed successfully!"
    else
        bad "Flashing stopped. Do NOT reboot until you fix the error."
    fi
    pause
}

# ---------------------------- GSI --------------------------------------------
wait_userspace() {
    local i
    for i in $(seq 1 60); do
        sleep 1
        if fb_present && [ "$(fb_var is-userspace)" = "yes" ]; then
            return 0
        fi
    done
    return 1
}

flash_gsi_screen() {
    header "Flash GSI System Image"
    wait_for_device fastboot || return 0
    echo ""

    pick_file "Select GSI image" 3 "*.img.xz" "*.img.gz" "system*.img" "*gsi*.img" \
        || { say "Cancelled."; pause; return 0; }
    local gsi="$PICKED" bn
    bn="$(basename "$gsi")"
    local lbn="${bn,,}"

    local slot has_ab=0 name_ab=0
    slot=$(fb_var current-slot)
    [ "$slot" != "UNKNOWN" ] && has_ab=1
    [[ "$lbn" == *-ab* || "$lbn" == *_ab* ]] && name_ab=1
    echo ""
    if [ "$has_ab" -eq 1 ] && [ "$name_ab" -eq 0 ]; then
        warn "Phone is A/B but this image name has no 'ab' (looks A-only)."
    elif [ "$has_ab" -eq 0 ] && [ "$name_ab" -eq 1 ]; then
        warn "Phone looks A-only but this image is an 'ab' build."
    fi

    # --- decompress if needed ---
    local sysimg="$gsi"
    case "$lbn" in
        *.img.xz|*.img.gz)
            local dec="xz" pk="xz-utils"
            [[ "$lbn" == *.gz ]] && { dec="gzip"; pk="gzip"; }
            need_pkg "$dec" "$pk" || { pause; return 1; }
            mkdir -p "$GSI_DIR"
            sysimg="$GSI_DIR/system.img"
            rm -f "$sysimg"
            if [ "$dec" = "xz" ]; then
                local unc free_kb
                unc=$(xz --robot -l "$gsi" 2>/dev/null | awk '/^totals/{print $5}')
                free_kb=$(df -kP "$BASE_DIR" 2>/dev/null | awk 'NR==2{print $4}')
                if [[ "${unc:-}" =~ ^[0-9]+$ ]] && [[ "${free_kb:-}" =~ ^[0-9]+$ ]] \
                    && [ $((free_kb * 1024)) -lt $((unc + 300000000)) ]; then
                    bad "Not enough free space. Need about $((unc / 1048576 + 300)) MB."
                    pause
                    return 1
                fi
            fi
            if animate "Decompressing $bn" bash -c "$dec -dc \"\$1\" > \"\$2\"" _ "$gsi" "$sysimg"; then
                ok "Decompressed ($(human_size "$sysimg"))."
            else
                bad "Decompression failed."
                tail -n 3 "$LAST_OUT"
                rm -f "$sysimg"
                pause
                return 1
            fi
            ;;
    esac

    local vbm
    vbm=$(find_files 3 "vbmeta.img" | head -n1)

    local wipe=0
    ask_yn "Wipe user data (recommended for GSI)?" y && wipe=1

    echo ""
    echo -e " ${CYAN}--- GSI Summary ---${RESET}"
    echo -e " Image  : ${BOLD}$(shorten "$bn" $((COLS - 14)))${RESET}"
    echo -e " Slot   : ${BOLD}$([ "$has_ab" -eq 1 ] && echo "A/B (active $slot)" || echo "A-only")${RESET}"
    echo -e " vbmeta : ${BOLD}$([ -n "$vbm" ] && echo "$(basename "$vbm") (verity off)" || echo "not found - skipped")${RESET}"
    if [ "$wipe" -eq 1 ]; then
        echo -e " Data   : ${RED}WILL BE ERASED${RESET}"
    else
        echo -e " Data   : ${GREEN}kept${RESET}"
    fi
    echo ""
    ask_yn "Start GSI flashing now?" n || { say "Cancelled."; pause; return 0; }
    echo ""

    # --- fastbootd for dynamic partitions ---
    if [ "$(fb_var is-userspace)" != "yes" ]; then
        if animate "Rebooting to fastbootd" fastboot reboot fastboot; then
            if animate "Waiting for fastbootd" wait_userspace; then
                ok "fastbootd ready."
            else
                warn "fastbootd not detected. Trying direct flash."
            fi
        else
            warn "No fastbootd support. Flashing directly."
        fi
    fi

    animate "Erasing system" fastboot erase system || warn "Erase system skipped."

    if animate "Flashing system image" fastboot flash system "$sysimg"; then
        ok "System image flashed."
    else
        bad "System flash failed:"
        tail -n 5 "$LAST_OUT"
        pause
        return 1
    fi

    if [ -n "$vbm" ]; then
        if animate "Flashing vbmeta (verity off)" fastboot --disable-verity --disable-verification flash vbmeta "$vbm"; then
            ok "vbmeta flashed."
        else
            warn "vbmeta flash failed (some devices do not need it)."
        fi
    else
        warn "No vbmeta.img in Downloads. If phone does not boot, flash vbmeta via menu 1."
    fi

    if [ "$wipe" -eq 1 ]; then
        animate "Wiping user data" fastboot -w && ok "Data wiped." || warn "Wipe failed; do a factory reset from recovery."
    fi

    rm -f "$GSI_DIR/system.img"
    echo ""
    ok "GSI flashing finished!"
    if ask_yn "Reboot to system now?" y; then
        countdown 3 "Rebooting"
        fastboot reboot >/dev/null 2>&1 || adb reboot >/dev/null 2>&1
        ok "Reboot command sent."
    fi
    pause
}

# ---------------------------- Device screens ---------------------------------
device_info_screen() {
    header "Device Information"
    wait_for_device fastboot || return 0
    echo ""
    progress_bar "Reading device info" 16
    local product slot unlocked serial
    product=$(fb_var product)
    slot=$(fb_var current-slot)
    unlocked=$(fb_var unlocked)
    serial=$(fb_var serialno)
    echo ""
    echo -e " ${CYAN}$(hline $((COLS - 2)) "─")${RESET}"
    echo -e "  Product  : ${BOLD}$product${RESET}"
    echo -e "  Serial   : ${BOLD}$serial${RESET}"
    echo -e "  Slot     : ${BOLD}$slot${RESET}"
    echo -e "  Unlocked : ${BOLD}$unlocked${RESET}"
    echo -e " ${CYAN}$(hline $((COLS - 2)) "─")${RESET}"
    pause
}

switch_slot_screen() {
    header "Switch A/B Slot"
    wait_for_device fastboot || return 0
    echo ""
    echo -e " Current slot: ${BOLD}$(fb_var current-slot)${RESET}"
    local slot
    printf " Enter target slot (a / b, 0 = back): "
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
    local mode="$1" label="$2" rc
    wait_for_device any || return 1
    if fb_present; then
        if [ "$mode" = "system" ]; then
            animate "Rebooting to $label" fastboot reboot
        else
            animate "Rebooting to $label" fastboot reboot "$mode"
        fi
    else
        if [ "$mode" = "system" ]; then
            animate "Rebooting to $label" adb reboot
        else
            animate "Rebooting to $label" adb reboot "$mode"
        fi
    fi
    rc=$?
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
    echo -e " ${GREEN}1${RESET}) Reboot to System"
    echo -e " ${GREEN}2${RESET}) Reboot to Recovery"
    echo -e " ${GREEN}3${RESET}) Reboot to Bootloader"
    echo -e " ${GREEN}4${RESET}) Reboot to Fastbootd"
    echo -e " ${GREEN}0${RESET}) Back"
    echo ""
    printf " Select mode: "
    local r_opt
    read -r r_opt || r_opt=0
    case "${r_opt:-}" in
        1) reboot_to system "System" ;;
        2) reboot_to recovery "Recovery" ;;
        3) reboot_to bootloader "Bootloader" ;;
        4) reboot_to fastboot "Fastbootd" ;;
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
    printf " Type 'WIPE' to confirm (anything else cancels): "
    read -r confirm || confirm=""
    if [ "$confirm" = "WIPE" ]; then
        if animate "Wiping user data" fastboot -w; then
            ok "Data wiped successfully."
        else
            warn "Standard wipe failed, trying manual erase..."
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
    calc_layout
    echo ""
    echo -n "$M"
    typewriter " ANDROID ULTIMATE FLASHER  v${VERSION}"
    echo ""
    progress_bar "Initializing" 24
    check_tools
    setup_storage
    progress_bar "Scanning files" 12
}

MENU_ANIM=1
mline() { # num color name desc
    echo -e "${M}$1 $2●${RESET} $(printf '%-18s' "$3") ${GRAY}$4${RESET}"
    [ "$MENU_ANIM" -eq 1 ] && sleep 0.025
}
msec() {
    echo -e "${M}${CYAN}── $1 ──${RESET}"
    [ "$MENU_ANIM" -eq 1 ] && sleep 0.025
}

main_menu() {
    splash
    while true; do
        clear
        calc_layout

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

        local img_count zip_count rom_count
        img_count=$(find_files 5 "*.img" | grep -c . || true)
        zip_count=$(find_files 3 "*.zip" | grep -c . || true)
        rom_count=$( { find_rom_dirs; find_rom_archives; } | grep -c . || true)

        draw_box "ANDROID ULTIMATE FLASHER" "Version ${VERSION} - Created by Rudra"
        echo ""
        echo -e "${M}Tools    $fb_dot fastboot  $adb_dot adb  $py_dot python"
        echo -e "${M}Device   $dev_text"
        echo -e "${M}Files    ${img_count} img • ${zip_count} zip • ${rom_count} rom"
        echo ""
        msec "FLASH"
        mline 1 "${GREEN}" "Flash Image"      "boot / recovery .img"
        mline 2 "${GREEN}" "Custom ROM (ADB)" "install .zip package"
        mline 3 "${YELLOW}" "Fastboot ROM"    "auto extract & flash"
        mline 4 "${YELLOW}" "Flash GSI"       "generic system image"
        msec "DEVICE"
        mline 5 "${GREEN}" "Device Info"      "model, slot, lock"
        mline 6 "${GREEN}" "Switch Slot"      "active A/B slot"
        mline 7 "${GREEN}" "Reboot"           "restart to a mode"
        mline 8 "${RED}" "Erase Data"         "factory reset"
        msec "EXIT"
        mline 0 "${GREEN}" "Exit"             "quit application"
        echo ""
        echo -e "${M}${GREEN}●${RESET} Safe  ${YELLOW}●${RESET} Careful  ${RED}●${RESET} Erases data"
        echo -e "${M}${GRAY}r = rescan storage${RESET}"
        echo ""
        MENU_ANIM=0
        printf "%s Select: " "$M"
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
                echo ""
                typewriter " Exiting tool safely. Goodbye!"
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
