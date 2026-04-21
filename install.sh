#!/bin/bash

###############################################################################
# Cloud Linux GUI - One-Command Installation
# Full Linux Desktop with GUI accessible from any browser via Cloudflare Tunnel
###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="$SCRIPT_DIR/noVNC"
VNC_PORT=5901
NOVNC_PORT=6080

# Print functions
print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}Cloud Linux GUI - Full Linux Desktop in Browser${NC}  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_step() {
    echo -e "${YELLOW}[*] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

# Kill all existing services
cleanup_services() {
    print_step "Cleaning up existing services..."
    pkill -9 -f "Xvfb" 2>/dev/null || true
    pkill -9 -f "vncserver" 2>/dev/null || true
    pkill -9 -f "tigervnc" 2>/dev/null || true
    pkill -9 -f "websockify" 2>/dev/null || true
    pkill -9 -f "cloudflared" 2>/dev/null || true
    sleep 2
}

# Detect OS
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

# Install required packages
install_dependencies() {
    print_step "Installing dependencies..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y \
            xfce4 xfce4-goodies xorg dbus-x11 \
            tigervnc-standalone-server tigervnc-common \
            websockify \
            curl wget git nano vim \
            fonts-noto-cjk 2>/dev/null || {
            sudo apt-get install -y \
                xfce4 xfce4-goodies xorg dbus-x11 \
                tightvncserver websockify \
                curl wget git nano vim \
                fonts-noto-cjk 2>/dev/null || true
        }
    elif command -v yum &> /dev/null; then
        sudo yum install -y \
            xfce4-session dbus-x11 \
            tigervnc-server \
            websockify \
            curl wget git nano vim 2>/dev/null || true
    fi

    print_success "Dependencies installed"
}

# Install Cloudflare Tunnel
install_cloudflared() {
    print_step "Installing Cloudflare Tunnel..."

    if command -v cloudflared &> /dev/null; then
        print_success "Cloudflared already installed"
        return
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64) CLOUDFLARED_ARCH="amd64" ;;
        aarch64|arm64) CLOUDFLARED_ARCH="arm64" ;;
        armv7l) CLOUDFLARED_ARCH="arm" ;;
        *) CLOUDFLARED_ARCH="amd64" ;;
    esac

    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"

    curl -sL "$CLOUDFLARED_URL" -o /tmp/cloudflared 2>/dev/null || wget -q "$CLOUDFLARED_URL" -O /tmp/cloudflared

    if [ -f /tmp/cloudflared ]; then
        chmod +x /tmp/cloudflared
        sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
        print_success "Cloudflared installed"
    else
        print_error "Failed to download cloudflared"
        exit 1
    fi
}

# Install noVNC from GitHub
install_novnc() {
    print_step "Installing noVNC from GitHub..."

    sudo mkdir -p "$NOVNC_DIR"

    if [ -d "$NOVNC_DIR/.git" ]; then
        cd "$NOVNC_DIR" && git pull 2>/dev/null || true
    else
        git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || {
            curl -sL https://github.com/novnc/noVNC/archive/refs/heads/master.tar.gz -o /tmp/novnc.tar.gz
            if [ -f /tmp/novnc.tar.gz ]; then
                tar -xzf /tmp/novnc.tar.gz -C "$SCRIPT_DIR"
                sudo mv "$SCRIPT_DIR/noVNC-master" "$NOVNC_DIR"
                rm -f /tmp/novnc.tar.gz
            fi
        }
    fi

    if [ -d "$NOVNC_DIR" ] && [ -f "$NOVNC_DIR/vnc.html" ]; then
        print_success "noVNC installed"
    else
        print_error "Failed to install noVNC"
        exit 1
    fi
}

