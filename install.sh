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
PORT=8080
SCRIPT_DIR="/opt/cloud-linux-gui"
LOG_FILE="/tmp/cloud-linux-gui-install.log"

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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}[!] Running as non-root user - will use sudo where needed${NC}"
    fi
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

    # Update package list
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq 2>/dev/null || true
        sudo apt-get install -y -qq \
            xfce4 xfce4-goodies xorg dbus-x11 \
            novnc novnc-webclient \
            tightvncserver websockify \
            curl wget git nano vim \
            fonts-noto-cjk 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        sudo yum install -y \
            xfce4-session dbus-x11 \
            novnc websockify \
            tigervnc-server \
            curl wget git nano vim 2>/dev/null || true
    elif command -v apk &> /dev/null; then
        sudo apk add \
            xfce4 dbus-x11 \
            novnc websockify \
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

    # Detect architecture
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

    # Download and install cloudflared
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"

    if command -v curl &> /dev/null; then
        curl -sL "$CLOUDFLARED_URL" -o /tmp/cloudflared
    else
        wget -q "$CLOUDFLARED_URL" -O /tmp/cloudflared 2>/dev/null || true
    fi

    if [ -f /tmp/cloudflared ]; then
        chmod +x /tmp/cloudflared
        sudo mv /tmp/cloudflared /usr/local/bin/cloudflared
        print_success "Cloudflared installed"
    else
        print_error "Failed to download cloudflared"
        exit 1
    fi
}

# Create directories
create_directories() {
    print_step "Creating directories..."

    sudo mkdir -p "$SCRIPT_DIR"
    sudo mkdir -p "$SCRIPT_DIR/web"
    sudo mkdir -p "$SCRIPT_DIR/vnc"

    print_success "Directories created"
}

# Install noVNC web interface
install_novnc() {
    print_step "Installing noVNC web interface..."

    # Create web index.html
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
        .container {
            text-align: center;
            padding: 40px;
        }
        .logo {
            font-size: 72px;
            margin-bottom: 20px;
            animation: pulse 2s infinite;
        }
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
        .subtitle {
            font-size: 1.2rem;
            color: #888;
            margin-bottom: 40px;
        }
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
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0, 212, 255, 0.4);
        }
        .info {
            margin-top: 40px;
            padding: 20px;
            background: rgba(255,255,255,0.05);
            border-radius: 15px;
            max-width: 500px;
        }
        .info p {
            margin: 8px 0;
            color: #aaa;
        }
        .status {
            display: inline-block;
            width: 10px;
            height: 10px;
            background: #00ff00;
            border-radius: 50%;
            margin-right: 8px;
            animation: blink 1s infinite;
        }
        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .keyboard-hint {
            margin-top: 30px;
            padding: 15px;
            background: rgba(0,212,255,0.1);
            border-radius: 10px;
            font-size: 0.9rem;
        }
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

        <div class="keyboard-hint">
            <strong>⌨️ Keyboard Shortcuts:</strong> F8 = Menu | Ctrl+Alt+Shift = Release
        </div>
    </div>
</body>
</html>
HTML_EOF

    print_success "Web interface installed"
}

# Configure VNC server
configure_vnc() {
    print_step "Configuring VNC server..."

    # Create VNC config directory
    mkdir -p ~/.vnc

    # Create VNC password if not exists
    if [ ! -f ~/.vnc/passwd ]; then
        echo "cloudlinux" | vncpasswd -f > ~/.vnc/passwd 2>/dev/null || true
        chmod 600 ~/.vnc/passwd
    fi

    # Create xstartup script
    cat > ~/.vnc/xstartup << 'VNC_EOF'
#!/bin/sh
# Uncomment the following two lines for normal desktop:
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Fix D-Bus issues
dbus-launch --exit-with-session startxfce4 &

# Start XFCE4 session
exec startxfce4
VNC_EOF

    chmod +x ~/.vnc/xstartup

    print_success "VNC configured"
}

# Start VNC server
start_vnc() {
    print_step "Starting VNC server..."

    # Kill existing VNC servers
    pkill -f "vncserver :1" 2>/dev/null || true
    pkill -f "Xvfb :1" 2>/dev/null || true

    sleep 1

    # Start Xvfb (virtual framebuffer)
    export DISPLAY=:1
    Xvfb :1 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
    sleep 2

    # Start VNC server
    vncserver :1 -geometry 1920x1080 -depth 24 &
    sleep 2

    print_success "VNC server started on :1"
}

# Start noVNC
start_novnc() {
    print_step "Starting noVNC..."

    # Kill existing websockify
    pkill -f "websockify :80" 2>/dev/null || true

    sleep 1

    # Start websockify with noVNC
    cd /usr/share/novnc
    nohup ./utils/launch.sh --vpn --listen 80 --web "$SCRIPT_DIR/web" > /tmp/novnc.log 2>&1 &

    # Alternative if noVNC launch script not found
    if [ ! -f /usr/share/novnc/utils/launch.sh ]; then
        websockify --web="$SCRIPT_DIR/web" 80 localhost:5901 &
    fi

    sleep 2
    print_success "noVNC started on port 80"
}

