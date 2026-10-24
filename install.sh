#!/usr/bin/env bash
# ==============================================================================
# Installer Script for Android Ultimate Flasher (Crafted by Rudra)
# ==============================================================================

set -e

echo -e "\033[1;34m[*] Installing Android Ultimate Flasher...\033[0m"

# Target installation directory
INSTALL_DIR="$HOME/.android-ultimate-flashing-tool"
mkdir -p "$INSTALL_DIR"

# Download the main tool script from your GitHub repository
# (GitHub ইউজারনেম ও রিপো নাম তোমার নিজের মতো করে এখানে বসিয়ে দেবে)
TOOL_URL="https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/tool.sh"

echo -e "\033[1;34m[*] Downloading tool files from GitHub...\033[0m"
if command -v curl >/dev/null 2>&1; then
    curl -s -L "$TOOL_URL" -o "$INSTALL_DIR/tool.sh"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALL_DIR/tool.sh" "$TOOL_URL"
else
    echo -e "\033[1;31m[-] Error: Neither curl nor wget found. Please install curl first.\033[0m"
    exit 1
fi

# Set executable permission for the tool
chmod +x "$INSTALL_DIR/tool.sh"

# Setup global command shortcut ('rudra') in Termux
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
if [ -d "$PREFIX/bin" ]; then
    ln -sf "$INSTALL_DIR/tool.sh" "$PREFIX/bin/rudra"
    chmod +x "$PREFIX/bin/rudra"
    echo -e "\033[1;32m[+] Installation completed successfully!\033[0m"
    echo -e "\033[1;32m[+] You can now type 'rudra' anytime to launch your tool.\033[0m"
else
    echo -e "\033[1;31m[-] Error: Termux bin directory not found. Are you running this in Termux?\033[0m"
    exit 1
fi
