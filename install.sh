#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} ${1}"; }
warn() { echo -e "${YELLOW}[!]${NC} ${1}"; }
err()  { echo -e "${RED}[-]${NC} ${1}"; }
step() { echo -e "${BLUE}[*]${NC} ${1}"; }

# ── Defaults (overridable via CLI flags) ──
RESOLUTION="1366x768"
VNC_PORT=5901
START_TUNNEL=true
DESKTOP="xfce"
PASSWORD_ARG=""
FORCE_NEW_PASSWORD=false

usage() {
    cat << 'USAGEEOF'
Cloud Linux GUI Installer

Usage: sudo bash install.sh [OPTIONS]

Options:
    --resolution WxH     Desktop resolution (default: 1366x768)
    --port N             VNC port, 5901-5999 (default: 5901)
    --desktop NAME       Desktop environment: xfce | mate (default: xfce)
    --password PASS      Set a specific VNC password (only first 8 chars are
                         used - RFB protocol limit)
    --new-password       Force generating a new password even if one exists
                         from a previous install
    --no-tunnel          Skip the Cloudflare quick tunnel
    -h, --help           Show this help
USAGEEOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --resolution)    RESOLUTION="${2:-}"; shift 2 ;;
        --port)          VNC_PORT="${2:-}"; shift 2 ;;
        --desktop)       DESKTOP="${2:-}"; shift 2 ;;
        --password)      PASSWORD_ARG="${2:-}"; shift 2 ;;
        --new-password)  FORCE_NEW_PASSWORD=true; shift ;;
        --no-tunnel)     START_TUNNEL=false; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               err "Unknown option: $1"; echo ""; usage; exit 1 ;;
    esac
done

# Validate flags
if ! [[ "${RESOLUTION}" =~ ^[0-9]{2,5}x[0-9]{2,5}$ ]]; then
    err "Invalid --resolution '${RESOLUTION}' (expected WxH, e.g. 1366x768)"
    exit 1
fi
if ! [[ "${VNC_PORT}" =~ ^[0-9]+$ ]] || [ "${VNC_PORT}" -lt 5901 ] || [ "${VNC_PORT}" -gt 5999 ]; then
    err "Invalid --port '${VNC_PORT}' (must be 5901-5999)"
    exit 1
fi
DESKTOP=$(echo "${DESKTOP}" | tr '[:upper:]' '[:lower:]')
if [ "${DESKTOP}" != "xfce" ] && [ "${DESKTOP}" != "mate" ]; then
    err "Invalid --desktop '${DESKTOP}' (supported: xfce, mate)"
    exit 1
fi

DISPLAY_NUM=$((VNC_PORT - 5900))
DISPLAY=":${DISPLAY_NUM}"

case "${DESKTOP}" in
    xfce) DESKTOP_PKGS="xfce4 xfce4-terminal dbus-x11"; SESSION_CMD="startxfce4" ;;
    mate) DESKTOP_PKGS="mate-desktop-environment-core mate-terminal dbus-x11"; SESSION_CMD="mate-session" ;;
esac

echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo -e "${GREEN}  Cloud Linux GUI Installer${NC}"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    err "Run as root: sudo bash install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── PID tracking: only kill what we ourselves started ──
PID_DIR="/tmp/cloud-gui-pids"
mkdir -p "$PID_DIR"

save_pid() {
    echo "$2" > "$PID_DIR/$1"
}

