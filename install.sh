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
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="$SCRIPT_DIR/noVNC"
VNC_PORT=5901
NOVNC_PORT=6080
CLOUD_USER="cloudlinux"
RUN_AS_USER="${RUN_AS_USER:-$CLOUD_USER}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1920x1080}"
VNC_DEPTH="${VNC_DEPTH:-24}"
LOG_DIR="/tmp/cloud-linux-gui"

# ─────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}Cloud Linux GUI - Full Linux Desktop in Browser${NC}  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step()    { echo -e "${YELLOW}[*]${NC} \$1"; }
print_success() { echo -e "${GREEN}[✓]${NC} \$1"; }
print_error()   { echo -e "${RED}[✗]${NC} \$1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} \$1"; }
print_info()    { echo -e "${CYAN}[i]${NC} \$1"; }

cleanup_on_error() {
    print_error "Installation failed! Cleaning up..."
    kill_all
    exit 1
}

trap cleanup_on_error ERR

# ─────────────────────────────────────────────
# System Detection
# ─────────────────────────────────────────────

detect_os() {
    print_step "Detecting system..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        VER=$(cat /etc/redhat-release | grep -oP '[0-9]+' | head -1)
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VER=$(cat /etc/debian_version)
    else
        OS="unknown"
        VER="unknown"
    fi

    ARCH=$(uname -m)
    print_success "Detected: $OS $VER ($ARCH)"

    # Validate supported OS
    case $OS in
        ubuntu|debian|centos|rhel|fedora|rocky|almalinux)
            ;;
        *)
            print_warning "Untested OS: $OS - proceeding anyway"
            ;;
    esac
}

# ─────────────────────────────────────────────
# Dependency Installation
# ─────────────────────────────────────────────

install_dependencies() {
    print_step "Installing dependencies (this may take a few minutes)..."

    if command -v apt-get &>/dev/null; then
        export DEBIAN_FRONTEND=noninteractive

        apt-get update -qq 2>/dev/null || true

        apt-get install -y --no-install-recommends \
            xfce4 \
            xfce4-terminal \
            xfce4-goodies \
            dbus-x11 \
            tigervnc-standalone-server \
            tigervnc-common \
            tigervnc-tools \
            websockify \
            x11-utils \
            x11-xserver-utils \
            xfonts-base \
            curl \
            wget \
            git \
            nano \
            vim \
            procps \
            net-tools \
            fonts-noto-cjk \
            fonts-ubuntu \
            fonts-liberation \
            sudo \
            2>/dev/null || true

    elif command -v dnf &>/dev/null; then
        dnf groupinstall -y "Xfce" 2>/dev/null || true
        dnf install -y \
            tigervnc-server \
            dbus-x11 \
            python3-websockify \
            xorg-x11-utils \
            xorg-x11-fonts-base \
            curl wget git nano vim \
            procps-ng net-tools \
            google-noto-cjk-fonts \
            sudo \
            2>/dev/null || true

    elif command -v yum &>/dev/null; then
        yum groupinstall -y "Xfce" 2>/dev/null || true
        yum install -y \
            tigervnc-server \
            dbus-x11 \
            python3-websockify \
            xorg-x11-utils \
            xorg-x11-fonts-base \
            curl wget git nano vim \
            procps net-tools \
            sudo \
            2>/dev/null || true
    else
        print_error "No supported package manager found (apt/dnf/yum)"
        exit 1
    fi

    print_success "Dependencies installed"
}

# ─────────────────────────────────────────────
# Cloudflared Installation
# ─────────────────────────────────────────────

install_cloudflared() {
    print_step "Installing Cloudflare Tunnel..."

    if command -v cloudflared &>/dev/null; then
        print_success "Cloudflared already installed ($(cloudflared --version 2>/dev/null | head -1))"
        return
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64)        CLOUDFLARED_ARCH="amd64" ;;
        aarch64|arm64) CLOUDFLARED_ARCH="arm64" ;;
        armv7l)        CLOUDFLARED_ARCH="arm"   ;;
        *)             CLOUDFLARED_ARCH="amd64" ;;
    esac

    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}"

    print_info "Downloading cloudflared for $CLOUDFLARED_ARCH..."

    if curl -sL "$CLOUDFLARED_URL" -o /tmp/cloudflared 2>/dev/null; then
        :
    elif wget -q "$CLOUDFLARED_URL" -O /tmp/cloudflared 2>/dev/null; then
        :
    else
        print_error "Failed to download cloudflared"
        exit 1
    fi

    # Verify download
    if [ ! -s /tmp/cloudflared ]; then
        print_error "Downloaded cloudflared file is empty"
        exit 1
    fi

    chmod +x /tmp/cloudflared
    mv /tmp/cloudflared /usr/local/bin/cloudflared

    # Verify installation
    if cloudflared --version &>/dev/null; then
        print_success "Cloudflared installed ($(cloudflared --version 2>/dev/null | head -1))"
    else
        print_error "Cloudflared installation verification failed"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# noVNC Installation
