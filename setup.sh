python - <<'PY'
from pathlib import Path
import re
import sys

p = Path.home() / ".android-ultimate-flashing-tool" / "setup.sh"

if not p.is_file():
    print("ERROR: Installed setup.sh was not found.")
    print("Open the folder where your current setup.sh is saved.")
    sys.exit(1)

s = p.read_text()
original = s

# Cache ROM discovery so the main menu does not repeatedly inspect archives.
if "ROM_CACHE_VALID=0" not in s:
    marker = "ROM_TREES=()"
    if marker not in s:
        print("ERROR: Expected ROM_TREES section was not found; no changes made.")
        sys.exit(1)
    s = s.replace(marker, marker + "\nROM_CACHE_VALID=0", 1)

old = '''refresh_rom_trees() {
    collect_roms
    ROM_TREES=("$ROMS_DIR")
    local i
    for ((i = 0; i < ${#ROM_PATH[@]}; i++)); do
        [ "${ROM_KIND[$i]}" = arc ] || ROM_TREES+=("${ROM_PATH[$i]}")
    done
}'''

new = '''refresh_rom_trees() {
    # Before the first scan, only the private ROM folder is known.
    if [ "$SCAN_DONE" -ne 1 ]; then
        ROM_TREES=("$ROMS_DIR")
        return 0
    fi

    # Reuse the result instead of re-inspecting ROM archives on every menu redraw.
    [ "$ROM_CACHE_VALID" -eq 1 ] && return 0

    collect_roms
    ROM_TREES=("$ROMS_DIR")
    local i
    for ((i = 0; i < ${#ROM_PATH[@]}; i++)); do
        [ "${ROM_KIND[$i]}" = arc ] || ROM_TREES+=("${ROM_PATH[$i]}")
    done
    ROM_CACHE_VALID=1
}'''

if old not in s:
    print("ERROR: ROM refresh function did not match; no changes made.")
    sys.exit(1)

s = s.replace(old, new, 1)

# Invalidate the cache after a fresh scan.
old_scan = '''    SCAN_DONE=1
    ok "Found $(grep -c . "$SCAN_FILE" 2>/dev/null || echo 0) flashable file(s)."'''

new_scan = '''    SCAN_DONE=1
    ROM_CACHE_VALID=0
    ok "Found $(grep -c . "$SCAN_FILE" 2>/dev/null || echo 0) flashable file(s)."'''

if old_scan not in s:
    print("ERROR: Scan completion section did not match; no changes made.")
    sys.exit(1)

s = s.replace(old_scan, new_scan, 1)

old_refresh = '''    SCAN_DONE=1
    refresh_rom_trees
}'''

new_refresh = '''    SCAN_DONE=1
    ROM_CACHE_VALID=0
    refresh_rom_trees
}'''

if old_refresh not in s:
    print("ERROR: Refresh scan section did not match; no changes made.")
    sys.exit(1)

s = s.replace(old_refresh, new_refresh, 1)

# Do not overwrite the script unless the edited Bash syntax is valid.
backup = p.with_suffix(".sh.backup")
backup.write_text(original)

import subprocess
check = subprocess.run(["bash", "-n"], input=s, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if check.returncode:
    print("ERROR: Bash syntax check failed; original file was preserved.")
    print(check.stderr)
    sys.exit(1)

p.write_text(s)
print("Updated setup.sh successfully.")
print("Backup:", backup)
print("Bash syntax check: passed")
PY