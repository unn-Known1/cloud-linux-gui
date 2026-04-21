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

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}Cloud Linux GUI - Full Linux Desktop in Browser${NC}  ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
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

detect_os() {
    print_step "Detecting system..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif command -v yum &> /dev/null; then
        OS="rhel"
    else
        OS="unknown"
    fi
    print_success "Detected: $OS"
}

install_dependencies() {
    print_step "Installing dependencies..."

    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y \
            xfce4 xfce4-goodies xorg dbus-x11 \
            tigervnc-standalone-server tigervnc-common \
            websockify curl wget git nano vim \
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
            websockpy python3-websockify \
            curl wget git nano vim 2>/dev/null || true
    elif command -v apk &> /dev/null; then
        sudo apk add \
            xfce4 dbus-x11 \
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
        x86_64) CLOUDFLARED_ARCH="amd64" ;;
        aarch64|arm64) CLOUDFLARED_ARCH="arm64" ;;
        armv7l) CLOUDFLARED_ARCH="arm" ;;
        *) CLOUDFLARED_ARCH="amd64" ;;
    esac

    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"

    curl -sL "$CLOUDFLARED_URL" -o /tmp/cloudflared 2>/dev/null || \
    wget -q "$CLOUDFLARED_URL" -O /tmp/cloudflared

    if [ -f /tmp/cloudflared ]; then
        chmod +x /tmp/cloudflared
        sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
        print_success "Cloudflared installed"
    else
        print_error "Failed to download cloudflared"
        exit 1
    fi
}

install_novnc() {
    print_step "Installing noVNC..."

    sudo mkdir -p "$NOVNC_DIR"

    if [ -d "$NOVNC_DIR/.git" ]; then
        cd "$NOVNC_DIR"
        git pull -q 2>/dev/null || true
    else
        rm -rf "$NOVNC_DIR"
        git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || {
            curl -sL https://github.com/novnc/noVNC/archive/refs/heads/master.tar.gz -o /tmp/novnc.tar.gz
            if [ -f /tmp/novnc.tar.gz ]; then
                tar -xzf /tmp/novnc.tar.gz -C /tmp
                mv /tmp/noVNC-master "$NOVNC_DIR"
                rm -f /tmp/novnc.tar.gz
            fi
        }
    fi

    if [ -f "$NOVNC_DIR/vnc.html" ]; then
        print_success "noVNC installed"
    else
        print_error "Failed to install noVNC"
        exit 1
    fi
}

