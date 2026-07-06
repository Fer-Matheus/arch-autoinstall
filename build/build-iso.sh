#!/bin/bash
# build-iso.sh — Builds a custom Arch Linux ISO with automated installation
#
# Requirements:
#   - Docker Desktop running (Windows with WSL 2 backend, or native Linux)
#   - Run this script from WSL or a Linux terminal
#
# Usage:
#   chmod +x build/build-iso.sh
#   bash build/build-iso.sh

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$SCRIPT_DIR/output"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║   Arch Linux Unattended ISO Builder          ║${NC}"
echo -e "${BOLD}${BLUE}║   Target: Jarvis (GNOME, NVMe, UEFI)         ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
echo -e "${CYAN}[check]${NC} Verifying requirements..."

if ! command -v docker &>/dev/null; then
    echo -e "${RED}[FAIL ]${NC} Docker not found."
    echo "        Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}[FAIL ]${NC} Docker daemon is not running."
    echo "        Start Docker Desktop and wait for it to be ready."
    exit 1
fi

if [[ ! -f "$PROJECT_DIR/config.json" ]]; then
    echo -e "${RED}[FAIL ]${NC} config.json not found at: $PROJECT_DIR/config.json"
    exit 1
fi

if [[ ! -f "$PROJECT_DIR/creds.json" ]]; then
    echo -e "${RED}[FAIL ]${NC} creds.json not found at: $PROJECT_DIR/creds.json"
    exit 1
fi

echo -e "${GREEN}[  ok ]${NC} Docker is running."
echo -e "${GREEN}[  ok ]${NC} config.json found."
echo -e "${GREEN}[  ok ]${NC} creds.json found."
echo ""

# ── Credential prompts ────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}Step 1 — WiFi Credentials${NC}"
echo -e "  These will be embedded in the ISO so the target machine"
echo -e "  can connect to the internet automatically on boot."
echo ""

read -r -p "  WiFi SSID (network name): " WIFI_SSID
if [[ -z "$WIFI_SSID" ]]; then
    echo -e "${RED}[FAIL ]${NC} SSID cannot be empty."
    exit 1
fi

read -r -s -p "  WiFi Password            : " WIFI_PASSWORD
echo ""
if [[ -z "$WIFI_PASSWORD" ]]; then
    echo -e "${RED}[FAIL ]${NC} WiFi password cannot be empty."
    exit 1
fi
echo ""

echo -e "${BOLD}${YELLOW}Step 2 — User Password${NC}"
echo -e "  Password for the '${CYAN}matheus${NC}' user (sudo enabled)."
echo -e "  This will be hashed with SHA-512 inside Docker — never stored in plaintext."
echo ""

while true; do
    read -r -s -p "  Password for 'matheus': " USER_PASSWORD
    echo ""
    read -r -s -p "  Confirm password       : " USER_PASSWORD_CONFIRM
    echo ""
    if [[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]]; then
        break
    fi
    echo -e "${RED}  Passwords do not match. Try again.${NC}"
    echo ""
done

if [[ -z "$USER_PASSWORD" ]]; then
    echo -e "${RED}[FAIL ]${NC} User password cannot be empty."
    exit 1
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}${YELLOW}Step 3 — Review Configuration${NC}"
echo ""
echo -e "  archinstall config : ${CYAN}config.json${NC}"
echo -e "  WiFi SSID          : ${CYAN}${WIFI_SSID}${NC}"
echo -e "  WiFi password      : ${CYAN}[hidden]${NC}"
echo -e "  User               : ${CYAN}matheus${NC} (sudo)"
echo -e "  User password      : ${CYAN}[hidden]${NC}"
echo -e "  Output ISO         : ${CYAN}${OUTPUT_DIR}/archlinux-jarvis-$(date +%Y%m%d).iso${NC}"
echo ""
echo -e "  ${YELLOW}IMPORTANT: This will WIPE /dev/nvme0n1 on the target machine!${NC}"
echo ""

read -r -p "  Proceed with build? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "  Build cancelled."
    exit 0
fi
echo ""

# ── Create output directory ───────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── Pull latest Arch Linux image ──────────────────────────────────────────────
echo -e "${BLUE}[build]${NC} Pulling archlinux:latest Docker image..."
docker pull archlinux:latest
echo ""

# ── Run the build inside Docker ───────────────────────────────────────────────
echo -e "${BLUE}[build]${NC} Starting ISO build in Docker container..."
echo -e "        This typically takes ${BOLD}15–30 minutes${NC} depending on internet speed."
echo -e "        Pulling packages for the full Arch Linux live environment..."
echo ""

docker run --rm --privileged \
    --name archiso-builder \
    -v "$PROJECT_DIR/config.json:/build/config.json:ro" \
    -v "$PROJECT_DIR/creds.json:/build/creds.json:ro" \
    -v "$SCRIPT_DIR/overlay:/build/overlay:ro" \
    -v "$SCRIPT_DIR/docker-entrypoint.sh:/docker-entrypoint.sh:ro" \
    -v "$OUTPUT_DIR:/output" \
    -e WIFI_SSID="$WIFI_SSID" \
    -e WIFI_PASSWORD="$WIFI_PASSWORD" \
    -e USER_PASSWORD="$USER_PASSWORD" \
    archlinux:latest \
    bash /docker-entrypoint.sh

# ── Final instructions ────────────────────────────────────────────────────────
ISO_FILE=$(ls "$OUTPUT_DIR"/archlinux-jarvis-*.iso 2>/dev/null | head -1 || true)

if [[ -n "$ISO_FILE" ]]; then
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   Build Successful!                          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ISO: ${CYAN}${ISO_FILE}${NC}"
    echo -e "  Size: $(du -sh "$ISO_FILE" | cut -f1)"
    echo ""
    echo -e "${BOLD}${YELLOW}Next steps:${NC}"
    echo ""
    echo -e "  1. Flash the ISO to a USB drive (8 GB+):"
    echo -e "     ${CYAN}Windows${NC}: Use Rufus — select GPT + UEFI, write in DD mode"
    echo -e "     ${CYAN}Linux  ${NC}: sudo dd if=\"$ISO_FILE\" of=/dev/sdX bs=4M status=progress"
    echo ""
    echo -e "  2. Boot the target machine from the USB drive."
    echo -e "     • Select the USB in UEFI boot menu (usually F2/F12/Del on startup)"
    echo -e "     • The installation starts AUTOMATICALLY — no keyboard needed"
    echo ""
    echo -e "  3. Wait for the installation to complete (~30 min for GNOME)."
    echo -e "     The machine will reboot into the new Arch Linux system."
    echo ""
    echo -e "  Login: ${CYAN}matheus${NC} / [password you set in Step 2 above]"
    echo ""
else
    echo -e "${RED}[FAIL ]${NC} No ISO found in $OUTPUT_DIR — check Docker output above."
    exit 1
fi
