#!/bin/bash
# Cloud Linux GUI - service status
# Works with both systemd-managed and nohup-managed installations

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}● Running${NC}  $1"; }
bad()  { echo -e "  ${RED}● Stopped${NC} $1"; }
maybe(){ echo -e "  ${YELLOW}● Unknown${NC} $1"; }

PID_DIR="/tmp/cloud-gui-pids"
VNC_PORT="${VNC_PORT:-5901}"

pid_alive() {
    local pidfile="$PID_DIR/$1"
    [ -f "$pidfile" ] || return 1
    local pid
    pid=$(cat "$pidfile" 2>/dev/null)
    [ -n "$pid" ] && [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null
}

port_listening() {
    ss -tlnp 2>/dev/null | grep -qE ":$1\b"
}

systemd_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

USE_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1 && \
   systemctl list-unit-files "cloud-gui-*" --no-legend 2>/dev/null | grep -q .; then
    USE_SYSTEMD=true
fi

echo ""
echo -e "${BLUE}═══════════ Cloud Linux GUI Status ═══════════${NC}"
echo ""

if [ "$USE_SYSTEMD" = true ]; then
    echo -e "${BLUE}Mode:${NC} systemd"
    echo ""
    for unit in xvfb desktop vnc novnc password-api tunnel; do
        if systemd_active "cloud-gui-${unit}"; then ok "$unit"; else bad "$unit"; fi
    done
else
    echo -e "${BLUE}Mode:${NC} nohup (no auto-restart)"
    echo ""
    { pid_alive xvfb || pid_alive xfce; } && ok "desktop (xvfb/xfce)" || bad "desktop (xvfb/xfce)"
    { pid_alive vnc || pid_alive x11vnc || pid_alive tigervnc; } && ok "vnc server" || bad "vnc server"
    pid_alive websockify && ok "websockify" || bad "websockify"
    pid_alive password_server && ok "password api" || bad "password api"
    pid_alive cloudflared && ok "cloudflared" || bad "cloudflared"
fi

echo ""
echo -e "${BLUE}Ports:${NC}"
port_listening "$VNC_PORT" && echo -e "  VNC        :${VNC_PORT}  ${GREEN}listening${NC}" || echo -e "  VNC        :${VNC_PORT}  ${RED}not listening${NC}"
port_listening 6080       && echo -e "  noVNC      :6080  ${GREEN}listening${NC}" || echo -e "  noVNC      :6080  ${RED}not listening${NC}"
port_listening 6081       && echo -e "  PasswordAPI:6081  ${GREEN}listening${NC}" || echo -e "  PasswordAPI:6081  ${RED}not listening${NC}"

echo ""
TUNNEL_URL=""
[ -s /opt/tunnel_url.txt ] && TUNNEL_URL=$(cat /opt/tunnel_url.txt)
if [ -z "$TUNNEL_URL" ]; then
    TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
fi
if [ -n "$TUNNEL_URL" ]; then
    echo -e "${BLUE}Desktop URL:${NC} ${GREEN}${TUNNEL_URL}/desktop.html${NC}"
else
    echo -e "${BLUE}Desktop URL:${NC} ${YELLOW}(tunnel URL not found yet)${NC}"
fi

echo ""
if [ -s /root/.vnc/password.txt ]; then
    echo -e "${BLUE}VNC password:${NC} /root/.vnc/password.txt (or /opt/vnc_password.txt)"
else
    echo -e "${BLUE}VNC password:${NC} ${RED}not set${NC}"
fi

echo ""
echo -e "${BLUE}Recent errors (last log lines):${NC}"
for f in xvfb xfce x11vnc novnc cloudflared; do
    if [ -f "/tmp/${f}.log" ]; then
        last=$(tail -3 "/tmp/${f}.log" 2>/dev/null | grep -iE "error|fail|fatal" | tail -1)
        [ -n "$last" ] && echo -e "  ${YELLOW}${f}.log:${NC} $last"
    fi
done
echo ""
