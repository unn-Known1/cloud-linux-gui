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

echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo -e "${GREEN}  Cloud Linux GUI Installer${NC}"
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    err "Run as root: sudo bash install.sh"
    exit 1
fi

# ── PID tracking: only kill what we ourselves started ──
PID_DIR="/tmp/cloud-gui-pids"
mkdir -p "$PID_DIR"

save_pid() {
    echo "$2" > "$PID_DIR/$1"
}

cleanup_all() {
    for f in "$PID_DIR"/*; do
        [ -f "$f" ] || continue
        local pid=$(cat "$f" 2>/dev/null)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    rm -rf "$PID_DIR"
}

# Clean up orphaned processes from a prior run (by PID file, not by name)
cleanup_all 2>/dev/null || true
mkdir -p "$PID_DIR"
rm -f /tmp/.X*-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X* 2>/dev/null || true

# ── Cleanup trap: kill only our tracked PIDs on Ctrl+C / SIGTERM ──
# NOTE: EXIT is intentionally omitted — we want services to keep running after script finishes
trap 'cleanup_all' INT TERM

step "System check..."
MIN_RAM_MB=1024
total_ram=$(free -m | awk '/^Mem:/{print $2}')
if [ "$total_ram" -lt "$MIN_RAM_MB" ]; then
    err "Only ${total_ram}MB RAM detected (minimum ${MIN_RAM_MB}MB required)"
    err "This system may not have enough memory to run a desktop environment"
fi

# ── Step 1: Wait for dpkg lock ──
step "Waiting for dpkg lock (if held by another process)..."
for i in $(seq 1 30); do
    if lsof /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null; then
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

install_pkg "desktop environment" xfce4 xfce4-terminal dbus-x11 || true
install_pkg "VNC server" tigervnc-standalone-server tigervnc-common || true
install_pkg "tools" websockify curl wget git procps net-tools xfonts-base fonts-ubuntu || true

# ── Step 3: Install cloudflared ──
step "Installing cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64)        CF_ARCH="amd64" ;;
        aarch64|arm64) CF_ARCH="arm64" ;;
        *)             CF_ARCH="amd64" ;;
    esac

    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    CF_FILE="/tmp/cloudflared-$$"
    trap 'rm -f "${CF_FILE}"' EXIT

    step "Downloading cloudflared..."
    if ! curl -sL "${CF_URL}" -o "${CF_FILE}"; then
        err "Failed to download cloudflared"
        exit 1
    fi

    step "Verifying binary..."
    if ! file "${CF_FILE}" | grep -q "ELF"; then
        err "Downloaded file is not a valid ELF binary - possible MITM attack"
        exit 1
    fi

    CF_SIZE=$(stat -c%s "${CF_FILE}" 2>/dev/null || stat -f%z "${CF_FILE}" 2>/dev/null)
    if [ "${CF_SIZE}" -lt 10000000 ] || [ "${CF_SIZE}" -gt 100000000 ]; then
        err "Downloaded file size ${CF_SIZE} bytes is unusual"
        exit 1
    fi

    step "Installing cloudflared..."
    mv "${CF_FILE}" /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    trap - EXIT
    log "Cloudflared downloaded, verified, and installed"
else
    log "Cloudflared already installed"
fi

# ── Step 4: Install noVNC ──
step "Installing noVNC..."
NOVNC_DIR="/opt/novnc"
if [ ! -f "${NOVNC_DIR}/core/rfb.js" ]; then
    rm -rf "${NOVNC_DIR}"
    git clone --depth 1 https://github.com/novnc/noVNC.git "${NOVNC_DIR}" 2>/dev/null
    log "noVNC cloned from GitHub"
else
    log "noVNC already installed"
fi

cat > "${NOVNC_DIR}/index.html" << 'IDXEOF'
<!DOCTYPE html>
<html>
<head><meta http-equiv="refresh" content="0;url=vnc_lite.html"></head>
<body>Redirecting to desktop...</body>
</html>
IDXEOF
log "noVNC redirect page created"

# ── Step 5: Configure VNC ──
step "Configuring VNC server..."
mkdir -p /root/.vnc
chmod 700 /root/.vnc

cat > /root/.vnc/xstartup << 'XEOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR
exec dbus-launch --exit-with-session startxfce4
XEOF
chmod +x /root/.vnc/xstartup

VNC_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)

echo "${VNC_PASS}" | vncpasswd -f > /root/.vnc/passwd 2>/dev/null
if [ ! -s /root/.vnc/passwd ]; then
    warn "Password method 1 failed, trying alternative..."
    printf '%s\n%s\nn\n' "${VNC_PASS}" "${VNC_PASS}" | vncpasswd /root/.vnc/passwd 2>/dev/null || true
fi
chmod 600 /root/.vnc/passwd

# Save password securely (never log it)
echo "${VNC_PASS}" > /root/.vnc/password.txt
chmod 600 /root/.vnc/password.txt
log "VNC password configured"

# ── Step 6: Start VNC Server ──
step "Starting VNC server..."

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

export DISPLAY=:1

# Step 6a: Start Xvfb virtual display
step "Starting Xvfb virtual display..."
nohup Xvfb :1 -screen 0 1366x768x24 -ac +extension GLX +render -noreset > /tmp/xvfb.log 2>&1 &
XVFB_PID=$!
save_pid "xvfb" "$XVFB_PID"
sleep 2

if ps -p "$XVFB_PID" > /dev/null 2>&1; then
    log "Xvfb started with PID ${XVFB_PID}"
else
    err "Xvfb failed to start - check /tmp/xvfb.log"
    cat /tmp/xvfb.log 2>/dev/null | tail -10
    warn "Attempting Xvfb without GLX..."
    nohup Xvfb :1 -screen 0 1366x768x24 -ac > /tmp/xvfb.log 2>&1 &
    XVFB_PID=$!
    save_pid "xvfb" "$XVFB_PID"
    sleep 3
fi

# Step 6b: Generate TLS certificate
step "Generating TLS certificate..."
CERT_DIR="/root/.vnc/certs"
mkdir -p "${CERT_DIR}"
chmod 700 "${CERT_DIR}"

if [ ! -f "${CERT_DIR}/server.crt" ] || [ ! -f "${CERT_DIR}/server.key" ]; then
    openssl req -x509 -newkey rsa:4096 -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.crt" \
        -days 365 -nodes -subj "/CN=VNC Server/O=Cloud Linux GUI" 2>/dev/null
    chmod 600 "${CERT_DIR}/server.key"
    chmod 644 "${CERT_DIR}/server.crt"
    log "TLS certificate generated"
else
    log "TLS certificate already exists"
fi

# Step 6c: Start XFCE desktop session
step "Starting XFCE desktop session..."
nohup dbus-launch --exit-with-session startxfce4 > /tmp/xfce.log 2>&1 &
XFCE_PID=$!
save_pid "xfce" "$XFCE_PID"
sleep 5

if ps -p "$XFCE_PID" > /dev/null 2>&1; then
    log "XFCE started with PID ${XFCE_PID}"
else
    warn "XFCE process may not be running - check /tmp/xfce.log"
fi

export DISPLAY=:1

# Step 6d: Start VNC server
step "Starting TigerVNC server..."

nohup tigervncserver :1 \
    -geometry 1366x768 \
    -depth 24 \
    -localhost no \
    -rfbport 5901 \
    -xstartup /root/.vnc/xstartup \
    -rfbauth /root/.vnc/passwd \
    > /tmp/vnc.log 2>&1 &

VNC_PID=$!
save_pid "tigervnc" "$VNC_PID"
sleep 3

VNC_RUNNING=false
if ss -tlnp 2>/dev/null | grep -q ":5901"; then
    VNC_RUNNING=true
    log "TigerVNC server running on port 5901"
elif command -v lsof >/dev/null && lsof -i :5901 >/dev/null 2>&1; then
    VNC_RUNNING=true
    log "VNC server is running on port 5901"
fi

if [ "$VNC_RUNNING" = "false" ]; then
    warn "TigerVNC failed - trying x11vnc fallback..."
    if ! command -v x11vnc > /dev/null 2>&1; then
        install_pkg "x11vnc" x11vnc || true
    fi

    nohup x11vnc -display :1 -rfbport 5901 -shared -forever -rfbauth /root/.vnc/passwd \
        > /tmp/x11vnc.log 2>&1 &
    X11VNC_PID=$!
    save_pid "x11vnc" "$X11VNC_PID"
    sleep 2

    if ss -tlnp 2>/dev/null | grep -q ":5901"; then
        VNC_RUNNING=true
        log "x11vnc fallback running on port 5901"
    else
        err "VNC server FAILED to start!"
        echo "  cat /tmp/vnc.log"
        echo "  cat /tmp/x11vnc.log"
        echo "  cat /tmp/xvfb.log"
    fi
fi

# ── Step 7: Start noVNC ──
step "Starting noVNC web server..."

if [ "$VNC_RUNNING" = "false" ]; then
    err "VNC server is not running! Cannot start noVNC."
else
    log "VNC is running on port 5901"
fi

step "Starting websockify..."
nohup websockify \
    --web="${NOVNC_DIR}" \
    --heartbeat=30 \
    --timeout=0 \
    6080 \
    localhost:5901 \
    > /tmp/novnc.log 2>&1 &

NOVNC_PID=$!
save_pid "websockify" "$NOVNC_PID"
sleep 4

if ss -tlnp 2>/dev/null | grep -q ":6080"; then
    log "noVNC websockify running on port 6080 (PID: ${NOVNC_PID})"
else
    warn "noVNC may have failed to start - trying fallback..."
    nohup python3 -m websockify \
        --web="${NOVNC_DIR}" \
        6080 \
        localhost:5901 \
        > /tmp/novnc2.log 2>&1 &
    NOVNC_PID=$!
    save_pid "websockify" "$NOVNC_PID"
    sleep 4
fi

step "Testing noVNC connection..."
for attempt in 1 2 3; do
    if curl -s --max-time 5 http://localhost:6080/ 2>/dev/null | grep -qi "novnc\|vnc"; then
        log "noVNC is serving content"
        break
    fi
    if [ $attempt -lt 3 ]; then
        warn "Attempt $attempt failed, retrying in 2s..."
        sleep 2
    fi
done

# ── Step 8: Start password API server ──
step "Starting password API server..."

cat > /tmp/vnc_password_server.py << 'PYSERVER'
#!/usr/bin/env python3
import os
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
                self.send_header('Access-Control-Allow-Origin', '*')
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

with ReusableTCPServer(("", PORT), VncPasswordHandler) as httpd:
    httpd.serve_forever()
PYSERVER

chmod +x /tmp/vnc_password_server.py

nohup python3 /tmp/vnc_password_server.py > /tmp/password_server.log 2>&1 &
PASSWORD_PID=$!
save_pid "password_server" "$PASSWORD_PID"
sleep 1

if ss -tlnp 2>/dev/null | grep -q ":6081"; then
    log "Password API server running on port 6081 (PID: ${PASSWORD_PID})"
fi

# ── Step 9: Start Cloudflare Tunnel ──
step "Starting Cloudflare Tunnel (please wait ~60 seconds)..."

nohup cloudflared tunnel \
    --url http://localhost:6080 \
    --no-autoupdate \
    > /tmp/cloudflared.log 2>&1 &

CF_PID=$!
save_pid "cloudflared" "$CF_PID"
TUNNEL_URL=""
TUNNEL_READY=false

step "Waiting for tunnel URL (up to 60 seconds)..."
for i in $(seq 1 30); do
    sleep 2

    if ! kill -0 ${CF_PID} 2>/dev/null; then
        err "Cloudflared process crashed!"
        cat /tmp/cloudflared.log 2>/dev/null | tail -20
        break
    fi

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
fi

# ── Step 10: Final Output ──
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         Cloud Linux GUI - Installation Complete${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

echo "${VNC_PASS}" > /opt/vnc_password.txt
chmod 600 /opt/vnc_password.txt

if [ -z "${TUNNEL_URL}" ]; then
    TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
fi

if [ -n "${TUNNEL_URL}" ]; then
    echo "${TUNNEL_URL}" > /opt/tunnel_url.txt
    echo ""
    echo -e "  ${GREEN}SUCCESS! Your Linux Desktop is ready!${NC}"
    echo ""
    echo -e "  ${BLUE}Desktop URL:${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/vnc.html${NC}"
    echo ""
    echo -e "  ${BLUE}Alternative (direct):${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/vnc_lite.html${NC}"
    echo ""
else
    echo ""
    echo -e "  ${YELLOW}Cloudflare Tunnel still initializing...${NC}"
    echo -e "  ${YELLOW}Get URL: cat /tmp/cloudflared.log | grep trycloudflare${NC}"
    echo -e "  ${YELLOW}Or wait: cat /opt/tunnel_url.txt${NC}"
    echo ""
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Service Status (checks by PID, not by name) ──
echo -e "${BLUE}Service Status:${NC}"
echo ""

check_pid() {
    local pidfile="$PID_DIR/$1"
    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

check_pid "tigervnc" || check_pid "x11vnc" \
    && echo -e "  VNC Server  : ${GREEN}● Running${NC}" \
    || echo -e "  VNC Server  : ${RED}● Stopped${NC}"
check_pid "websockify" \
    && echo -e "  noVNC       : ${GREEN}● Running${NC}" \
    || echo -e "  noVNC       : ${RED}● Stopped${NC}"
check_pid "cloudflared" \
    && echo -e "  Tunnel      : ${GREEN}● Running${NC}" \
    || echo -e "  Tunnel      : ${RED}● Stopped${NC}"
check_pid "xfce" \
    && echo -e "  Desktop     : ${GREEN}● Running${NC}" \
    || echo -e "  Desktop     : ${RED}● Stopped${NC}"

echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo ""
echo -e "  ${YELLOW}Get URL:${NC}    cat /opt/tunnel_url.txt"
echo -e "  ${YELLOW}VNC Log:${NC}    cat /tmp/vnc.log"
echo -e "  ${YELLOW}Tunnel Log:${NC} cat /tmp/cloudflared.log | tail -20"
echo -e "  ${YELLOW}Restart:${NC}    sudo bash install.sh"
echo -e "  ${YELLOW}Stop All:${NC}   /opt/cloud-linux-gui/stop.sh"
echo ""

if [ -n "${TUNNEL_URL}" ]; then
    echo -e "  ${YELLOW}Your VNC password is saved in:${NC} /root/.vnc/password.txt"
    echo -e "  ${YELLOW}Backup copy:${NC} /opt/vnc_password.txt"
    echo ""
fi