# ─────────────────────────────────────────────

install_novnc() {
    print_step "Installing noVNC from GitHub..."

    mkdir -p "$SCRIPT_DIR"

    if [ -d "$NOVNC_DIR/.git" ]; then
        print_info "Updating existing noVNC..."
        cd "$NOVNC_DIR" && git pull --quiet 2>/dev/null || true
    elif [ -d "$NOVNC_DIR" ] && [ -f "$NOVNC_DIR/core/rfb.js" ]; then
        print_info "noVNC already present"
    else
        rm -rf "$NOVNC_DIR" 2>/dev/null || true

        if git clone --depth 1 https://github.com/novnc/noVNC.git "$NOVNC_DIR" 2>/dev/null; then
            :
        else
            print_info "Git clone failed, trying tarball..."
            curl -sL https://github.com/novnc/noVNC/archive/refs/heads/master.tar.gz -o /tmp/novnc.tar.gz
            if [ -f /tmp/novnc.tar.gz ] && [ -s /tmp/novnc.tar.gz ]; then
                tar -xzf /tmp/novnc.tar.gz -C "$SCRIPT_DIR"
                mv "$SCRIPT_DIR/noVNC-master" "$NOVNC_DIR"
                rm -f /tmp/novnc.tar.gz
            else
                print_error "Failed to download noVNC"
                exit 1
            fi
        fi
    fi

    # Verify
    if [ -f "$NOVNC_DIR/core/rfb.js" ]; then
        print_success "noVNC installed"
    else
        print_error "noVNC installation incomplete - core/rfb.js not found"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Custom VNC Web Page
# ─────────────────────────────────────────────

create_vnc_page() {
    print_step "Creating custom VNC web page..."

    cat > "$NOVNC_DIR/vnc.html" << 'VNC_EOF'
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

        /* Loading Screen */
        #loading {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(135deg, #0f0f1a 0%, #1a1a2e 50%, #16213e 100%);
            display: flex; flex-direction: column; align-items: center; justify-content: center;
            z-index: 1000; transition: opacity 0.5s ease;
        }
        #loading.hidden { opacity: 0; pointer-events: none; }
        .logo { font-size: 100px; animation: pulse 2s infinite; }
        @keyframes pulse { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.1); } }
        .title {
            color: #fff; font-size: 2rem; margin-top: 20px; font-weight: 700;
            background: linear-gradient(90deg, #00d4ff, #7b2cbf);
            -webkit-background-clip: text; -webkit-text-fill-color: transparent;
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

        /* VNC Screen */
        #screen { position: fixed; top: 0; left: 0; width: 100%; height: 100%; }

        /* URL Bar */
        #url-bar {
            position: fixed; top: 15px; left: 50%; transform: translateX(-50%);
            background: rgba(26,26,46,0.95); backdrop-filter: blur(10px);
            border-radius: 25px; padding: 12px 25px;
            color: #00d4ff; font-size: 14px; z-index: 100;
            border: 1px solid rgba(0,212,255,0.3);
            display: flex; align-items: center; gap: 10px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
            transition: opacity 0.3s;
            opacity: 0.8;
        }
        #url-bar:hover { opacity: 1; }
        .dot {
            width: 8px; height: 8px; background: #00ff00;
            border-radius: 50%; animation: pulse-dot 1s infinite;
        }
        .dot.disconnected { background: #ff4444; }
        @keyframes pulse-dot { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }

        /* Controls */
        #controls {
            position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
            display: flex; gap: 15px; z-index: 100;
            opacity: 0.3; transition: opacity 0.3s;
        }
        #controls:hover { opacity: 1; }
        .btn {
            width: 55px; height: 55px; border-radius: 50%; border: none;
            background: linear-gradient(135deg, rgba(0,212,255,0.2), rgba(123,44,191,0.2));
            backdrop-filter: blur(10px); color: #fff; font-size: 22px;
            cursor: pointer; transition: all 0.3s ease;
            display: flex; align-items: center; justify-content: center;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.1);
        }
        .btn:hover { transform: scale(1.15); background: rgba(0,212,255,0.3); }
        .btn:active { transform: scale(0.95); }

        /* Toast Notification */
        .toast {
            position: fixed; top: 80px; left: 50%; transform: translateX(-50%);
            background: rgba(0,212,255,0.9); color: #000;
            padding: 12px 24px; border-radius: 25px;
            font-size: 14px; font-weight: 600; z-index: 200;
            opacity: 0; transition: opacity 0.3s;
            pointer-events: none;
        }
        .toast.show { opacity: 1; }
    </style>
