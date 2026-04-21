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
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="$SCRIPT_DIR/noVNC"

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
            print_error "Failed to install some packages, trying alternatives..."
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
    elif command -v apk &> /dev/null; then
        sudo apk add \
            xfce4 dbus-x11 \
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
        x86_64)
            CLOUDFLARED_ARCH="amd64"
            ;;
        aarch64|arm64)
            CLOUDFLARED_ARCH="arm64"
            ;;
        armv7l)
            CLOUDFLARED_ARCH="arm"
            ;;
        *)
            CLOUDFLARED_ARCH="amd64"
            ;;
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
        cd "$NOVNC_DIR"
        git pull 2>/dev/null || true
    else
        git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null || {
            print_error "Failed to clone noVNC, trying wget..."
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

# Create web interface
create_web_interface() {
    print_step "Creating web interface..."

    sudo mkdir -p "$SCRIPT_DIR/web"

    # Create index.html (landing page)
    sudo tee "$SCRIPT_DIR/web/index.html" > /dev/null << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cloud Linux GUI</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: #fff;
        }
        .container { text-align: center; padding: 40px; }
        .logo { font-size: 72px; margin-bottom: 20px; animation: pulse 2s infinite; }
        @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.05); }
        }
        h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle { font-size: 1.2rem; color: #888; margin-bottom: 40px; }
        .btn {
            display: inline-block;
            padding: 15px 40px;
            font-size: 1.1rem;
            background: linear-gradient(135deg, #00d4ff, #7b2cbf);
            color: #fff;
            text-decoration: none;
            border-radius: 30px;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(0, 212, 255, 0.3);
        }
        .btn:hover { transform: translateY(-2px); box-shadow: 0 6px 20px rgba(0, 212, 255, 0.4); }
        .info { margin-top: 40px; padding: 20px; background: rgba(255,255,255,0.05); border-radius: 15px; max-width: 500px; }
        .info p { margin: 8px 0; color: #aaa; }
        .status {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: #00ff00;
            border-radius: 50%;
            margin-right: 8px;
            animation: blink 1s infinite;
        }
        @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🖥️</div>
        <h1>Cloud Linux GUI</h1>
        <p class="subtitle">Full Linux Desktop - Accessible from Anywhere</p>
        <a href="/vnc.html" class="btn">🚀 Launch Desktop</a>
        <div class="info">
            <p><span class="status"></span>System Ready</p>
            <p>Full XFCE4 Desktop Environment</p>
            <p>Access from any browser, any device</p>
        </div>
    </div>
</body>
</html>
HTML_EOF

    print_success "Web interface created"
}

# Configure and start VNC
setup_vnc() {
    print_step "Setting up VNC server..."

    # Create VNC config directory
    mkdir -p ~/.vnc

    # Create xstartup script
    cat > ~/.vnc/xstartup << 'VNC_EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

# Start XFCE4
dbus-launch --exit-with-session startxfce4 &
exec startxfce4
VNC_EOF

    chmod +x ~/.vnc/xstartup
    print_success "VNC configured"
}

# Start services
start_services() {
    print_step "Starting VNC server..."

    # Kill existing
    pkill -f "vncserver" 2>/dev/null || true
    pkill -f "Xvfb" 2>/dev/null || true
    sleep 1

    # Start Xvfb
    export DISPLAY=:1
    Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
    sleep 2

    # Start VNC
    vncserver :1 -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup 2>/dev/null || \
    tigervncserver :1 -geometry 1920x1080 -depth 24 -xstartup ~/.vnc/xstartup 2>/dev/null || {
        # Fallback: just start with basic xstartup
        vncserver :1 -geometry 1920x1080 -depth 24 2>/dev/null || \
        tigervncserver :1 -geometry 1920x1080 -depth 24
    }
    sleep 2

    print_success "VNC server started on :1 (port 5901)"
}

# Start noVNC
start_novnc() {
    print_step "Starting noVNC..."

    pkill -f "websockify.*6080" 2>/dev/null || true
    sleep 1

    cd "$NOVNC_DIR"

    # Use websockify to proxy VNC
    nohup websockify --web="$SCRIPT_DIR/web" 6080 localhost:5901 > /tmp/novnc.log 2>&1 &

    # Alternative: use noVNC's launch script if available
    if [ -f "$NOVNC_DIR/utils/launch.sh" ]; then
        pkill -f "launch.sh" 2>/dev/null || true
        sleep 1
        nohup "$NOVNC_DIR/utils/launch.sh" --listen 6080 --vnc localhost:5901 > /tmp/novnc.log 2>&1 &
    fi

    sleep 2
    print_success "noVNC started on port 6080"
}

# Start Cloudflare Tunnel
start_tunnel() {
    print_step "Starting Cloudflare Tunnel..."

    pkill -f "cloudflared tunnel" 2>/dev/null || true
    sleep 1

    # Start cloudflared tunnel to port 6080 (where noVNC is listening)
    nohup cloudflared tunnel --url http://localhost:6080 --logfile /tmp/cloudflared.log > /tmp/tunnel.log 2>&1 &

    sleep 8

    # Get tunnel URL
    TUNNEL_URL=""
    for i in {1..15}; do
        if [ -f /tmp/tunnel.log ]; then
            TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/tunnel.log 2>/dev/null | head -1)
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
        print_error "Failed to get tunnel URL. Check /tmp/tunnel.log"
        cat /tmp/tunnel.log 2>/dev/null | tail -20
    fi
}

# Create management scripts
create_scripts() {
    print_step "Creating management scripts..."

    sudo tee "$SCRIPT_DIR/tunnel.sh" > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
SCRIPT_DIR="/opt/cloud-linux-gui"

case "$1" in
    start)
        echo "Starting services..."
        export DISPLAY=:1
        [ -f ~/.vnc/xstartup ] || (mkdir -p ~/.vnc && cat > ~/.vnc/xstartup << 'VNC'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
dbus-launch --exit-with-session startxfce4 &
exec startxfce4
VNC
chmod +x ~/.vnc/xstartup)
        Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
        sleep 2
        vncserver :1 -geometry 1920x1080 -depth 24 2>/dev/null || tigervncserver :1 -geometry 1920x1080 -depth 24
        sleep 2
        cd "$SCRIPT_DIR/noVNC"
        websockify --web="$SCRIPT_DIR/web" 6080 localhost:5901 > /tmp/novnc.log 2>&1 &
        sleep 2
        cloudflared tunnel --url http://localhost:6080 --logfile /tmp/cloudflared.log > /tmp/tunnel.log 2>&1 &
        sleep 8
        grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/tunnel.log 2>/dev/null | head -1
        ;;
    stop)
        pkill -f "cloudflared|vncserver|Xvfb|websockify" 2>/dev/null
        echo "All services stopped"
        ;;
    url)
        cat "$SCRIPT_DIR/tunnel_url.txt" 2>/dev/null || echo "Run 'tunnel.sh start' first"
        ;;
esac
SCRIPT_EOF

    sudo chmod +x "$SCRIPT_DIR/tunnel.sh"
    print_success "Scripts created"
}

# Display status
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

# Main
main() {
    print_header
    detect_os
    install_dependencies
    install_cloudflared
    install_novnc
    create_web_interface
    setup_vnc
    start_services
    start_novnc
    create_scripts
    start_tunnel
    display_status
}

main "$@"