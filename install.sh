#!/bin/bash

###############################################################################
# Cloud Linux GUI - One-Command Installation
# Full Linux Desktop with GUI accessible from any browser via Cloudflare Tunnel
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="$SCRIPT_DIR/noVNC"
VNC_PORT=5901
NOVNC_PORT=6080
CLOUD_USER="cloudlinux"
RUN_AS_USER="${RUN_AS_USER:-$CLOUD_USER}"

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}Cloud Linux GUI - Full Linux Desktop in Browser${NC}  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_step()    { echo -e "${YELLOW}[*] $1${NC}"; }
print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error()   { echo -e "${RED}[✗] $1${NC}"; }
print_warning()  { echo -e "${YELLOW}[!] $1${NC}"; }

detect_os() {
    print_step "Detecting system..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS="unknown"
    fi
    print_success "Detected: $OS $VER"
}

install_dependencies() {
    print_step "Installing dependencies..."
    if command -v apt-get &> /dev/null; then
        apt-get update -qq 2>/dev/null || true
        apt-get install -y \
            xfce4 xfce4-goodies xorg dbus-x11 \
            tigervnc-standalone-server tigervnc-common \
            xvfb x11-apps x11-utils \
            websockify \
            curl wget git nano vim \
            fonts-noto-cjk 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        yum install -y \
            xfce4-session dbus-x11 tigervnc-server \
            xorg-x11-server-Xvfb \
            xorg-x11-apps xorg-x11-utils \
            websockify \
            curl wget git nano vim 2>/dev/null || true
    elif command -v dnf &> /dev/null; then
        dnf install -y \
            xfce4-session dbus-x11 tigervnc-server \
            xorg-x11-server-Xvfb \
            xorg-x11-apps xorg-x11-utils \
            websockify \
            curl wget git nano vim 2>/dev/null || true
    fi
    print_success "Dependencies installed"
}

install_cloudflared() {
    print_step "Installing Cloudflare Tunnel..."
    if command -v cloudflared &> /dev/null; then
        print_success "Cloudflared already installed"
        return
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)          CLOUDFLARED_ARCH="amd64" ;;
        aarch64|arm64)   CLOUDFLARED_ARCH="arm64" ;;
        armv7l)          CLOUDFLARED_ARCH="arm" ;;
        *)               CLOUDFLARED_ARCH="amd64" ;;
    esac

    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"
    curl -sL "$CLOUDFLARED_URL" -o /tmp/cloudflared 2>/dev/null || \
        wget -q "$CLOUDFLARED_URL" -O /tmp/cloudflared

    if [ -f /tmp/cloudflared ]; then
        chmod +x /tmp/cloudflared
        mv /tmp/cloudflared /usr/local/bin/cloudflared
        print_success "Cloudflared installed"
    else
        print_error "Failed to download cloudflared"
        exit 1
    fi
}

install_novnc() {
    print_step "Installing noVNC from GitHub..."
    mkdir -p "$NOVNC_DIR"
    if [ -d "$NOVNC_DIR/.git" ]; then
        cd "$NOVNC_DIR" && git pull 2>/dev/null || true
    else
        git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || {
            curl -sL https://github.com/novnc/noVNC/archive/refs/heads/master.tar.gz -o /tmp/novnc.tar.gz
            if [ -f /tmp/novnc.tar.gz ]; then
                tar -xzf /tmp/novnc.tar.gz -C "$SCRIPT_DIR"
                mv "$SCRIPT_DIR/noVNC-master" "$NOVNC_DIR"
                rm -f /tmp/novnc.tar.gz
            fi
        }
    fi

    if [ -d "$NOVNC_DIR" ] && [ -f "$NOVNC_DIR/core/rfb.js" ]; then
        print_success "noVNC installed"
    else
        print_error "Failed to install noVNC"
        exit 1
    fi
}