</head>
<body>
    <div id="loading">
        <div class="logo">🖥️</div>
        <div class="title">Cloud Linux GUI</div>
        <div class="subtitle" id="status-text">Establishing secure connection...</div>
        <div class="spinner"></div>
    </div>

    <div id="screen" tabindex="0"></div>

    <div id="url-bar">
        <span class="dot" id="status-dot"></span>
        <span id="current-url">Connecting...</span>
    </div>

    <div id="controls">
        <button class="btn" onclick="toggleFullscreen()" title="Fullscreen">⛶</button>
        <button class="btn" onclick="sendCtrlAltDel()" title="Ctrl+Alt+Del">⌨️</button>
        <button class="btn" onclick="clipboardSync()" title="Clipboard">📋</button>
        <button class="btn" onclick="doRefresh()" title="Reconnect">🔄</button>
    </div>

    <div id="toast" class="toast"></div>

    <script type="module">
        import RFB from './core/rfb.js';

        let rfb;
        let reconnectAttempts = 0;
        const MAX_RECONNECT = 10;

        function getWebSocketURL() {
            const proto = window.location.protocol === 'https:' ? 'wss' : 'ws';
            const host  = window.location.hostname;
            const port  = window.location.port ? ':' + window.location.port : '';
            return proto + '://' + host + port + '/websockify';
        }

        function updateStatus(connected) {
            const dot = document.getElementById('status-dot');
            if (connected) {
                dot.classList.remove('disconnected');
            } else {
                dot.classList.add('disconnected');
            }
        }

        function connect() {
            const screen = document.getElementById('screen');
            const url = getWebSocketURL();
            document.getElementById('current-url').textContent = window.location.href;

            try {
                rfb = new RFB(screen, url, {
                    credentials: { password: '' },
                    wsProtocols: ['binary'],
                });

                rfb.scaleViewport = true;
                rfb.resizeSession = true;
                rfb.clipViewport  = false;
                rfb.showDotCursor = true;

                rfb.addEventListener('connect', function() {
                    document.getElementById('loading').classList.add('hidden');
                    reconnectAttempts = 0;
                    updateStatus(true);
                    showToast('Connected to desktop');
                });

                rfb.addEventListener('disconnect', function(e) {
                    updateStatus(false);
                    document.getElementById('loading').classList.remove('hidden');

                    if (reconnectAttempts < MAX_RECONNECT) {
                        reconnectAttempts++;
                        var delay = Math.min(2000 * reconnectAttempts, 10000);
                        document.getElementById('status-text').textContent =
                            'Reconnecting (attempt ' + reconnectAttempts + '/' + MAX_RECONNECT + ')...';
                        setTimeout(connect, delay);
                    } else {
                        document.getElementById('status-text').textContent =
                            'Connection failed. Click Reconnect button or refresh the page.';
                    }
                });

                rfb.addEventListener('credentialsrequired', function() {
                    rfb.sendCredentials({ password: '' });
                });

            } catch (e) {
                console.error('RFB connection error:', e);
                document.getElementById('status-text').textContent =
                    'Failed to connect. Retrying in 3s...';
                setTimeout(connect, 3000);
            }
        }

        function toggleFullscreen() {
            if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen().catch(function() {});
                showToast('Entered fullscreen');
            } else {
                document.exitFullscreen();
                showToast('Exited fullscreen');
            }
        }

        function sendCtrlAltDel() {
            if (rfb) {
                rfb.sendCtrlAltDel();
                showToast('Ctrl+Alt+Del sent');
            }
        }

        function clipboardSync() {
            if (rfb && navigator.clipboard) {
                navigator.clipboard.readText().then(function(text) {
                    rfb.clipboardPasteFrom(text);
                    showToast('Clipboard synced');
                }).catch(function() {
                    showToast('Clipboard access denied');
                });
            } else {
                showToast('Clipboard not available');
            }
        }

        function doRefresh() {
            reconnectAttempts = 0;
            if (rfb) {
                try { rfb.disconnect(); } catch(e) {}
            }
            document.getElementById('loading').classList.remove('hidden');
            document.getElementById('status-text').textContent = 'Reconnecting...';
            setTimeout(connect, 1000);
        }

        function showToast(msg) {
            var t = document.getElementById('toast');
            t.textContent = msg;
            t.classList.add('show');
            setTimeout(function() { t.classList.remove('show'); }, 2000);
        }

        // Expose to global scope for button onclick
        window.toggleFullscreen = toggleFullscreen;
        window.sendCtrlAltDel   = sendCtrlAltDel;
        window.clipboardSync    = clipboardSync;
        window.doRefresh        = doRefresh;

        // Keyboard shortcut: F11 for fullscreen
        document.addEventListener('keydown', function(e) {
            if (e.key === 'F11') {
                e.preventDefault();
                toggleFullscreen();
            }
        });

        // Start connection on page load
        window.addEventListener('load', connect);
    </script>
