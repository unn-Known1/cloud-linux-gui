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


### Management Commands

```bash
# View current tunnel URL
cat /opt/cloud-linux-gui/tunnel_url.txt

# Restart all services
/opt/cloud-linux-gui/tunnel.sh start

# Stop all services
/opt/cloud-linux-gui/tunnel.sh stop

# Check status
/opt/cloud-linux-gui/tunnel.sh status
```

### Quick Actions (in browser)

- **Fullscreen** - Click the ⛶ button or press F11
- **Ctrl+Alt+Del** - Click the ⌨️ button
- **Keyboard** - Mobile on-screen keyboard
- **Refresh** - Reconnect to desktop

## 🏗️ Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Browser   │ ←──→ │ Cloudflare  │ ←──→ │   noVNC     │
│   (Any!)    │ HTTPS│   Tunnel    │ HTTP │  + WebSocket│
└─────────────┘      └─────────────┘      └──────┬──────┘
                                                  │
                                                  ▼
                                           ┌─────────────┐
                                           │  TigerVNC   │
                                           │   Server    │
                                           └──────┬──────┘
                                                  │
                                                  ▼
                                           ┌─────────────┐
                                           │    Xvfb     │
                                           │  (Virtual)  │
                                           └──────┬──────┘
                                                  │
                                                  ▼
                                           ┌─────────────┐
                                           │   XFCE4     │
                                           │  Desktop    │
                                           └─────────────┘
```

## 📋 Requirements

- **OS**: Ubuntu 20.04+ / Debian 10+ / CentOS 8+
- **RAM**: 1GB+ recommended
- **Disk**: 5GB+ free space
- **Internet**: Required for tunnel connection


## ⚠️ Important Notes

1. **Cloudflare Tunnel URL expires** when services are stopped. Restart services to get a new URL.
2. **Public access** - The tunnel URL is public. Don't use for sensitive data without additional authentication.
3. **Performance** - For best experience, use a machine with good network connectivity.


## 🔒 Security


- All traffic is encrypted via HTTPS through Cloudflare
- VNC traffic is tunneled securely
- No VNC password required by default (access controlled by tunnel URL)


## 🤝 Contributing

Contributions welcome! Please open an issue or submit a PR.

## 📄 License

MIT License - feel free to use and modify.
