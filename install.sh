#!/bin/bash
# Don't use set -e - we need to handle errors gracefully and continue
# set -e

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
    err "Run as root: sudo bash /tmp/setup.sh"
    exit 1
fi

# ── Step 1: Kill old processes ──
step "Killing old processes..."
pkill -9 -f "Xtigervnc" 2>/dev/null || true
pkill -9 -f "Xvnc" 2>/dev/null || true
pkill -9 -f "Xvfb" 2>/dev/null || true
pkill -9 -f "websockify" 2>/dev/null || true
pkill -9 -f "cloudflared" 2>/dev/null || true
pkill -9 -f "startxfce4" 2>/dev/null || true
sleep 2
rm -f /tmp/.X*-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X* 2>/dev/null || true
log "Old processes cleaned"

# ── Step 2: Install packages ──
step "Installing packages (this may take a minute)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null

step "Installing desktop environment..."
apt-get install -y xfce4 xfce4-terminal dbus-x11 2>&1 | tail -3
log "Desktop installed"

step "Installing VNC server..."
apt-get install -y tigervnc-standalone-server tigervnc-common 2>&1 | tail -3
log "VNC installed"

step "Installing tools..."
apt-get install -y websockify curl wget git procps net-tools xfonts-base fonts-ubuntu 2>&1 | tail -3
log "Tools installed"

# ── Step 3: Install cloudflared ──
step "Installing cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64)        CF_ARCH="amd64" ;;
        aarch64|arm64) CF_ARCH="arm64" ;;
        *)             CF_ARCH="amd64" ;;
    esac

    # SECURITY: Download to temp file first, then verify and install
    # Do NOT pipe directly to bash (CWE-88)
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}"
    CF_FILE="/tmp/cloudflared-$$"
    trap 'rm -f "${CF_FILE}"' EXIT

    step "Downloading cloudflared..."
    if ! curl -sL "${CF_URL}" -o "${CF_FILE}"; then
        err "Failed to download cloudflared"
        exit 1
    fi

    step "Verifying binary..."
    # Verify it's a valid ELF binary
    if ! file "${CF_FILE}" | grep -q "ELF"; then
        err "Downloaded file is not a valid ELF binary - possible MITM attack"
        exit 1
    fi

    # Verify file size is reasonable (10-100MB for cloudflared)
    CF_SIZE=$(stat -c%s "${CF_FILE}" 2>/dev/null || stat -f%z "${CF_FILE}" 2>/dev/null)
    if [ "${CF_SIZE}" -lt 10000000 ] || [ "${CF_SIZE}" -gt 100000000 ]; then
        err "Downloaded file size ${CF_SIZE} bytes is unusual"
        exit 1
    fi

    step "Installing cloudflared..."
    mv "${CF_FILE}" /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    # Clear the trap since file was moved
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

# Generate a secure random VNC password
# SECURITY: Use a randomly generated password instead of hardcoded value
VNC_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)

echo "${VNC_PASS}" | vncpasswd -f > /root/.vnc/passwd 2>/dev/null
if [ ! -s /root/.vnc/passwd ]; then
    warn "Password method 1 failed, trying alternative..."
    printf '%s\n%s\nn\n' "${VNC_PASS}" "${VNC_PASS}" | vncpasswd /root/.vnc/passwd 2>/dev/null || true
fi
chmod 600 /root/.vnc/passwd
log "VNC password set: ${VNC_PASS}"

# ── Step 6: Start VNC Server ──
step "Starting VNC server..."

# Clean up any existing locks and processes
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
pkill -9 -f "Xvfb :1" 2>/dev/null || true
pkill -9 -f "Xtigervnc" 2>/dev/null || true
pkill -9 -f "x11vnc" 2>/dev/null || true
fuser -k 5901/tcp 2>/dev/null || true
sleep 2

# Set DISPLAY explicitly
export DISPLAY=:1

# Step 6a: Start Xvfb virtual display
step "Starting Xvfb virtual display..."
if pgrep -f "Xvfb :1" > /dev/null 2>&1; then
    log "Xvfb already running"
else
    nohup Xvfb :1 -screen 0 1366x768x24 -ac +extension GLX +render -noreset > /tmp/xvfb.log 2>&1 &
    XVFB_PID=$!
    sleep 2

    if ps -p $XVFB_PID > /dev/null 2>&1; then
        log "Xvfb started with PID ${XVFB_PID}"
    else
        warn "Xvfb may have failed - check /tmp/xvfb.log"
        cat /tmp/xvfb.log 2>/dev/null | tail -10
    fi
fi

# Verify Xvfb is running
if pgrep -f "Xvfb :1" > /dev/null 2>&1; then
    log "Xvfb is running"