</body>
</html>
VNC_EOF

    # Create index.html redirect
    cat > "$NOVNC_DIR/index.html" << 'INDEX_EOF'
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0;url=vnc.html">
    <title>Redirecting...</title>
</head>
<body>
    <p>Redirecting to <a href="vnc.html">Cloud Linux GUI Desktop</a>...</p>
</body>
</html>
INDEX_EOF

    print_success "VNC web page created with auto-redirect"
}

# ─────────────────────────────────────────────
# User Setup
# ─────────────────────────────────────────────

create_service_user() {
    print_step "Setting up service user..."

    if [ "$(id -u)" -ne 0 ]; then
        print_warning "Not running as root - using current user: $(whoami)"
        RUN_AS_USER="$(whoami)"
        return
    fi

    # Create user if it doesn't exist
    if ! id "$RUN_AS_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$RUN_AS_USER" 2>/dev/null || true
        print_success "Created user: $RUN_AS_USER"
    else
        print_success "User $RUN_AS_USER already exists"
    fi

    # Add to necessary groups
    for group in video render audio dialout; do
        groupadd -f "$group" 2>/dev/null || true
        usermod -aG "$group" "$RUN_AS_USER" 2>/dev/null || true
    done

    # Allow sudo without password (optional, for convenience)
    echo "$RUN_AS_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$RUN_AS_USER" 2>/dev/null || true
    chmod 440 "/etc/sudoers.d/$RUN_AS_USER" 2>/dev/null || true

    # Set ownership
    mkdir -p "$SCRIPT_DIR"
    chown -R "$RUN_AS_USER:$RUN_AS_USER" "$SCRIPT_DIR" 2>/dev/null || true

    print_success "User $RUN_AS_USER configured with required groups"
}

# ─────────────────────────────────────────────
# VNC Setup
# ─────────────────────────────────────────────

get_user_home() {
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        getent passwd "$RUN_AS_USER" | cut -d: -f6
    else
        echo "$HOME"
    fi
}

setup_vnc() {
    print_step "Setting up VNC server..."

    local VNC_HOME_DIR
    VNC_HOME_DIR="$(get_user_home)"

    mkdir -p "$VNC_HOME_DIR/.vnc"
    chmod 700 "$VNC_HOME_DIR/.vnc"

    # ── xstartup (single exec, no duplicates) ──
    cat > "$VNC_HOME_DIR/.vnc/xstartup" << 'XSTARTUP_EOF'
#!/bin/sh
# Cloud Linux GUI - VNC xstartup

# Clean environment
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Set up XDG runtime directory
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -un)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Load X resources if available
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"

# Start XFCE4 desktop (single exec - no duplicates)
exec dbus-launch --exit-with-session startxfce4
XSTARTUP_EOF
    chmod +x "$VNC_HOME_DIR/.vnc/xstartup"

    # ── VNC Config ──
    cat > "$VNC_HOME_DIR/.vnc/config" << VNCCONFIG_EOF
geometry=${VNC_RESOLUTION}
depth=${VNC_DEPTH}
localhost=no
alwaysshared
VNCCONFIG_EOF

    # ── Generate VNC Password ──
    if [ -n "$VNC_PASSWORD" ]; then
        VNC_PASS="$VNC_PASSWORD"
        print_info "Using VNC_PASSWORD from environment"
    else
        # Secure random password (alphanumeric, 12 chars)
        VNC_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
        print_info "Generated secure random VNC password"
    fi

    # Create VNC password file using vncpasswd
    echo "$VNC_PASS" | vncpasswd -f > "$VNC_HOME_DIR/.vnc/passwd" 2>/dev/null

    # Verify password file was created
    if [ ! -s "$VNC_HOME_DIR/.vnc/passwd" ]; then
        print_warning "vncpasswd -f failed, trying alternative method..."
        # Alternative: use expect-style input
        printf '%s\n%s\n\n' "$VNC_PASS" "$VNC_PASS" | vncpasswd "$VNC_HOME_DIR/.vnc/passwd" 2>/dev/null || true
    fi

    chmod 600 "$VNC_HOME_DIR/.vnc/passwd"

    # Save password securely to file
    echo "$VNC_PASS" > "$VNC_HOME_DIR/.vnc/.password_plain"
    chmod 600 "$VNC_HOME_DIR/.vnc/.password_plain"

    # Fix ownership if running as root
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        chown -R "$RUN_AS_USER:$RUN_AS_USER" "$VNC_HOME_DIR/.vnc"
    fi

    echo ""
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}🔑 VNC Password:${NC} ${GREEN}${VNC_PASS}${NC}"
    echo -e "  ${YELLOW}📁 Saved to:${NC}     ${BLUE}${VNC_HOME_DIR}/.vnc/.password_plain${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    print_success "VNC configured"
}