# Create custom vnc.html with proper connection
create_vnc_page() {
    print_step "Creating VNC page..."

    sudo tee "$NOVNC_DIR/vnc.html" > /dev/null << 'VNC_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Cloud Linux GUI - Desktop</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #1a1a2e;
            overflow: hidden;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        #loading {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: linear-gradient(135deg, #0f0f1a 0%, #1a1a2e 100%);
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            transition: opacity 0.5s ease;
        }
        #loading.hidden { opacity: 0; pointer-events: none; }
        .logo { font-size: 100px; animation: pulse 2s infinite; }
        @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.1); }
        }
        .title {
            color: #fff;
            font-size: 2rem;
            margin-top: 20px;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle { color: #888; font-size: 1rem; margin-top: 10px; }
        .spinner {
            width: 50px; height: 50px;
            border: 3px solid rgba(255,255,255,0.1);
            border-top-color: #00d4ff;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-top: 30px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
        #screen {
            position: fixed;
            top: 0; left: 0;
            width: 100%; height: 100%;
        }
        #url-bar {
            position: fixed;
            top: 15px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(26, 26, 46, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 25px;
            padding: 12px 25px;
            color: #00d4ff;
            font-size: 14px;
            z-index: 100;
            border: 1px solid rgba(0, 212, 255, 0.3);
            display: flex;
            align-items: center;
            gap: 10px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
        }
        .dot {
            width: 8px; height: 8px;
            background: #00ff00;
            border-radius: 50%;
            animation: pulse-dot 1s infinite;
        }
        @keyframes pulse-dot { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
        #controls {
            position: fixed;
            bottom: 20px;
            left: 50%;
            transform: translateX(-50%);
            display: flex;
            gap: 15px;
            z-index: 100;
        }
        .btn {
            width: 55px; height: 55px;
            border-radius: 50%;
            border: none;
            background: linear-gradient(135deg, rgba(0, 212, 255, 0.2), rgba(123, 44, 191, 0.2));
            backdrop-filter: blur(10px);
            color: #fff;
            font-size: 22px;
            cursor: pointer;
            transition: all 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .btn:hover { transform: scale(1.15); }
        .btn:active { transform: scale(0.95); }
        .btn.connected { border-color: #00ff00; box-shadow: 0 0 15px rgba(0, 255, 0, 0.3); }
        #mobile-keys {
            position: fixed;
            bottom: 90px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(26, 26, 46, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 10px;
            display: none;
            gap: 8px;
            z-index: 100;
            flex-wrap: wrap;
            max-width: 95%;
            justify-content: center;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
        }
        .key {
            padding: 8px 14px;
            border: 1px solid rgba(255, 255, 255, 0.1);
            background: rgba(255, 255, 255, 0.05);
            color: #fff;
            border-radius: 8px;
            font-size: 13px;
            cursor: pointer;
            transition: all 0.2s;
        }
        .key:hover { background: rgba(0, 212, 255, 0.2); border-color: #00d4ff; }
        .toast {
            position: fixed;
            top: 80px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0, 255, 0, 0.9);
            color: #000;
            padding: 12px 24px;
            border-radius: 25px;
            font-size: 14px;
            z-index: 200;
            opacity: 0;
            transition: opacity 0.3s;
        }
        .toast.show { opacity: 1; }
        @media (max-width: 768px) {
            #mobile-keys { display: flex; }
            #controls { bottom: 160px; }
        }
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
        <button class="btn" onclick="copyUrl()" style="width:35px;height:35px;font-size:14px;">📋</button>
    </div>

    <div id="controls">
        <button class="btn" onclick="toggleFullscreen()" title="Fullscreen">⛶</button>
        <button class="btn" onclick="sendCtrlAltDel()" title="Ctrl+Alt+Del">⌨️</button>
        <button class="btn" onclick="toggleKeyboard()" title="Toggle Keyboard">⌨️</button>
        <button class="btn" onclick="refresh()" title="Refresh">🔄</button>
        <button class="btn" onclick="showKeyboard()" title="Keyboard">⌨️</button>
    </div>

    <div id="mobile-keys">
        <button class="key" onclick="sendKey('Escape')">ESC</button>
        <button class="key" onclick="sendKey('Tab')">TAB</button>
        <button class="key" onclick="sendKey('Control_L')">CTRL</button>
        <button class="key" onclick="sendKey('Alt_L')">ALT</button>
        <button class="key" onclick="sendKey('Shift_L')">SHIFT</button>
        <button class="key" onclick="sendKey('Enter')">ENTER</button>
        <button class="key" onclick="sendKey('BackSpace')">⌫</button>
        <button class="key" onclick="sendKey('ArrowUp')">↑</button>
        <button class="key" onclick="sendKey('ArrowDown')">↓</button>
        <button class="key" onclick="sendKey('ArrowLeft')">←</button>
        <button class="key" onclick="sendKey('ArrowRight')">→</button>
    </div>

    <div id="toast" class="toast">Copied!</div>

    <script type="module">
        import RFB from './core/rfb.js';

        let rfb;
        let connected = false;

        function getCurrentURL() {
            const url = window.location.href;
            document.getElementById('current-url').textContent = url;
            return url;
        }

        function connect() {
            const screen = document.getElementById('screen');
            const host = window.location.hostname;
            const port = window.location.port || (window.location.protocol === 'https:' ? 443 : 80);

            try {
                const url = window.location.protocol === 'https:'
                    ? `wss://${host}:${port}/`
                    : `ws://${host}:${port}/`;

                rfb = new RFB(screen, url, {
                    credentials: { password: '' },
                    reconnect: true,
                    reconnectDelay: 1000,
                    maxReconnectAttempts: 10
                });

                rfb.addEventListener('connect', () => {
                    connected = true;
                    document.getElementById('loading').classList.add('hidden');
                    document.querySelectorAll('#controls .btn')[3].classList.add('connected');
                });

                rfb.addEventListener('disconnect', () => {
                    connected = false;
                    document.getElementById('loading').classList.remove('hidden');
                    document.querySelectorAll('#controls .btn')[3].classList.remove('connected');
                });

                rfb.addEventListener('clipboard', (e) => {
                    navigator.clipboard.writeText(e.detail.text).then(() => {
                        showToast('Copied to clipboard!');
                    }).catch(() => {});
                });

            } catch (e) {
                console.error('Connection error:', e);
                document.querySelector('.subtitle').textContent = 'Connection failed. Retrying...';
                setTimeout(connect, 3000);
            }
        }

        function toggleFullscreen() {
            if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen();
            } else {
                document.exitFullscreen();
            }
        }

        function sendCtrlAltDel() {
            if (rfb && connected) {
                rfb.sendCtrlAltDel();
                showToast('Ctrl+Alt+Del sent');
            }
        }

        function toggleKeyboard() {
            const kb = document.getElementById('mobile-keys');
            kb.style.display = kb.style.display === 'none' ? 'flex' : 'none';
        }

        function showKeyboard() {
            document.getElementById('mobile-keys').style.display = 'flex';
        }

        function sendKey(key) {
            if (rfb && connected) {
                rfb.sendKey(key);
            }
        }

        function refresh() {
            if (rfb) {
                rfb.disconnect();
                setTimeout(connect, 1000);
            }
        }

        function copyUrl() {
            navigator.clipboard.writeText(window.location.href).then(() => {
                showToast('URL copied!');
            }).catch(() => {});
        }

        function showToast(message) {
            const toast = document.getElementById('toast');
            toast.textContent = message;
            toast.classList.add('show');
            setTimeout(() => toast.classList.remove('show'), 2000);
        }

        document.addEventListener('paste', (e) => {
            const text = e.clipboardData.getData('text');
            if (rfb && connected && text) {
                rfb.clipboardPaste(text);
            }
        });

        window.addEventListener('load', () => {
            getCurrentURL();
            connect();
        });

        window.addEventListener('resize', () => {
            if (rfb && connected) rfb.resize();
        });

        document.addEventListener('keydown', (e) => {
            if (e.key === 'F11') {
                toggleFullscreen();
                e.preventDefault();
            }
        });
    </script>
</body>
</html>
VNC_EOF

    print_success "VNC page created"
}

# Configure VNC
setup_vnc() {
    print_step "Setting up VNC server..."

    mkdir -p ~/.vnc

    # Create xstartup with proper XFCE4 startup
    cat > ~/.vnc/xstartup << 'VNC_EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

dbus-launch --exit-with-session startxfce4 &
exec startxfce4
VNC_EOF

    chmod +x ~/.vnc/xstartup

    # Create VNC password file
    mkdir -p ~/.vnc
    (echo ""; echo "") | vncpasswd -f > ~/.vnc/passwd 2>/dev/null || true
    chmod 600 ~/.vnc/passwd

    print_success "VNC configured"
}

# Start services
start_services() {
    print_step "Starting VNC server..."

    # Kill ALL existing services first
    cleanup_services

    # Start Xvfb
    export DISPLAY=:99
    Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
    sleep 3

    if ! pgrep -f "Xvfb :99" > /dev/null; then
        # Try :1 if :99 fails
        export DISPLAY=:1
        Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
        sleep 3
        
        if ! pgrep -f "Xvfb :1" > /dev/null; then
            print_error "Failed to start Xvfb"
            exit 1
        fi
    fi

    # Start VNC
    export DISPLAY=:99
    tigervncserver :1 \
        -geometry 1920x1080 \
        -depth 24 \
        -xstartup ~/.vnc/xstartup \
        -localhost no \
        -rfbport $VNC_PORT \
        > /tmp/vnc.log 2>&1 &

    sleep 3

    if pgrep -f "vncserver" > /dev/null || pgrep -f "tigervnc" > /dev/null; then
        print_success "VNC server started on :1 (port $VNC_PORT)"
    else
        print_error "VNC server failed to start"
        cat /tmp/vnc.log 2>/dev/null
    fi
}

# Start noVNC
start_novnc() {
    print_step "Starting noVNC..."

    cd "$NOVNC_DIR"

    nohup websockify \
        --web="$NOVNC_DIR" \
        --vnc="localhost:$VNC_PORT" \
        --prefer-js=true \
        $NOVNC_PORT \
        > /tmp/novnc.log 2>&1 &

    sleep 3

    if pgrep -f "websockify" > /dev/null; then
        print_success "noVNC started on port $NOVNC_PORT"
    else
        print_error "noVNC failed to start"
        cat /tmp/novnc.log 2>/dev/null
    fi
}

# Start Cloudflare Tunnel
start_tunnel() {
    print_step "Starting Cloudflare Tunnel..."

    nohup cloudflared tunnel --url http://localhost:$NOVNC_PORT \
        --logfile /tmp/cloudflared.log \
        --metrics 0.0.0.0:9090 \
        > /tmp/tunnel.log 2>&1 &

    sleep 10

    TUNNEL_URL=""
    for i in {1..15}; do
        if [ -f /tmp/cloudflared.log ]; then
            TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
            if [ -n "$TUNNEL_URL" ]; then
                break
            fi
        fi
        sleep 2
    done

    if [ -n "$TUNNEL_URL" ]; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}║${NC}         🎉 CLOUDFLARE TUNNEL READY! 🎉            ${GREEN}║${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "   ${BLUE}Your Cloud Linux Desktop:${NC}"
        echo -e "   ${GREEN}$TUNNEL_URL${NC}"
        echo ""
        echo -e "   ${YELLOW}Click the URL above to access your Linux desktop${NC}"
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"
    else
        print_error "Failed to get tunnel URL"
        cat /tmp/tunnel.log 2>/dev/null | tail -20
    fi
}

# Create management scripts
create_scripts() {
    print_step "Creating management scripts..."

    sudo tee "$SCRIPT_DIR/tunnel.sh" > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="/opt/cloud-linux-gui"
VNC_PORT=5901
NOVNC_PORT=6080

case "$1" in
    start)
        echo "Starting services..."
        
        # Kill all existing
        pkill -9 -f "Xvfb" 2>/dev/null || true
        pkill -9 -f "vncserver" 2>/dev/null || true
        pkill -9 -f "websockify" 2>/dev/null || true
        pkill -9 -f "cloudflared" 2>/dev/null || true
        sleep 2

        export DISPLAY=:99
        Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
        sleep 3

        mkdir -p ~/.vnc
        [ -f ~/.vnc/xstartup ] || (cat > ~/.vnc/xstartup << 'VNC'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
dbus-launch --exit-with-session startxfce4 &
exec startxfce4
VNC
chmod +x ~/.vnc/xstartup
(echo ""; echo "") | vncpasswd -f > ~/.vnc/passwd 2>/dev/null || true
chmod 600 ~/.vnc/passwd)

        tigervncserver :1 -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup -localhost no -rfbport $VNC_PORT > /tmp/vnc.log 2>&1 &
        sleep 3

        cd "$SCRIPT_DIR/noVNC"
        nohup websockify --web="$SCRIPT_DIR/noVNC" --vnc="localhost:$VNC_PORT" --prefer-js=true $NOVNC_PORT > /tmp/novnc.log 2>&1 &
        sleep 3

        nohup cloudflared tunnel --url http://localhost:$NOVNC_PORT --logfile /tmp/cloudflared.log > /tmp/tunnel.log 2>&1 &
        sleep 10

        grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1
        ;;
    stop)
        pkill -9 -f "cloudflared|vncserver|Xvfb|websockify" 2>/dev/null
        echo "All services stopped"
        ;;
    url)
        cat "$SCRIPT_DIR/tunnel_url.txt" 2>/dev/null || echo "Run 'tunnel.sh start' first"
        ;;
    status)
        echo "=== Services Status ==="
        pgrep -f "Xvfb" > /dev/null && echo "Xvfb: Running" || echo "Xvfb: Stopped"
        pgrep -f "vncserver" > /dev/null && echo "VNC: Running" || echo "VNC: Stopped"
        pgrep -f "websockify" > /dev/null && echo "noVNC: Running" || echo "noVNC: Stopped"
        pgrep -f "cloudflared" > /dev/null && echo "Cloudflare: Running" || echo "Cloudflare: Stopped"
        ;;
esac
SCRIPT_EOF

    sudo chmod +x "$SCRIPT_DIR/tunnel.sh"
    print_success "Scripts created"
}

display_status() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}         ✅ INSTALLATION COMPLETE! ✅                   ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$SCRIPT_DIR/tunnel_url.txt" ]; then
        TUNNEL_URL=$(cat "$SCRIPT_DIR/tunnel_url.txt")
        echo -e "   ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "   ${YELLOW}Your Cloud Linux Desktop is ready!${NC}"
        echo ""
        echo -e "   ${BLUE}🌐 Access URL:${NC}"
        echo -e "   ${GREEN}$TUNNEL_URL${NC}"
        echo ""
        echo -e "   ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    echo ""
    echo -e "   ${YELLOW}Commands:${NC}"
    echo -e "   • View URL: ${BLUE}cat $SCRIPT_DIR/tunnel_url.txt${NC}"
    echo -e "   • Restart: ${BLUE}$SCRIPT_DIR/tunnel.sh start${NC}"
    echo -e "   • Stop: ${BLUE}$SCRIPT_DIR/tunnel.sh stop${NC}"
    echo ""
}

main() {
    print_header
    detect_os
    cleanup_services
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