cleanup_all() {
    for f in "$PID_DIR"/*; do
        [ -f "$f" ] || continue
        local pid
        pid=$(cat "$f" 2>/dev/null)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    rm -rf "$PID_DIR"
}

# Clean up orphaned processes from a prior run (by PID file, not by name)
cleanup_all 2>/dev/null || true
mkdir -p "$PID_DIR"
# Only remove locks/sockets for OUR display - never touch other X servers
rm -f "/tmp/.X${DISPLAY_NUM}-lock" 2>/dev/null || true
rm -rf "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true

# ── Cleanup trap: kill only our tracked PIDs on Ctrl+C / SIGTERM ──
# NOTE: EXIT is intentionally omitted — we want services to keep running after script finishes
trap 'cleanup_all' INT TERM

# ── Detect init system: systemd units preferred, nohup fallback otherwise ──
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    SYSTEMD=true
else
    SYSTEMD=false
    warn "systemd not available - services will run via nohup (no auto-restart/reboot persistence)"
fi

APP_DIR="/opt/cloud-linux-gui"
BIN_DIR="${APP_DIR}/bin"
mkdir -p "${BIN_DIR}"

step "System check..."
MIN_RAM_MB=1024
total_ram=$(free -m | awk '/^Mem:/{print $2}')
if [ "$total_ram" -lt "$MIN_RAM_MB" ]; then
    err "Only ${total_ram}MB RAM detected (minimum ${MIN_RAM_MB}MB required)"
    err "This system may not have enough memory to run a desktop environment"
fi

# ── Step 1: Wait for dpkg lock ──
dpkg_lock_held() {
    # fuser (psmisc) is preinstalled on most images; lsof may not be yet
    if command -v fuser >/dev/null 2>&1; then
        fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1
    elif command -v lsof >/dev/null 2>&1; then
        lsof /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1
    else
        return 1  # cannot detect; proceed and let apt fail loudly if locked
    fi
}

step "Waiting for dpkg lock (if held by another process)..."
if ! command -v fuser >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
    warn "Neither fuser nor lsof available - skipping dpkg lock wait"
fi
for i in $(seq 1 30); do
    if dpkg_lock_held; then
        if [ "$i" -eq 30 ]; then
            err "dpkg lock still held after 60s. Aborting."
            exit 1
        fi
        warn "dpkg lock held, waiting (${i}/30)..."
        sleep 2
    else
        break
    fi
done

# ── Step 2: Install packages ──
step "Installing packages (this may take a minute)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>&1 || warn "apt-get update had issues (network may be slow)"

install_pkg() {
    local desc="$1"
    shift
    step "Installing ${desc}..."
    apt-get install -y "$@" 2>&1 | tail -3
    local apt_exit=${PIPESTATUS[0]}
    if [ "$apt_exit" -ne 0 ]; then
        err "Failed to install ${desc} (exit code $apt_exit)"
        return 1
    fi
    for pkg in "$@"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            warn "Package '$pkg' may not have been installed correctly"
        fi
    done
    log "${desc} installed"
}

install_pkg "${DESKTOP} desktop environment" ${DESKTOP_PKGS} || true
install_pkg "VNC server" tigervnc-standalone-server tigervnc-common || true
install_pkg "tools" websockify curl wget git procps net-tools x11vnc xauth || true

# ── Step 3: Install cloudflared (pinned version + SHA256 verification) ──
CLOUDFLARED_VERSION="${CLOUDFLARED_VERSION:-2026.8.2}"
CF_SHA256_AMD64="fcfb02b575a52ca1af2e3267af4e1517bcdeb30ac48c834c69abaed3c0576ad2"
CF_SHA256_ARM64="7747d94570fb390cf47dcb4f9555c193c6355cda9793f0d878d9049e5d6a7790"

step "Installing cloudflared (${CLOUDFLARED_VERSION})..."
if ! command -v cloudflared &>/dev/null; then
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64)        CF_ARCH="amd64"; CF_SHA256="${CF_SHA256_AMD64}" ;;
        aarch64|arm64) CF_ARCH="arm64"; CF_SHA256="${CF_SHA256_ARM64}" ;;
        *)             err "Unsupported architecture: ${ARCH}"; exit 1 ;;
    esac

    CF_URL="https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${CF_ARCH}"
    CF_FILE="/tmp/cloudflared-$$"
    trap 'rm -f "${CF_FILE}"' EXIT

    step "Downloading cloudflared..."
    if ! curl -sL "${CF_URL}" -o "${CF_FILE}"; then
        err "Failed to download cloudflared"
        exit 1
    fi

    step "Verifying SHA256 checksum..."
    CF_ACTUAL=$(sha256sum "${CF_FILE}" 2>/dev/null | awk '{print $1}')
    if [ "${CF_ACTUAL}" != "${CF_SHA256}" ]; then
        err "Checksum mismatch! Expected ${CF_SHA256}, got ${CF_ACTUAL}"
        rm -f "${CF_FILE}"
        exit 1
    fi
    log "Checksum OK"

    step "Installing cloudflared..."
    mv "${CF_FILE}" /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    trap - EXIT
    log "cloudflared ${CLOUDFLARED_VERSION} installed"
else
    log "Cloudflared already installed ($(cloudflared --version 2>/dev/null | head -1))"
    warn "Note: pinned version is ${CLOUDFLARED_VERSION}; existing install was left untouched"
fi

# ── Step 4: Install noVNC ──
step "Installing noVNC..."
NOVNC_DIR="/opt/novnc"
if [ ! -f "${NOVNC_DIR}/core/rfb.js" ]; then
    rm -rf "${NOVNC_DIR}"
    if ! git clone --depth 1 https://github.com/novnc/noVNC.git "${NOVNC_DIR}"; then
        err "Failed to clone noVNC from GitHub"
        exit 1
    fi
    log "noVNC cloned from GitHub"
else
    log "noVNC already installed"
fi

# Install the custom UI shipped with this repo (falls back to upstream pages
# when running standalone via curl | bash)
if [ -f "${SCRIPT_DIR}/web/desktop.html" ] && [ -f "${SCRIPT_DIR}/web/vnc.html" ]; then
    cp "${SCRIPT_DIR}/web/desktop.html" "${NOVNC_DIR}/desktop.html"
    cp "${SCRIPT_DIR}/web/vnc.html" "${NOVNC_DIR}/vnc.html"
    # Backward-compat stub for old bookmarks
    printf '<!DOCTYPE html>\n<html><head><meta http-equiv="refresh" content="0;url=desktop.html"></head>\n<body>Redirecting...</body></html>\n' > "${NOVNC_DIR}/vnc_lite1.html"
    INDEX_TARGET="desktop.html"
    log "Custom UI installed (desktop.html, vnc.html)"
else
    INDEX_TARGET="vnc_lite.html"
    warn "Repo web/ files not found - using upstream noVNC example pages"
fi

cat > "${NOVNC_DIR}/index.html" << IDXEOF
<!DOCTYPE html>
<html>
<head><meta http-equiv="refresh" content="0;url=${INDEX_TARGET}"></head>
<body>Redirecting to desktop...</body>
</html>
IDXEOF
log "noVNC redirect page created"

# ── Step 5: Configure VNC ──
step "Configuring VNC server..."
mkdir -p /root/.vnc
chmod 700 /root/.vnc

cat > /root/.vnc/xstartup << XEOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p \$XDG_RUNTIME_DIR
chmod 700 \$XDG_RUNTIME_DIR
exec dbus-launch --exit-with-session ${SESSION_CMD}
XEOF
chmod +x /root/.vnc/xstartup

# Password handling:
#   --password PASS   use it (RFB protocol only uses the first 8 chars)
#   --new-password    regenerate even if a previous password exists
#   otherwise         reuse the existing password so re-runs don't break clients
if [ -n "${PASSWORD_ARG}" ]; then
    VNC_PASS="${PASSWORD_ARG}"
    if [ ${#VNC_PASS} -gt 8 ]; then
        warn "Password longer than 8 chars - VNC will use only the first 8 ('${VNC_PASS:0:8}')"
    fi
elif [ "${FORCE_NEW_PASSWORD}" = true ] || [ ! -s /root/.vnc/password.txt ]; then
    # RFB authentication keys are exactly 8 bytes - generate exactly that
    VNC_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 8)
else
    VNC_PASS=$(cat /root/.vnc/password.txt)
    log "Reusing existing VNC password from previous install (--new-password to rotate)"
fi

printf '%s' "${VNC_PASS}" | vncpasswd -f > /root/.vnc/passwd 2>/dev/null
if [ ! -s /root/.vnc/passwd ]; then
    warn "Password method 1 failed, trying alternative..."
    printf '%s\n%s\nn\n' "${VNC_PASS}" "${VNC_PASS}" | vncpasswd /root/.vnc/passwd 2>/dev/null || true
fi
chmod 600 /root/.vnc/passwd

# Save password securely (never log it)
echo "${VNC_PASS}" > /root/.vnc/password.txt
chmod 600 /root/.vnc/password.txt
log "VNC password configured"

# ── Step 6: Service wrappers (single source of truth for both systemd and nohup) ──
step "Writing service wrappers..."

cat > "${BIN_DIR}/run-xvfb.sh" << EOF
#!/bin/bash
exec >> /tmp/xvfb.log 2>&1
exec Xvfb ${DISPLAY} -screen 0 ${RESOLUTION}x24 -ac +extension GLX +render -noreset
EOF

cat > "${BIN_DIR}/run-desktop.sh" << EOF
#!/bin/bash
export DISPLAY=${DISPLAY}
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p \$XDG_RUNTIME_DIR
chmod 700 \$XDG_RUNTIME_DIR
exec >> /tmp/xfce.log 2>&1
exec dbus-launch --exit-with-session ${SESSION_CMD}
EOF

# If our Xvfb display exists, mirror it with x11vnc; otherwise fall back to
# tigervncserver which brings its own X server (and uses xstartup).
cat > "${BIN_DIR}/run-vnc.sh" << EOF
#!/bin/bash
# Wait briefly for the Xvfb socket - Type=simple units are "started" before
# Xvfb has actually created it
for _ in \$(seq 1 15); do
    [ -S /tmp/.X11-unix/X${DISPLAY_NUM} ] && break
    sleep 1
done
if [ -S /tmp/.X11-unix/X${DISPLAY_NUM} ]; then
    exec x11vnc -display ${DISPLAY} -rfbport ${VNC_PORT} -shared -forever \\
        -rfbauth /root/.vnc/passwd
else
    exec tigervncserver :${DISPLAY_NUM} \\
        -geometry ${RESOLUTION} \\
        -depth 24 \\
        -localhost no \\
        -rfbport ${VNC_PORT} \\
        -xstartup /root/.vnc/xstartup \\
        -rfbauth /root/.vnc/passwd \\
        -fg \\
        -BlacklistThreshold=5 \\
        -BlacklistTimeout=60
fi
EOF

cat > "${BIN_DIR}/run-novnc.sh" << EOF
#!/bin/bash
exec >> /tmp/novnc.log 2>&1
exec websockify --web=${NOVNC_DIR} --heartbeat=30 --timeout=0 6080 localhost:${VNC_PORT}
EOF

cat > "${BIN_DIR}/run-tunnel.sh" << 'EOF'
#!/bin/bash
exec >> /tmp/cloudflared.log 2>&1
exec cloudflared tunnel --url http://localhost:6080 --no-autoupdate
EOF

chmod +x "${BIN_DIR}"/*.sh

# Password API server lives in /opt now (survives /tmp cleanup)
cat > "${BIN_DIR}/vnc_password_server.py" << 'PYSERVER'
#!/usr/bin/env python3
import http.server
import socketserver
import json

PORT = 6081

class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True

class VncPasswordHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/vnc-password', '/api/password'):
            try:
                with open('/root/.vnc/password.txt', 'r') as f:
                    password = f.read().strip()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', 'http://localhost:6080')
                self.end_headers()
                self.wfile.write(json.dumps({'password': password}).encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
        elif self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

# Bind to localhost only - this endpoint hands out the VNC password and
# must never be reachable from the network
with ReusableTCPServer(("127.0.0.1", PORT), VncPasswordHandler) as httpd:
    httpd.serve_forever()
PYSERVER

cat > "${BIN_DIR}/run-password-api.sh" << 'EOF'
#!/bin/bash
exec >> /tmp/password_server.log 2>&1
exec python3 /opt/cloud-linux-gui/bin/vnc_password_server.py
EOF

chmod +x "${BIN_DIR}/run-password-api.sh"

# ── Step 7: Start services ──
port_listening() {
    ss -tlnp 2>/dev/null | grep -qE ":$1\b"
}

wait_for_port() {
    local port="$1" tries="$2"
    for _ in $(seq 1 "$tries"); do
        port_listening "$port" && return 0
        sleep 1
    done
    return 1
}

if [ "${SYSTEMD}" = true ]; then
    step "Creating systemd services..."
    UNIT_NAMES=(cloud-gui-password-api cloud-gui-xvfb cloud-gui-desktop cloud-gui-vnc cloud-gui-novnc)

    write_unit() {
        local name="$1" desc="$2" after="$3" requires="$4"
        {
            echo "[Unit]"
            echo "Description=${desc}"
            echo "After=${after}"
            [ -n "${requires}" ] && echo "Requires=${requires}"
            echo ""
            echo "[Service]"
            echo "Type=simple"
            echo "User=root"
            echo "Environment=HOME=/root"
            echo "ExecStart=${BIN_DIR}/run-${1#cloud-gui-}.sh"
            echo "Restart=on-failure"
            echo "RestartSec=3"
            echo ""
            echo "[Install]"
            echo "WantedBy=multi-user.target"
        } > "/etc/systemd/system/${name}.service"
    }

    write_unit cloud-gui-xvfb         "Cloud Linux GUI - virtual display"   ""                                    ""
    write_unit cloud-gui-desktop      "Cloud Linux GUI - desktop session"   "cloud-gui-xvfb.service"              "cloud-gui-xvfb.service"
    write_unit cloud-gui-vnc          "Cloud Linux GUI - VNC server"        "cloud-gui-desktop.service"           ""
    write_unit cloud-gui-novnc        "Cloud Linux GUI - noVNC websocket"   "cloud-gui-vnc.service"               ""
    write_unit cloud-gui-password-api "Cloud Linux GUI - password API"      ""                                    ""

    if [ "${START_TUNNEL}" = true ]; then
        write_unit cloud-gui-tunnel "Cloud Linux GUI - Cloudflare tunnel" "network-online.target cloud-gui-novnc.service" ""
        UNIT_NAMES+=(cloud-gui-tunnel)
    fi

    systemctl daemon-reload
    step "Starting services via systemctl..."
    systemctl enable --now "${UNIT_NAMES[@]}" 2>&1 | grep -v "^Created symlink" || true
    log "Services enabled (auto-start on boot, restart on failure)"

    XVFB_PID=$(systemctl show -p MainPID --value cloud-gui-xvfb 2>/dev/null)
    save_pid "xvfb" "${XVFB_PID:-0}"
else
    step "Starting services via nohup..."

    nohup "${BIN_DIR}/run-xvfb.sh" &
    XVFB_PID=$!
    save_pid "xvfb" "$XVFB_PID"
    sleep 2

    if ! ps -p "$XVFB_PID" > /dev/null 2>&1; then
        err "Xvfb failed to start - check /tmp/xvfb.log"
        tail -10 /tmp/xvfb.log 2>/dev/null
    else
        log "Xvfb started with PID ${XVFB_PID}"
    fi

    nohup "${BIN_DIR}/run-desktop.sh" &
    XFCE_PID=$!
    save_pid "xfce" "$XFCE_PID"
    sleep 5

    if ps -p "$XFCE_PID" > /dev/null 2>&1; then
        log "Desktop session started with PID ${XFCE_PID}"
    else
        warn "Desktop process may not be running - check /tmp/xfce.log"
    fi
fi

# Give the desktop time to come up before mirroring it
sleep 2

if [ "${SYSTEMD}" = true ]; then
    systemctl start cloud-gui-vnc.service 2>/dev/null || true
else
    nohup "${BIN_DIR}/run-vnc.sh" > /tmp/vnc-wrapper.log 2>&1 &
    save_pid "vnc" "$!"
    sleep 3
fi

VNC_RUNNING=false
if wait_for_port "${VNC_PORT}" 10; then
    VNC_RUNNING=true
    log "VNC server running on port ${VNC_PORT}"
else
    err "VNC server FAILED to start!"
    echo "  cat /tmp/x11vnc.log /tmp/vnc.log /tmp/xvfb.log"
fi

if [ "${SYSTEMD}" = true ]; then
    systemctl start cloud-gui-novnc.service 2>/dev/null || true
else
    nohup "${BIN_DIR}/run-novnc.sh" &
    NOVNC_PID=$!
    save_pid "websockify" "$NOVNC_PID"
fi

if wait_for_port 6080 8; then
    log "noVNC websockify running on port 6080"
else
    warn "noVNC may have failed to start - check /tmp/novnc.log"
fi

step "Testing noVNC connection..."
for attempt in 1 2 3; do
    # index.html is a redirect page; test an actual content page
    if curl -sL --max-time 5 "http://localhost:6080/${INDEX_TARGET}" 2>/dev/null | grep -qi "novnc\|vnc"; then
        log "noVNC is serving content"
        break
    fi
    if [ $attempt -lt 3 ]; then
        warn "Attempt $attempt failed, retrying in 2s..."
        sleep 2
    fi
done

if [ "${SYSTEMD}" = true ]; then
    systemctl start cloud-gui-password-api.service 2>/dev/null || true
else
    nohup "${BIN_DIR}/run-password-api.sh" &
    save_pid "password_server" "$!"
fi

if wait_for_port 6081 5; then
    log "Password API server running on port 6081 (localhost only)"
fi

# ── Step 8: Start Cloudflare Tunnel ──
TUNNEL_URL=""
TUNNEL_READY=false
if [ "${START_TUNNEL}" = false ]; then
    log "Skipping Cloudflare tunnel (--no-tunnel)"
elif [ "${SYSTEMD}" = true ]; then
    systemctl start cloud-gui-tunnel.service 2>/dev/null || true
else
    step "Starting Cloudflare Tunnel..."
    nohup "${BIN_DIR}/run-tunnel.sh" &
    save_pid "cloudflared" "$!"
fi

if [ "${START_TUNNEL}" = true ]; then
    step "Waiting for tunnel URL (up to 60 seconds)..."
    for i in $(seq 1 30); do
        sleep 2
        TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
        if [ -n "${TUNNEL_URL}" ]; then
            TUNNEL_READY=true
            log "Cloudflare Tunnel ready: ${TUNNEL_URL}"
            break
        fi
        printf "."
    done
    echo ""

    if [ "$TUNNEL_READY" = "false" ]; then
        warn "Tunnel URL not yet visible - cloudflared may still be initializing"
        # Background watcher: write the URL to /opt/tunnel_url.txt as soon as it appears
        nohup bash -c '
            for i in $(seq 1 150); do
                URL=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" /tmp/cloudflared.log 2>/dev/null | head -1)
                if [ -n "$URL" ]; then
                    echo "$URL" > /opt/tunnel_url.txt
                    exit 0
                fi
                sleep 2
            done
       ' > /dev/null 2>&1 &
        save_pid "urlwatch" "$!"
    fi
fi

# ── Final Output ──
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Cloud Linux GUI - Installation Complete${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

echo "${VNC_PASS}" > /opt/vnc_password.txt
chmod 600 /opt/vnc_password.txt

# Install management scripts so the paths printed below actually exist
cp "${SCRIPT_DIR}/stop.sh" "${APP_DIR}/stop.sh" 2>/dev/null || true
cp "${SCRIPT_DIR}/status.sh" "${APP_DIR}/status.sh" 2>/dev/null || true
cp "${BASH_SOURCE[0]}" "${APP_DIR}/install.sh" 2>/dev/null || true
chmod +x "${APP_DIR}"/*.sh 2>/dev/null || true

if [ -z "${TUNNEL_URL}" ] && [ "${START_TUNNEL}" = true ]; then
    TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
fi

if [ "${START_TUNNEL}" = true ] && [ -n "${TUNNEL_URL}" ]; then
    echo "${TUNNEL_URL}" > /opt/tunnel_url.txt
    echo ""
    echo -e "  ${GREEN}SUCCESS! Your Linux Desktop is ready!${NC}"
    echo ""
    echo -e "  ${BLUE}Desktop URL:${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/desktop.html${NC}"
    echo ""
    echo -e "  ${BLUE}Alternative:${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/vnc.html${NC}"
    echo ""
elif [ "${START_TUNNEL}" = true ]; then
    echo ""
    echo -e "  ${YELLOW}Cloudflare Tunnel still initializing...${NC}"
    echo -e "  ${YELLOW}Get URL: grep trycloudflare /tmp/cloudflared.log${NC}"
    echo -e "  ${YELLOW}Or wait: cat /opt/tunnel_url.txt${NC}"
    echo ""
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Service Status ──
echo -e "${BLUE}Service Status:${NC}"
echo ""

check_pid() {
    local pidfile="$PID_DIR/$1"
    if [ -f "$pidfile" ]; then
        local pid
        pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

status_line() {
    local label="$1" ok="$2"
    if [ "$ok" = "true" ]; then
        echo -e "  ${label}: ${GREEN}● Running${NC}"
    else
        echo -e "  ${label}: ${RED}● Stopped${NC}"
    fi
}

VNC_STATUS=false
{ check_pid "vnc" || check_pid "x11vnc" || check_pid "tigervnc"; } && VNC_STATUS=true
[ "$VNC_RUNNING" = true ] && VNC_STATUS=true
NOVNC_STATUS=false
port_listening 6080 && NOVNC_STATUS=true
TUNNEL_STATUS=false
if [ "${START_TUNNEL}" = true ]; then
    if [ "${SYSTEMD}" = true ]; then
        [ "$(systemctl is-active cloud-gui-tunnel 2>/dev/null)" = "active" ] && TUNNEL_STATUS=true
    else
        check_pid "cloudflared" && TUNNEL_STATUS=true
    fi
    [ -n "$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)" ] && TUNNEL_STATUS=true
fi
DESKTOP_STATUS=false
if [ "${SYSTEMD}" = true ]; then
    [ "$(systemctl is-active cloud-gui-xvfb 2>/dev/null)" = "active" ] && DESKTOP_STATUS=true
else
    { check_pid "xfce" || check_pid "xvfb"; } && DESKTOP_STATUS=true
fi

status_line "VNC Server  " "$VNC_STATUS"
status_line "noVNC       " "$NOVNC_STATUS"
status_line "Tunnel      " "$TUNNEL_STATUS"
status_line "Desktop     " "$DESKTOP_STATUS"

echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo ""
echo -e "  ${YELLOW}Status:${NC}     sudo ${APP_DIR}/status.sh"
echo -e "  ${YELLOW}Get URL:${NC}    cat /opt/tunnel_url.txt"
echo -e "  ${YELLOW}Logs:${NC}       /tmp/{xvfb,xfce,x11vnc,novnc,cloudflared}.log"
if [ "${SYSTEMD}" = true ]; then
    echo -e "  ${YELLOW}Restart:${NC}    sudo systemctl restart cloud-gui-*"
else
    echo -e "  ${YELLOW}Restart:${NC}    sudo bash ${APP_DIR}/install.sh"
fi
echo -e "  ${YELLOW}Stop All:${NC}   sudo ${APP_DIR}/stop.sh"
echo ""
echo -e "  ${YELLOW}Your VNC password is saved in:${NC} /root/.vnc/password.txt"
echo -e "  ${YELLOW}Backup copy:${NC} /opt/vnc_password.txt"
echo ""