# ─────────────────────────────────────────────
# Process Management
# ─────────────────────────────────────────────

kill_all() {
    print_step "Stopping existing services..."

    # Graceful stop first
    pkill -f "cloudflared"      2>/dev/null || true
    pkill -f "websockify"       2>/dev/null || true

    # Kill VNC server properly
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        su - "$RUN_AS_USER" -c "tigervncserver -kill :1" 2>/dev/null || true
    else
        tigervncserver -kill :1 2>/dev/null || true
    fi

    sleep 1

    # Force kill if still running
    pkill -9 -f "Xtigervnc"    2>/dev/null || true
    pkill -9 -f "websockify"   2>/dev/null || true
    pkill -9 -f "cloudflared"  2>/dev/null || true

    sleep 1

    # Clean up stale lock files
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
    rm -f /tmp/.X2-lock /tmp/.X11-unix/X2 2>/dev/null || true
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true

    print_success "Existing services stopped"
}

# Helper: run a command as the service user
run_as_user() {
    local cmd="\$1"
    if [ "$(id -u)" -eq 0 ] && [ "$RUN_AS_USER" != "root" ]; then
        su - "$RUN_AS_USER" -c "$cmd"
    else
        eval "$cmd"
    fi
}

# ─────────────────────────────────────────────
# Start Services
# ─────────────────────────────────────────────

start_services() {
    print_step "Starting VNC server..."

    kill_all

    # Create log directory
    mkdir -p "$LOG_DIR"
    chmod 777 "$LOG_DIR" 2>/dev/null || true

    local VNC_HOME_DIR
    VNC_HOME_DIR="$(get_user_home)"

    # ── Start TigerVNC Server ──
    # TigerVNC has its own built-in X server (Xtigervnc)
    # No need for a separate Xvfb!

    run_as_user "tigervncserver :1 \
        -geometry ${VNC_RESOLUTION} \
        -depth ${VNC_DEPTH} \
        -localhost no \
        -rfbport ${VNC_PORT} \
        -xstartup ${VNC_HOME_DIR}/.vnc/xstartup \
        -rfbauth ${VNC_HOME_DIR}/.vnc/passwd \
        -AlwaysShared \
        > ${LOG_DIR}/vnc.log 2>&1" || true

    sleep 4

    # Verify VNC is running
    if pgrep -f "Xtigervnc.*:1" > /dev/null; then
        print_success "VNC server started on display :1 (port ${VNC_PORT})"
    else
        print_error "VNC server failed to start"
        echo ""
        print_info "VNC log output:"
        cat "${LOG_DIR}/vnc.log" 2>/dev/null || true
        echo ""

        # Try alternative start method
        print_warning "Trying alternative VNC start method..."
        run_as_user "vncserver :1 \
            -geometry ${VNC_RESOLUTION} \
            -depth ${VNC_DEPTH} \
            -localhost no \
            > ${LOG_DIR}/vnc.log 2>&1" || true

        sleep 3

        if pgrep -f "Xtigervnc.*:1\|Xvnc.*:1" > /dev/null; then
            print_success "VNC server started (alternative method)"
        else
            print_error "VNC server failed to start with both methods"
            cat "${LOG_DIR}/vnc.log" 2>/dev/null
            exit 1
        fi
    fi
}

# ─────────────────────────────────────────────
# Start noVNC
# ─────────────────────────────────────────────