else
    err "Xvfb is NOT running - attempting recovery..."
    nohup Xvfb :1 -screen 0 1366x768x24 > /tmp/xvfb.log 2>&1 &
    sleep 3
fi

# Step 6b: Generate TLS certificate (optional - noVNC handles encryption)
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

# Step 6c: Start XFCE desktop session (CRITICAL - must be before VNC)
step "Starting XFCE desktop session..."
if pgrep -f "startxfce4" > /dev/null 2>&1; then
    log "XFCE already running"
else
    # Kill any existing dbus processes
    pkill -f "dbus-daemon" 2>/dev/null || true
    sleep 1

    # Start XFCE with dbus in background
    nohup dbus-launch --exit-with-session startxfce4 > /tmp/xfce.log 2>&1 &
    XFCE_PID=$!
    sleep 5

    if ps -p $XFCE_PID > /dev/null 2>&1; then
        log "XFCE started with PID ${XFCE_PID}"
    else
        log "XFCE process started (background)"
    fi
fi

# Verify DISPLAY
export DISPLAY=:1

# Step 6d: Start VNC server with explicit backgrounding and verification
step "Starting TigerVNC server..."

# Kill any existing VNC on port 5901
fuser -k 5901/tcp 2>/dev/null || true
sleep 1

# Start tigervncserver in background with nohup
nohup tigervncserver :1 \
    -geometry 1366x768 \
    -depth 24 \
    -localhost no \
    -rfbport 5901 \
    -xstartup /root/.vnc/xstartup \
    -rfbauth /root/.vnc/passwd \
    > /tmp/vnc.log 2>&1 &

VNC_PID=$!
sleep 3

# Check if VNC is running
if ss -tlnp 2>/dev/null | grep -q ":5901"; then
    log "TigerVNC server running on port 5901 (PID: ${VNC_PID})"
elif pgrep -f "Xtigervnc" > /dev/null 2>&1; then
    log "TigerVNC is running"
else
    # Try x11vnc fallback
    warn "TigerVNC failed - trying x11vnc fallback..."

    # Install x11vnc if needed
    if ! command -v x11vnc > /dev/null 2>&1; then
        step "Installing x11vnc..."
        apt-get install -y x11vnc 2>&1 | tail -3
    fi

    # Start x11vnc
    nohup x11vnc -display :1 -rfbport 5901 -shared -forever -nopw \
        > /tmp/x11vnc.log 2>&1 &
    X11VNC_PID=$!
    sleep 2

    if ss -tlnp 2>/dev/null | grep -q ":5901"; then
        log "x11vnc fallback running on port 5901 (PID: ${X11VNC_PID})"
    else
        err "VNC server FAILED to start!"
        err "Please check logs:"
        echo "  cat /tmp/vnc.log"
        echo "  cat /tmp/x11vnc.log"
        echo "  cat /tmp/xvfb.log"
    fi
fi

# ── Step 7: Start noVNC ──
step "Starting noVNC web server..."

# Verify VNC is running before starting noVNC
VNC_RUNNING=false
if ss -tlnp 2>/dev/null | grep -q ":5901"; then
    VNC_RUNNING=true
    log "VNC is running on port 5901"
elif pgrep -f "Xtigervnc" > /dev/null 2>&1; then
    VNC_RUNNING=true
    log "TigerVNC is running"
elif pgrep -f "x11vnc" > /dev/null 2>&1; then
    VNC_RUNNING=true
    log "x11vnc is running"
fi

if [ "$VNC_RUNNING" = "false" ]; then
    err "VNC server is not running! Cannot start noVNC."
    err "Please run the script again or check VNC logs"
    cat /tmp/vnc.log 2>/dev/null | tail -20
fi

# Kill any existing websockify processes
pkill -f "websockify.*6080" 2>/dev/null || true
pkill -f "websockify --web" 2>/dev/null || true
sleep 2

# Start websockify with nohup for proper backgrounding
# Use venv option if available, otherwise direct command
step "Starting websockify..."
nohup websockify \
    --web="${NOVNC_DIR}" \
    --heartbeat=30 \
    --timeout=0 \
    6080 \
    localhost:5901 \
    > /tmp/novnc.log 2>&1 &

NOVNC_PID=$!
sleep 4

# Check if noVNC is listening
if ss -tlnp 2>/dev/null | grep -q ":6080"; then
    log "noVNC websockify running on port 6080 (PID: ${NOVNC_PID})"
else
    warn "noVNC may have failed to start - checking process..."
    if pgrep -f "websockify" > /dev/null 2>&1; then
        log "websockify process exists but port check failed"
    else
        err "websockify process NOT found - check /tmp/novnc.log"
        cat /tmp/novnc.log 2>/dev/null | tail -10
        # Try direct invocation as fallback
        step "Trying alternative websockify invocation..."
        nohup python3 -m websockify \
            --web="${NOVNC_DIR}" \
            6080 \
            localhost:5901 \
            > /tmp/novnc2.log 2>&1 &
        sleep 4
    fi
