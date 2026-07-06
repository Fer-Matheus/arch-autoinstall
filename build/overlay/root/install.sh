#!/bin/bash
# install.sh — Automated Arch Linux installer
# Runs automatically on boot via archinstall-auto.service

set -euo pipefail

LOG="/var/log/archinstall-auto.log"
exec > >(tee -a "$LOG") 2>&1

echo "============================================"
echo "  Arch Linux Automated Installation"
echo "  Host: Jarvis"
echo "  Started: $(date)"
echo "============================================"
echo ""

# ── 1. Wait for NetworkManager to connect to WiFi ────────────────────────────
echo "[*] Waiting for network connectivity..."

TIMEOUT=180
ELAPSED=0
while ! ping -c 1 -W 3 archlinux.org &>/dev/null 2>&1; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo ""
        echo "[!] ERROR: No network after ${TIMEOUT}s."
        echo "    Check that the WiFi credentials embedded in this ISO are correct."
        echo "    SSID and password are set during the ISO build step."
        echo ""
        echo "    NetworkManager status:"
        nmcli general status 2>/dev/null || true
        nmcli connection show 2>/dev/null || true
        exit 1
    fi
    printf "\r    Elapsed: %3ds — still waiting..." "$ELAPSED"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done
echo ""
echo "[+] Network is up!"
echo ""

# ── 2. Sync time ─────────────────────────────────────────────────────────────
echo "[*] Syncing time via NTP..."
timedatectl set-ntp true
sleep 2

# ── 3. Update archinstall to latest before installing ────────────────────────
echo "[*] Updating archinstall..."
pacman -Sy --noconfirm archinstall 2>&1 | tail -5

# ── 4. Run archinstall silently ───────────────────────────────────────────────
echo ""
echo "[*] Starting archinstall (silent mode)..."
echo "    Config : /root/config.json"
echo "    Creds  : /root/creds.json"
echo ""

archinstall \
    --config  /root/config.json \
    --creds   /root/creds.json  \
    --silent

# ── 5. Done — reboot into the new system ─────────────────────────────────────
echo ""
echo "[+] ============================================"
echo "[+]  Installation complete! Rebooting in 10s..."
echo "[+] ============================================"
sleep 10
systemctl reboot