start_novnc() {
    print_step "Starting noVNC web server..."

    pkill -f "websockify" 2>/dev/null || true
    sleep 1

    # Start websockify with noVNC web directory
    nohup websockify \
        --web="$NOVNC_DIR" \
        --heartbeat=30 \
        "$NOVNC_PORT" \
        "localhost:${VNC_PORT}" \
        > "${LOG_DIR}/novnc.log" 2>&1 &

    sleep 3

    if pgrep -f "websockify" > /dev/null; then
        print_success "noVNC running on port ${NOVNC_PORT}"
        print_info "Local access: http://localhost:${NOVNC_PORT}/vnc.html"
    else
        print_error "noVNC failed to start"
        cat "${LOG_DIR}/novnc.log" 2>/dev/null
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Cloudflare Tunnel
# ─────────────────────────────────────────────

start_tunnel() {
    print_step "Starting Cloudflare Tunnel..."

    pkill -f "cloudflared" 2>/dev/null || true
    sleep 1

    # Start cloudflared tunnel
    nohup cloudflared tunnel \
        --url "http://localhost:${NOVNC_PORT}" \
        --logfile "${LOG_DIR}/cloudflared.log" \
        --no-autoupdate \
        > "${LOG_DIR}/tunnel_stdout.log" 2>&1 &

    TUNNEL_PID=$!

    # Wait for tunnel URL
    print_info "Waiting for Cloudflare tunnel URL..."
    TUNNEL_URL=""
    for i in $(seq 1 30); do
        sleep 2

        # Check if process is still alive
        if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
            print_error "Cloudflared process died unexpectedly"
            cat "${LOG_DIR}/cloudflared.log" 2>/dev/null | tail -20
            exit 1
        fi

        TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' "${LOG_DIR}/cloudflared.log" 2>/dev/null | head -1)
        if [ -n "$TUNNEL_URL" ]; then
            break
        fi

        # Show progress
        if [ $((i % 5)) -eq 0 ]; then
            print_info "Still waiting... (${i}/30)"
        fi
    done

    mkdir -p "$SCRIPT_DIR"

    if [ -n "$TUNNEL_URL" ]; then
        echo "$TUNNEL_URL" > "$SCRIPT_DIR/tunnel_url.txt"

        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}  🎉 CLOUDFLARE TUNNEL IS READY!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${BLUE}🖥️  Desktop URL:${NC}"
        echo -e "  ${GREEN}  ${TUNNEL_URL}/vnc.html${NC}"
        echo ""
        echo -e "  ${BLUE}🔗 Direct URL (auto-redirect):${NC}"
        echo -e "  ${GREEN}  ${TUNNEL_URL}${NC}"
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        print_error "Failed to obtain Cloudflare tunnel URL after 60 seconds"
        print_info "Cloudflared log:"
        tail -20 "${LOG_DIR}/cloudflared.log" 2>/dev/null
        print_info "You can try accessing: http://localhost:${NOVNC_PORT}/vnc.html"
    fi
}

# ─────────────────────────────────────────────
# Management Scripts
# ─────────────────────────────────────────────