create_vnc_page() {
    print_step "Creating VNC page..."

    cat > "$NOVNC_DIR/vnc.html" << 'VNC_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Cloud Linux GUI - Desktop</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background: #1a1a2e; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
        #loading {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(135deg, #0f0f1a 0%, #1a1a2e 100%);
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            z-index: 1000; transition: opacity 0.5s ease;
        }
        #loading.hidden { opacity: 0; pointer-events: none; }
        .logo { font-size: 100px; animation: pulse 2s infinite; }
        @keyframes pulse { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.1); } }
        .title { color: #fff; font-size: 2rem; margin-top: 20px; background: linear-gradient(90deg, #00d4ff, #7b2cbf); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .subtitle { color: #888; font-size: 1rem; margin-top: 10px; }
        .spinner { width: 50px; height: 50px; border: 3px solid rgba(255,255,255,0.1); border-top-color: #00d4ff; border-radius: 50%; animation: spin 1s linear infinite; margin-top: 30px; }
        @keyframes spin { to { transform: rotate(360deg); } }
        #screen { position: fixed; top: 0; left: 0; width: 100%; height: 100%; }
        #url-bar {
            position: fixed; top: 15px; left: 50%; transform: translateX(-50%);
            background: rgba(26,26,46,0.95); backdrop-filter: blur(10px); border-radius: 25px;
            padding: 12px 25px; color: #00d4ff; font-size: 14px; z-index: 100;
            border: 1px solid rgba(0,212,255,0.3); display: flex; align-items: center; gap: 10px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        }
        .dot { width: 8px; height: 8px; background: #00ff00; border-radius: 50%; animation: pulse-dot 1s infinite; }
        @keyframes pulse-dot { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
        #controls { position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%); display: flex; gap: 15px; z-index: 100; }
        .btn {
            width: 55px; height: 55px; border-radius: 50%; border: none;
            background: linear-gradient(135deg, rgba(0,212,255,0.2), rgba(123,44,191,0.2));
            backdrop-filter: blur(10px); color: #fff; font-size: 22px; cursor: pointer;
            transition: all 0.3s ease; display: flex; align-items: center; justify-content: center;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.1);
        }
        .btn:hover { transform: scale(1.15); }
        .btn:active { transform: scale(0.95); }
        .toast { position: fixed; top: 80px; left: 50%; transform: translateX(-50%); background: rgba(0,255,0,0.9); color: #000; padding: 12px 24px; border-radius: 25px; font-size: 14px; z-index: 200; opacity: 0; transition: opacity 0.3s; }
        .toast.show { opacity: 1; }
    </style>
</head>
<body>
    <div id="loading">
        <div class="logo">🖥️</div>
        <div class="title">Cloud Linux GUI</div>
        <div class="subtitle">Establishing secure connection...</div>
        <div class="spinner"></div>
    </div>
    <div id="screen" tabindex="0"></div>
    <div id="url-bar">
        <span class="dot"></span>
        <span id="current-url">Connecting...</span>
    </div>
    <div id="controls">
        <button class="btn" onclick="toggleFullscreen()" title="Fullscreen">⛶</button>
        <button class="btn" onclick="sendCtrlAltDel()" title="Ctrl+Alt+Del">⌨️</button>
        <button class="btn" onclick="doRefresh()" title="Refresh">🔄</button>
    </div>
    <div id="toast" class="toast"></div>

    <script type="module">
        import RFB from './core/rfb.js';

        let rfb;

        function getWebSocketURL() {
            const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
            const host  = window.location.hostname;
            const port  = window.location.port ? `:${window.location.port}` : '';
            return `${proto}://${host}${port}/websockify`;
        }

        function connect() {
            const screen = document.getElementById('screen');
            const url = getWebSocketURL();
            document.getElementById('current-url').textContent = window.location.href;

            try {
                rfb = new RFB(screen, url, {
                    credentials: { password: '' },
                    reconnect: true,
                    reconnectDelay: 2000,
                });

                rfb.addEventListener('connect', () => {
                    document.getElementById('loading').classList.add('hidden');
                    rfb.scaleViewport = true;
                    rfb.resizeSession = true;
                });

                rfb.addEventListener('disconnect', (e) => {
                    document.getElementById('loading').classList.remove('hidden');
                    document.querySelector('.subtitle').textContent =
                        e.detail.clean ? 'Disconnected. Reconnecting...' : 'Connection lost. Retrying...';
                });

            } catch (e) {
                console.error('RFB error:', e);
                document.querySelector('.subtitle').textContent = 'Failed to connect. Retrying in 3s...';
                setTimeout(connect, 3000);
            }
        }

        function toggleFullscreen() {
            if (!document.fullscreenElement) document.documentElement.requestFullscreen();
            else document.exitFullscreen();
        }

        function sendCtrlAltDel() {
            if (rfb) { rfb.sendCtrlAltDel(); showToast('Ctrl+Alt+Del sent'); }
        }

        function doRefresh() {
            if (rfb) rfb.disconnect();
            setTimeout(connect, 1000);
        }

        function showToast(msg) {
            const t = document.getElementById('toast');
            t.textContent = msg;
            t.classList.add('show');
            setTimeout(() => t.classList.remove('show'), 2000);
        }

        window.toggleFullscreen = toggleFullscreen;
        window.sendCtrlAltDel  = sendCtrlAltDel;
        window.doRefresh        = doRefresh;

        window.addEventListener('load', connect);
    </script>
</body>
</html>
VNC_EOF

    print_success "VNC page created"
}

create_service_user() {
    print_step "Creating dedicated service user for security..."

    # Check if running as root
    if [ "$(id -u)" -eq 0 ]; then
        # Create user if it doesn't exist
        if ! id "$RUN_AS_USER" &>/dev/null; then
            useradd -m -s /bin/bash "$RUN_AS_USER" 2>/dev/null || true
            print_success "Created user: $RUN_AS_USER"
        else
            print_success "User $RUN_AS_USER already exists"
        fi

        # Add user to video group for X11/VNC
        usermod -aG video,render,dialout "$RUN_AS_USER" 2>/dev/null || true

        # Create directories and set permissions
        mkdir -p /opt/cloud-linux-gui
        chown -R "$RUN_AS_USER:$RUN_AS_USER" /opt/cloud-linux-gui 2>/dev/null || true

        # Set HOME for the user
        eval "echo ~$RUN_AS_USER" > /dev/null 2>/dev/null || true
    else
        print_warning "Not running as root - cannot create service user"
        print_warning "Set RUN_AS_USER environment variable to specify a user"
    fi
}

setup_vnc() {
    print_step "Setting up VNC server..."

    # Set target home directory
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        TARGET_HOME=$(eval "echo ~$RUN_AS_USER" 2>/dev/null || echo "/root")
        VNC_HOME_DIR="$TARGET_HOME"
    else
        VNC_HOME_DIR="$HOME"
    fi

    mkdir -p "$VNC_HOME_DIR/.vnc"


    cat > "$VNC_HOME_DIR/.vnc/xstartup" << 'VNC_EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
dbus-launch --exit-with-session startxfce4 &
exec startxfce4
VNC_EOF
    chmod +x "$VNC_HOME_DIR/.vnc/xstartup"

    # Generate secure random VNC password
    # Use environment variable if set, otherwise generate a secure random password
    if [ -n "$VNC_PASSWORD" ]; then
        VNC_PASS="$VNC_PASSWORD"
        print_success "Using VNC_PASSWORD from environment"
    else
        # Generate a secure random 12-character password using /dev/urandom
        VNC_PASS=$(head -c 100 /dev/urandom | tr -dc 'A-Za-z0-9!@#$%' | head -c 12)
        print_success "Generated secure random VNC password"
    fi

    # Set permissions for .vnc directory
    mkdir -p "$VNC_HOME_DIR/.vnc"
    chmod 700 "$VNC_HOME_DIR/.vnc"

    # Create VNC password file
    printf '\n%s\n%s\n' "$VNC_PASS" "$VNC_PASS" | vncpasswd -f > "$VNC_HOME_DIR/.vnc/passwd" 2>/dev/null || true
    chmod 600 "$VNC_HOME_DIR/.vnc/passwd"

    print_success "VNC configured with secure password"
    echo ""
    print_warning "IMPORTANT: Your VNC password is: $VNC_PASS"
    print_warning "Please save this password securely - it will not be shown again."
    echo ""
}

kill_all() {
    pkill -9 -f "Xvfb"        2>/dev/null || true
    pkill -9 -f "Xtigervnc"   2>/dev/null || true
    pkill -9 -f "vncserver"   2>/dev/null || true
    pkill -9 -f "websockify"  2>/dev/null || true
    pkill -9 -f "cloudflared" 2>/dev/null || true
    sleep 2
}

start_services() {
    print_step "Starting VNC server..."

    kill_all

    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
    rm -f /tmp/.X2-lock /tmp/.X11-unix/X2 2>/dev/null || true
    sleep 1

    XVFB_DISPLAY=:99
    export DISPLAY=$XVFB_DISPLAY

    # Function to run command as non-root user if possible
    run_as_user() {
        if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
            su - "$RUN_AS_USER" -c "export DISPLAY=$XVFB_DISPLAY; $1"
        else
            eval "$1"
        fi
    }

    # Start Xvfb
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        # Run as non-root user
        su - "$RUN_AS_USER" -c "Xvfb $XVFB_DISPLAY -screen 0 1920x1080x24 -ac +extension GLX +render -noreset" > /dev/null 2>&1 &
    else
        Xvfb $XVFB_DISPLAY -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
    fi
    sleep 3

    if ! pgrep -f "Xvfb $XVFB_DISPLAY" > /dev/null; then
        print_error "Failed to start Xvfb"
        exit 1
    fi
    print_success "Xvfb started on display $XVFB_DISPLAY"

    # Set target home for VNC
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        VNC_TARGET_HOME=$(eval "echo ~$RUN_AS_USER" 2>/dev/null || echo "/root")
    else
        VNC_TARGET_HOME="$HOME"
    fi

    # Start VNC server
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        # Run as non-root user
        su - "$RUN_AS_USER" -c "tigervncserver :1 -geometry 1920x1080 -depth 24 -xstartup $VNC_TARGET_HOME/.vnc/xstartup -localhost no -rfbport $VNC_PORT -rfbauth $VNC_TARGET_HOME/.vnc/passwd" > /tmp/vnc.log 2>&1 || true
    else
        tigervncserver :1 \
            -geometry 1920x1080 \
            -depth 24 \
            -xstartup "$VNC_TARGET_HOME/.vnc/xstartup" \
            -localhost no \
            -rfbport $VNC_PORT \
            -rfbauth "$VNC_TARGET_HOME/.vnc/passwd" \
            > /tmp/vnc.log 2>&1 || true
    fi
    sleep 3

    if ! pgrep -f "Xtigervnc.*:1" > /dev/null; then
        print_error "VNC server failed to start"
        cat /tmp/vnc.log 2>/dev/null
        exit 1
    fi
    print_success "VNC server started on :1 (port $VNC_PORT)"
}

start_novnc() {
    print_step "Starting noVNC..."

    pkill -f "websockify" 2>/dev/null || true
    sleep 1

    nohup websockify \
        --web="$NOVNC_DIR" \
        --heartbeat=30 \
        $NOVNC_PORT \
        localhost:$VNC_PORT \
        > /tmp/novnc.log 2>&1 &

    sleep 3

    if pgrep -f "websockify" > /dev/null; then
        print_success "noVNC started on port $NOVNC_PORT"
    else
        print_error "noVNC failed to start"
        cat /tmp/novnc.log 2>/dev/null
        exit 1
    fi
}

start_tunnel() {
    print_step "Starting Cloudflare Tunnel..."

    pkill -f "cloudflared" 2>/dev/null || true
    sleep 1

    nohup cloudflared tunnel \
        --url http://localhost:$NOVNC_PORT \
        --logfile /tmp/cloudflared.log \
        > /tmp/tunnel.log 2>&1 &

    TUNNEL_URL=""
    for i in $(seq 1 20); do
        sleep 2
        TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
        [ -n "$TUNNEL_URL" ] && break
    done

    mkdir -p "$SCRIPT_DIR"

    if [ -n "$TUNNEL_URL" ]; then
        echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  🎉 CLOUDFLARE TUNNEL READY!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${BLUE}Access your Linux Desktop:${NC}"
        echo -e "  ${GREEN}${TUNNEL_URL}/vnc_lite.html${NC}"
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        print_error "Failed to get tunnel URL"
        tail -20 /tmp/tunnel.log 2>/dev/null
    fi
}

create_scripts() {
    print_step "Creating management scripts..."
    mkdir -p "$SCRIPT_DIR"

    cat > "$SCRIPT_DIR/tunnel.sh" << 'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="/opt/cloud-linux-gui"
VNC_PORT=5901
NOVNC_PORT=6080

kill_all() {
    pkill -9 -f "Xvfb"        2>/dev/null || true
    pkill -9 -f "Xtigervnc"   2>/dev/null || true
    pkill -9 -f "vncserver"   2>/dev/null || true
    pkill -9 -f "websockify"  2>/dev/null || true
    pkill -9 -f "cloudflared" 2>/dev/null || true
    sleep 2
}

case "$1" in
    start)
        kill_all
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
    rm -f /tmp/.X2-lock /tmp/.X11-unix/X2 2>/dev/null || true
    sleep 1
        export DISPLAY=:99
        Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
        sleep 3
        tigervncserver :1 -geometry 1920x1080 -depth 24 \
            -xstartup ~/.vnc/xstartup -localhost no -rfbport $VNC_PORT \
            -rfbauth ~/.vnc/passwd > /tmp/vnc.log 2>&1 || true
        sleep 2
        websockify --web="$SCRIPT_DIR/noVNC" --heartbeat=30 $NOVNC_PORT localhost:$VNC_PORT > /tmp/novnc.log 2>&1 &
        sleep 2
        cloudflared tunnel --url http://localhost:$NOVNC_PORT --logfile /tmp/cloudflared.log > /tmp/tunnel.log 2>&1 &
        sleep 15
        URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
        [ -n "$URL" ] && echo "${URL}/vnc.html" || echo "Tunnel URL not found yet, check /tmp/cloudflared.log"
        ;;
    stop)
        kill_all
        echo "All services stopped"
        ;;
    url)
        cat "$SCRIPT_DIR/tunnel_url.txt" 2>/dev/null && echo "/vnc.html" || echo "Run './tunnel.sh start' first"
        ;;
    status)
        echo "=== Service Status ==="
        pgrep -f "Xvfb :99"        > /dev/null && echo "Xvfb:        Running" || echo "Xvfb:        Stopped"
        pgrep -f "Xtigervnc.*:1"   > /dev/null && echo "VNC:         Running" || echo "VNC:         Stopped"
        pgrep -f "websockify"       > /dev/null && echo "noVNC:       Running" || echo "noVNC:       Stopped"
        pgrep -f "cloudflared"      > /dev/null && echo "Cloudflare:  Running" || echo "Cloudflare:  Stopped"
        ;;
    *)
        echo "Usage: $0 {start|stop|url|status}"
        ;;
esac
SCRIPT_EOF

    chmod +x "$SCRIPT_DIR/tunnel.sh"
    print_success "Scripts created"
}

display_status() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ✅ INSTALLATION COMPLETE!                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ -f "$SCRIPT_DIR/tunnel_url.txt" ]; then
        URL=$(cat "$SCRIPT_DIR/tunnel_url.txt")
        echo -e "  ${GREEN}${URL}/vnc.html${NC}"
        echo ""
    fi
    echo -e "  ${YELLOW}Commands:${NC}"
    echo -e "  Restart : ${BLUE}$SCRIPT_DIR/tunnel.sh start${NC}"
    echo -e "  Stop    : ${BLUE}$SCRIPT_DIR/tunnel.sh stop${NC}"
    echo -e "  Status  : ${BLUE}$SCRIPT_DIR/tunnel.sh status${NC}"
    echo -e "  Get URL : ${BLUE}$SCRIPT_DIR/tunnel.sh url${NC}"
    echo ""
}

main() {
    print_header
    detect_os
    install_dependencies
    install_cloudflared
    install_novnc
    create_vnc_page
    setup_vnc
    start_services
    start_novnc
    create_scripts
    start_tunnel
    display_status
}

main "$@"