create_custom_vnc_html() {
    print_step "Creating custom VNC interface..."

    cat > "$NOVNC_DIR/vnc.html" << 'VNCHTML_EOF'
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
            top: 0; left: 0;
            width: 100%; height: 100%;
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
        #screen:focus { outline: none; }
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
        @keyframes pulse-dot {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.4; }
        }
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
        .key:hover {
            background: rgba(0, 212, 255, 0.2);
            border-color: #00d4ff;
        }
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
        <button class="btn" id="refreshBtn" onclick="refresh()" title="Refresh">🔄</button>
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
                const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
                const url = protocol + host + ':' + port + '/';

                rfb = new RFB(screen, url, {
                    credentials: { password: '' },
                    reconnect: true,
                    reconnectDelay: 1000,
                    maxReconnectAttempts: 10
                });

                rfb.addEventListener('connect', () => {
                    connected = true;
                    document.getElementById('loading').classList.add('hidden');
                    document.getElementById('refreshBtn').classList.add('connected');
                });

                rfb.addEventListener('disconnect', () => {
                    connected = false;
                    document.getElementById('loading').classList.remove('hidden');
                    document.getElementById('refreshBtn').classList.remove('connected');
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
            const kb = document.getElementById('mobile-keys');
            kb.style.display = 'flex';
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
VNCHTML_EOF

    print_success "Custom VNC interface created"
}

setup_vnc() {
    print_step "Configuring VNC server..."

    mkdir -p ~/.vnc

    cat > ~/.vnc/xstartup << 'VNC_EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

xrdb $HOME/.Xresources 2>/dev/null || true
dbus-launch --exit-with-session startxfce4 &
VNC_EOF

    chmod +x ~/.vnc/xstartup

    print_success "VNC configured"
}

start_services() {
    print_step "Stopping existing services..."

    pkill -9 -f "Xvfb.*:1" 2>/dev/null || true
    pkill -9 -f "vncserver.*:1" 2>/dev/null || true
    pkill -9 -f "tigervncserver" 2>/dev/null || true
    pkill -9 -f "websockify.*6080" 2>/dev/null || true
    pkill -9 -f "cloudflared" 2>/dev/null || true
    sleep 2

    print_step "Starting Xvfb..."
    export DISPLAY=:1
    Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
    sleep 3

    if ! pgrep -f "Xvfb :1" > /dev/null; then
        print_error "Failed to start Xvfb"
        exit 1
    fi
    print_success "Xvfb started"

    print_step "Starting VNC server..."
    tigervncserver :1 -fg -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup > /tmp/vnc.log 2>&1 || \
    vncserver :1 -fg -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup > /tmp/vnc.log 2>&1
    sleep 2

    if pgrep -f "vncserver.*:1" > /dev/null || pgrep -f "tigervncserver" > /dev/null; then
        print_success "VNC server started on :1 (port $VNC_PORT)"
    else
        print_error "VNC server failed to start"
        cat /tmp/vnc.log
        exit 1
    fi

    print_step "Starting noVNC..."
    cd "$NOVNC_DIR"
    nohup websockify --web="$NOVNC_DIR" --vnc="localhost:$VNC_PORT" --prefer-js=true $NOVNC_PORT > /tmp/novnc.log 2>&1 &
    sleep 3

    if pgrep -f "websockify.*$NOVNC_PORT" > /dev/null; then
        print_success "noVNC started on port $NOVNC_PORT"
    else
        print_error "noVNC failed to start"
        cat /tmp/novnc.log
        exit 1
    fi
}

start_tunnel() {
    print_step "Starting Cloudflare Tunnel..."

    rm -f /tmp/tunnel.log /tmp/cloudflared.log 2>/dev/null || true

    nohup cloudflared tunnel --url http://localhost:$NOVNC_PORT --logfile /tmp/cloudflared.log > /tmp/tunnel.log 2>&1 &

    sleep 10

    TUNNEL_URL=""
    for i in {1..20}; do
        if [ -f /tmp/cloudflared.log ]; then
            TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1)
            if [ -n "$TUNNEL_URL" ]; then
                break
            fi
        fi
        sleep 1
    done

    if [ -n "$TUNNEL_URL" ]; then
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}║${NC}         🎉 CLOUDFLARE TUNNEL READY! 🎉                  ${GREEN}║${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "   ${BLUE}Your Cloud Linux Desktop:${NC}"
        echo -e "   ${GREEN}$TUNNEL_URL${NC}"
        echo ""
        echo -e "   ${YELLOW}Open this URL in your browser to access your desktop${NC}"
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"
        print_success "Tunnel URL saved"
    else
        print_error "Failed to get tunnel URL"
        echo "Check logs: cat /tmp/tunnel.log"
        cat /tmp/tunnel.log 2>/dev/null | tail -20
        exit 1
    fi
}

create_scripts() {
    print_step "Creating management scripts..."

    sudo tee "$SCRIPT_DIR/tunnel.sh" > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="$SCRIPT_DIR/noVNC"
VNC_PORT=5901
NOVNC_PORT=6080

case "$1" in
    start|restart)
        pkill -9 -f "Xvfb.*:1" 2>/dev/null || true
        pkill -9 -f "vncserver.*:1" 2>/dev/null || true
        pkill -9 -f "tigervncserver" 2>/dev/null || true
        pkill -9 -f "websockify.*6080" 2>/dev/null || true
        pkill -9 -f "cloudflared" 2>/dev/null || true
        sleep 2

        export DISPLAY=:1
        Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &
        sleep 3

        mkdir -p ~/.vnc
        [ -f ~/.vnc/xstartup ] || cat > ~/.vnc/xstartup << 'VNCX'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