create_scripts() {
    print_step "Creating management scripts..."

    mkdir -p "$SCRIPT_DIR"

    local VNC_HOME_DIR
    VNC_HOME_DIR="$(get_user_home)"

    # ── Main control script ──
    cat > "$SCRIPT_DIR/gui-control.sh" << SCRIPT_EOF
#!/bin/bash
# Cloud Linux GUI - Control Script

SCRIPT_DIR="/opt/cloud-linux-gui"
NOVNC_DIR="\$SCRIPT_DIR/noVNC"
VNC_PORT=${VNC_PORT}
NOVNC_PORT=${NOVNC_PORT}
LOG_DIR="${LOG_DIR}"
VNC_HOME="${VNC_HOME_DIR}"
VNC_RESOLUTION="${VNC_RESOLUTION}"
VNC_DEPTH="${VNC_DEPTH}"
RUN_AS_USER="${RUN_AS_USER}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

run_as_user() {
    local cmd="\\$1"
    if [ "\$(id -u)" -eq 0 ] && [ "\$RUN_AS_USER" != "root" ]; then
        su - "\$RUN_AS_USER" -c "\$cmd"
    else
        eval "\$cmd"
    fi
}

do_stop() {
    echo -e "\${YELLOW}[*] Stopping all services...\${NC}"
    pkill -f "cloudflared"      2>/dev/null || true
    pkill -f "websockify"       2>/dev/null || true
    run_as_user "tigervncserver -kill :1" 2>/dev/null || true
    sleep 1
    pkill -9 -f "Xtigervnc"    2>/dev/null || true
    pkill -9 -f "websockify"   2>/dev/null || true
    pkill -9 -f "cloudflared"  2>/dev/null || true
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
    echo -e "\${GREEN}[✓] All services stopped\${NC}"
}

do_start() {
    do_stop
    sleep 2

    mkdir -p "\$LOG_DIR"
    chmod 777 "\$LOG_DIR" 2>/dev/null || true

    echo -e "\${YELLOW}[*] Starting VNC server...\${NC}"
    run_as_user "tigervncserver :1 \\
        -geometry \${VNC_RESOLUTION} \\
        -depth \${VNC_DEPTH} \\
        -localhost no \\
        -rfbport \${VNC_PORT} \\
        -xstartup \${VNC_HOME}/.vnc/xstartup \\
        -rfbauth \${VNC_HOME}/.vnc/passwd \\
        -AlwaysShared \\
        > \${LOG_DIR}/vnc.log 2>&1" || true
    sleep 3

    if pgrep -f "Xtigervnc.*:1" > /dev/null; then
        echo -e "\${GREEN}[✓] VNC server running\${NC}"
    else
        echo -e "\${RED}[✗] VNC failed to start\${NC}"
        cat "\${LOG_DIR}/vnc.log" 2>/dev/null
        return 1
    fi

    echo -e "\${YELLOW}[*] Starting noVNC...\${NC}"
    nohup websockify --web="\$NOVNC_DIR" --heartbeat=30 \\
        \$NOVNC_PORT localhost:\$VNC_PORT \\
        > "\${LOG_DIR}/novnc.log" 2>&1 &
    sleep 2

    if pgrep -f "websockify" > /dev/null; then
        echo -e "\${GREEN}[✓] noVNC running on port \${NOVNC_PORT}\${NC}"
    else
        echo -e "\${RED}[✗] noVNC failed\${NC}"
        return 1
    fi

    echo -e "\${YELLOW}[*] Starting Cloudflare tunnel...\${NC}"
    nohup cloudflared tunnel \\
        --url http://localhost:\$NOVNC_PORT \\
        --logfile "\${LOG_DIR}/cloudflared.log" \\
        --no-autoupdate \\
        > "\${LOG_DIR}/tunnel_stdout.log" 2>&1 &
    sleep 15

    URL=\$(grep -oP 'https://[a-z0-9-]+\\.trycloudflare\\.com' "\${LOG_DIR}/cloudflared.log" 2>/dev/null | head -1)
    if [ -n "\$URL" ]; then
        echo "\$URL" > "\$SCRIPT_DIR/tunnel_url.txt"
        echo ""
        echo -e "\${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
        echo -e "\${GREEN}  🎉 Desktop ready!\${NC}"
        echo -e "\${GREEN}  🔗 \${URL}/vnc.html\${NC}"
        echo -e "\${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\${NC}"
    else
        echo -e "\${YELLOW}[!] Tunnel URL not found yet. Check: \${LOG_DIR}/cloudflared.log\${NC}"
        echo -e "\${CYAN}[i] Local access: http://localhost:\${NOVNC_PORT}/vnc.html\${NC}"
    fi
}

do_status() {
    echo ""
    echo -e "\${BLUE}╔═══════════════════════════════════════╗\${NC}"
    echo -e "\${BLUE}║       Service Status                  ║\${NC}"
    echo -e "\${BLUE}╚═══════════════════════════════════════╝\${NC}"
    echo ""

    if pgrep -f "Xtigervnc.*:1" > /dev/null; then
        echo -e "  VNC Server   : \${GREEN}● Running\${NC}"
    else
        echo -e "  VNC Server   : \${RED}● Stopped\${NC}"
    fi

    if pgrep -f "websockify" > /dev/null; then
        echo -e "  noVNC        : \${GREEN}● Running\${NC} (port \${NOVNC_PORT})"
    else
        echo -e "  noVNC        : \${RED}● Stopped\${NC}"
    fi

    if pgrep -f "cloudflared" > /dev/null; then
        echo -e "  Cloudflare   : \${GREEN}● Running\${NC}"
        URL=\$(cat "\$SCRIPT_DIR/tunnel_url.txt" 2>/dev/null)
        [ -n "\$URL" ] && echo -e "  Tunnel URL   : \${CYAN}\${URL}/vnc.html\${NC}"
    else
        echo -e "  Cloudflare   : \${RED}● Stopped\${NC}"
    fi
    echo ""
}

do_url() {
    URL=\$(cat "\$SCRIPT_DIR/tunnel_url.txt" 2>/dev/null)
    if [ -n "\$URL" ]; then
        echo -e "\${GREEN}\${URL}/vnc.html\${NC}"
    else
        # Try to get from log
        URL=\$(grep -oP 'https://[a-z0-9-]+\\.trycloudflare\\.com' "\${LOG_DIR}/cloudflared.log" 2>/dev/null | head -1)
        if [ -n "\$URL" ]; then
            echo "\$URL" > "\$SCRIPT_DIR/tunnel_url.txt"
            echo -e "\${GREEN}\${URL}/vnc.html\${NC}"
        else
            echo "No tunnel URL found. Run: \\$0 start"
        fi
    fi
}

do_logs() {
    echo -e "\${BLUE}=== VNC Log ===\${NC}"
    tail -20 "\${LOG_DIR}/vnc.log" 2>/dev/null || echo "(empty)"
    echo ""
    echo -e "\${BLUE}=== noVNC Log ===\${NC}"
    tail -20 "\${LOG_DIR}/novnc.log" 2>/dev/null || echo "(empty)"
    echo ""
    echo -e "\${BLUE}=== Cloudflared Log ===\${NC}"
    tail -20 "\${LOG_DIR}/cloudflared.log" 2>/dev/null || echo "(empty)"
}

do_password() {
    PASS=\$(cat "\${VNC_HOME}/.vnc/.password_plain" 2>/dev/null)
    if [ -n "\$PASS" ]; then
        echo -e "\${YELLOW}VNC Password:\${NC} \${GREEN}\${PASS}\${NC}"
    else
        echo "Password file not found"
    fi
}

case "\${1:-help}" in
    start)    do_start    ;;
    stop)     do_stop     ;;
    restart)  do_start    ;;
    status)   do_status   ;;
    url)      do_url      ;;
    logs)     do_logs     ;;
    password) do_password ;;
    help|*)
        echo ""
        echo "Cloud Linux GUI - Control Script"
        echo ""
        echo "Usage: \\$0 <command>"
        echo ""
        echo "Commands:"
        echo "  start     - Start all services and create tunnel"
        echo "  stop      - Stop all services"
        echo "  restart   - Restart all services"
        echo "  status    - Show service status"
        echo "  url       - Show tunnel URL"
        echo "  logs      - Show service logs"
        echo "  password  - Show VNC password"
        echo ""
        ;;
