#!/bin/bash
# Cloud Linux GUI - uninstaller
#
# Removes services and program files. Configuration (VNC passwords) is kept
# unless --purge is given; apt packages are kept unless --remove-packages.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} ${1}"; }
warn() { echo -e "${YELLOW}[!]${NC} ${1}"; }
err()  { echo -e "${RED}[-]${NC} ${1}"; }
step() { echo -e "${BLUE}[*]${NC} ${1}"; }

PURGE=false
REMOVE_PACKAGES=false
VNC_PORT="${VNC_PORT:-5901}"

usage() {
    cat << 'USAGEEOF'
Cloud Linux GUI Uninstaller

Usage: sudo bash uninstall.sh [OPTIONS]

Options:
    --purge             Also remove configuration and secrets
                        (/root/.vnc, /opt/vnc_password.txt, /opt/tunnel_url.txt)
    --remove-packages   Also apt-purge the installed desktop/VNC packages and
                        remove the cloudflared binary
    --port N            VNC port used at install time if not the default 5901
                        (used to clean up the right X lock/socket)
    -h, --help          Show this help
USAGEEOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --purge)           PURGE=true; shift ;;
        --remove-packages) REMOVE_PACKAGES=true; shift ;;
        --port)            VNC_PORT="${2:-}"; shift 2 ;;
        -h|--help)         usage; exit 0 ;;
        *)                 err "Unknown option: $1"; echo ""; usage; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    err "Run as root: sudo bash uninstall.sh"
    exit 1
fi

if ! [[ "${VNC_PORT}" =~ ^[0-9]+$ ]]; then
    err "Invalid --port '${VNC_PORT}'"
    exit 1
fi
DISPLAY_NUM=$((VNC_PORT - 5900))

echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo -e "${GREEN}  Cloud Linux GUI Uninstaller${NC}"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""

APP_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="/opt/novnc"
PID_DIR="/tmp/cloud-gui-pids"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USE_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1 && \
   systemctl list-unit-files "cloud-gui-*" --no-legend 2>/dev/null | grep -q .; then
    USE_SYSTEMD=true
fi

# ── Step 1: Stop services ──
step "Stopping services..."
if [ "$USE_SYSTEMD" = true ]; then
    systemctl disable --now cloud-gui-tunnel.service \
                              cloud-gui-novnc.service \
                              cloud-gui-vnc.service \
                              cloud-gui-desktop.service \
                              cloud-gui-xvfb.service \
                              cloud-gui-password-api.service 2>/dev/null || true
    log "systemd units stopped and disabled"
elif [ -x "${APP_DIR}/stop.sh" ]; then
    bash "${APP_DIR}/stop.sh"
elif [ -f "${SCRIPT_DIR}/stop.sh" ]; then
    bash "${SCRIPT_DIR}/stop.sh"
else
    warn "stop.sh not found - attempting inline PID cleanup"
    if [ -d "$PID_DIR" ]; then
        for f in "$PID_DIR"/*; do
            [ -f "$f" ] || continue
            pid=$(cat "$f" 2>/dev/null)
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
            rm -f "$f"
        done
        rmdir "$PID_DIR" 2>/dev/null || true
    fi
fi

sleep 1

# ── Step 2: Remove systemd units ──
if [ "$USE_SYSTEMD" = true ]; then
    step "Removing systemd units..."
    rm -f /etc/systemd/system/cloud-gui-*.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    log "Units removed"
fi

# ── Step 3: Remove program files ──
step "Removing program files..."
rm -rf "${APP_DIR}" "${NOVNC_DIR}"
log "Removed ${APP_DIR} and ${NOVNC_DIR}"

# ── Step 4: Remove logs and runtime artifacts ──
step "Removing logs and runtime files..."
rm -f /tmp/xvfb.log /tmp/xfce.log /tmp/vnc.log /tmp/x11vnc.log \
      /tmp/novnc.log /tmp/novnc2.log /tmp/cloudflared.log \
      /tmp/password_server.log /tmp/vnc-wrapper.log /tmp/vnc_password_server.py 2>/dev/null
rm -rf "$PID_DIR" /tmp/runtime-root 2>/dev/null
rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null
log "Logs and runtime files removed"

# ── Step 5: Optional purge of config/secrets ──
if [ "$PURGE" = true ]; then
    step "Purging configuration (--purge)..."
    rm -rf /root/.vnc
    rm -f /opt/vnc_password.txt /opt/tunnel_url.txt
    log "VNC passwords and tunnel URL removed"
else
    echo ""
    warn "Kept configuration: /root/.vnc, /opt/vnc_password.txt, /opt/tunnel_url.txt"
    warn "Run with --purge to remove these too (contains your VNC password)"
fi

# ── Step 6: Optional package removal ──
if [ "$REMOVE_PACKAGES" = true ]; then
    step "Removing packages (--remove-packages)..."
    export DEBIAN_FRONTEND=noninteractive
    # Only desktop/VNC-specific packages - curl/git/wget etc. are left alone
    apt-get purge -y \
        xfce4 xfce4-terminal \
        mate-desktop-environment-core mate-terminal \
        dbus-x11 tigervnc-standalone-server tigervnc-common \
        x11vnc websockify xauth xfonts-base fonts-ubuntu > /dev/null 2>&1 || true
    apt-get autoremove -y > /dev/null 2>&1 || true
    rm -f /usr/local/bin/cloudflared
    log "Packages and cloudflared removed"
else
    echo ""
    warn "Kept apt packages and /usr/local/bin/cloudflared"
    warn "Run with --remove-packages to remove them too"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Cloud Linux GUI has been uninstalled${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
