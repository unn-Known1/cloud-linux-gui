#!/bin/bash
set -e

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
    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" \
        -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    log "Cloudflared downloaded and installed"
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

VNC_PASS="desktop123"

echo "${VNC_PASS}" | vncpasswd -f > /root/.vnc/passwd 2>/dev/null
if [ ! -s /root/.vnc/passwd ]; then
    warn "Password method 1 failed, trying alternative..."
    printf '%s\n%s\nn\n' "${VNC_PASS}" "${VNC_PASS}" | vncpasswd /root/.vnc/passwd 2>/dev/null || true
fi
chmod 600 /root/.vnc/passwd
log "VNC password set: ${VNC_PASS}"

# ── Step 6: Start VNC Server ──
step "Starting VNC server..."
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

tigervncserver :1 \
    -geometry 1366x768 \
    -depth 24 \
    -localhost yes \
    -rfbport 5901 \
    -xstartup /root/.vnc/xstartup \
    -rfbauth /root/.vnc/passwd \
    > /tmp/vnc.log 2>&1 || {
    warn "tigervncserver failed, trying Xvfb + x11vnc fallback..."
    apt-get install -y x11vnc 2>/dev/null | tail -2
    Xvfb :1 -screen 0 1366x768x24 &
    sleep 2
    export DISPLAY=:1
    dbus-launch startxfce4 &
    sleep 3
    x11vnc -display :1 -rfbport 5901 -shared -forever -nopw > /tmp/x11vnc.log 2>&1 &
    sleep 2
}

sleep 3

if ss -tlnp | grep -q ":5901"; then
    log "VNC server running on port 5901"
else
    err "VNC server NOT listening on port 5901"
    warn "VNC log output:"
    cat /tmp/vnc.log 2>/dev/null
fi

# ── Step 7: Start noVNC ──
step "Starting noVNC web server..."

nohup websockify \
    --web="${NOVNC_DIR}" \
    --heartbeat=30 \
    6080 \
    localhost:5901 \
    > /tmp/novnc.log 2>&1 &

sleep 3

if ss -tlnp | grep -q ":6080"; then
    log "noVNC running on port 6080"
else
    err "noVNC failed to start"
    cat /tmp/novnc.log 2>/dev/null
    exit 1
fi

# ── Step 8: Test local connection ──
step "Testing local web server..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:6080/ 2>/dev/null || echo "000")
if [ "${HTTP_CODE}" = "200" ]; then
    log "Web server responding (HTTP 200)"
else
    warn "Web server returned HTTP ${HTTP_CODE} (may still work)"
fi

# ── Step 9: Start Cloudflare Tunnel ──
step "Starting Cloudflare Tunnel (please wait ~30 seconds)..."

nohup cloudflared tunnel \
    --url http://localhost:6080 \
    --no-autoupdate \
    > /tmp/cloudflared.log 2>&1 &

CF_PID=$!
TUNNEL_URL=""

for i in $(seq 1 30); do
    sleep 2

    if ! kill -0 ${CF_PID} 2>/dev/null; then
        err "Cloudflared process crashed!"
        cat /tmp/cloudflared.log | tail -20
        exit 1
    fi

    TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
    if [ -n "${TUNNEL_URL}" ]; then
        break
    fi

    printf "."
done
echo ""

# ── Step 10: Final Output ──
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"

if [ -n "${TUNNEL_URL}" ]; then
    echo ""
    echo -e "  ${GREEN}🎉 SUCCESS! Your Linux Desktop is ready!${NC}"
    echo ""
    echo -e "  ${BLUE}📺 Desktop URL:${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/vnc_lite.html${NC}"
    echo ""
    echo -e "  ${BLUE}🔑 VNC Password:${NC} ${YELLOW}${VNC_PASS}${NC}"
    echo ""
    echo -e "  ${BLUE}📺 Alternative (auto-connect):${NC}"
    echo -e "     ${GREEN}${TUNNEL_URL}/vnc.html?autoconnect=true${NC}"
    echo ""
    echo "${TUNNEL_URL}" > /opt/tunnel_url.txt
else
    err "Tunnel URL not found after 60 seconds"
    echo ""
    echo -e "  ${YELLOW}Check manually:${NC}"
    echo -e "     grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log"
    echo ""
    echo -e "  ${YELLOW}Local access:${NC}"
    echo -e "     http://localhost:6080/vnc_lite.html"
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