esac
SCRIPT_EOF

    chmod +x "$SCRIPT_DIR/gui-control.sh"

    # Create symlink for easy access
    ln -sf "$SCRIPT_DIR/gui-control.sh" /usr/local/bin/cloud-gui 2>/dev/null || true

    print_success "Management scripts created"
    print_info "Quick command: cloud-gui {start|stop|restart|status|url|logs|password}"
}

# ─────────────────────────────────────────────
# Final Status Display
# ─────────────────────────────────────────────

display_status() {
    local VNC_HOME_DIR
    VNC_HOME_DIR="$(get_user_home)"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✅ INSTALLATION COMPLETE!                            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ -f "$SCRIPT_DIR/tunnel_url.txt" ]; then
        URL=$(cat "$SCRIPT_DIR/tunnel_url.txt")
        echo -e "  ${BLUE}🖥️  Access your Linux Desktop:${NC}"
        echo -e "     ${GREEN}${URL}/vnc.html${NC}"
        echo ""
        echo -e "  ${BLUE}🔗 Auto-redirect URL:${NC}"
        echo -e "     ${GREEN}${URL}${NC}"
        echo ""
    fi

    if [ -f "${VNC_HOME_DIR}/.vnc/.password_plain" ]; then
        VNC_PASS=$(cat "${VNC_HOME_DIR}/.vnc/.password_plain")
        echo -e "  ${YELLOW}🔑 VNC Password:${NC} ${GREEN}${VNC_PASS}${NC}"
        echo ""
    fi

    echo -e "  ${CYAN}━━━━━━━━━━━━━ Quick Commands ━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}cloud-gui start${NC}     Start all services"
    echo -e "  ${YELLOW}cloud-gui stop${NC}      Stop all services"
    echo -e "  ${YELLOW}cloud-gui restart${NC}   Restart everything"
    echo -e "  ${YELLOW}cloud-gui status${NC}    Check service status"
    echo -e "  ${YELLOW}cloud-gui url${NC}       Show tunnel URL"
    echo -e "  ${YELLOW}cloud-gui logs${NC}      View service logs"
    echo -e "  ${YELLOW}cloud-gui password${NC}  Show VNC password"
    echo ""
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}⚠️  Note:${NC} Free Cloudflare tunnels generate random URLs"
    echo -e "  that change on restart. Run ${BLUE}cloud-gui url${NC} to get the"
    echo -e "  current URL after restarting."
    echo ""
    echo -e "  ${YELLOW}📁 Logs:${NC} ${BLUE}${LOG_DIR}/${NC}"
    echo -e "  ${YELLOW}📁 Config:${NC} ${BLUE}${VNC_HOME_DIR}/.vnc/${NC}"
    echo ""
}

# ─────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────

main() {
    # Check for minimum requirements
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[!] Warning: Running without root privileges.${NC}"
        echo -e "${YELLOW}[!] Some features may not work. Consider running with sudo.${NC}"
        echo ""
    fi

    print_header
    detect_os
    install_dependencies
    install_cloudflared
    install_novnc
    create_vnc_page
    create_service_user
    setup_vnc
    start_services
    start_novnc
    create_scripts
    start_tunnel
    display_status
}

main "$@"
