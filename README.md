# 🖥️ Cloud Linux GUI

**Full Linux Desktop accessible from any browser - with one command installation!**

Deploy a complete Linux desktop environment with XFCE4 GUI that you can access from anywhere in the world via a Cloudflare Tunnel URL.

## ⚡ Quick Start

```bash
curl -sL https://raw.githubusercontent.com/unn-known1/cloud-linux-gui/main/install.sh | bash
```

That's it! You'll get a Cloudflare URL like `https://xxxx.trycloudflare.com` to access your full Linux desktop.

## ✨ Features

- **🖥️ Full Desktop Environment** - XFCE4 desktop with complete GUI
- **🌐 Access Anywhere** - Cloudflare Tunnel provides secure global access
- **📱 Mobile-Friendly** - Works on any device with a browser
- **⌨️ Full Keyboard Support** - On-screen keyboard for mobile devices
- **🔄 Auto-Reconnect** - Automatic reconnection on network issues
- **📋 Clipboard Support** - Copy/paste between browser and desktop
- **⛶ Fullscreen Mode** - Immersive full desktop experience
- **🎨 Modern UI** - Beautiful gradient interface with loading animations

## 🔧 What You Get

| Component | Description |
|-----------|-------------|
| **Desktop** | XFCE4 - lightweight but full-featured |
| **Web Server** | noVNC for browser-based access |
| **Tunnel** | Cloudflare Tunnel for global access |
| **Resolution** | 1920x1080 (configurable) |
| **Color Depth** | 24-bit true color |

## 🚀 Installation

### One-Command Install (Recommended)

```bash
curl -sL https://raw.githubusercontent.com/unn-known1/cloud-linux-gui/main/install.sh | bash
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/unn-known1/cloud-linux-gui.git
cd cloud-linux-gui

# Make scripts executable
chmod +x install.sh

# Run installation
sudo ./install.sh
```

## 📖 Usage

### After Installation

The installer automatically starts everything and displays your tunnel URL:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Your Cloud Linux Desktop:
https://xxxx.trycloudflare.com
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Managing the Service

```bash
# View current tunnel URL
cat /opt/cloud-linux-gui/tunnel_url.txt

# Restart tunnel
/opt/cloud-linux-gui/tunnel.sh restart

# Stop all services
pkill -f 'Xvfb|vncserver|novnc|cloudflared'

# Quick access (if installed)
/usr/local/bin/cloud-linux
```

## 🎮 Controls

| Button | Function |
|--------|----------|
| ⛶ | Toggle fullscreen |
| ⌨️ (1st) | Send Ctrl+Alt+Del |
| ⌨️ (2nd) | Toggle mobile keyboard |
| 🔄 | Refresh connection |
| ⌨️ (3rd) | Show keyboard |

### Mobile Keyboard Keys

ESC | TAB | CTRL | ALT | SHIFT | ENTER | ⌫ | ↑↓←→

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| F11 | Fullscreen |
| Ctrl+Alt+Shift | Release mouse |

## 🔐 Security

- **Cloudflare Protected** - All traffic routes through Cloudflare's secure network
- **No Port Forwarding** - No exposed ports on your machine
- **Encrypted Connection** - HTTPS via Cloudflare Tunnel
- **Self-Hosted** - Your data stays on your machine

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Cloudflare                              │
│                                                             │
│   ┌──────────┐      ┌──────────────┐      ┌────────────┐  │
│   │  Browser │ ───> │ trycloudflare│ ───> │ Your Server │  │
│   │  (Any)   │      │    .com      │      │  (Cloudflare│  │
│   └──────────┘      └──────────────┘      │   Tunnel)   │  │
│                                           └──────┬───────┘  │
│                                                  │          │
│                                           ┌──────┴───────┐  │
│                                           │              │  │
│                                      ┌────┴────┐   ┌─────┴──┐  │
│                                      │ noVNC   │   │  VNC   │  │
│                                      │ (Web)   │   │Server  │  │
│                                      └─────────┘   └────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 📋 Requirements

- **OS**: Linux (Ubuntu, Debian, CentOS, Fedora, Alpine)
- **Architecture**: x86_64, arm64, or armv7l
- **Tools**: curl or wget (for installation)
- **Root/Sudo**: Required for package installation

### Installed Packages

- Xvfb (virtual framebuffer)
- xfce4 (desktop environment)
- tightvncserver or tigervnc (VNC server)
- novnc (web-based VNC client)
- cloudflared (Cloudflare Tunnel)

## 🐛 Troubleshooting

### Installation Fails

```bash
# Check if running with sudo/root
sudo bash -c "curl -sL https://raw.githubusercontent.com/unn-known1/cloud-linux-gui/main/install.sh | bash"
```

### No Tunnel URL

```bash
# Check tunnel logs
cat /tmp/tunnel.log

# Restart tunnel manually
/opt/cloud-linux-gui/tunnel.sh restart
```

### VNC Not Connecting

```bash
# Check if VNC is running
ps aux | grep vnc

# Restart VNC
pkill -f vncserver
vncserver :1 -geometry 1920x1080 -depth 24
```

### Port Already in Use

```bash
# Kill existing processes
pkill -f 'Xvfb|vncserver|novnc|websockify|cloudflared'
```

## 📝 Customization

### Change Resolution

Edit `/root/.vnc/xstartup` and modify the `Xvfb` command:

```bash
Xvfb :1 -screen 0 1280x720x24 -ac +extension GLX +render -noreset &
```

### Change VNC Password

```bash
vncpasswd
```

### Different Desktop Environment

Replace `startxfce4` in `~/.vnc/xstartup` with:
- `startlxde` (LXDE)
- `startplasma-x11` (KDE)
- `gnome-session` (GNOME)

## 🤝 Contributing

Contributions welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT License - feel free to use, modify, and distribute.

---

**Built with ❤️ for cloud computing, remote work, and accessibility**