# Start Cloudflare Tunnel
start_tunnel() {
    print_step "Starting Cloudflare Tunnel..."

    # Kill existing cloudflared
    pkill -f "cloudflared tunnel" 2>/dev/null || true

    sleep 1

    # Start cloudflared tunnel
    nohup cloudflared tunnel --url http://localhost:80 --logfile /tmp/cloudflared.log --metrics 0.0.0.0:9090 > /tmp/tunnel.log 2>&1 &

    sleep 5

    # Get tunnel URL
    TUNNEL_URL=""
    for i in {1..10}; do
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

        # Save URL for reference
        echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"
    else
        print_error "Failed to get tunnel URL. Check /tmp/tunnel.log"
    fi
}

# Create tunnel management script
create_tunnel_script() {
    print_step "Creating tunnel management script..."

    sudo tee "$SCRIPT_DIR/tunnel.sh" > /dev/null << 'SCRIPT_EOF'
#!/bin/bash
# Cloud Linux GUI - Tunnel Management Script

SCRIPT_DIR="/opt/cloud-linux-gui"
LOG_FILE="/tmp/cloudflared.log"

start_tunnel() {
    echo "Starting Cloudflare Tunnel..."
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    sleep 1
    nohup cloudflared tunnel --url http://localhost:80 --logfile /tmp/cloudflared.log --metrics 0.0.0.0:9090 > /tmp/tunnel.log 2>&1 &
    sleep 5

    TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/tunnel.log 2>/dev/null | head -1)
    if [ -n "$TUNNEL_URL" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Your Cloud Linux Desktop:"
        echo "$TUNNEL_URL"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"
    else
        echo "Waiting for tunnel URL..."
        for i in {1..10}; do
            sleep 2
            TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/tunnel.log 2>/dev/null | head -1)
            if [ -n "$TUNNEL_URL" ]; then
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "Your Cloud Linux Desktop:"
                echo "$TUNNEL_URL"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"
                break
            fi
        done
    fi
}

stop_tunnel() {
    echo "Stopping Cloudflare Tunnel..."
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    echo "Tunnel stopped"
}

case "$1" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    restart)
        stop_tunnel
        sleep 2
        start_tunnel
        ;;
    url)
        if [ -f "$SCRIPT_DIR/tunnel_url.txt" ]; then
            cat "$SCRIPT_DIR/tunnel_url.txt"
        else
            echo "No tunnel URL found. Run 'tunnel.sh start'"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|url}"
        exit 1
        ;;
esac
SCRIPT_EOF

    sudo chmod +x "$SCRIPT_DIR/tunnel.sh"
    print_success "Tunnel script created"
}

# Create quick-access script
create_quick_access() {
    print_step "Creating quick-access scripts..."

    sudo tee "/usr/local/bin/cloud-linux" > /dev/null << 'ACCESS_EOF'
#!/bin/bash
# Quick access to Cloud Linux GUI

if [ -f "/opt/cloud-linux-gui/tunnel_url.txt" ]; then
    URL=$(cat "/opt/cloud-linux-gui/tunnel_url.txt")
    echo "Opening Cloud Linux GUI: $URL"
    if command -v xdg-open &> /dev/null; then
        xdg-open "$URL" 2>/dev/null || echo "$URL"
    else
        echo "$URL"
    fi
else
    echo "Cloud Linux GUI not running. Run: /opt/cloud-linux-gui/tunnel.sh start"
fi
ACCESS_EOF

    sudo chmod +x "/usr/local/bin/cloud-linux"
    print_success "Quick access script created"
}

# Display final status
display_status() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}         ✅ INSTALLATION COMPLETE! ✅                   ${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${BLUE}Services Status:${NC}"
    echo -e "   • VNC Server: ${GREEN}Running on :1${NC}"
    echo -e "   • noVNC: ${GREEN}Running on port 80${NC}"
    echo -e "   • Cloudflare Tunnel: ${GREEN}Active${NC}"
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
    echo -e "   ${YELLOW}Management Commands:${NC}"
    echo -e "   • View URL: ${BLUE}cat /opt/cloud-linux-gui/tunnel_url.txt${NC}"
    echo -e "   • Restart Tunnel: ${BLUE}/opt/cloud-linux-gui/tunnel.sh restart${NC}"
    echo -e "   • Stop All: ${BLUE}pkill -f 'Xvfb|vncserver|novnc|cloudflared'${NC}"
    echo ""
}

# Main installation
main() {
    print_header
    check_root
    detect_os
    install_dependencies
    install_cloudflared
    create_directories
    install_novnc
    configure_vnc
    start_vnc
    start_novnc
    create_tunnel_script
    create_quick_access
    start_tunnel
    display_status
}

main "$@"