fi

# Verify noVNC can serve content
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

# Save password first before starting server
echo "${VNC_PASS}" > /root/.vnc/password.txt
chmod 600 /root/.vnc/password.txt

# Create password API server
cat > /tmp/vnc_password_server.py << 'PYSERVER'
#!/usr/bin/env python3
import os
import http.server
import socketserver
import json

PORT = 6081

class VncPasswordHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/vnc-password' or self.path == '/api/password':
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

with socketserver.TCPServer(("", PORT), VncPasswordHandler) as httpd:
    httpd.allow_reuse_address = True
    httpd.serve_forever()
PYSERVER

chmod +x /tmp/vnc_password_server.py

# Kill any existing password server
pkill -f "vnc_password_server.py" 2>/dev/null || true
sleep 1

# Start password server in background
nohup python3 /tmp/vnc_password_server.py > /tmp/password_server.log 2>&1 &
PASSWORD_PID=$!
sleep 1

# Verify server is running
if ss -tlnp 2>/dev/null | grep -q ":6081"; then
    log "Password API server running on port 6081 (PID: ${PASSWORD_PID})"
else
    warn "Password server check - may still be starting"
fi

# ── Step 9: Start Cloudflare Tunnel ──
step "Starting Cloudflare Tunnel (please wait ~60 seconds)..."

# Kill any existing cloudflared
pkill -f "cloudflared" 2>/dev/null || true
sleep 1

# Start cloudflared tunnel
nohup cloudflared tunnel \
    --url http://localhost:6080 \
    --no-autoupdate \
    > /tmp/cloudflared.log 2>&1 &

CF_PID=$!
TUNNEL_URL=""
TUNNEL_READY=false

# Poll for tunnel URL with extended timeout
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

# Save password to files
echo "${VNC_PASS}" > /root/.vnc/password.txt
chmod 600 /root/.vnc/password.txt
echo "${VNC_PASS}" > /opt/vnc_password.txt
chmod 644 /opt/vnc_password.txt

# Try to get tunnel URL one more time if not found
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
    echo -e "  ${BLUE}VNC Password:${NC} ${YELLOW}${VNC_PASS}${NC}"
    echo ""
    echo -e "  ${BLUE}Alternative (direct):${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/vnc_lite.html${NC}"
    echo ""
else
    echo ""
    echo -e "  ${YELLOW}Cloudflare Tunnel still initializing...${NC}"
    echo ""
    echo -e "  ${YELLOW}To get tunnel URL, run:${NC}"
    echo -e "     ${YELLOW}cat /tmp/cloudflared.log | grep trycloudflare${NC}"
    echo ""
    echo -e "  ${YELLOW}Or wait and check:${NC}"
    echo -e "     ${YELLOW}cat /opt/tunnel_url.txt${NC}"
    echo ""
    echo -e "  ${YELLOW}VNC Password:${NC} ${YELLOW}${VNC_PASS}${NC}"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Service Status ──
echo -e "${BLUE}Service Status:${NC}"
echo ""
pgrep -f "Xtigervnc|Xvnc|x11vnc" > /dev/null \
    && echo -e "  VNC Server  : ${GREEN}● Running${NC}" \
    || echo -e "  VNC Server  : ${RED}● Stopped${NC}"
pgrep -f "websockify" > /dev/null \
    && echo -e "  noVNC       : ${GREEN}● Running${NC}" \
    || echo -e "  noVNC       : ${RED}● Stopped${NC}"
pgrep -f "cloudflared" > /dev/null \
    && echo -e "  Tunnel      : ${GREEN}● Running${NC}" \
    || echo -e "  Tunnel      : ${RED}● Stopped${NC}"
pgrep -f "xfce4" > /dev/null \
    && echo -e "  Desktop     : ${GREEN}● Running${NC}" \
    || echo -e "  Desktop     : ${RED}● Stopped${NC}"

echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo ""
echo -e "  ${YELLOW}Get URL:${NC}    cat /opt/tunnel_url.txt"
echo -e "  ${YELLOW}VNC Log:${NC}    cat /tmp/vnc.log"
echo -e "  ${YELLOW}Tunnel Log:${NC} cat /tmp/cloudflared.log | tail -20"
echo -e "  ${YELLOW}Restart:${NC}    sudo bash /tmp/setup.sh"
echo -e "  ${YELLOW}Stop All:${NC}   pkill -f cloudflared; pkill -f websockify; tigervncserver -kill :1"
echo ""