xrdb $HOME/.Xresources 2>/dev/null || true
dbus-launch --exit-with-session startxfce4 &
VNCX
        chmod +x ~/.vnc/xstartup

        tigervncserver :1 -fg -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup > /tmp/vnc.log 2>&1 || \
        vncserver :1 -fg -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup > /tmp/vnc.log 2>&1
        sleep 2

        cd "$NOVNC_DIR"
        websockify --web="$NOVNC_DIR" --vnc="localhost:$VNC_PORT" --prefer-js=true $NOVNC_PORT > /tmp/novnc.log 2>&1 &
        sleep 3

        cloudflared tunnel --url http://localhost:$NOVNC_PORT --logfile /tmp/cloudflared.log > /tmp/tunnel.log 2>&1 &
        sleep 10

        grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cloudflared.log 2>/dev/null | head -1
        ;;
    stop)
        pkill -9 -f "Xvfb.*:1" 2>/dev/null || true
        pkill -9 -f "vncserver.*:1" 2>/dev/null || true
        pkill -9 -f "tigervncserver" 2>/dev/null || true
        pkill -9 -f "websockify.*6080" 2>/dev/null || true
        pkill -9 -f "cloudflared" 2>/dev/null || true
        echo "All services stopped"
        ;;
    url)
        cat "$SCRIPT_DIR/tunnel_url.txt" 2>/dev/null || echo "Run 'tunnel.sh start' first"
        ;;
    status)
        echo "=== Service Status ==="
        pgrep -f "Xvfb :1" > /dev/null && echo "✓ Xvfb running" || echo "✗ Xvfb not running"
        (pgrep -f "vncserver.*:1" > /dev/null || pgrep -f "tigervncserver" > /dev/null) && echo "✓ VNC running" || echo "✗ VNC not running"
        pgrep -f "websockify.*6080" > /dev/null && echo "✓ noVNC running" || echo "✗ noVNC not running"
        pgrep -f "cloudflared" > /dev/null && echo "✓ Tunnel running" || echo "✗ Tunnel not running"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|url|status}"
        ;;
esac
SCRIPT_EOF

    sudo chmod +x "$SCRIPT_DIR/tunnel.sh"

    sudo tee /usr/local/bin/cloud-linux > /dev/null << 'CMD_EOF'
#!/bin/bash
[ -f /opt/cloud-linux-gui/tunnel_url.txt ] && cat /opt/cloud-linux-gui/tunnel_url.txt || /opt/cloud-linux-gui/tunnel.sh "$@"
CMD_EOF
    sudo chmod +x /usr/local/bin/cloud-linux

    print_success "Scripts created"
}

display_status() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}         ✅ INSTALLATION COMPLETE! ✅                       ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$SCRIPT_DIR/tunnel_url.txt" ]; then
        TUNNEL_URL=$(cat "$SCRIPT_DIR/tunnel_url.txt")
        echo -e "   ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "   ${YELLOW}Your Cloud Linux Desktop is ready!${NC}"
        echo ""
        echo -e "   ${BLUE}🌐 Access URL:${NC}"
        echo -e "   ${GREEN}$TUNNEL_URL${NC}"
        echo ""
        echo -e "   ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi

    echo ""
    echo -e "   ${YELLOW}Quick Commands:${NC}"
    echo -e "   • View URL:  ${BLUE}cloud-linux${NC} or ${BLUE}cat $SCRIPT_DIR/tunnel_url.txt${NC}"
    echo -e "   • Restart:   ${BLUE}$SCRIPT_DIR/tunnel.sh start${NC}"
    echo -e "   • Stop:      ${BLUE}$SCRIPT_DIR/tunnel.sh stop${NC}"
    echo -e "   • Status:    ${BLUE}$SCRIPT_DIR/tunnel.sh status${NC}"
    echo ""
}

main() {
    print_header
    detect_os
    install_dependencies
    install_cloudflared
    install_novnc
    create_custom_vnc_html
    setup_vnc
    start_services
    start_tunnel
    create_scripts
    display_status
}

main "$@"