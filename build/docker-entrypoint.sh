#!/bin/bash
# docker-entrypoint.sh — Runs INSIDE the Arch Linux Docker container
# Called by build-iso.sh to build the custom ISO with archiso.
#
# Required environment variables (injected by build-iso.sh):
#   WIFI_SSID       — name of the WiFi network
#   WIFI_PASSWORD   — WiFi pre-shared key
#   USER_PASSWORD   — plaintext password for user "matheus" (hashed here, never stored)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[build]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn]${NC} $*"; }
die()  { echo -e "${RED}[FAIL ]${NC} $*" >&2; exit 1; }

PROFILE_DIR="/build/archprofile"
OUTPUT_DIR="/output"

# ── 1. Bootstrap pacman keyring ───────────────────────────────────────────────
log "Initializing pacman keyring..."
pacman-key --init
pacman-key --populate archlinux

# ── 2. Install archiso and dependencies ──────────────────────────────────────
log "Installing archiso..."
pacman -Syu --noconfirm --needed archiso squashfs-tools libisoburn
ok "archiso installed."

# ── 3. Copy the releng base profile ──────────────────────────────────────────
log "Setting up archiso profile from releng..."
cp -r /usr/share/archiso/configs/releng "$PROFILE_DIR"

# ── 4. Create overlay directory structure ────────────────────────────────────
log "Creating overlay directories..."
mkdir -p "$PROFILE_DIR/airootfs/root"
mkdir -p "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants"
mkdir -p "$PROFILE_DIR/airootfs/etc/NetworkManager/system-connections"

# ── 5. Copy archinstall config ────────────────────────────────────────────────
log "Copying archinstall config.json..."
cp /build/config.json "$PROFILE_DIR/airootfs/root/config.json"

# ── 6. Generate creds.json with hashed password ──────────────────────────────
log "Generating creds.json with hashed password..."

# Hash the password using SHA-512 crypt (same format as /etc/shadow).
# The resulting hash looks like $6$salt$hash — bash heredoc inserts it literally.
HASHED_PASS=$(openssl passwd -6 "${USER_PASSWORD}")

cat > "$PROFILE_DIR/airootfs/root/creds.json" << CREDSEOF
{
    "users": [
        {
            "sudo": true,
            "username": "matheus",
            "enc_password": "${HASHED_PASS}"
        }
    ]
}
CREDSEOF

ok "creds.json generated (password hashed with SHA-512)."

# ── 7. Copy overlay files (install.sh + systemd service) ─────────────────────
log "Copying overlay files..."
cp -r /build/overlay/. "$PROFILE_DIR/airootfs/"
chmod +x "$PROFILE_DIR/airootfs/root/install.sh"

# ── 8. Generate WiFi NetworkManager connection profile ───────────────────────
log "Generating WiFi connection profile (SSID: ${WIFI_SSID})..."

WIFI_CONN_FILE="$PROFILE_DIR/airootfs/etc/NetworkManager/system-connections/wifi-auto.nmconnection"

# Bash heredoc expands ${WIFI_SSID} and ${WIFI_PASSWORD} literally into the file.
# Special characters in the values (e.g. $, \) are safe: bash does not
# recursively expand the results of variable substitution.
cat > "${WIFI_CONN_FILE}" << NMEOF
[connection]
id=wifi-auto
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
NMEOF
chmod 600 "${WIFI_CONN_FILE}"

ok "WiFi profile written with permissions 600."

# ── 9. Enable the auto-install systemd service ───────────────────────────────
log "Enabling archinstall-auto.service..."
ln -sf \
    /etc/systemd/system/archinstall-auto.service \
    "$PROFILE_DIR/airootfs/etc/systemd/system/multi-user.target.wants/archinstall-auto.service"
ok "Service enabled."

# ── 10. Ensure archinstall package is in the live ISO packages list ───────────
log "Checking packages list..."
PACKAGES_FILE="$PROFILE_DIR/packages.x86_64"
if ! grep -qx "archinstall" "$PACKAGES_FILE"; then
    echo "archinstall" >> "$PACKAGES_FILE"
    warn "Added 'archinstall' to packages.x86_64 (was missing)."
else
    ok "'archinstall' already in packages list."
fi

# ── 11. Build the ISO ─────────────────────────────────────────────────────────
log "Starting mkarchiso build — this takes 15–30 min..."
echo ""
mkdir -p /tmp/archiso-work
mkarchiso -v -w /tmp/archiso-work -o "$OUTPUT_DIR" "$PROFILE_DIR"

# ── 12. Rename the output ISO ─────────────────────────────────────────────────
ISO_FILE=$(ls "$OUTPUT_DIR"/archlinux-*.iso 2>/dev/null | head -1 || true)
if [[ -n "$ISO_FILE" ]]; then
    DATESTAMP=$(date +%Y%m%d)
    FINAL_NAME="$OUTPUT_DIR/archlinux-jarvis-${DATESTAMP}.iso"
    mv "$ISO_FILE" "$FINAL_NAME"
    echo ""
    ok "============================================"
    ok "ISO ready: $FINAL_NAME"
    ok "Size     : $(du -sh "$FINAL_NAME" | cut -f1)"
    ok "============================================"
else
    die "No ISO file found in $OUTPUT_DIR after build."
fi
