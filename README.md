# 🐧 Cloud Linux GUI — Full Linux Desktop in Your Browser

Spin up a full Linux graphical desktop — accessible from any browser, anywhere — with a single command.

![Linux](https://img.shields.io/badge/Linux-Desktop-blue?style=for-the-badge)
![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-orange?style=for-the-badge)
![NoVNC](https://img.shields.io/badge/NoVNC-Web--native-cyan?style=for-the-badge)

## ✨ Features

- **🖥️ Full desktop experience** — GNOME/KDE inside your browser, no VNC client needed
- **⚡ One-command setup** — install and run in under 2 minutes
- **🔒 No open ports** — Cloudflare Tunnel handles the exposure securely
- **📱 Works on everything** — desktop, tablet, phone, old browsers
- **💪 Real Linux** — full apt/dpkg packages, run GUI apps natively
- **🧩 Lightweight** — works on a $5/month VPS with 1GB RAM

## 🚀 Quick Start

```bash
# One-line install
bash -c "$(curl -fsSL https://raw.githubusercontent.com/unn-known1/cloud-linux-gui/main/install.sh)"

# Or step by step
git clone https://github.com/unn-known1/cloud-linux-gui.git
cd cloud-linux-gui
chmod +x install.sh && ./install.sh
```

Then create a Cloudflare Tunnel to expose it:
```bash
cloudflared tunnel create linux-gui
cloudflared tunnel route dns linux-gui gui.yourdomain.com
cloudflared tunnel run linux-gui
```

## 🏗️ Stack

- **Desktop:** VNC (tigervnc or x11vnc) + noVNC for web access
- **Tunnel:** Cloudflare Tunnel (cloudflared)
- **Session manager:** xrdp or tigerVNC

## 💡 Use Cases

- Run GUI apps on a remote server without SSH X-forwarding
- Access your Linux desktop from a locked-down corporate network
- Browser-only device (Chromebook, iPad) accessing a full Linux machine
- Quick Linux desktop for testing without a VM

## ⭐ If this helped you, star the repo!

MIT License — built with 💻 by [Gaurang Patel](https://github.com/unn-known1)